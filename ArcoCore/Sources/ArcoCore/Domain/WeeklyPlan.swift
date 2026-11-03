import Foundation

/// Convención ÚNICA de días de la semana en todo Arco: la de `Calendar` de Apple
/// (gregoriano): 1 = domingo, 2 = lunes, 3 = martes, 4 = miércoles, 5 = jueves,
/// 6 = viernes, 7 = sábado. `RoutineTemplateModel.weekday` y `ReminderRuleModel.weekday`
/// se guardan en esta convención; ninguna vista debe convertirla.
public enum Weekday: Int, CaseIterable, Sendable, Codable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    /// Día de la semana de una fecha según el calendario dado.
    public static func of(_ date: Date, calendar: Calendar) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
    }

    /// Orden de presentación empezando por lunes (o domingo si se configura).
    public static func ordered(startingMonday: Bool) -> [Weekday] {
        startingMonday
            ? [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]
            : [.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday]
    }

    public var displayName: String {
        switch self {
        case .sunday: return "Domingo"
        case .monday: return "Lunes"
        case .tuesday: return "Martes"
        case .wednesday: return "Miércoles"
        case .thursday: return "Jueves"
        case .friday: return "Viernes"
        case .saturday: return "Sábado"
        }
    }
}

/// Plan semanal: qué días se entrena y qué días son descanso planificado (spec §2, §14).
public struct WeeklyPlan: Sendable, Equatable {
    public struct Day: Sendable, Equatable, Codable {
        public let weekday: Weekday
        public let isRest: Bool
        public let groups: [MuscleGroup]
        public init(weekday: Weekday, isRest: Bool, groups: [MuscleGroup]) {
            self.weekday = weekday
            self.isRest = isRest
            self.groups = groups
        }
    }

    public let days: [Day]

    public init(days: [Day]) { self.days = days }

    /// Rutina confirmada por el propietario: lunes empuje, martes tirón, miércoles pierna y
    /// abdomen, viernes tren superior y antebrazo, sábado pierna y abdomen; jueves y domingo
    /// descanso planificado (spec §2).
    public static let ownerDefault = WeeklyPlan(days: [
        Day(weekday: .monday, isRest: false, groups: [.chest, .shoulders, .triceps]),
        Day(weekday: .tuesday, isRest: false, groups: [.back, .biceps]),
        Day(weekday: .wednesday, isRest: false, groups: [.legs, .core]),
        Day(weekday: .thursday, isRest: true, groups: []),
        Day(weekday: .friday, isRest: false, groups: [.chest, .back, .shoulders, .biceps, .triceps, .forearm]),
        Day(weekday: .saturday, isRest: false, groups: [.legs, .core]),
        Day(weekday: .sunday, isRest: true, groups: [])
    ])

    public func day(for weekday: Weekday) -> Day? {
        days.first { $0.weekday == weekday }
    }

    /// ¿Hay entrenamiento planificado ese día? Sin plan para ese día => no planificado.
    public func isPlannedTraining(_ date: Date, calendar: Calendar) -> Bool {
        guard let d = day(for: .of(date, calendar: calendar)) else { return false }
        return !d.isRest
    }

    /// ¿Es descanso planificado ese día?
    public func isPlannedRest(_ date: Date, calendar: Calendar) -> Bool {
        day(for: .of(date, calendar: calendar))?.isRest ?? false
    }

    public var trainingWeekdays: Set<Weekday> {
        Set(days.filter { !$0.isRest }.map(\.weekday))
    }

    /// Fechas planificadas de entrenamiento en `[start, start + days)`.
    public func plannedTrainingDates(from start: Date, days count: Int, calendar: Calendar) -> [Date] {
        let first = calendar.startOfDay(for: start)
        return (0..<max(0, count)).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: first) else { return nil }
            return isPlannedTraining(date, calendar: calendar) ? date : nil
        }
    }
}
