import Foundation

public extension Muscle {
    /// Nombre en español. El conteo general de brazo se etiqueta como "flexores del codo"
    /// (bíceps/braquial) y el braquiorradial como región del antebrazo (spec §10.2).
    var displayName: String {
        switch self {
        case .pectoral: return "Pectoral"
        case .deltoidAnterior: return "Deltoides anterior"
        case .deltoidLateral: return "Deltoides lateral"
        case .deltoidPosterior: return "Deltoides posterior"
        case .lats: return "Dorsales"
        case .scapularRetractors: return "Retractores escapulares"
        case .elbowFlexors: return "Bíceps / flexores del codo"
        case .brachioradialis: return "Braquiorradial"
        case .triceps: return "Tríceps"
        case .forearm: return "Antebrazo (flexores/extensores de muñeca)"
        case .quadriceps: return "Cuádriceps"
        case .hamstrings: return "Isquiotibiales"
        case .glutes: return "Glúteos"
        case .calves: return "Pantorrillas"
        case .abdomen: return "Abdomen"
        case .hipFlexors: return "Flexores de cadera"
        }
    }
}

public extension MuscleGroup {
    var displayName: String {
        switch self {
        case .chest: return "Pecho"
        case .shoulders: return "Hombros"
        case .back: return "Espalda"
        case .biceps: return "Bíceps"
        case .triceps: return "Tríceps"
        case .forearm: return "Antebrazo"
        case .legs: return "Pierna"
        case .core: return "Abdomen y cadera"
        }
    }
}

/// Periodo de consulta del conteo por músculo (spec §12: distinguir semana calendario y
/// últimos 7 días; etiquetar periodos incompletos).
public enum CountPeriod: String, CaseIterable, Sendable {
    case currentWeek, previousWeek, last7Days, last14Days

    public var displayName: String {
        switch self {
        case .currentWeek: return "Esta semana"
        case .previousWeek: return "Semana anterior"
        case .last7Days: return "Últimos 7 días"
        case .last14Days: return "Últimos 14 días"
        }
    }

    /// Intervalo [inicio, fin) y si está incompleto respecto de `now`.
    public func interval(now: Date, calendar: Calendar) -> (start: Date, end: Date, isPartial: Bool) {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        switch self {
        case .currentWeek:
            let week = calendar.dateInterval(of: .weekOfYear, for: now)
            let start = week?.start ?? today
            let end = week?.end ?? tomorrow
            return (start, end, end > tomorrow)
        case .previousWeek:
            let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? today
            let start = calendar.date(byAdding: .day, value: -7, to: current) ?? current
            return (start, current, false)
        case .last7Days:
            return (calendar.date(byAdding: .day, value: -6, to: today) ?? today, tomorrow, false)
        case .last14Days:
            return (calendar.date(byAdding: .day, value: -13, to: today) ?? today, tomorrow, false)
        }
    }
}

/// Última exposición directa e indirecta de un músculo (spec §11.5). Sin registro => nil
/// ("sin datos"). Las horas son tiempo transcurrido, no una medida de recuperación.
public struct MuscleExposure: Sendable, Equatable {
    public let muscle: Muscle
    public let lastDirect: Date?
    public let lastIndirect: Date?

    public func hoursSinceDirect(now: Date) -> Int? {
        lastDirect.map { Int(now.timeIntervalSince($0) / 3600) }
    }
}

public enum MuscleWeek {
    /// Series atribuidas dentro del intervalo [start, end).
    public static func filter(_ sets: [AttributedSet], from start: Date, to end: Date) -> [AttributedSet] {
        sets.filter { s in
            guard let d = s.performedAt else { return false }
            return d >= start && d < end
        }
    }

    /// Última exposición directa/indirecta por músculo.
    public static func exposures(_ sets: [AttributedSet]) -> [Muscle: MuscleExposure] {
        var direct: [Muscle: Date] = [:]
        var indirect: [Muscle: Date] = [:]
        for s in sets {
            guard let d = s.performedAt else { continue }
            for m in Muscle.allCases {
                switch s.ruleSet.role(for: m) {
                case .direct: if (direct[m] ?? .distantPast) < d { direct[m] = d }
                case .indirect: if (indirect[m] ?? .distantPast) < d { indirect[m] = d }
                default: break
                }
            }
        }
        var out: [Muscle: MuscleExposure] = [:]
        for m in Muscle.allCases where direct[m] != nil || indirect[m] != nil {
            out[m] = MuscleExposure(muscle: m, lastDirect: direct[m], lastIndirect: indirect[m])
        }
        return out
    }

    /// Ejercicios que aportan a un músculo, con su papel y número de exposiciones.
    public static func contributors(_ sets: [AttributedSet], muscle: Muscle) -> [(exerciseID: String, role: AttributionRole, count: Int)] {
        var counts: [String: (AttributionRole, Int)] = [:]
        for s in MuscleCounter.bodyExposures(sets) {
            let role = s.ruleSet.role(for: muscle)
            guard role == .direct || role == .indirect || (role == .unknown && s.ruleSet.attributions.contains { $0.muscle == muscle }) else { continue }
            let current = counts[s.exerciseID] ?? (role, 0)
            counts[s.exerciseID] = (current.0, current.1 + 1)
        }
        return counts.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.count > $1.count }
    }

    /// Mensaje de progreso respecto a un objetivo elegido, con el MISMO método (spec §10.5).
    public static func goalMessage(count: MuscleCount?, method: GoalMethod, target: Decimal) -> String {
        let value: Decimal = {
            switch method {
            case .direct: return Decimal(count?.direct ?? 0)
            case .fractional: return Decimal(count?.fractional ?? 0)
            }
        }()
        let noun = method == .direct ? "series directas" : "series (estimación fraccional)"
        let valueText = NSDecimalNumber(decimal: value).stringValue
        let targetText = NSDecimalNumber(decimal: target).stringValue
        if value >= target {
            return "\(valueText) \(noun); objetivo elegido: \(targetText)"
        }
        let gap = NSDecimalNumber(decimal: target - value).stringValue
        return "\(valueText) \(noun); objetivo elegido: \(targetText) (\(gap) por debajo de tu meta configurada)"
    }
}

/// Método de conteo de un objetivo (spec §10.5).
public enum GoalMethod: String, Sendable, CaseIterable {
    case direct, fractional

    public var displayName: String {
        switch self {
        case .direct: return "Series directas"
        case .fractional: return "Estimación fraccional"
        }
    }

    /// Valida el objetivo: entero no negativo para directas; múltiplo de 0,5 para fraccional.
    public func isValid(_ target: Decimal) -> Bool {
        guard target >= 0 else { return false }
        let doubled = target * 2
        var rounded = Decimal()
        var copy = doubled
        NSDecimalRound(&rounded, &copy, 0, .plain)
        switch self {
        case .direct:
            var whole = Decimal(); var t = target
            NSDecimalRound(&whole, &t, 0, .plain)
            return whole == target
        case .fractional:
            return rounded == doubled
        }
    }
}

/// Altura vigente en una fecha para el IMC histórico (spec §18, T58).
public struct HeightRecord: Sendable, Equatable {
    public let date: Date
    public let meters: Decimal
    public init(date: Date, meters: Decimal) { self.date = date; self.meters = meters }
}

public enum BMIHistory {
    public struct Point: Sendable, Equatable {
        public let date: Date
        public let bmi: BMIResult
        /// La altura usada es posterior al pesaje (supuesto identificado, no recálculo silencioso).
        public let usesLaterHeight: Bool
    }

    /// Altura vigente en `date`: la última medida en o antes de esa fecha. Si no existe,
    /// se usa la primera conocida marcándola como supuesto.
    public static func height(at date: Date, in heights: [HeightRecord]) -> (meters: Decimal, assumed: Bool)? {
        let sorted = heights.filter { $0.meters > 0 }.sorted { $0.date < $1.date }
        if let valid = sorted.last(where: { $0.date <= date }) { return (valid.meters, false) }
        if let first = sorted.first { return (first.meters, true) }
        return nil
    }

    public static func points(weights: [BodyWeightEntry], heights: [HeightRecord]) -> [Point] {
        weights.filter(\.isValid).sorted { $0.measurementDate < $1.measurementDate }.compactMap { w in
            guard let h = height(at: w.measurementDate, in: heights),
                  let bmi = BMICalculator.bmi(massKilograms: w.kilograms, heightMeters: h.meters, isEstimated: w.isEstimated)
            else { return nil }
            return Point(date: w.measurementDate, bmi: bmi, usesLaterHeight: h.assumed)
        }
    }
}

public enum AgeCalculator {
    /// Edad en años cumplidos en la fecha de referencia (calendario, no constante).
    public static func age(birthDate: Date, on reference: Date, calendar: Calendar) -> Int? {
        guard birthDate < reference else { return nil }
        return calendar.dateComponents([.year], from: birthDate, to: reference).year
    }
}
