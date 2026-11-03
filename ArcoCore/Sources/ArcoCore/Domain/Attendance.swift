import Foundation

/// Procedencia de un evento de asistencia (spec §14).
public enum AttendanceSource: String, Sendable, Equatable {
    case automatic   // creada al confirmar la primera serie de trabajo elegible
    case manual      // "sí fui" sin inventar series
}

/// Estado de una celda del calendario (spec §14).
public enum CalendarDayState: String, Sendable, Equatable {
    case trainedRegistered      // entrenamiento registrado
    case manualAttendance       // asistencia manual
    case plannedRest            // descanso planificado
    case confirmedRest          // descanso puntual confirmado
    case plannedUnconfirmed     // planificado sin registro, sin confirmar
    case confirmedAbsence       // ausencia confirmada
    case future                 // futuro
    case notTracked             // antes de empezar a usar Arco: sin plan conocido, neutro
}

/// Un día asistido. Varias sesiones el mismo día = un día asistido (T35).
public struct AttendanceDay: Sendable, Equatable {
    public let date: Date                 // fecha civil de entrenamiento
    public let sources: Set<AttendanceSource>
    public let sessionCount: Int
    public let isPartial: Bool            // alguna sesión parcial (T36)

    public init(date: Date, sources: Set<AttendanceSource>, sessionCount: Int, isPartial: Bool) {
        self.date = date
        self.sources = sources
        self.sessionCount = sessionCount
        self.isPartial = isPartial
    }
}

public enum AttendanceEngine {

    /// Determina si una sesión debe crear asistencia automática: requiere al menos una serie
    /// de trabajo elegible confirmada (spec §14, T34). Calentamiento aislado o abrir la rutina
    /// no bastan (T07, T34).
    public static func qualifiesForAutomaticAttendance(sessionSets: [SetRecord]) -> Bool {
        sessionSets.contains { $0.isEligibleForWorkCount }
    }

    /// Consolida eventos del mismo día civil en un único día asistido (T35).
    /// `events`: tuplas (fecha civil, procedencia, parcial).
    public static func consolidate(
        events: [(date: Date, source: AttendanceSource, partial: Bool)],
        calendar: Calendar
    ) -> [AttendanceDay] {
        var byDay: [Date: (sources: Set<AttendanceSource>, count: Int, partial: Bool)] = [:]
        for e in events {
            let day = calendar.startOfDay(for: e.date)
            var acc = byDay[day] ?? (sources: [], count: 0, partial: false)
            acc.sources.insert(e.source)
            acc.count += 1
            acc.partial = acc.partial || e.partial
            byDay[day] = acc
        }
        return byDay
            .map { AttendanceDay(date: $0.key, sources: $0.value.sources, sessionCount: $0.value.count, isPartial: $0.value.partial) }
            .sorted { $0.date < $1.date }
    }
}

/// Métricas de adherencia separadas (spec §14). Si no hay plan, no se inventa porcentaje.
public struct AdherenceMetrics: Sendable, Equatable {
    public let attendedDays: Int
    public let completedSessions: Int
    public let plannedDays: Int
    /// Cumplimiento respecto del plan vigente, nil si no hay plan o denominador 0.
    public var compliance: Double? {
        guard plannedDays > 0 else { return nil }
        return Double(completedSessions) / Double(plannedDays)
    }

    public init(attendedDays: Int, completedSessions: Int, plannedDays: Int) {
        self.attendedDays = attendedDays
        self.completedSessions = completedSessions
        self.plannedDays = plannedDays
    }
}
