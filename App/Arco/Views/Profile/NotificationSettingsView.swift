import SwiftUI
import SwiftData
import UserNotifications
import ArcoCore

/// Ajustes de recordatorios locales (spec §15). La app funciona si el permiso se deniega:
/// muestra el estado real y da acceso a Ajustes del sistema (T40). Sin servidor ni APNs.
struct NotificationSettingsView: View {
    @Environment(AppState.self) private var appState
    @Query private var templates: [RoutineTemplateModel]

    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var trainingEnabled = false
    @State private var trainingHour = 18
    @State private var attendanceReviewEnabled = true
    @State private var reviewHour = 21

    var body: some View {
        Form {
            permissionSection
            trainingSection
            attendanceSection
            explanationSection
        }
        .navigationTitle("Recordatorios")
        .task { status = await appState.notifications.currentStatus() }
    }

    // MARK: - Secciones

    @ViewBuilder
    private var permissionSection: some View {
        Section("Permiso") {
            HStack {
                Text("Estado")
                Spacer()
                Text(statusText).foregroundStyle(.secondary)
            }
            switch status {
            case .notDetermined:
                Button("Activar notificaciones") {
                    Task { status = await appState.notifications.requestAuthorization() }
                }
            case .denied:
                // T40: la app funciona; se ofrece ir a Ajustes, sin bloquear nada.
                Button("Abrir Ajustes del sistema") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            default:
                EmptyView()
            }
        }
    }

    private var trainingSection: some View {
        Section("Recordatorio de entrenamiento") {
            Toggle("Recordarme entrenar", isOn: $trainingEnabled)
            if trainingEnabled {
                Stepper("Hora: \(trainingHour):00", value: $trainingHour, in: 5...22)
                Text("Se programa un aviso por cada día con rutina planificada, a la hora elegida.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onChange(of: trainingEnabled) { _, _ in applyTrainingReminders() }
        .onChange(of: trainingHour) { _, _ in applyTrainingReminders() }
    }

    private var attendanceSection: some View {
        Section("Revisión de asistencia") {
            Toggle("Preguntar por la noche", isOn: $attendanceReviewEnabled)
            if attendanceReviewEnabled {
                Stepper("Hora: \(reviewHour):00", value: $reviewHour, in: 18...23)
                Text("En días planificados se te preguntará \"¿Cómo fue tu entrenamiento?\". Si ya registraste series antes de esa hora, el aviso de ese día se cancela.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .onChange(of: attendanceReviewEnabled) { _, _ in applyAttendanceReviews() }
        .onChange(of: reviewHour) { _, _ in applyAttendanceReviews() }
    }

    private var explanationSection: some View {
        Section {
            Text("Los recordatorios se programan y se guardan solo en este dispositivo. iOS no garantiza ejecutar comprobaciones cada noche: Arco repone los avisos pendientes cuando abres la app.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Lógica

    private var statusText: String {
        switch status {
        case .authorized: return "Autorizado"
        case .denied: return "Denegado"
        case .notDetermined: return "Sin decidir"
        case .provisional: return "Provisional"
        case .ephemeral: return "Temporal"
        @unknown default: return "Desconocido"
        }
    }

    private func applyTrainingReminders() {
        // Un recordatorio semanal por cada weekday con rutina no-descanso.
        let plannedWeekdays = templates.filter { !$0.isRestDay }.map { modelToCalendarWeekday($0.weekday) }
        for wd in 1...7 {
            let enabled = trainingEnabled && plannedWeekdays.contains(wd)
            appState.notifications.scheduleTrainingReminder(weekday: wd, hour: trainingHour, minute: 0, enabled: enabled)
        }
    }

    private func applyAttendanceReviews() {
        Task {
            guard attendanceReviewEnabled else {
                // Cancelar la ventana futura de revisiones si se desactiva.
                await appState.notifications.reconcilePendingWindow(plannedDates: [], hour: reviewHour, minute: 0, timeZone: .current)
                return
            }
            let dates = upcomingPlannedDates()
            await appState.notifications.scheduleAttendanceReviews(plannedDates: dates, hour: reviewHour, minute: 0, timeZone: .current)
        }
    }

    /// Fechas planificadas en las próximas ~8 semanas (ventana futura acotada, spec §15).
    private func upcomingPlannedDates() -> [Date] {
        let calendar = Calendar.current
        let plannedWeekdays = Set(templates.filter { !$0.isRestDay }.map { modelToCalendarWeekday($0.weekday) })
        var result: [Date] = []
        for dayOffset in 0..<56 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: Date()) else { continue }
            if plannedWeekdays.contains(calendar.component(.weekday, from: date)) {
                result.append(date)
            }
        }
        return result
    }

    /// Modelo (1=lunes…7=domingo) → Calendar (1=domingo…7=sábado).
    private func modelToCalendarWeekday(_ modelWeekday: Int) -> Int {
        modelWeekday == 7 ? 1 : modelWeekday + 1
    }
}
