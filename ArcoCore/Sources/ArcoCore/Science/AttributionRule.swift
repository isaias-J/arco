import Foundation

/// Una entrada de atribución músculo→papel con su justificación y soporte (spec §10.3).
/// Conserva: regla, músculo, papel, justificación, fuente relacionada, tipo de soporte y límites.
public struct MuscleAttribution: Codable, Sendable, Equatable {
    public let muscle: Muscle
    public let role: AttributionRole
    public let support: SupportLevel
    /// Justificación breve mostrada al usuario (clave de localización o texto).
    public let rationaleKey: String
    /// Identificadores de fuentes relacionadas (E01…, B01…). Puede estar vacío para heurística.
    public let sourceIDs: [String]

    public init(
        muscle: Muscle,
        role: AttributionRole,
        support: SupportLevel,
        rationaleKey: String,
        sourceIDs: [String] = []
    ) {
        self.muscle = muscle
        self.role = role
        self.support = support
        self.rationaleKey = rationaleKey
        self.sourceIDs = sourceIDs
    }
}

/// Conjunto de atribuciones para una familia de ejercicio o variante, en una versión de reglas.
/// Invariante clave (T10): un músculo no puede aparecer dos veces con papeles contradictorios.
public struct AttributionRuleSet: Codable, Sendable, Equatable {
    /// Identificador de la familia/variante a la que aplica (p. ej. "chest_incline_barbell").
    public let exerciseID: String
    /// Versión de las reglas de atribución (spec §10.4). Se conserva al registrar.
    public let version: AttributionVersion
    public let attributions: [MuscleAttribution]
    /// Marca que el usuario personalizó esta regla (no es regla científica revisada — §10.4).
    public let userCustomized: Bool

    public init(
        exerciseID: String,
        version: AttributionVersion,
        attributions: [MuscleAttribution],
        userCustomized: Bool = false
    ) {
        self.exerciseID = exerciseID
        self.version = version
        self.attributions = attributions
        self.userCustomized = userCustomized
    }

    /// Papel resuelto de un músculo. `notCounted` si no está listado (sin crédito automático).
    /// Si hubiera entradas contradictorias, se resuelve a un único papel con prioridad
    /// direct > indirect > unknown > notCounted y se marca como inconsistencia (T10).
    public func role(for muscle: Muscle) -> AttributionRole {
        let roles = attributions.filter { $0.muscle == muscle }.map(\.role)
        if roles.isEmpty { return .notCounted }
        if roles.contains(.direct) { return .direct }
        if roles.contains(.indirect) { return .indirect }
        if roles.contains(.unknown) { return .unknown }
        return .notCounted
    }

    /// Valida que ningún músculo tenga a la vez papel directo e indirecto (T10).
    public var hasRoleConflict: Bool {
        for muscle in Muscle.allCases {
            let roles = Set(attributions.filter { $0.muscle == muscle }.map(\.role))
            if roles.contains(.direct) && roles.contains(.indirect) { return true }
        }
        return false
    }

    /// Música con papel directo en esta regla.
    public var directMuscles: [Muscle] {
        Muscle.allCases.filter { role(for: $0) == .direct }
    }
}

/// Versión semántica de las reglas de atribución. Se guarda con cada serie (spec §10.4).
public struct AttributionVersion: Codable, Sendable, Equatable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int

    public init(_ major: Int, _ minor: Int) {
        self.major = major
        self.minor = minor
    }

    public static func < (lhs: AttributionVersion, rhs: AttributionVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }

    public var description: String { "v\(major).\(minor)" }

    /// Versión inicial conservadora del catálogo base.
    public static let initial = AttributionVersion(1, 0)
}
