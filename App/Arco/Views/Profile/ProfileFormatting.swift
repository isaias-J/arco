import Foundation
import ArcoCore

/// Utilidades de presentación compartidas por las vistas de Perfil y Progreso.
/// No alteran los registros: solo convierten para mostrar (spec §7: la unidad original se conserva).
enum ProfileFormat {
    /// Número con coma/punto según la configuración regional y hasta `maxDecimals` decimales.
    static func number(_ value: Decimal, maxDecimals: Int = 1) -> String {
        NSDecimalNumber(decimal: value).doubleValue
            .formatted(.number.precision(.fractionLength(0...maxDecimals)))
    }

    static func number(_ value: Double, maxDecimals: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...maxDecimals)))
    }

    /// Kilogramos → unidad de visualización configurada.
    static func mass(kilograms: Decimal, in unit: MassUnit) -> Decimal {
        UnitConverter.convertMass(kilograms, from: .kilograms, to: unit)
    }

    /// Texto "72,5 kg" en la unidad configurada a partir de kilogramos.
    static func massText(kilograms: Decimal, unit: MassUnit, maxDecimals: Int = 1) -> String {
        "\(number(mass(kilograms: kilograms, in: unit), maxDecimals: maxDecimals)) \(unit.rawValue)"
    }

    /// Longitud en cualquier unidad → unidad objetivo (vía metros, sin redondeo intermedio).
    static func length(_ amount: Decimal, from source: LengthUnit, to target: LengthUnit) -> Decimal {
        if source == target { return amount }
        return UnitConverter.meters(amount, from: source) / target.metersPerUnit
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month().year())
    }

    /// "hoy", "hace 1 día", "hace N días" desde la fecha de medición (spec §18: antigüedad).
    static func age(of date: Date, now: Date = Date(), calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "medido hoy"
        case 1: return "medido hace 1 día"
        default: return "medido hace \(days) días"
        }
    }
}

/// Validación de valores corporales positivos (spec §7: peso, altura y perímetros positivos y
/// finitos; vacío, 0, negativos y textos ambiguos se rechazan sin corregirlos).
enum BodyValueValidation {
    enum Outcome: Equatable {
        case valid(Decimal)
        case empty
        case notANumber
        case notPositive
    }

    static func validate(_ text: String, locale: Locale = .current) -> Outcome {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return .empty }
        if trimmed.hasPrefix("-") || trimmed.hasPrefix("−") { return .notPositive }
        guard let value = DecimalParser(locale: locale).parse(trimmed) else { return .notANumber }
        guard value > 0 else { return .notPositive }
        return .valid(value)
    }

    static func message(for outcome: Outcome) -> String? {
        switch outcome {
        case .valid, .empty: return nil
        case .notANumber: return "No se reconoce el número. Usa solo cifras y un separador decimal (por ejemplo 72,5)."
        case .notPositive: return "El valor debe ser mayor que cero."
        }
    }
}
