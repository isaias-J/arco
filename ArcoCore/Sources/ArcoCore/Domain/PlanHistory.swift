import Foundation

/// Historial de versiones del plan semanal (spec §14): cada fecha se evalúa con el plan que
/// estaba vigente ese día, de modo que cambiar la rutina hoy no altera el pasado (T39).
public struct PlanHistory: Sendable, Equatable {
    public struct Version: Sendable, Equatable {
        public let validFrom: Date
        public let plan: WeeklyPlan
        public init(validFrom: Date, plan: WeeklyPlan) { self.validFrom = validFrom; self.plan = plan }
    }

    public let versions: [Version]

    public init(versions: [Version]) {
        self.versions = versions.sorted { $0.validFrom < $1.validFrom }
    }

    /// Plan vigente en `date`. Antes de la primera versión no hay plan conocido (nil): no se
    /// inventa un denominador de adherencia.
    public func plan(on date: Date) -> WeeklyPlan? {
        versions.last { $0.validFrom <= date }?.plan
    }

    public static func encode(_ plan: WeeklyPlan) -> String {
        let data = (try? JSONEncoder().encode(plan.days)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    public static func decode(_ json: String) -> WeeklyPlan? {
        guard let days = try? JSONDecoder().decode([WeeklyPlan.Day].self, from: Data(json.utf8)) else { return nil }
        return WeeklyPlan(days: days)
    }
}

/// Adherencia y constancia calculadas con el plan de cada fecha (spec §14).
public enum Constancy {

    /// Métricas en [start, end] (fechas civiles), excluyendo días futuros respecto de `today`.
    public static func adherence(
        history: PlanHistory,
        from start: CivilDay,
        to end: CivilDay,
        today: CivilDay,
        attended: Set<CivilDay>,
        completedSessions: Set<CivilDay>,
        calendar: Calendar
    ) -> AdherenceMetrics {
        var planned = 0, attendedCount = 0, completed = 0
        var day = start
        while day <= end && day <= today {
            if let date = day.startDate(in: calendar), let plan = history.plan(on: date), plan.isPlannedTraining(date, calendar: calendar) {
                planned += 1
                if completedSessions.contains(day) { completed += 1 }
            }
            if attended.contains(day) { attendedCount += 1 }
            guard let next = day.adding(days: 1, calendar: calendar) else { break }
            day = next
        }
        return AdherenceMetrics(attendedDays: attendedCount, completedSessions: completed, plannedDays: planned)
    }

    /// Racha de oportunidades planificadas cumplidas, contando hacia atrás desde hoy.
    /// - Los descansos planificados no la rompen ni la aumentan.
    /// - Un descanso puntual confirmado es neutro (no se culpa por descansar).
    /// - Hoy, si aún no hay asistencia, no rompe la racha (el día no ha terminado).
    /// - Entrenar en un día de descanso suma, pero un descanso nunca resta.
    public static func streak(
        history: PlanHistory,
        today: CivilDay,
        attended: Set<CivilDay>,
        restResolutions: Set<CivilDay>,
        calendar: Calendar,
        maxDays: Int = 730
    ) -> Int {
        var count = 0
        var day = today
        for _ in 0..<maxDays {
            guard let date = day.startDate(in: calendar) else { break }
            guard let plan = history.plan(on: date) else { break }
            if attended.contains(day) {
                count += 1
            } else if plan.isPlannedTraining(date, calendar: calendar) && day != today && !restResolutions.contains(day) {
                break
            }
            guard let previous = day.adding(days: -1, calendar: calendar) else { break }
            day = previous
        }
        return count
    }
}

/// Resumen semanal calculado con los registros reales (spec §3.14). Sin promesas ni culpa.
public struct WeeklySummary: Sendable, Equatable {
    public let start: Date
    public let end: Date
    public let isPartial: Bool
    public let sessions: Int
    public let workingSets: Int
    public let previousWeekWorkingSets: Int?
    public let attendedDays: Int
    public let plannedDays: Int
    public let topGroups: [(group: MuscleGroup, direct: Int)]
    public let streak: Int

    public static func == (a: WeeklySummary, b: WeeklySummary) -> Bool {
        a.start == b.start && a.sessions == b.sessions && a.workingSets == b.workingSets
            && a.attendedDays == b.attendedDays && a.plannedDays == b.plannedDays && a.streak == b.streak
            && a.topGroups.map(\.group) == b.topGroups.map(\.group)
    }

    /// Mensajes basados solo en datos (spec §3.14). Nunca "fallaste" ni promesas de resultado.
    public var messages: [String] {
        var out: [String] = []
        if sessions == 0 {
            out.append(isPartial ? "Aún no hay sesiones registradas esta semana." : "No hubo sesiones registradas esa semana.")
        } else {
            out.append("\(sessions) \(sessions == 1 ? "sesión" : "sesiones") y \(workingSets) series de trabajo\(isPartial ? " hasta hoy" : "").")
        }
        if plannedDays > 0 {
            out.append("Asistencia: \(attendedDays) de \(plannedDays) días planificados\(isPartial ? " transcurridos" : "").")
        }
        if let prev = previousWeekWorkingSets, !isPartial {
            if prev == 0 {
                out.append("La semana anterior no tuvo series registradas.")
            } else {
                let diff = workingSets - prev
                out.append(diff == 0 ? "Mismo número de series que la semana anterior." : "\(abs(diff)) series \(diff > 0 ? "más" : "menos") que la semana anterior.")
            }
        }
        if streak >= 2 {
            out.append("Racha: \(streak) días de entrenamiento planificado cumplidos seguidos.")
        }
        return out
    }
}
