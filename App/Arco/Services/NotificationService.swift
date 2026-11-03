//
//  NotificationService.swift
//  Arco
//
//  Servicio de notificaciones locales (spec §15 "Notificaciones locales y revisión
//  nocturna"). Usa exclusivamente UserNotifications; no hay servidor ni APNs para
//  los recordatorios definidos en el dispositivo. [A01]
//
//  Criterios de aceptación cubiertos (§22):
//   - T40: si el permiso se deniega la app sigue funcionando y se reporta el estado real.
//   - T41: una asistencia válida antes de la revisión cancela el aviso de ESA fecha,
//          sin tocar las semanas futuras (las revisiones se programan por fecha concreta).
//   - T42: una acción respondida al día siguiente se dirige a la fecha original del aviso
//          (identificadores deterministas con la fecha civil embebida).
//   - T43: posponer varias veces no duplica solicitudes ni cruza a otra fecha.
//   - T44: con sesión activa o entrenamiento posterior a la revisión, se reconcilia para
//          no mostrar avisos contradictorios.
//

import Foundation
import UserNotifications

// MARK: - Categorías e identificadores

/// Categorías de notificación de la app (spec §15 "Categorías").
///
/// El `rawValue` se usa como prefijo estable de los identificadores de solicitud, de modo
/// que podamos localizar y cancelar solicitudes por categoría + fecha sin ambigüedad.
public enum NotificationCategory: String, Sendable, CaseIterable {
    /// 1. Recordatorio de entrenamiento, horario independiente por día.
    case trainingReminder = "training-reminder"
    /// 2. Cambio "solo hoy", sin alterar todos los lunes posteriores.
    case trainingReminderToday = "training-reminder-today"
    /// 3. Revisión de asistencia: por defecto 21:00 en días planificados, editable/desactivable.
    case attendanceReview = "attendance-review"
    /// 4. Recordatorio semanal de fotos, desactivado hasta elegir día y hora.
    case photoReminder = "photo-reminder"
    /// 5. Resumen semanal opcional (invitación genérica; las cifras se calculan al abrir la app).
    case weeklySummary = "weekly-summary"

    /// Identificador de categoría registrado en el `UNUserNotificationCenter` para asociar
    /// las acciones interactivas (botones) con la categoría.
    var categoryIdentifier: String { "arco." + rawValue }
}

/// Acciones de la revisión de asistencia (spec §15 "Revisión de asistencia").
/// Son estables para poder enrutarlas desde el delegado del centro de notificaciones.
public enum AttendanceReviewAction: String, Sendable {
    case didAttend = "attendance.did-attend"     // "Sí fui"
    case didRest = "attendance.did-rest"          // "Hoy descansé"
    case later = "attendance.later"               // "Voy más tarde"
}

// MARK: - Servicio

/// Programa, reconcilia y cancela notificaciones locales.
///
/// Está marcado `@MainActor` porque toca `UNUserNotificationCenter` (API UI-bound) y porque
/// las decisiones de reconciliación se coordinan con el estado de la app. El trabajo que de
/// verdad podría tardar (consultas al centro) se expone como `async` y se apoya en
/// continuations sobre las APIs con callback; no se usan semáforos ni bloqueos (skill de
/// Swift Concurrency).
///
/// Importante sobre la "revisión nocturna" (spec §15 "Programación correcta"):
/// iOS NO ejecuta código arbitrario garantizado cada noche para consultar una condición.
/// Por eso NO programamos una única repetición semanal; programamos FECHAS CONCRETAS futuras
/// dentro de una ventana limitada y la reconciliamos cada vez que se abre la app, se cambian
/// ajustes o llega una acción. Si el usuario pasa mucho tiempo sin abrir la app, la ventana
/// se agota y dejan de llegar revisiones hasta la próxima apertura: eso es una limitación
/// real del sistema, no una promesa de programación condicional indefinida.
@MainActor
public final class NotificationService {

    /// Centro de notificaciones inyectable para poder sustituirlo en pruebas.
    private let center: UNUserNotificationCenter

    /// Límite real del sistema de notificaciones *pendientes* por app. Dejamos un margen de
    /// seguridad para no copar el presupuesto con un solo tipo de aviso.
    private let systemPendingLimit: Int = 64

    /// Formateador determinista para los sufijos de fecha de los identificadores.
    /// `yyyy-MM-dd` en calendario y zona fijos evita que un cambio de configuración regional
    /// mueva el identificador de una fecha ya programada (T42).
    private let identifierDateFormatter: DateFormatter

    public init(center: UNUserNotificationCenter = .current()) {
        self.center = center

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        self.identifierDateFormatter = formatter
    }

    // MARK: - Permisos (T40)

    /// Solicita permiso de notificaciones. Debe llamarse SOLO cuando el usuario habilita
    /// avisos (spec §15: "permisos solicitados cuando el usuario habilite avisos").
    ///
    /// Devuelve el estado real resultante. Si el usuario deniega, la app sigue funcionando y
    /// simplemente reporta el estado verdadero (T40). No pedimos `criticalAlert`: un
    /// recordatorio de gimnasio no justifica alertas críticas [A02].
    @discardableResult
    public func requestAuthorization() async -> UNAuthorizationStatus {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Un fallo al solicitar no debe romper la app; devolvemos el estado real.
        }
        return await currentStatus()
    }

    /// Estado actual de autorización, consultado en vivo (T40).
    public func currentStatus() async -> UNAuthorizationStatus {
        await authorizationStatus()
    }

    // MARK: - Registro de categorías interactivas

    /// Registra las categorías interactivas (botones de la revisión de asistencia).
    /// Debe invocarse una vez al arrancar la app para que las acciones aparezcan en el aviso.
    public func registerCategories() async {
        let later = UNNotificationAction(
            identifier: AttendanceReviewAction.later.rawValue,
            title: "Voy más tarde",
            options: []
        )
        let didAttend = UNNotificationAction(
            identifier: AttendanceReviewAction.didAttend.rawValue,
            title: "Sí fui",
            options: []
        )
        let didRest = UNNotificationAction(
            identifier: AttendanceReviewAction.didRest.rawValue,
            title: "Hoy descansé",
            options: []
        )

        let attendanceCategory = UNNotificationCategory(
            identifier: NotificationCategory.attendanceReview.categoryIdentifier,
            actions: [didAttend, didRest, later],
            intentIdentifiers: [],
            options: []
        )

        center.setNotificationCategories([attendanceCategory])
    }

    // MARK: - Recordatorio de entrenamiento (categoría 1)

    /// Programa (o cancela) el recordatorio de entrenamiento de un día de la semana.
    ///
    /// Este recordatorio sí es una repetición semanal legítima, porque no está condicionado a
    /// que ocurra algo esa noche (a diferencia de la revisión de asistencia). El horario es
    /// independiente por día (spec §15, categoría 1), así que cada weekday tiene su propia
    /// solicitud identificada de forma determinista.
    ///
    /// - Parameters:
    ///   - weekday: día de la semana en convención `DateComponents` (1 = domingo … 7 = sábado).
    ///   - enabled: si es `false`, se cancela la solicitud de ese día sin tocar los demás.
    public func scheduleTrainingReminder(weekday: Int, hour: Int, minute: Int, enabled: Bool) {
        let identifier = trainingReminderIdentifier(weekday: weekday)

        guard enabled else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let content = UNMutableNotificationContent()
        content.title = "Arco"
        content.body = "Es tu día de entrenar. ¿Empezamos?"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.trainingReminder.categoryIdentifier
        // Sin fotos, peso, PIN ni información privada en el aviso (spec §15).

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Revisión de asistencia (categoría 3)

    /// Programa una ventana futura de revisiones de asistencia en FECHAS CONCRETAS.
    ///
    /// No se usa una repetición semanal porque una revisión condicionada a la asistencia debe
    /// poder cancelarse por fecha sin reaparecer esa misma noche ya completada (spec §15
    /// "Programación correcta"). Cada fecha recibe su propia solicitud con identificador
    /// determinista `attendance-review-yyyy-MM-dd` (T41, T42).
    ///
    /// La hora se compone en la zona horaria indicada: los futuros avisos siguen la hora local
    /// elegida y se respetan los cambios de horario de verano porque usamos componentes de
    /// calendario, no instantes absolutos congelados (spec §15 "Respetar cambios de zona").
    ///
    /// - Parameters:
    ///   - plannedDates: fechas planificadas (cualquier instante dentro del día objetivo).
    ///   - hour: hora local de la revisión (por defecto 21).
    ///   - minute: minuto local (por defecto 0).
    ///   - timeZone: zona horaria con la que se interpreta la hora local.
    public func scheduleAttendanceReviews(
        plannedDates: [Date],
        hour: Int = 21,
        minute: Int = 0,
        timeZone: TimeZone = .current
    ) async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let now = Date()

        for date in plannedDates {
            // Solo fechas cuya revisión aún no ha pasado: no programamos el pasado.
            guard let fireDate = reviewFireDate(for: date, hour: hour, minute: minute, calendar: calendar),
                  fireDate > now else {
                continue
            }
            scheduleSingleAttendanceReview(on: date, fireDate: fireDate, calendar: calendar)
        }
    }

    /// Cancela la revisión de asistencia de UNA fecha concreta (T41).
    ///
    /// Al estar cada fecha en su propia solicitud, cancelar aquí no afecta a las semanas
    /// futuras ni a ninguna otra fecha. Se usa cuando se registra una asistencia válida antes
    /// de la hora de revisión, o cuando el usuario responde el aviso.
    public func cancelAttendanceReview(for date: Date) {
        let identifier = attendanceReviewIdentifier(for: date)
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        // También retiramos una posible entrega ya realizada para que no quede un aviso
        // "huérfano" en el centro tras confirmar la asistencia.
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    /// Pospone la revisión de asistencia de una fecha sin cruzar a otra fecha y sin duplicar
    /// solicitudes (T43).
    ///
    /// Reemplaza la solicitud existente por la misma fecha usando el mismo identificador
    /// determinista, de modo que `add` sustituye en lugar de añadir una segunda. Si el
    /// aplazamiento empujara el aviso a la fecha civil siguiente, se recorta al final del día
    /// de la revisión para no "cruzar de fecha inadvertidamente" (spec §15).
    ///
    /// - Parameters:
    ///   - date: fecha civil de la revisión (la del entrenamiento).
    ///   - minutes: minutos a posponer (p. ej. 30/60/120).
    public func snoozeAttendanceReview(for date: Date, minutes: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = identifierDateFormatter.timeZone ?? .current

        let identifier = attendanceReviewIdentifier(for: date)
        let now = Date()
        let proposed = now.addingTimeInterval(TimeInterval(minutes * 60))

        // No cruzar de fecha: limitamos al final del día civil de la revisión.
        guard let endOfDay = endOfCivilDay(for: date, calendar: calendar) else { return }
        let fireDate = min(proposed, endOfDay)

        // Si ya no cabe hoy (p. ej. se pospone pasada la medianoche lógica), no reprogramamos:
        // la revisión queda "sin confirmar" (spec §15) en lugar de saltar a mañana.
        guard fireDate > now, fireDate <= endOfDay else {
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            return
        }

        // Mismo identificador => sustituye la solicitud, no duplica (T43).
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let interval = max(1, fireDate.timeIntervalSince(now))
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(
            identifier: identifier,
            content: attendanceReviewContent(for: date),
            trigger: trigger
        )
        center.add(request)
    }

    // MARK: - Reconciliación de la ventana futura

    /// Rellena la ventana futura de revisiones respetando el límite real del sistema de
    /// notificaciones pendientes (spec §15 "Consulta los límites vigentes … prioriza
    /// recordatorios elegidos por el usuario").
    ///
    /// Estrategia:
    ///  1. Consulta `pendingNotificationRequests` para conocer el presupuesto ya usado.
    ///  2. Reserva el espacio de los recordatorios elegidos por el usuario (entrenamiento,
    ///     fotos, resumen): tienen prioridad y no se recortan.
    ///  3. Con el presupuesto restante, programa tantas revisiones de asistencia futuras como
    ///     quepan, en orden cronológico (las más próximas primero).
    ///
    /// Debe llamarse al abrir la app, al cambiar ajustes y al recibir una acción (T44), para
    /// mantener la ventana y evitar avisos contradictorios.
    public func reconcilePendingWindow(
        plannedDates: [Date],
        hour: Int = 21,
        minute: Int = 0,
        timeZone: TimeZone = .current
    ) async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let now = Date()

        let pending = await pendingIdentifiers()

        // Prioridad a los recordatorios elegidos por el usuario: cuentan contra el límite pero
        // nunca se recortan para hacer sitio a revisiones de asistencia.
        let userChosenPrefixes = [
            NotificationCategory.trainingReminder.rawValue,
            NotificationCategory.trainingReminderToday.rawValue,
            NotificationCategory.photoReminder.rawValue,
            NotificationCategory.weeklySummary.rawValue
        ]
        let userChosenCount = pending.filter { identifier in
            userChosenPrefixes.contains { identifier.hasPrefix($0) }
        }.count

        // Identificadores de revisión ya pendientes, para no duplicar y para saber cuáles
        // siguen vigentes.
        let existingReviewIdentifiers = Set(
            pending.filter { $0.hasPrefix(NotificationCategory.attendanceReview.rawValue) }
        )

        // Presupuesto disponible para revisiones de asistencia.
        let budgetForReviews = max(0, systemPendingLimit - userChosenCount)

        // Fechas futuras candidatas, en orden cronológico ascendente.
        let candidates = plannedDates
            .compactMap { date -> (date: Date, fire: Date, id: String)? in
                guard let fire = reviewFireDate(for: date, hour: hour, minute: minute, calendar: calendar),
                      fire > now else { return nil }
                return (date, fire, attendanceReviewIdentifier(for: date))
            }
            .sorted { $0.fire < $1.fire }

        // Reprograma hasta agotar el presupuesto. Reutiliza identificadores existentes (no
        // duplica) y solo añade las que caben.
        var scheduledReviewIdentifiers = Set<String>()
        for (index, candidate) in candidates.enumerated() {
            guard index < budgetForReviews else { break }
            scheduledReviewIdentifiers.insert(candidate.id)
            // `add` con el mismo identificador sustituye; es idempotente.
            scheduleSingleAttendanceReview(on: candidate.date, fireDate: candidate.fire, calendar: calendar)
        }

        // Limpia revisiones que ya no deberían existir (p. ej. quedaron fuera de la ventana o
        // de la planificación actual) para no dejar avisos obsoletos (T44).
        let toRemove = existingReviewIdentifiers.subtracting(scheduledReviewIdentifiers)
        if !toRemove.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(toRemove))
        }
    }

    // MARK: - Helpers de programación

    private func scheduleSingleAttendanceReview(on date: Date, fireDate: Date, calendar: Calendar) {
        let identifier = attendanceReviewIdentifier(for: date)

        // Usamos componentes de calendario (no un instante absoluto) para respetar cambios de
        // zona/horario de verano entre la programación y el disparo (spec §15).
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: attendanceReviewContent(for: date),
            trigger: trigger
        )
        // Mismo identificador => idempotente: reprogramar no duplica (T42, T43).
        center.add(request)
    }

    /// Contenido del aviso de revisión de asistencia. Embebe la fecha civil objetivo en
    /// `userInfo` para que la acción se dirija a la fecha ORIGINAL aunque se pulse al día
    /// siguiente (T42). El mensaje es discreto (spec §15 "Revisión de asistencia").
    private func attendanceReviewContent(for date: Date) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = "Arco"
        content.body = "¿Cómo fue tu entrenamiento de hoy?"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.attendanceReview.categoryIdentifier
        // Clave determinista de fecha (yyyy-MM-dd) para enrutar la acción a su fecha original.
        content.userInfo = [
            "category": NotificationCategory.attendanceReview.rawValue,
            "reviewDate": identifierDateFormatter.string(from: date)
        ]
        return content
    }

    /// Instante de disparo de la revisión para una fecha dada (hora local indicada).
    private func reviewFireDate(for date: Date, hour: Int, minute: Int, calendar: Calendar) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }

    /// Último instante del día civil de la revisión (para el tope de posponer, T43).
    private func endOfCivilDay(for date: Date, calendar: Calendar) -> Date? {
        guard let startOfNextDay = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: date)
        ) else { return nil }
        return startOfNextDay.addingTimeInterval(-1)
    }

    // MARK: - Identificadores deterministas

    /// `attendance-review-yyyy-MM-dd` (spec §15 / T42).
    func attendanceReviewIdentifier(for date: Date) -> String {
        "\(NotificationCategory.attendanceReview.rawValue)-\(identifierDateFormatter.string(from: date))"
    }

    /// `training-reminder-weekday-N` (horario independiente por día, categoría 1).
    func trainingReminderIdentifier(weekday: Int) -> String {
        "\(NotificationCategory.trainingReminder.rawValue)-weekday-\(weekday)"
    }

    // MARK: - Puentes async/await sobre APIs con callback

    /// Envuelve `getNotificationSettings` (callback) en async/await sin semáforos.
    /// Estado de autorización como valor Sendable (`UNAuthorizationStatus` es Sendable),
    /// extraído dentro del contexto nonisolated para no cruzar el objeto settings.
    private nonisolated func authorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    /// Identificadores de las solicitudes pendientes como `[String]` (Sendable), extraídos
    /// dentro del contexto nonisolated para no cruzar los objetos `UNNotificationRequest`.
    private nonisolated func pendingIdentifiers() async -> [String] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests.map(\.identifier))
            }
        }
    }
}
