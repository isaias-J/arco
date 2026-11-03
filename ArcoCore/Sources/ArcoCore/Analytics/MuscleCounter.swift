import Foundation

/// Una serie elegible acompañada de la regla de atribución del ejercicio que la generó.
/// El motor de conteo opera sobre esta vista; no conoce persistencia.
public struct AttributedSet: Sendable, Equatable {
    public let setID: UUID
    public let exerciseID: String
    public let side: BodySide
    public let ruleSet: AttributionRuleSet
    /// Agrupa las series unilaterales que pueden emparejarse (normalmente el ID de la
    /// sesión-ejercicio). Series de lados opuestos con la misma clave forman pares (spec §7).
    public let pairingKey: String?
    /// Instante de la serie; necesario para explicar sugerencias y última exposición.
    public let performedAt: Date?

    public init(
        setID: UUID,
        exerciseID: String,
        side: BodySide,
        ruleSet: AttributionRuleSet,
        pairingKey: String? = nil,
        performedAt: Date? = nil
    ) {
        self.setID = setID
        self.exerciseID = exerciseID
        self.side = side
        self.ruleSet = ruleSet
        self.pairingKey = pairingKey
        self.performedAt = performedAt
    }
}

/// Conteo de un músculo en un periodo (spec §10.1).
public struct MuscleCount: Sendable, Equatable {
    public let muscle: Muscle
    public let direct: Int        // D
    public let indirect: Int      // I
    public let unknown: Int       // U: series relevantes con atribución sin resolver
    /// F = D + 0,5·I (convención agregada etiquetada, no garantía — §10.1).
    public var fractional: Double { Double(direct) + 0.5 * Double(indirect) }

    public init(muscle: Muscle, direct: Int, indirect: Int, unknown: Int) {
        self.muscle = muscle
        self.direct = direct
        self.indirect = indirect
        self.unknown = unknown
    }
}

/// Conteo de un grupo visual (spec §10.2): crédito del padre = máximo de hijos por serie,
/// unión de series. NUNCA suma de subregiones.
public struct MuscleGroupCount: Sendable, Equatable {
    public let group: MuscleGroup
    public let direct: Int
    public let indirect: Int
    public let unknown: Int
    public var fractional: Double { Double(direct) + 0.5 * Double(indirect) }

    public init(group: MuscleGroup, direct: Int, indirect: Int, unknown: Int) {
        self.group = group
        self.direct = direct
        self.indirect = indirect
        self.unknown = unknown
    }
}

/// Motor de conteo muscular puro, determinista y versionado.
public enum MuscleCounter {

    /// Convierte filas por lado en exposiciones del cuerpo completo (spec §7, T12/T13).
    ///
    /// Una serie izquierda y una derecha del mismo ejercicio y la misma clave de
    /// emparejamiento forman UN par: tres pares son tres exposiciones, no seis. Un lado sin
    /// pareja cuenta como su propia exposición (no se imputa el otro lado), de modo que
    /// para cada grupo el total es `max(izquierdas, derechas)`. Las series bilaterales no
    /// cambian. El análisis por lado usa `countByMuscle(_:side:)`, que no aplica esta regla.
    public static func bodyExposures(_ sets: [AttributedSet]) -> [AttributedSet] {
        struct Key: Hashable { let exerciseID: String; let pairing: String? }
        var bilateral: [AttributedSet] = []
        var left: [Key: [AttributedSet]] = [:]
        var right: [Key: [AttributedSet]] = [:]
        var order: [Key] = []
        for set in sets {
            let key = Key(exerciseID: set.exerciseID, pairing: set.pairingKey)
            switch set.side {
            case .bilateral:
                bilateral.append(set)
            case .left:
                if left[key] == nil && right[key] == nil { order.append(key) }
                left[key, default: []].append(set)
            case .right:
                if left[key] == nil && right[key] == nil { order.append(key) }
                right[key, default: []].append(set)
            }
        }
        var result = bilateral
        for key in order {
            let l = left[key] ?? []
            let r = right[key] ?? []
            result.append(contentsOf: l.count >= r.count ? l : r)
        }
        return result
    }

    /// Cuenta por músculo sobre un conjunto de series ya filtradas al periodo.
    /// Cada serie contribuye como MUCHO un papel por músculo (T09, T10).
    ///
    /// Unilateralidad (spec §7, T12/T13): las filas izquierda/derecha se convierten primero
    /// en exposiciones del cuerpo (`bodyExposures`): tres pares cuentan 3, no 6.
    public static func countByMuscle(_ sets: [AttributedSet]) -> [Muscle: MuscleCount] {
        countRows(bodyExposures(sets))
    }

    /// Conteo sin emparejar: cada fila cuenta una vez. Se usa para el análisis por lado.
    private static func countRows(_ sets: [AttributedSet]) -> [Muscle: MuscleCount] {
        var direct: [Muscle: Int] = [:]
        var indirect: [Muscle: Int] = [:]
        var unknown: [Muscle: Int] = [:]

        for set in sets {
            for muscle in Muscle.allCases {
                switch set.ruleSet.role(for: muscle) {
                case .direct: direct[muscle, default: 0] += 1
                case .indirect: indirect[muscle, default: 0] += 1
                case .unknown:
                    // Solo cuenta como U si el ejercicio menciona el músculo (relevante pero
                    // sin resolver). Músculos no listados son notCounted, no U.
                    if set.ruleSet.attributions.contains(where: { $0.muscle == muscle }) {
                        unknown[muscle, default: 0] += 1
                    }
                case .notCounted:
                    break
                }
            }
        }

        var result: [Muscle: MuscleCount] = [:]
        for muscle in Muscle.allCases {
            let dd = direct[muscle] ?? 0
            let ii = indirect[muscle] ?? 0
            let uu = unknown[muscle] ?? 0
            if dd == 0 && ii == 0 && uu == 0 { continue }
            result[muscle] = MuscleCount(muscle: muscle, direct: dd, indirect: ii, unknown: uu)
        }
        return result
    }

    /// Conteo por músculo filtrando por un lado concreto (análisis unilateral, T13).
    public static func countByMuscle(_ sets: [AttributedSet], side: BodySide) -> [Muscle: MuscleCount] {
        countRows(sets.filter { $0.side == side })
    }

    /// Agregación por grupo visual (spec §10.2). Para cada serie y grupo, el crédito es el
    /// MÁXIMO papel entre los músculos hijos presentes en esa serie (direct > indirect > unknown),
    /// y se cuenta una sola vez por serie (unión). Evita doble conteo cuando una serie alcanza
    /// dos regiones del mismo grupo (T11).
    public static func countByGroup(_ sets: [AttributedSet]) -> [MuscleGroup: MuscleGroupCount] {
        var direct: [MuscleGroup: Int] = [:]
        var indirect: [MuscleGroup: Int] = [:]
        var unknown: [MuscleGroup: Int] = [:]

        for set in bodyExposures(sets) {
            for group in MuscleGroup.allCases {
                let children = Muscle.allCases.filter { $0.group == group }
                var best: AttributionRole? = nil
                for child in children {
                    let role = set.ruleSet.role(for: child)
                    best = maxRole(best, role, hasEntry: set.ruleSet.attributions.contains { $0.muscle == child })
                }
                switch best {
                case .direct: direct[group, default: 0] += 1
                case .indirect: indirect[group, default: 0] += 1
                case .unknown: unknown[group, default: 0] += 1
                default: break
                }
            }
        }

        var result: [MuscleGroup: MuscleGroupCount] = [:]
        for group in MuscleGroup.allCases {
            let dd = direct[group] ?? 0
            let ii = indirect[group] ?? 0
            let uu = unknown[group] ?? 0
            if dd == 0 && ii == 0 && uu == 0 { continue }
            result[group] = MuscleGroupCount(group: group, direct: dd, indirect: ii, unknown: uu)
        }
        return result
    }

    /// Combina el papel actual con uno nuevo tomando el mayor crédito (direct > indirect > unknown).
    /// `notCounted` solo cuenta como unknown si el ejercicio lista el músculo.
    private static func maxRole(_ current: AttributionRole?, _ new: AttributionRole, hasEntry: Bool) -> AttributionRole? {
        let effective: AttributionRole?
        switch new {
        case .direct: effective = .direct
        case .indirect: effective = .indirect
        case .unknown: effective = hasEntry ? .unknown : nil
        case .notCounted: effective = nil
        }
        guard let effective else { return current }
        guard let current else { return effective }
        return rank(effective) > rank(current) ? effective : current
    }

    private static func rank(_ role: AttributionRole) -> Int {
        switch role {
        case .direct: return 3
        case .indirect: return 2
        case .unknown: return 1
        case .notCounted: return 0
        }
    }
}
