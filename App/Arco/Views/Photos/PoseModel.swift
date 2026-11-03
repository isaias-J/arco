//
//  PoseModel.swift
//  Arco
//
//  Modelo de poses de la bóveda de fotos (spec §16 "Poses").
//
//  DECISIONES LIGADAS A LA SPEC
//  ----------------------------
//  - Poses base: frontal relajado, lateral y espalda. Adicionales opcionales:
//    doble bíceps frontal, bíceps de perfil y poses personalizadas (spec §16).
//  - Cada pose ofrece un nombre y una descripción sencilla, NEUTRA y NO
//    sexualizada (spec §16 "ofrecer una ilustración original, neutra y no
//    sexualizada"). La "ilustración" se representa aquí con un símbolo SF neutro
//    como referencia de encuadre; no se usa reconocimiento del cuerpo.
//  - `custom(String)` permite poses adicionales del usuario sin imponerlas.
//

import Foundation

/// Pose fotográfica de un check-in de progreso.
///
/// Es un `enum` con un caso asociado para poses personalizadas. Se declara
/// `Sendable` para poder cruzar fronteras de aislamiento (descifrado fuera del
/// main actor, presentación en el main actor — skill de concurrencia).
enum Pose: Hashable, Sendable, Identifiable {
    /// Pose base: de frente, en posición relajada.
    case frontRelaxed
    /// Pose base: de lado (perfil).
    case side
    /// Pose base: de espaldas.
    case back
    /// Pose opcional: doble bíceps de frente.
    case frontDoubleBiceps
    /// Pose opcional: bíceps de perfil.
    case sideBiceps
    /// Pose personalizada definida por el usuario (texto libre, neutro).
    case custom(String)

    // MARK: - Identidad estable

    /// Identidad estable para `ForEach` / `Picker` (nunca índices).
    /// Las poses personalizadas se identifican por su texto normalizado.
    var id: String { rawValue }

    // MARK: - Serialización

    /// Valor persistible en `PhotoCheckInModel.poseRaw`. Las poses base usan
    /// claves estables en inglés (desacopladas del idioma de la interfaz); las
    /// personalizadas se prefijan con `custom:` para poder reconstruirlas.
    var rawValue: String {
        switch self {
        case .frontRelaxed: return "frontRelaxed"
        case .side: return "side"
        case .back: return "back"
        case .frontDoubleBiceps: return "frontDoubleBiceps"
        case .sideBiceps: return "sideBiceps"
        case .custom(let name): return "custom:\(name)"
        }
    }

    /// Reconstruye una pose desde su valor persistido. Nunca falla: un valor
    /// desconocido se interpreta como personalizado para no perder el registro.
    init(rawValue: String) {
        switch rawValue {
        case "frontRelaxed": self = .frontRelaxed
        case "side": self = .side
        case "back": self = .back
        case "frontDoubleBiceps": self = .frontDoubleBiceps
        case "sideBiceps": self = .sideBiceps
        default:
            if rawValue.hasPrefix("custom:") {
                self = .custom(String(rawValue.dropFirst("custom:".count)))
            } else {
                // Tolerante: cualquier otro texto se trata como pose personalizada.
                self = .custom(rawValue)
            }
        }
    }

    // MARK: - Presentación (español, neutro)

    /// Nombre legible en español para la interfaz.
    var displayName: String {
        switch self {
        case .frontRelaxed: return "Frontal relajado"
        case .side: return "Lateral"
        case .back: return "Espalda"
        case .frontDoubleBiceps: return "Doble bíceps frontal"
        case .sideBiceps: return "Bíceps de perfil"
        case .custom(let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Personalizada" : trimmed
        }
    }

    /// Descripción breve, neutra y no sexualizada que explica el encuadre
    /// (spec §16 "Explicar la pose de forma sencilla").
    var shortDescription: String {
        switch self {
        case .frontRelaxed:
            return "De frente a la cámara, de pie y relajado, brazos a los lados."
        case .side:
            return "De perfil, mirando al frente, con el cuerpo de lado a la cámara."
        case .back:
            return "De espaldas a la cámara, de pie y relajado."
        case .frontDoubleBiceps:
            return "De frente, con ambos brazos elevados a la altura de los hombros."
        case .sideBiceps:
            return "De perfil, con un brazo flexionado hacia el frente."
        case .custom:
            return "Pose personalizada. Mantén el mismo encuadre entre registros para comparar con honestidad."
        }
    }

    /// Símbolo SF neutro usado como referencia de encuadre (no es análisis del
    /// cuerpo, solo una guía visual — spec §16 "No usar reconocimiento facial").
    var referenceSymbol: String {
        switch self {
        case .frontRelaxed, .frontDoubleBiceps: return "figure.stand"
        case .side, .sideBiceps: return "figure.walk"
        case .back: return "figure.stand"
        case .custom: return "person.crop.rectangle"
        }
    }

    /// Indica si es una de las tres poses base (spec §16).
    var isBase: Bool {
        switch self {
        case .frontRelaxed, .side, .back: return true
        default: return false
        }
    }

    // MARK: - Catálogo

    /// Poses base sugeridas por defecto en la captura (spec §16).
    static let base: [Pose] = [.frontRelaxed, .side, .back]

    /// Poses opcionales predefinidas (sin incluir personalizadas).
    static let optional: [Pose] = [.frontDoubleBiceps, .sideBiceps]

    /// Todas las poses predefinidas (base + opcionales), para selección en UI.
    static let predefined: [Pose] = base + optional
}
