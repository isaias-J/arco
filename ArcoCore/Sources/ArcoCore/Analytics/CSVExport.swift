import Foundation

/// Exportación CSV de registros de entrenamiento (spec §19). UTF-8, caracteres españoles
/// correctos y tratamiento SEGURO de celdas que una hoja de cálculo podría interpretar como
/// fórmula (T69). No incluye secretos, claves ni PIN.
public enum CSVExport {

    /// Fila exportable (desacoplada de persistencia).
    public struct Row: Sendable {
        public let setID: String
        public let sessionID: String
        public let trainingDate: String   // fecha civil ISO
        public let timeZone: String
        public let exercise: String
        public let variant: String
        public let equipment: String
        public let type: String
        public let state: String
        public let load: String
        public let unit: String
        public let reps: String
        public let side: String
        public let rir: String

        public init(setID: String, sessionID: String, trainingDate: String, timeZone: String, exercise: String, variant: String, equipment: String, type: String, state: String, load: String, unit: String, reps: String, side: String, rir: String) {
            self.setID = setID; self.sessionID = sessionID; self.trainingDate = trainingDate
            self.timeZone = timeZone; self.exercise = exercise; self.variant = variant
            self.equipment = equipment; self.type = type; self.state = state; self.load = load
            self.unit = unit; self.reps = reps; self.side = side; self.rir = rir
        }

        var fields: [String] {
            [setID, sessionID, trainingDate, timeZone, exercise, variant, equipment, type, state, load, unit, reps, side, rir]
        }
    }

    public static let header = [
        "set_id", "session_id", "training_date", "time_zone", "exercise", "variant",
        "equipment", "type", "state", "load", "unit", "reps", "side", "rir"
    ]

    /// Genera el CSV completo. Usa CRLF entre filas y comillas RFC 4180.
    public static func generate(rows: [Row]) -> String {
        var lines: [String] = [header.map(escape).joined(separator: ",")]
        for row in rows {
            lines.append(row.fields.map(escape).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    /// Escapa un campo. Dos capas:
    /// 1) Prevención de inyección de fórmulas: si empieza por = + - @ (o tab/CR), se antepone
    ///    un apóstrofo para que la hoja de cálculo no lo evalúe (T69).
    /// 2) Comillas RFC 4180 si contiene coma, comilla o salto de línea.
    public static func escape(_ field: String) -> String {
        var value = field
        if let first = value.first, "=+-@\t\r".contains(first) {
            value = "'" + value
        }
        let needsQuoting = value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r")
        if needsQuoting {
            value = "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }

    /// Datos UTF-8 con BOM para que hojas de cálculo reconozcan tildes (spec §19).
    public static func data(rows: [Row]) -> Data {
        let bom = Data([0xEF, 0xBB, 0xBF])
        return bom + Data(generate(rows: rows).utf8)
    }
}
