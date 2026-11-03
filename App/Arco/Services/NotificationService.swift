//
//  NotificationService.swift
//  Arco
//
//  Avisos locales (spec §15). Solo UserNotifications: sin servidor ni APNs [A01].
//
//  Modelo: `ReminderPlanner` (ArcoCore) calcula qué avisos deben existir en una ventana
//  futura de fechas concretas; este servicio sincroniza esa lista con las solicitudes
//  pendientes del sistema (añade, actualiza y retira). Cada aviso se identifica por
//  categoría + fecha civil ("arco.review.2026-11-05"), así que cancelar o responder uno afecta
//  solo a esa fecha (T41, T42). iOS no ejecuta código cada noche: la ventana se repone al abrir
//  la app, al cambiar ajustes, al registrar asistencia y al responder un aviso. Si la app no se
//  abre durante más de 4 semanas, los avisos se agotan hasta la siguiente apertura.
//

import Foundation
import UserNotifications
import ArcoCore

/// Acciones del aviso de revisión de asistencia (spec §15).
enum AttendanceReviewAction: String, Sendable {
    case didAttend = "attendance.did-attend"     // "Sí fui"
    case didRest = "attendance.did-rest"         // "Hoy descansé"
    case later = "attendance.later"              // "Voy más tarde" (abre la app para elegir)
}

@MainActor
final class NotificationService {

    nonisolated static let reviewCategoryID = "arco.category.review"
    nonisolated static let prefix = "arco."

    // MARK: - Permisos (T40)

    /// Pide permiso SOLO cuando el usuario activa avisos. Sin alertas críticas [A02].
    @discardableResult
    func requestAuthorization() async -> UNAuthorizationStatus {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        return await currentStatus()
    }

    /// Estado real del permiso.
    func currentStatus() async -> UNAuthorizationStatus {
        await Self.authorizationStatus()
    }

    // MARK: - Categorías interactivas

    /// Registra las acciones de la revisión. Se llama al arrancar la app.
    func registerCategories() {
        let didAttend = UNNotificationAction(identifier: AttendanceReviewAction.didAttend.rawValue, title: "Sí fui", options: [])
        let didRest = UNNotificationAction(identifier: AttendanceReviewAction.didRest.rawValue, title: "Hoy descansé", options: [])
        // "Voy más tarde" abre la app para ofrecer 30/60/120 minutos (spec §15).
        let later = UNNotificationAction(identifier: AttendanceReviewAction.later.rawValue, title: "Voy más tarde", options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.reviewCategoryID, actions: [didAttend, didRest, later], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // MARK: - Sincronización con el plan

    /// Sustituye las solicitudes pendientes de Arco por las planificadas. Sin permiso, retira
    /// todo y no programa nada (la app sigue funcionando — T40).
    func apply(_ planned: [PlannedReminder], calendar: Calendar, authorized: Bool) async {
        let center = UNUserNotificationCenter.current()
        let pending = await Self.pendingIdentifiers().filter { $0.hasPrefix(Self.prefix) }
        let wanted = authorized ? planned : []
        let wantedIDs = Set(wanted.map(\.id))
        let obsolete = pending.filter { !wantedIDs.contains($0) }
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
        }
        // Retirar del centro las revisiones ya entregadas cuyo día quedó resuelto.
        let delivered = await Self.deliveredIdentifiers().filter { $0.hasPrefix(Self.prefix) }
        let resolvedDelivered = delivered.filter { id in
            guard let parsed = ReminderPlanner.parse(id), parsed.category == .review else { return false }
            return !wantedIDs.contains(id) && parsed.day < CivilDay(Date(), calendar: calendar).adding(days: 1, calendar: calendar)!
        }
        if !resolvedDelivered.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: resolvedDelivered)
        }
        for reminder in wanted {
            let content = Self.content(for: reminder)
            var components = DateComponents(year: reminder.day.year, month: reminder.day.month, day: reminder.day.day, hour: reminder.hour, minute: reminder.minute)
            components.calendar = calendar
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            // Mismo identificador => sustituye; nunca duplica (T43).
            try? await center.add(UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger))
        }
    }

    /// Texto de cada aviso. Sin fotos, peso, PIN ni datos privados (spec §15).
    static func content(for reminder: PlannedReminder) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = "Arco"
        c.sound = .default
        c.userInfo = ["day": reminder.day.key, "category": reminder.category.rawValue]
        switch reminder.category {
        case .training:
            c.body = "Hoy tienes entrenamiento planificado."
        case .review:
            c.body = "¿Cómo fue tu entrenamiento de hoy?"
            c.categoryIdentifier = reviewCategoryID
        case .photo:
            c.body = "Si quieres, es buen momento para tu foto de progreso."
        case .summary:
            c.body = "Tu resumen semanal está disponible en la app."
        }
        return c
    }

    // MARK: - Puentes sobre APIs con callback

    nonisolated static func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    nonisolated static func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }

    nonisolated static func deliveredIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getDeliveredNotifications { notes in
                continuation.resume(returning: notes.map(\.request.identifier))
            }
        }
    }

    /// Identificadores pendientes con su fecha y hora (para mostrar el estado real en ajustes).
    nonisolated static func pendingSummary() async -> [String] {
        await pendingIdentifiers().filter { $0.hasPrefix(prefix) }.sorted()
    }
}

/// Delegado del centro de avisos: enruta las acciones a la fecha del aviso, aunque se pulsen
/// al día siguiente (T42). Las acciones son idempotentes.
final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    // Invariante: `appState` solo se lee/escribe en el actor principal (se asigna en el
    // arranque de la app y se usa dentro de `MainActor.run`).
    nonisolated(unsafe) weak var appState: AppState?

    static let shared = NotificationCoordinator()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        let actionID = response.actionIdentifier
        guard let parsed = ReminderPlanner.parse(identifier), parsed.category == .review,
              let action = AttendanceReviewAction(rawValue: actionID) else { return }
        await MainActor.run {
            guard let state = self.appState else { return }
            Task { await state.handleAttendanceAction(action, day: parsed.day) }
        }
    }
}
