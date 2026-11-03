import Foundation

/// Tipo de serie (spec §7). Solo las de trabajo completadas cuentan para volumen/asistencia.
public enum SetType: String, Codable, Sendable, CaseIterable {
    case warmup   // calentamiento: visible en historial, excluido de conteo de trabajo (T07)
    case working  // trabajo
    case attempt  // intento fallido: se conserva, excluido del conteo principal
}

/// Estado del ciclo de vida de una serie (spec §7).
public enum SetState: String, Codable, Sendable, CaseIterable {
    case pending    // pendiente (borrador no confirmado)
    case completed  // completada
    case skipped    // omitida
    case deleted    // eliminada (borrado lógico; excluida de conteos y récords)
}

/// Lado para ejercicios registrados por lados (spec §7, unilateralidad).
public enum BodySide: String, Codable, Sendable, CaseIterable {
    case bilateral  // una sola fila que representa ejecución bilateral
    case left
    case right
}

/// RIR (repeticiones en reserva) opcional. Permite categorías abiertas sin inventar
/// un número exacto (spec §7): "4 o más" y "no sé" no se convierten en valores exactos.
public enum RIR: Codable, Sendable, Equatable {
    case exact(Int)        // 0…N
    case atLeast(Int)      // "N o más" (categoría abierta)
    case unknown           // "no sé"

    /// Valor numérico utilizable para filtros que requieren RIR concreto (p. ej. e1RM),
    /// solo cuando es exacto. Categorías abiertas y desconocido devuelven nil.
    public var exactValue: Int? {
        if case let .exact(v) = self { return v }
        return nil
    }
}

/// Registro de una serie. Núcleo del registro rápido (spec §5, §7).
/// Conserva carga original y unidad; la normalización se calcula, no se almacena como única verdad.
public struct SetRecord: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let load: Load
    /// Repeticiones: entero positivo para una serie completada normal. `nil` para un intento
    /// fallido sin repeticiones (no se convierte en 0 — spec §7).
    public let reps: Int?
    public let type: SetType
    public let state: SetState
    public let side: BodySide
    public let rir: RIR?
    /// Instante absoluto de confirmación (para vistas de tiempo transcurrido).
    public let performedAt: Date
    /// Versión de atribución vigente al registrar (spec §10.4).
    public let attributionVersion: AttributionVersion

    public init(
        id: UUID = UUID(),
        load: Load,
        reps: Int?,
        type: SetType = .working,
        state: SetState = .completed,
        side: BodySide = .bilateral,
        rir: RIR? = nil,
        performedAt: Date,
        attributionVersion: AttributionVersion = .initial
    ) {
        self.id = id
        self.load = load
        self.reps = reps
        self.type = type
        self.state = state
        self.side = side
        self.rir = rir
        self.performedAt = performedAt
        self.attributionVersion = attributionVersion
    }

    /// Una serie es elegible para conteo de trabajo y récords cuando es de trabajo,
    /// completada, no eliminada y tiene repeticiones válidas (spec §7, §10.1, §14).
    /// RIR desconocido NO la invalida (T08).
    public var isEligibleForWorkCount: Bool {
        type == .working
            && state == .completed
            && (reps ?? 0) > 0
    }

    /// Validación de entrada de la serie (spec §7). Devuelve errores encontrados.
    public func validationErrors() -> [SetValidationError] {
        var errors: [SetValidationError] = []

        // Carga: cuando es conocida y la convención no es asistencia/none, debe ser no negativa.
        if let amount = load.amount {
            if amount < 0 && load.convention != .assistance {
                errors.append(.negativeLoad)
            }
        }

        // Repeticiones: una serie de trabajo completada necesita entero positivo.
        if type == .working && state == .completed {
            if let reps {
                if reps <= 0 { errors.append(.nonPositiveReps) }
            } else {
                errors.append(.missingReps)
            }
        }

        // RIR: no negativo.
        if case let .exact(v) = rir, v < 0 { errors.append(.negativeRIR) }
        if case let .atLeast(v) = rir, v < 0 { errors.append(.negativeRIR) }

        return errors
    }

    public var isValid: Bool { validationErrors().isEmpty }
}

public enum SetValidationError: String, Error, Sendable, Equatable {
    case negativeLoad
    case nonPositiveReps
    case missingReps
    case negativeRIR
}
