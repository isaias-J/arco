import Foundation

/// Banda de IMC adulto según marco NHS/NICE 18+ (spec §18, B01/B02).
/// NO es clasificación CDC para menores de 20; se identifica el marco usado.
public enum BMIBand: String, Sendable {
    case underweight     // < 18,5
    case healthy         // 18,5 a < 25
    case overweight      // 25 a < 30
    case obese           // >= 30

    public var localizationKey: String { "bmi.band.\(rawValue)" }
}

/// Resultado del cálculo de IMC. Conserva el valor sin redondear para clasificar (T56)
/// y expone el valor mostrado con un decimal (T55).
public struct BMIResult: Sendable, Equatable {
    /// Valor exacto sin redondear (p. ej. 24,221453...). Se usa para la banda.
    public let rawValue: Decimal
    /// Si el peso usado fue estimado, el IMC resultante es estimado (spec §18).
    public let isEstimated: Bool

    public init(rawValue: Decimal, isEstimated: Bool) {
        self.rawValue = rawValue
        self.isEstimated = isEstimated
    }

    /// Banda calculada SOBRE el valor sin redondear (T56): 24,96 no pasa a 25.
    public var band: BMIBand {
        if rawValue < Decimal(string: "18.5")! { return .underweight }
        if rawValue < Decimal(string: "25")! { return .healthy }
        if rawValue < Decimal(string: "30")! { return .overweight }
        return .obese
    }

    /// Valor mostrado con 1 decimal (redondeo half-up). Presentación, no clasificación.
    public var displayValue: Decimal {
        var result = Decimal()
        var input = rawValue
        NSDecimalRound(&result, &input, 1, .plain)
        return result
    }

    /// Indica si el redondeo visual cruza una frontera respecto a la banda real,
    /// para mostrar precisión adicional y evitar contradicción aparente (spec §18).
    public var displayCrossesBoundary: Bool {
        let shown = BMIResult(rawValue: displayValue, isEstimated: isEstimated)
        return shown.band != band
    }
}

public enum BMICalculator {
    /// IMC = peso(kg) / altura(m)². Fórmula adulta, no cambia por género (spec §18).
    /// Devuelve nil si faltan datos o la altura no es positiva (no inventa resultado).
    public static func bmi(
        massKilograms: Decimal,
        heightMeters: Decimal,
        isEstimated: Bool
    ) -> BMIResult? {
        guard heightMeters > 0, massKilograms > 0 else { return nil }
        let value = massKilograms / (heightMeters * heightMeters)
        return BMIResult(rawValue: value, isEstimated: isEstimated)
    }

    /// Conveniencia con unidades de registro.
    public static func bmi(
        mass: Decimal, massUnit: MassUnit,
        height: Decimal, heightUnit: LengthUnit,
        isEstimated: Bool
    ) -> BMIResult? {
        let kg = mass * massUnit.kilogramsPerUnit
        let m = UnitConverter.meters(height, from: heightUnit)
        return bmi(massKilograms: kg, heightMeters: m, isEstimated: isEstimated)
    }
}
