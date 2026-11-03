import Foundation

/// Interpreta números decimales respetando el separador de la configuración regional (spec §7):
/// "2,5" en es-ES no debe convertirse en 25. Valida formatos ambiguos.
public struct DecimalParser: Sendable {
    private let decimalSeparator: String
    private let groupingSeparator: String

    public init(locale: Locale) {
        self.decimalSeparator = locale.decimalSeparator ?? "."
        self.groupingSeparator = locale.groupingSeparator ?? ","
    }

    /// Crea un parser con separadores explícitos (útil en pruebas).
    public init(decimalSeparator: String, groupingSeparator: String) {
        self.decimalSeparator = decimalSeparator
        self.groupingSeparator = groupingSeparator
    }

    /// Devuelve el `Decimal` si el texto es un número válido, o nil. No convierte vacío en 0.
    public func parse(_ text: String) -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Quitar separadores de millar y normalizar el separador decimal a ".".
        var normalized = trimmed.replacingOccurrences(of: groupingSeparator, with: "")
        if decimalSeparator != "." {
            // Rechazar si hay puntos usados como decimales junto a comas ambiguas.
            normalized = normalized.replacingOccurrences(of: decimalSeparator, with: ".")
        }

        // Debe contener solo dígitos y a lo sumo un punto.
        let allowed = CharacterSet(charactersIn: "0123456789.")
        guard normalized.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        guard normalized.filter({ $0 == "." }).count <= 1 else { return nil }

        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
