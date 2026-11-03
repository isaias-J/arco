import Foundation

/// Un récord conserva la serie de origen para poder recalcularlo si se corrige/borra (spec §13).
public struct PersonalRecord: Sendable, Equatable {
    public enum Kind: String, Sendable { case maxLoad, repsAtLoad }
    public let kind: Kind
    public let setID: UUID
    public let loadKilograms: Decimal
    public let reps: Int
    public let side: BodySide
    public let date: Date
}

public enum RecordsEngine {
    /// Récord de mayor carga. Excluye calentamientos, intentos y eliminadas (spec §13).
    /// No genera récord de "fuerza" por mayor asistencia (T26): las convenciones de
    /// asistencia se excluyen del récord de carga.
    public static func maxLoadRecord(from sets: [SetRecord], side: BodySide? = nil) -> PersonalRecord? {
        let eligible = sets.filter {
            $0.isEligibleForWorkCount
            && $0.load.convention != .assistance
            && $0.load.kilograms != nil
            && (side == nil || $0.side == side)
        }
        guard let best = eligible.max(by: { ($0.load.kilograms ?? 0) < ($1.load.kilograms ?? 0) }) else { return nil }
        return PersonalRecord(
            kind: .maxLoad,
            setID: best.id,
            loadKilograms: best.load.kilograms ?? 0,
            reps: best.reps ?? 0,
            side: best.side,
            date: best.performedAt
        )
    }

    /// Récord de repeticiones a una carga dada (misma convención/unidad normalizada).
    public static func repsRecord(from sets: [SetRecord], atKilograms kg: Decimal, side: BodySide? = nil) -> PersonalRecord? {
        let eligible = sets.filter {
            $0.isEligibleForWorkCount
            && $0.load.kilograms == kg
            && (side == nil || $0.side == side)
        }
        guard let best = eligible.max(by: { ($0.reps ?? 0) < ($1.reps ?? 0) }) else { return nil }
        return PersonalRecord(
            kind: .repsAtLoad,
            setID: best.id,
            loadKilograms: kg,
            reps: best.reps ?? 0,
            side: best.side,
            date: best.performedAt
        )
    }
}

/// Resultado de comparar dos sesiones del mismo ejercicio (T27, T28).
public struct ProgressComparison: Sendable, Equatable {
    public let repsProgressAtSameLoad: Bool   // misma carga, más reps (T27)
    public let loadIncreased: Bool
    public let repsDecreased: Bool
    /// Cuando sube carga pero bajan reps, ambas variables se muestran sin proclamar
    /// superioridad absoluta no definida (T28).
    public var ambiguousTradeoff: Bool { loadIncreased && repsDecreased }
}

public enum ProgressionAnalyzer {
    /// Compara la mejor serie de trabajo de dos sesiones del mismo ejercicio.
    public static func compare(previous: [SetRecord], current: [SetRecord]) -> ProgressComparison? {
        let p = previous.filter { $0.isEligibleForWorkCount }
        let c = current.filter { $0.isEligibleForWorkCount }
        guard let pb = p.max(by: { topKey($0) < topKey($1) }),
              let cb = c.max(by: { topKey($0) < topKey($1) }) else { return nil }
        let pKg = pb.load.kilograms ?? 0
        let cKg = cb.load.kilograms ?? 0
        let sameLoad = pKg == cKg
        return ProgressComparison(
            repsProgressAtSameLoad: sameLoad && (cb.reps ?? 0) > (pb.reps ?? 0),
            loadIncreased: cKg > pKg,
            repsDecreased: (cb.reps ?? 0) < (pb.reps ?? 0)
        )
    }

    private static func topKey(_ s: SetRecord) -> Decimal {
        // Orden por carga, luego reps como desempate dentro de misma carga.
        (s.load.kilograms ?? 0) * 1000 + Decimal(s.reps ?? 0)
    }
}

/// Configuración de doble progresión por ejercicio (spec §13). Desactivable.
public struct DoubleProgressionConfig: Sendable, Equatable {
    public let enabled: Bool
    public let repRangeLower: Int
    public let repRangeUpper: Int
    public let referenceSets: Int        // nº de series de referencia
    public let incrementKilograms: Decimal

    public init(enabled: Bool, repRangeLower: Int, repRangeUpper: Int, referenceSets: Int, incrementKilograms: Decimal) {
        self.enabled = enabled
        self.repRangeLower = repRangeLower
        self.repRangeUpper = repRangeUpper
        self.referenceSets = referenceSets
        self.incrementKilograms = incrementKilograms
    }
}

public enum DoubleProgression {
    /// Sugiere incremento SOLO si TODAS las series de referencia alcanzan el extremo superior
    /// del rango bajo condiciones comparables (spec §13, T30). Una sola serie no basta.
    /// No cambia pesos: solo sugiere.
    public static func suggestsIncrease(config: DoubleProgressionConfig, workingSets: [SetRecord]) -> Bool {
        guard config.enabled else { return false }
        let eligible = workingSets.filter { $0.isEligibleForWorkCount }
        guard eligible.count >= config.referenceSets else { return false }
        // Tomar las primeras `referenceSets` series de referencia.
        let reference = Array(eligible.prefix(config.referenceSets))
        return reference.allSatisfy { ($0.reps ?? 0) >= config.repRangeUpper }
    }
}
