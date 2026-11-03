import SwiftUI
import SwiftData
import UserNotifications
import ArcoCore

/// Ajustes de avisos locales (spec §15). Cada día tiene su propio horario y se guarda en
/// `ReminderRuleModel` (weekday con la convención de Calendar). La app funciona sin permiso:
/// muestra el estado real y un acceso a Ajustes (T40).
struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query private var rules: [ReminderRuleModel]
    @Query private var templates: [RoutineTemplateModel]
    @State private var pending: [String] = []

    private var plan: WeeklyPlan { WeeklyPlan(templates: templates) }
    private var days: [Weekday] { Weekday.ordered(startingMonday: appState.settings.weekStartsMonday) }

    var body: some View {
        Form {
            permissionSection
            Section {
                ForEach(days, id: \.self) { day in
                    DayReminderRow(category: .training, weekday: day, isRest: plan.day(for: day)?.isRest ?? true)
                }
            } header: {
                Text("Recordatorio de entrenamiento")
            } footer: {
                Text("Solo se avisa en días con rutina planificada y aún sin asistencia. Los días de descanso de tu rutina no reciben aviso.")
            }
            Section {
                ForEach(days, id: \.self) { day in
                    DayReminderRow(category: .review, weekday: day, isRest: plan.day(for: day)?.isRest ?? true)
                }
            } header: {
                Text("Revisión de asistencia")
            } footer: {
                Text("“¿Cómo fue tu entrenamiento de hoy?” con las acciones Sí fui, Hoy descansé y Voy más tarde. Se cancela para ese día cuando registras una serie de trabajo o confirmas asistencia o descanso. Si entrenas a la hora de la revisión o después, se mueve dos horas más tarde.")
            }
            Section {
                ForEach(days, id: \.self) { day in
                    DayReminderRow(category: .photo, weekday: day, isRest: false)
                }
            } header: {
                Text("Recordatorio de fotos")
            } footer: {
                Text("Desactivado hasta que elijas un día y una hora.")
            }
            Section {
                ForEach(days, id: \.self) { day in
                    DayReminderRow(category: .summary, weekday: day, isRest: false)
                }
            } header: {
                Text("Resumen semanal")
            } footer: {
                Text("Desactivado por defecto. El aviso es una invitación genérica; las cifras se calculan al abrir la app.")
            }
            .accessibilityIdentifier("notifications.summary")
            Section {
                Text("Los avisos se programan en este dispositivo para las próximas 4 semanas y se renuevan al abrir Arco. iOS no permite comprobar condiciones cada noche: si no abres la app en ese tiempo, los avisos se detienen hasta la próxima apertura.")
                    .font(.footnote).foregroundStyle(.secondary)
                if appState.notificationStatus.allowsScheduling {
                    LabeledContent("Avisos programados", value: "\(pending.count)")
                }
            }
        }
        .navigationTitle("Recordatorios")
        .task { await refresh() }
        .onChange(of: rules.map { "\($0.categoryRaw)\($0.weekday ?? 0)\($0.hour)\($0.minute)\($0.enabled)" }) { _, _ in
            Task { await refresh() }
        }
    }

    @ViewBuilder
    private var permissionSection: some View {
        Section("Permiso del sistema") {
            LabeledContent("Estado", value: statusText)
            switch appState.notificationStatus {
            case .notDetermined:
                Button("Permitir avisos") {
                    Task {
                        _ = await appState.notifications.requestAuthorization()
                        await refresh()
                    }
                }
            case .denied:
                Text("Los avisos están desactivados en Ajustes. El resto de Arco funciona igual.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("Abrir Ajustes del sistema") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            default:
                EmptyView()
            }
        }
    }

    private var statusText: String {
        switch appState.notificationStatus {
        case .authorized: return "Permitidos"
        case .denied: return "Denegados"
        case .notDetermined: return "Sin decidir"
        case .provisional: return "Provisionales"
        case .ephemeral: return "Temporales"
        @unknown default: return "Desconocido"
        }
    }

    private func refresh() async {
        await appState.refreshReminders()
        pending = await NotificationService.pendingSummary()
    }
}

/// Fila de un día: activar y elegir hora y minutos. Crea o actualiza la regla de ese día.
private struct DayReminderRow: View {
    let category: ReminderCategory
    let weekday: Weekday
    let isRest: Bool

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Query private var rules: [ReminderRuleModel]

    private var rule: ReminderRuleModel? {
        rules.first { $0.categoryRaw == category.rawValue && $0.weekday == weekday.rawValue }
    }
    /// Regla general (sin día) usada como valor por defecto, p. ej. la revisión a las 21:00.
    private var generalRule: ReminderRuleModel? {
        rules.first { $0.categoryRaw == category.rawValue && $0.weekday == nil }
    }

    private var enabled: Bool { rule?.enabled ?? generalRule?.enabled ?? false }
    private var hour: Int { rule?.hour ?? generalRule?.hour ?? defaultHour }
    private var minute: Int { rule?.minute ?? generalRule?.minute ?? 0 }
    private var defaultHour: Int {
        switch category {
        case .review: return ReminderPlanner.defaultReviewHour
        case .training: return 18
        case .photo, .summary: return 10
        }
    }

    var body: some View {
        if isRest && category != .photo && category != .summary {
            LabeledContent(weekday.displayName, value: "Descanso planificado")
                .foregroundStyle(.secondary)
        } else {
            HStack {
                Toggle(weekday.displayName, isOn: Binding(get: { enabled }, set: { save(enabled: $0, time: time) }))
                if enabled {
                    DatePicker("Hora", selection: Binding(get: { time }, set: { save(enabled: true, time: $0) }), displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var time: Date {
        Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }

    private func save(enabled: Bool, time: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let model = rule ?? {
            let m = ReminderRuleModel(categoryRaw: category.rawValue, weekday: weekday.rawValue, hour: hour, minute: minute, enabled: enabled, timeZoneID: TimeZone.current.identifier)
            context.insert(m)
            return m
        }()
        model.enabled = enabled
        model.hour = c.hour ?? hour
        model.minute = c.minute ?? minute
        model.timeZoneID = TimeZone.current.identifier
        try? context.save()
        if enabled && appState.notificationStatus == .notDetermined {
            Task { _ = await appState.notifications.requestAuthorization(); await appState.refreshReminders() }
        }
    }
}
