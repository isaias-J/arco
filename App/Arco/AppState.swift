import Foundation
import SwiftData
import Observation
import UserNotifications
import ArcoCore

/// Pestañas de la navegación inferior (spec §20).
enum AppTab: Hashable { case today, progress, photos, attendance, profile }

/// Modo de solicitud de RIR (spec §3: opcional; puede pedirse solo en la última serie).
enum RIRMode: String, CaseIterable, Identifiable {
    case off, allSets, lastSet
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "No pedir"
        case .allSets: return "En todas las series"
        case .lastSet: return "Solo en la última serie"
        }
    }
}

/// Preferencias no sensibles guardadas en UserDefaults. Viajan en la copia de seguridad.
enum Preferences {
    static let rirModeKey = "arco.rirMode"
    static let useFaceIDKey = "arco.useFaceID"
    static let reviewOnboardedKey = "arco.reviewRulesSeeded"
    /// Fecha civil ("yyyy-MM-dd") en que el usuario dice haber empezado a entrenar (spec §2).
    /// Opcional: si no la indica, queda desconocida. No altera la asistencia ni la adherencia.
    static let trainingStartKey = "arco.trainingStartDay"

    private static let exported = [rirModeKey, useFaceIDKey, trainingStartKey]

    static var all: [String: String] {
        var out: [String: String] = [:]
        for key in exported {
            if let v = UserDefaults.standard.string(forKey: key) { out[key] = v }
        }
        return out
    }

    static func restore(_ values: [String: String]) {
        for (k, v) in values where exported.contains(k) {
            UserDefaults.standard.set(v, forKey: k)
        }
    }

    static var trainingStart: CivilDay? {
        get { UserDefaults.standard.string(forKey: trainingStartKey).flatMap(CivilDay.init(key:)) }
        set {
            if let newValue { UserDefaults.standard.set(newValue.key, forKey: trainingStartKey) }
            else { UserDefaults.standard.removeObject(forKey: trainingStartKey) }
        }
    }
}

/// Estado global de la app, ligado a la interfaz (@Observable + @MainActor).
@MainActor
@Observable
final class AppState {
    let context: ModelContext

    /// Ajustes vigentes (se crean en el seed).
    var settings: AppSettingsModel

    /// Bóveda de fotos (PIN + Face ID). Se bloquea al pasar a segundo plano.
    let vaultLock: VaultLock

    /// Cifrado de la bóveda (clave local del dispositivo).
    let vaultCrypto = VaultCrypto()

    /// Avisos locales.
    let notifications = NotificationService()

    /// Archivo de respaldo v1 (solo datos, sin fotos): se mantiene para leer copias antiguas.
    let backup = BackupArchive()

    /// Fecha civil de una revisión para la que el usuario pulsó "Voy más tarde" (abre la hoja
    /// para elegir 30/60/120 minutos).
    var snoozeRequestDay: CivilDay?

    /// Estado real del permiso de avisos.
    var notificationStatus: UNAuthorizationStatus = .notDetermined

    /// Pestaña seleccionada (permite saltar a Fotos tras guardar un peso).
    var selectedTab: AppTab = .today

    /// Pesaje recién guardado al que el usuario quiere añadir una foto (spec §16 "Añadir foto").
    /// La sección Fotos lo consume tras desbloquear la bóveda.
    var pendingPhotoWeightID: UUID?

    init(context: ModelContext) {
        self.context = context
        let fetched = (try? context.fetch(FetchDescriptor<AppSettingsModel>()))?.first
        let settings = fetched ?? AppSettingsModel()
        self.settings = settings
        self.vaultLock = VaultLock(pinAuth: PINAuth(), biometricAuth: BiometricAuth())
        if fetched == nil { context.insert(settings) }
    }

    var theme: AppTheme { AppTheme(rawValue: settings.themeRaw) ?? .system }

    var needsOnboarding: Bool { !settings.onboardingCompleted }

    var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = settings.weekStartsMonday ? 2 : 1
        return c
    }

    var repository: WorkoutRepository { WorkoutRepository(context: context, calendar: calendar) }

    var attendance: AttendanceRepository { AttendanceRepository(context: context, calendar: calendar) }

    var weeklyPlan: WeeklyPlan { PersistenceController.weeklyPlan(context) }

    var catalog: CatalogRepository { CatalogRepository(context: context) }

    /// Historial de versiones del plan (spec §14, T39).
    var planHistory: PlanHistory { catalog.planHistory() }

    /// Nombre mostrado de un ejercicio: el guardado (renombrable, spec §6) o el del catálogo.
    func exerciseName(_ id: String) -> String {
        let predicate = #Predicate<ExerciseModel> { $0.id == id }
        if let name = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first?.name, !name.isEmpty {
            return name
        }
        return ExerciseNames.localized(id)
    }

    var rirMode: RIRMode {
        get { RIRMode(rawValue: UserDefaults.standard.string(forKey: Preferences.rirModeKey) ?? "") ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Preferences.rirModeKey) }
    }

    var useFaceID: Bool {
        get { UserDefaults.standard.string(forKey: Preferences.useFaceIDKey) == "true" }
        set { UserDefaults.standard.set(newValue ? "true" : "false", forKey: Preferences.useFaceIDKey) }
    }

    func completeOnboarding() {
        settings.onboardingCompleted = true
        try? context.save()
    }

    // MARK: - Avisos (spec §15)

    /// Reglas guardadas (convención de weekday de Calendar).
    func reminderRules() -> [ReminderRule] {
        let models = (try? context.fetch(FetchDescriptor<ReminderRuleModel>())) ?? []
        return models.compactMap { m in
            guard let category = ReminderCategory(rawValue: m.categoryRaw) else { return nil }
            return ReminderRule(
                category: category,
                weekday: m.weekday.flatMap(Weekday.init(rawValue:)),
                hour: m.hour, minute: m.minute, enabled: m.enabled
            )
        }
    }

    func reminderOverrides() -> [ReminderOverride] {
        let models = (try? context.fetch(FetchDescriptor<ReminderOverrideModel>())) ?? []
        return models.compactMap { m in
            guard let category = ReminderCategory(rawValue: m.categoryRaw), let day = CivilDay(key: m.dayKey) else { return nil }
            return ReminderOverride(category: category, day: day, hour: m.hour, minute: m.minute, enabled: m.enabled)
        }
    }

    /// Crea la regla de revisión nocturna por defecto (21:00, días planificados) la primera vez.
    /// No pide permisos: solo se programa cuando el usuario autoriza avisos.
    func seedDefaultReminderRulesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Preferences.reviewOnboardedKey) else { return }
        let existing = (try? context.fetch(FetchDescriptor<ReminderRuleModel>())) ?? []
        if !existing.contains(where: { $0.categoryRaw == ReminderCategory.review.rawValue }) {
            context.insert(ReminderRuleModel(categoryRaw: ReminderCategory.review.rawValue, weekday: nil, hour: ReminderPlanner.defaultReviewHour, minute: 0, enabled: true, timeZoneID: TimeZone.current.identifier))
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: Preferences.reviewOnboardedKey)
    }

    /// Recalcula y aplica la ventana de avisos. Se llama al abrir la app, al cambiar ajustes,
    /// al registrar asistencia y al responder un aviso (T41, T44).
    func refreshReminders() async {
        notificationStatus = await notifications.currentStatus()
        let cal = calendar
        let attendance = attendance
        let input = ReminderPlanner.Input(
            plan: weeklyPlan,
            rules: reminderRules(),
            overrides: reminderOverrides(),
            attendedDays: attendance.attendedDays(),
            resolvedDays: Set(attendance.resolutions().keys),
            activeSessionDay: repository.activeSession().map { CivilDay($0.trainingDate, calendar: cal) },
            now: Date(),
            calendar: cal
        )
        let planned = ReminderPlanner.plan(input)
        await notifications.apply(planned, calendar: cal, authorized: notificationStatus.allowsScheduling)
    }

    // MARK: - Acciones del aviso de asistencia (T42: dirigidas a la fecha del aviso)

    func handleAttendanceAction(_ action: AttendanceReviewAction, day: CivilDay) async {
        switch action {
        case .didAttend:
            attendance.markAttended(day)
        case .didRest:
            attendance.markResolution(.rest, on: day)
        case .later:
            snoozeRequestDay = day
        }
        await refreshReminders()
    }

    /// "Voy más tarde": aplaza la revisión de ese día sin cruzar al siguiente (T43).
    /// Devuelve false si el aplazamiento cruzaría de fecha (queda sin confirmar).
    @discardableResult
    func snoozeReview(day: CivilDay, minutes: Int) async -> Bool {
        let key = day.key
        let category = ReminderCategory.review.rawValue
        let predicate = #Predicate<ReminderOverrideModel> { $0.dayKey == key && $0.categoryRaw == category }
        let existing = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        guard let time = ReminderPlanner.snoozeTime(for: day, minutes: minutes, now: Date(), calendar: calendar) else {
            await refreshReminders()
            return false
        }
        if let o = existing.first {
            o.hour = time.hour; o.minute = time.minute; o.enabled = true
            for extra in existing.dropFirst() { context.delete(extra) }
        } else {
            context.insert(ReminderOverrideModel(categoryRaw: category, dayKey: key, hour: time.hour, minute: time.minute, enabled: true))
        }
        try? context.save()
        await refreshReminders()
        return true
    }
}

extension UNAuthorizationStatus {
    var allowsScheduling: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }
}
