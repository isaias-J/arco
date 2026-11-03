import SwiftUI
import SwiftData
import ArcoCore

/// Construye el resumen semanal con los registros reales (spec §3.14): semana calendario de la
/// app, sesiones con series de trabajo, series de trabajo, semana anterior completa,
/// asistencia frente a días planificados transcurridos (plan vigente en cada fecha) y racha.
@MainActor
enum WeeklySummaryBuilder {
    static func summary(weekOffset: Int, sessions: [WorkoutSessionModel], appState: AppState, now: Date = Date()) -> WeeklySummary? {
        let cal = appState.calendar
        guard let current = cal.dateInterval(of: .weekOfYear, for: now),
              let start = cal.date(byAdding: .weekOfYear, value: weekOffset, to: current.start),
              let end = cal.date(byAdding: .weekOfYear, value: 1, to: start),
              let previousStart = cal.date(byAdding: .weekOfYear, value: -1, to: start)
        else { return nil }
        let isPartial = now < end

        func workingSets(_ s: WorkoutSessionModel) -> Int {
            s.exercises.reduce(0) { total, se in total + se.sets.filter { $0.toDomain().isEligibleForWorkCount }.count }
        }
        let inWeek = sessions.filter { $0.trainingDate >= start && $0.trainingDate < end }
        let perSession = inWeek.map(workingSets)
        let previous = sessions
            .filter { $0.trainingDate >= previousStart && $0.trainingDate < start }
            .map(workingSets).reduce(0, +)

        let history = appState.planHistory
        let attendance = appState.attendance
        let attended = attendance.attendedDays()
        let restDays = Set(attendance.resolutions().filter { $0.value == .rest }.keys)
        let today = CivilDay(now, calendar: cal)
        let completed = Set(sessions.filter { $0.stateRaw == "finished" }.map { CivilDay($0.trainingDate, calendar: cal) })
        let adherence = Constancy.adherence(
            history: history,
            from: CivilDay(start, calendar: cal),
            to: CivilDay(end.addingTimeInterval(-1), calendar: cal),
            today: today, attended: attended, completedSessions: completed, calendar: cal
        )
        // La racha es un dato de hoy: solo se muestra en la semana en curso.
        let streak = weekOffset == 0
            ? Constancy.streak(history: history, today: today, attended: attended, restResolutions: restDays, calendar: cal)
            : 0

        let groupCounts = MuscleCounter.countByGroup(
            MuscleWeek.filter(MuscleProgressData.attributedSets(inWeek, context: appState.context), from: start, to: end)
        )
        let top = groupCounts.values
            .filter { $0.direct > 0 }
            .sorted { $0.direct != $1.direct ? $0.direct > $1.direct : $0.group.rawValue < $1.group.rawValue }
            .prefix(3)
            .map { (group: $0.group, direct: $0.direct) }

        return WeeklySummary(
            start: start, end: end, isPartial: isPartial,
            sessions: perSession.filter { $0 > 0 }.count,
            workingSets: perSession.reduce(0, +),
            previousWeekWorkingSets: previous,
            attendedDays: adherence.attendedDays, plannedDays: adherence.plannedDays,
            topGroups: Array(top), streak: streak
        )
    }
}

/// Tarjeta breve de Hoy: 1–2 mensajes del resumen de la semana en curso.
struct WeeklySummaryCompactCard: View {
    @Environment(AppState.self) private var appState
    @Query private var sessions: [WorkoutSessionModel]
    @Query private var events: [AttendanceEventModel]
    @Query private var resolutions: [AttendanceResolutionModel]
    @Query private var planVersions: [PlanVersionModel]

    var body: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Esta semana").font(.headline)
                if let summary = WeeklySummaryBuilder.summary(weekOffset: 0, sessions: sessions, appState: appState) {
                    ForEach(Array(summary.messages.filter { !$0.hasPrefix("Racha") }.prefix(2).enumerated()), id: \.offset) { _, message in
                        Text(message).font(.subheadline).monospacedDigit()
                    }
                    Text("Racha actual: \(summary.streak) \(summary.streak == 1 ? "día planificado cumplido" : "días planificados cumplidos seguidos")")
                        .font(.subheadline).monospacedDigit()
                }
                Text("Los descansos planificados no cuentan en contra.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("today.weekSummary")
        }
    }
}

/// Tarjeta de Progreso: todos los mensajes, con selector esta semana / semana anterior.
struct WeeklySummaryCard: View {
    @Environment(AppState.self) private var appState
    @Query private var sessions: [WorkoutSessionModel]
    @Query private var events: [AttendanceEventModel]
    @Query private var resolutions: [AttendanceResolutionModel]
    @Query private var planVersions: [PlanVersionModel]
    @State private var weekOffset = 0

    var body: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Resumen semanal").font(.headline)
                Picker("Semana", selection: $weekOffset) {
                    Text("Esta semana").tag(0)
                    Text("Semana anterior").tag(-1)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("progress.summary.week")
                if let summary = WeeklySummaryBuilder.summary(weekOffset: weekOffset, sessions: sessions, appState: appState) {
                    Text("\(ProfileFormat.date(summary.start)) – \(ProfileFormat.date(summary.end.addingTimeInterval(-1)))")
                        .font(.caption).foregroundStyle(.secondary)
                    if summary.isPartial {
                        Label("Semana en curso, incompleta", systemImage: "clock.badge.exclamationmark")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(Array(summary.messages.enumerated()), id: \.offset) { _, message in
                        Text(message).font(.subheadline).monospacedDigit()
                    }
                    if !summary.topGroups.isEmpty {
                        Text("Más series directas: \(summary.topGroups.map { "\($0.group.displayName) (\($0.direct))" }.joined(separator: ", ")).")
                            .font(.subheadline).monospacedDigit()
                    }
                    Text("Calculado ahora en este iPhone con tus registros. La asistencia usa la rutina vigente en cada fecha.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("progress.weekSummary")
        }
    }
}
