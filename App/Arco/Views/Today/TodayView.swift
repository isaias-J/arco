import SwiftUI
import SwiftData
import ArcoCore

/// Pantalla Hoy (spec §8): fecha, rutina del plan para hoy, sesión activa si existe y acceso
/// principal a empezar o reanudar. Más tranquila que el panel de progreso.
struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Query private var templates: [RoutineTemplateModel]
    @Query(filter: #Predicate<WorkoutSessionModel> { $0.stateRaw == "active" }, sort: \WorkoutSessionModel.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSessionModel]
    @Query private var events: [AttendanceEventModel]
    @State private var path = NavigationPath()

    /// Plantilla del día según la convención única de weekday (Calendar: 1 = domingo).
    private var todayTemplate: RoutineTemplateModel? {
        let weekday = Weekday.of(Date(), calendar: appState.calendar)
        return templates.first { $0.weekday == weekday.rawValue }
    }

    private var weekAttendance: Int {
        let cal = appState.calendar
        guard let week = cal.dateInterval(of: .weekOfYear, for: Date()) else { return 0 }
        return Set(events.filter { week.contains($0.trainingDate) }.map { CivilDay($0.trainingDate, calendar: cal) }).count
    }

    private var plannedThisWeek: Int {
        WeeklyPlan(templates: templates).trainingWeekdays.count
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    if let session = activeSessions.first {
                        ArcoCard {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Label("Sesión en curso", systemImage: "play.circle.fill").font(.headline)
                                Text("Empezada \(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(session.exercises.count) ejercicios")
                                    .font(.footnote).foregroundStyle(.secondary)
                                NavigationLink(value: session.id) {
                                    Text("Reanudar entrenamiento").frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("today.resume")
                            }
                        }
                    } else {
                        planCard
                    }
                    constancyCard
                }
                .padding(Spacing.lg)
            }
            .background(ArcoColor.background)
            .navigationTitle("Hoy")
            .navigationDestination(for: UUID.self) { id in
                if let session = activeSessions.first(where: { $0.id == id }) ?? fetchSession(id) {
                    SessionView(session: session)
                }
            }
        }
    }

    private func fetchSession(_ id: UUID) -> WorkoutSessionModel? {
        let predicate = #Predicate<WorkoutSessionModel> { $0.id == id }
        return (try? appState.context.fetch(FetchDescriptor(predicate: predicate)))?.first
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.title2.bold())
            if let t = todayTemplate {
                Text(t.isRestDay ? "Descanso planificado" : t.name)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("today.routine")
            } else {
                Text("Sin rutina para hoy").foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var planCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let t = todayTemplate, t.isRestDay {
                    Text("Hoy es un día de descanso planificado. Puedes entrenar igualmente si quieres.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                NavigationLink {
                    ExerciseSelectionView(template: todayTemplate) { session in
                        path.append(session.id)
                    }
                } label: {
                    Label("Empezar entrenamiento", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("today.start")
            }
        }
    }

    private var constancyCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Esta semana").font(.headline)
                Text("\(weekAttendance) de \(plannedThisWeek) días planificados con asistencia")
                    .font(.subheadline)
                    .monospacedDigit()
                Text("Los descansos planificados no cuentan en contra.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
