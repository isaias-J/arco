import Foundation

/// Nodo de la jerarquía muscular. Evita equivalencias anatómicas falsas (spec §5, §10.2).
/// Un `parent` agrupa regiones visualmente; el crédito del padre se calcula como el
/// MÁXIMO de sus hijos por serie, con unión de series — nunca la suma (spec §10.2, T11).
public enum Muscle: String, Codable, Sendable, CaseIterable {
    // Pecho
    case pectoral

    // Hombro (regiones separadas: la spec exige separar anterior/lateral/posterior)
    case deltoidAnterior
    case deltoidLateral
    case deltoidPosterior

    // Espalda
    case lats                 // dorsales
    case scapularRetractors   // retractores escapulares

    // Brazo
    case elbowFlexors         // flexores del codo (bíceps / braquial)
    case brachioradialis      // braquiorradial (región de antebrazo)
    case triceps
    case forearm

    // Pierna
    case quadriceps
    case hamstrings
    case glutes
    case calves

    // Tronco
    case abdomen
    case hipFlexors           // flexores de cadera

    /// Grupo visual padre al que pertenece la región, para agregaciones de alto nivel.
    public var group: MuscleGroup {
        switch self {
        case .pectoral: return .chest
        case .deltoidAnterior, .deltoidLateral, .deltoidPosterior: return .shoulders
        case .lats, .scapularRetractors: return .back
        case .elbowFlexors: return .biceps
        // El braquiorradial es una región del antebrazo (spec §10.2): su trabajo directo en el
        // curl invertido debe aparecer en el grupo antebrazo, sin duplicar en bíceps.
        case .brachioradialis: return .forearm
        case .triceps: return .triceps
        case .forearm: return .forearm
        case .quadriceps, .hamstrings, .glutes, .calves: return .legs
        case .abdomen, .hipFlexors: return .core
        }
    }

    /// Clave de localización para el nombre mostrado.
    public var localizationKey: String { "muscle.\(rawValue)" }
}

/// Agrupaciones visuales de alto nivel. Son agrupaciones de presentación, no dosis
/// biológicas: su crédito usa máximo de hijos + unión de series (spec §10.2).
public enum MuscleGroup: String, Codable, Sendable, CaseIterable {
    case chest
    case shoulders
    case back
    case biceps
    case triceps
    case forearm
    case legs
    case core

    public var localizationKey: String { "muscleGroup.\(rawValue)" }
}

/// Papel de un músculo en una serie, bajo una versión de reglas (spec §10.1).
/// Un músculo tiene UN solo papel por serie en una versión dada (T10).
public enum AttributionRole: String, Codable, Sendable {
    /// Directo: cuenta 1 en D.
    case direct
    /// Indirecto: cuenta 1 en I (y 0,5 en el fraccional).
    case indirect
    /// No contabilizado en esta estimación (ausencia de crédito, NO ausencia fisiológica).
    case notCounted
    /// Desconocido / depende de variante o falta información: se identifica aparte (U).
    case unknown
}

/// Nivel de soporte de una regla de atribución (spec §10.3).
public enum SupportLevel: String, Codable, Sendable {
    case longitudinalSpecific    // estudio longitudinal específico del ejercicio
    case longitudinalRelated     // estudio longitudinal relacionado
    case biomechanical           // razonamiento biomecánico
    case productInference        // inferencia de producto (heurística)
}
