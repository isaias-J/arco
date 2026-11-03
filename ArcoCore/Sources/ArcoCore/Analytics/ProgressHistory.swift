import Foundation

// MARK: - Series por músculo a lo largo del tiempo (spec §12)

/// Escala de la curva histórica.
public enum HistoryScale: String, CaseIterable, Sendable {
    case week, month, year

    public var displayName: String {
        switch self {
        case .week: return "Semanas"
        case .month: return "Meses"
        case .year: return "Años"
        }
    }

    /// Número de periodos que se muestran hacia atrás (el actual incluido).
    public var defaultPeriods: Int {
        switch self {
        case .week: return 12
        case .month: return 12
        case .year: return 5
        }
    }

    var component: Calendar.Component {
        switch self {
        case .week: return .weekOfYear
        case .month: return .month
        case .year: return .year
        }
    }
}

/// Qué se cuenta: un grupo visual (unión de series de sus subregiones) o un músculo concreto.
public enum MuscleTarget: Hashable, Sendable {
    case group(MuscleGroup)
    case muscle(Muscle)

    public var displayName: String {
        switch self {
        case .group(let g): return g.displayName
        case .muscle(let m): return m.displayName
        }
    }
}

/// Un periodo de la curva.
public struct MuscleHistoryBucket: Sendable, Equatable, Identifiable {
    public let start: Date
    public let end: Date
    /// El periodo aún no ha terminado o empezó antes del primer registro de Arco.
    public let isPartial: Bool
    /// Hubo series de trabajo registradas (de cualquier ejercicio) en el periodo. Si no, no se
    /// sabe si entrenaste: el valor es "sin registros", no un cero.
    public let hasWorkRecords: Bool
    /// Días con asistencia manual ("Sí fui") sin series registradas en el periodo.
    public let attendanceWithoutSets: Int
    public let direct: Int
    public let indirect: Int
    public let unknown: Int

    public var id: Date { start }
    /// F = D + 0,5 × I (convención agregada etiquetada; no mide hipertrofia).
    public var fractional: Double { Double(direct) + 0.5 * Double(indirect) }
    /// Valor que se puede dibujar: nil si no hay registros de trabajo en el periodo.
    public func value(_ method: MuscleHistoryMethod) -> Double? {
        guard hasWorkRecords else { return nil }
        switch method {
        case .direct: return Double(direct)
        case .directAndIndirect: return Double(direct + indirect)
        case .fractional: return fractional
        }
    }
}

/// Método de conteo mostrado en la curva.
public enum MuscleHistoryMethod: String, CaseIterable, Sendable {
    case direct, directAndIndirect, fractional

    public var displayName: String {
        switch self {
        case .direct: return "Directas"
        case .directAndIndirect: return "Directas e indirectas"
        case .fractional: return "Estimación fraccional"
        }
    }

    public var explanation: String {
        switch self {
        case .direct:
            return "Cada barra es el número de series de trabajo en las que este músculo es objetivo principal (D)."
        case .directAndIndirect:
            return "Cada barra apila las series directas (D) y las indirectas (I): el músculo participa como sinergista. Cada serie cuenta una sola vez."
        case .fractional:
            return "Cada barra es F = D + 0,5 × I: una convención agregada para repartir el trabajo, no una medida exacta de estímulo ni de crecimiento."
        }
    }
}

public enum MuscleHistory {

    /// Periodos de la escala que terminan en el actual, sin empezar antes del primer registro.
    ///
    /// - `sets`: series atribuidas (trabajo elegible). Los pares izquierda/derecha se cuentan
    ///   como una exposición y el grupo usa la unión de series, nunca la suma de subregiones.
    /// - `workDates`: instantes de todas las series de trabajo, con o sin atribución, para saber
    ///   si en un periodo hubo registros.
    /// - `manualAttendanceDays`: días con "Sí fui" sin series; el periodo sigue sin datos de
    ///   series, pero se informa.
    public static func buckets(
        _ sets: [AttributedSet],
        target: MuscleTarget,
        scale: HistoryScale,
        periods: Int? = nil,
        workDates: [Date],
        manualAttendanceDays: [Date] = [],
        now: Date,
        calendar: Calendar
    ) -> [MuscleHistoryBucket] {
        let firstRecord = (workDates + manualAttendanceDays).min()
        guard let firstRecord, let current = calendar.dateInterval(of: scale.component, for: now) else { return [] }
        let count = max(1, periods ?? scale.defaultPeriods)

        var intervals: [DateInterval] = []
        var start = current.start
        for _ in 0..<count {
            guard let interval = calendar.dateInterval(of: scale.component, for: start) else { break }
            if interval.end <= firstRecord { break }
            intervals.insert(interval, at: 0)
            guard let previous = calendar.date(byAdding: scale.component, value: -1, to: interval.start) else { break }
            start = previous
        }

        let manualDays = Set(manualAttendanceDays.map { calendar.startOfDay(for: $0) })
        let workDays = Set(workDates.map { calendar.startOfDay(for: $0) })

        return intervals.map { interval in
            let inPeriod = MuscleWeek.filter(sets, from: interval.start, to: interval.end)
            let hasWork = workDates.contains { $0 >= interval.start && $0 < interval.end }
            let manualOnly = manualDays.filter { $0 >= interval.start && $0 < interval.end && !workDays.contains($0) }.count
            let (d, i, u): (Int, Int, Int) = {
                switch target {
                case .group(let g):
                    let c = MuscleCounter.countByGroup(inPeriod)[g]
                    return (c?.direct ?? 0, c?.indirect ?? 0, c?.unknown ?? 0)
                case .muscle(let m):
                    let c = MuscleCounter.countByMuscle(inPeriod)[m]
                    return (c?.direct ?? 0, c?.indirect ?? 0, c?.unknown ?? 0)
                }
            }()
            let partial = interval.end > now || interval.start < calendar.startOfDay(for: firstRecord)
            return MuscleHistoryBucket(
                start: interval.start, end: interval.end, isPartial: partial,
                hasWorkRecords: hasWork, attendanceWithoutSets: manualOnly,
                direct: d, indirect: i, unknown: u
            )
        }
    }
}

// MARK: - Evolución de repeticiones por ejercicio (spec §12)

/// Qué repeticiones se comparan entre sesiones de una misma combinación comparable
/// (ejercicio + variante + convención de carga).
public enum RepsComparison: Hashable, Sendable {
    /// Mejor serie de cada sesión con exactamente esta carga (kg). Es la comparación directa.
    case atLoad(Decimal)
    /// Repeticiones de la serie con más carga de cada sesión; la carga puede cambiar entre
    /// puntos y se muestra junto a cada uno.
    case heaviestSet
    /// Ejercicios sin carga registrada: mejor serie de cada sesión.
    case withoutLoad
}

public struct RepsPoint: Sendable, Equatable {
    public let sessionID: UUID
    public let date: Date
    public let side: BodySide
    public let reps: Int
    /// Carga asociada, en kg (nil si no hay carga).
    public let loadKilograms: Decimal?
}

public struct RepsSession: Sendable {
    public let id: UUID
    public let date: Date
    public let sets: [SetRecord]
    public init(id: UUID, date: Date, sets: [SetRecord]) { self.id = id; self.date = date; self.sets = sets }
}

public enum RepsHistory {
    /// Tolerancia para considerar dos cargas iguales (kg). Evita separar 20 kg de 20,0000001 kg
    /// tras convertir libras.
    static let loadTolerance = Decimal(string: "0.01")!

    private static func usable(_ s: SetRecord) -> Bool {
        s.isEligibleForWorkCount && (s.reps ?? 0) > 0
    }

    private static func sameLoad(_ a: Decimal, _ b: Decimal) -> Bool {
        let diff = a - b
        return (diff < 0 ? -diff : diff) < loadTolerance
    }

    private static func rounded(_ kg: Decimal) -> Decimal {
        var value = kg, result = Decimal()
        NSDecimalRound(&result, &value, 2, .plain)
        return result
    }

    /// Cargas usadas (kg, redondeadas a 0,01) con el número de sesiones en que aparecen, de la
    /// más repetida a la menos; a igualdad, la más alta primero.
    public static func loads(_ sessions: [RepsSession]) -> [(kilograms: Decimal, sessions: Int)] {
        var counts: [Decimal: Set<UUID>] = [:]
        for session in sessions {
            for set in session.sets where usable(set) {
                guard let kg = set.load.kilograms else { continue }
                counts[rounded(kg), default: []].insert(session.id)
            }
        }
        return counts.map { ($0.key, $0.value.count) }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 > $1.0 }
    }

    /// Comparación por defecto: la carga usada en más sesiones si se repite en al menos dos;
    /// si no, la serie más pesada; sin cargas, sin carga.
    public static func defaultComparison(_ sessions: [RepsSession]) -> RepsComparison {
        let l = loads(sessions)
        if l.isEmpty { return .withoutLoad }
        if let top = l.first, top.sessions >= 2 { return .atLoad(top.kilograms) }
        return .heaviestSet
    }

    /// Un punto por sesión y lado. Las sesiones sin series que cumplan el criterio no generan
    /// punto (no se dibujan como cero). Los lados izquierdo y derecho se mantienen separados.
    public static func points(_ sessions: [RepsSession], comparison: RepsComparison) -> [RepsPoint] {
        var out: [RepsPoint] = []
        for session in sessions.sorted(by: { $0.date < $1.date }) {
            let bySide = Dictionary(grouping: session.sets.filter(usable), by: \.side)
            for side in [BodySide.bilateral, .left, .right] {
                guard let sets = bySide[side], !sets.isEmpty else { continue }
                let candidates: [SetRecord]
                switch comparison {
                case .atLoad(let kg):
                    candidates = sets.filter { $0.load.kilograms.map { sameLoad($0, kg) } ?? false }
                case .heaviestSet:
                    let known = sets.filter { $0.load.kilograms != nil }
                    guard let maxKg = known.compactMap({ $0.load.kilograms }).max() else { continue }
                    candidates = known.filter { sameLoad($0.load.kilograms!, maxKg) }
                case .withoutLoad:
                    candidates = sets
                }
                guard let best = candidates.max(by: { ($0.reps ?? 0) < ($1.reps ?? 0) }), let reps = best.reps else { continue }
                out.append(RepsPoint(sessionID: session.id, date: session.date, side: side, reps: reps,
                                     loadKilograms: best.load.kilograms.map(rounded)))
            }
        }
        return out
    }
}
