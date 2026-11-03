import Foundation

/// Unidad de masa en la que el usuario registró u observa un valor.
/// La unidad original SIEMPRE se conserva en el registro; la normalización a
/// kilogramos se usa solo para cálculo y comparación (spec §7).
public enum MassUnit: String, Codable, Sendable, CaseIterable {
    case kilograms = "kg"
    case pounds = "lb"

    /// Factor exacto de conversión a kilogramos. 1 lb = 0,45359237 kg (spec §7, T23).
    /// Se usa `Decimal` para evitar deriva acumulativa en conversiones ida y vuelta.
    public var kilogramsPerUnit: Decimal {
        switch self {
        case .kilograms: return 1
        case .pounds: return Decimal(string: "0.45359237")!
        }
    }
}

/// Unidad de longitud para altura y perímetros corporales.
public enum LengthUnit: String, Codable, Sendable, CaseIterable {
    case centimeters = "cm"
    case inches = "in"

    /// Metros por unidad. 1 in = 0,0254 m exacto.
    public var metersPerUnit: Decimal {
        switch self {
        case .centimeters: return Decimal(string: "0.01")!
        case .inches: return Decimal(string: "0.0254")!
        }
    }
}

/// Convención de carga de una serie. Diferenciar estas convenciones es obligatorio:
/// no se comparan ni se suman entre sí sin contexto (spec §7).
public enum LoadConvention: String, Codable, Sendable, CaseIterable {
    /// Peso externo total, incluyendo barra si la hay. Convención por defecto para barra.
    case externalTotal
    /// Peso por mancuerna (se muestra "kg por mancuerna", no se duplica — T24).
    case perDumbbell
    /// Valor nominal indicado por una máquina (no es fuerza real transmitida).
    case machineNominal
    /// Peso de asistencia: más cantidad = menos dificultad; nunca se premia como más fuerza (T26).
    case assistance
    /// Peso corporal, con lastre opcional.
    case bodyweight
    /// Ejercicio sin carga registrada (distinto de carga 0 desconocida).
    case none

    /// Indica si la cifra representa peso movido (comparable como "más carga"). La asistencia
    /// resta dificultad y "none" no tiene carga: ninguno es peso levantado (spec §7, T26).
    public var isLiftedLoad: Bool {
        switch self {
        case .externalTotal, .perDumbbell, .machineNominal, .bodyweight: return true
        case .assistance, .none: return false
        }
    }

    /// Texto de unidad mostrado junto al valor (spec §7: "kg por mancuerna").
    public func unitLabel(_ unit: MassUnit) -> String {
        switch self {
        case .perDumbbell: return "\(unit.rawValue) por mancuerna"
        case .machineNominal: return "\(unit.rawValue) (máquina)"
        case .assistance: return "\(unit.rawValue) de asistencia"
        case .bodyweight: return "\(unit.rawValue) de lastre"
        case .externalTotal, .none: return unit.rawValue
        }
    }

    /// Nombre corto en español para selectores.
    public var displayName: String {
        switch self {
        case .externalTotal: return "Peso total"
        case .perDumbbell: return "Por mancuerna"
        case .machineNominal: return "Máquina (nominal)"
        case .assistance: return "Asistencia"
        case .bodyweight: return "Peso corporal + lastre"
        case .none: return "Sin carga"
        }
    }

    /// Convención por defecto según el equipo del ejercicio (spec §7).
    public static func defaultFor(_ loadType: LoadType) -> LoadConvention {
        switch loadType {
        case .barbell, .mixed: return .externalTotal
        case .dumbbell: return .perDumbbell
        case .machine, .cable: return .machineNominal
        case .bodyweight: return .bodyweight
        }
    }
}

/// Un valor de carga con su unidad y convención. Un valor "desconocido" se representa
/// con `amount == nil`, NUNCA con 0 (spec §7: diferenciar desconocido y cero).
public struct Load: Codable, Sendable, Equatable {
    /// Cantidad en la unidad original. `nil` = desconocido. 0 solo es válido cuando la
    /// convención lo permite (p. ej. `bodyweight` sin lastre, o `none`).
    public let amount: Decimal?
    public let unit: MassUnit
    public let convention: LoadConvention

    public init(amount: Decimal?, unit: MassUnit, convention: LoadConvention) {
        self.amount = amount
        self.unit = unit
        self.convention = convention
    }

    /// Carga desconocida para una convención dada.
    public static func unknown(unit: MassUnit = .kilograms, convention: LoadConvention) -> Load {
        Load(amount: nil, unit: unit, convention: convention)
    }

    public var isKnown: Bool { amount != nil }

    /// Carga normalizada a kilogramos para cálculo. `nil` si es desconocida.
    /// No se redondea aquí para evitar deriva acumulativa (T23).
    public var kilograms: Decimal? {
        guard let amount else { return nil }
        return amount * unit.kilogramsPerUnit
    }
}

/// Utilidades de conversión puras y exactas.
public enum UnitConverter {
    /// Convierte una cantidad entre unidades de masa sin deriva (usa Decimal exacto).
    public static func convertMass(_ amount: Decimal, from source: MassUnit, to target: MassUnit) -> Decimal {
        if source == target { return amount }
        let kilograms = amount * source.kilogramsPerUnit
        return kilograms / target.kilogramsPerUnit
    }

    /// Convierte una longitud a metros (para IMC).
    public static func meters(_ amount: Decimal, from unit: LengthUnit) -> Decimal {
        amount * unit.metersPerUnit
    }
}
