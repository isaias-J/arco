import Foundation
import SwiftData

/// Tipo de resolución de un día sin asistencia (spec §14).
public enum AttendanceResolutionKind: String, Sendable {
    case rest      // "Hoy descansé": descanso puntual confirmado
    case absence   // ausencia confirmada
}

/// Acciones de asistencia: "Sí fui", "Hoy descansé", deshacer, y lectura de estados del día.
/// Todas son idempotentes y se dirigen a una fecha civil concreta (T42).
@MainActor
public struct AttendanceRepository {
    public let context: ModelContext
    public let calendar: Calendar

    public init(context: ModelContext, calendar: Calendar = .current) {
        self.context = context
        self.calendar = calendar
    }

    /// "Sí fui": confirmación manual sin fabricar series. Repetirla no duplica (T35).
    /// Elimina una resolución de descanso/ausencia previa de ese mismo día.
    public func markAttended(_ day: CivilDay) {
        guard let date = day.startDate(in: calendar) else { return }
        removeResolution(day)
        let manual = AttendanceSource.manual.rawValue
        let existing = events(on: day).contains { $0.sourceRaw == manual }
        if !existing {
            context.insert(AttendanceEventModel(trainingDate: date, sourceRaw: manual))
        }
        try? context.save()
    }

    /// "Hoy descansé": guarda la excepción. No borra asistencia real de ese día: si ya hay
    /// series registradas, el día sigue contando como asistido.
    public func markResolution(_ kind: AttendanceResolutionKind, on day: CivilDay) {
        let key = day.key
        let predicate = #Predicate<AttendanceResolutionModel> { $0.dayKey == key }
        let existing = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        if let first = existing.first {
            first.kindRaw = kind.rawValue
            for extra in existing.dropFirst() { context.delete(extra) }
        } else {
            context.insert(AttendanceResolutionModel(dayKey: key, kindRaw: kind.rawValue))
        }
        try? context.save()
    }

    /// Deshace una confirmación manual del día (decisión explícita del usuario, T37).
    public func removeManualAttendance(_ day: CivilDay) {
        let manual = AttendanceSource.manual.rawValue
        for event in events(on: day) where event.sourceRaw == manual {
            context.delete(event)
        }
        try? context.save()
    }

    public func removeResolution(_ day: CivilDay) {
        let key = day.key
        let predicate = #Predicate<AttendanceResolutionModel> { $0.dayKey == key }
        for r in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            context.delete(r)
        }
        try? context.save()
    }

    public func events(on day: CivilDay) -> [AttendanceEventModel] {
        let all = (try? context.fetch(FetchDescriptor<AttendanceEventModel>())) ?? []
        return all.filter { CivilDay($0.trainingDate, calendar: calendar) == day }
    }

    /// Días con asistencia válida.
    public func attendedDays() -> Set<CivilDay> {
        let all = (try? context.fetch(FetchDescriptor<AttendanceEventModel>())) ?? []
        return Set(all.map { CivilDay($0.trainingDate, calendar: calendar) })
    }

    /// Resoluciones por día.
    public func resolutions() -> [CivilDay: AttendanceResolutionKind] {
        let all = (try? context.fetch(FetchDescriptor<AttendanceResolutionModel>())) ?? []
        var map: [CivilDay: AttendanceResolutionKind] = [:]
        for r in all {
            if let day = CivilDay(key: r.dayKey), let kind = AttendanceResolutionKind(rawValue: r.kindRaw) {
                map[day] = kind
            }
        }
        return map
    }

    /// Estado del calendario para un día (spec §14). Nunca convierte la falta de datos en
    /// ausencia: un día planificado sin registro queda "sin confirmar".
    public func state(
        of day: CivilDay,
        plan: WeeklyPlan,
        today: CivilDay,
        attended: Set<CivilDay>? = nil,
        manualDays: Set<CivilDay>? = nil,
        resolved: [CivilDay: AttendanceResolutionKind]? = nil
    ) -> CalendarDayState {
        CalendarStateResolver.state(
            of: day, plan: plan, today: today, calendar: calendar,
            automaticDays: (attended ?? attendedDays()).subtracting(manualDays ?? []),
            manualDays: manualDays ?? [],
            resolutions: resolved ?? resolutions()
        )
    }
}

/// Regla pura del estado de un día del calendario (spec §14).
public enum CalendarStateResolver {
    public static func state(
        of day: CivilDay,
        plan: WeeklyPlan,
        today: CivilDay,
        calendar: Calendar,
        automaticDays: Set<CivilDay>,
        manualDays: Set<CivilDay>,
        resolutions: [CivilDay: AttendanceResolutionKind]
    ) -> CalendarDayState {
        if day > today { return .future }
        if automaticDays.contains(day) { return .trainedRegistered }
        if manualDays.contains(day) { return .manualAttendance }
        switch resolutions[day] {
        case .rest: return .confirmedRest
        case .absence: return .confirmedAbsence
        case nil: break
        }
        guard let date = day.startDate(in: calendar) else { return .plannedUnconfirmed }
        if plan.isPlannedRest(date, calendar: calendar) { return .plannedRest }
        if plan.isPlannedTraining(date, calendar: calendar) { return .plannedUnconfirmed }
        // Sin plan para ese día: no se afirma nada; se muestra como descanso no planificado.
        return .plannedRest
    }
}
