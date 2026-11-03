import Foundation

/// Una medición de peso corporal (spec §5, §18). Conserva fecha de medición y de ingreso por
/// separado: registrar hoy un peso antiguo no mueve el "peso actual" (T52).
public struct BodyWeightEntry: Sendable, Identifiable, Equatable {
    public let id: UUID
    /// Fecha civil a la que corresponde la medición (editable).
    public let measurementDate: Date
    /// Instante en que se ingresó el dato en la app.
    public let enteredAt: Date
    public let amount: Decimal
    public let unit: MassUnit
    /// Medido vs estimado (spec §18). Un peso estimado produce IMC estimado.
    public let isEstimated: Bool

    public init(
        id: UUID = UUID(),
        measurementDate: Date,
        enteredAt: Date,
        amount: Decimal,
        unit: MassUnit,
        isEstimated: Bool
    ) {
        self.id = id
        self.measurementDate = measurementDate
        self.enteredAt = enteredAt
        self.amount = amount
        self.unit = unit
        self.isEstimated = isEstimated
    }

    public var kilograms: Decimal { amount * unit.kilogramsPerUnit }

    /// Un peso corporal válido es positivo (spec §7: valores positivos y finitos).
    /// Las entradas no válidas nunca se consideran "peso actual" ni entran en tendencias.
    public var isValid: Bool { amount > 0 && !amount.isNaN }
}

public struct WeightTrendPoint: Sendable, Equatable {
    public let date: Date          // día calendario
    public let averageKilograms: Decimal
}

public enum BodyWeightAnalytics {
    /// "Peso actual": medición VÁLIDA más reciente por fecha de medición, no la última fila
    /// editada (spec §18). Devuelve la entrada completa para poder indicar si es estimado.
    public static func currentWeight(from entries: [BodyWeightEntry]) -> BodyWeightEntry? {
        entries.filter(\.isValid).max { $0.measurementDate < $1.measurementDate }
    }

    /// Tendencia de 7 días (spec §18): promediar primero los pesajes MEDIDOS de cada fecha,
    /// luego las medias diarias de las últimas 7 fechas calendario. Se muestra (devuelve no vacío)
    /// solo cuando hay ≥3 fechas con medición. No imputa días ausentes.
    public static func sevenDayTrend(
        from entries: [BodyWeightEntry],
        endingOn referenceDate: Date,
        calendar: Calendar
    ) -> [WeightTrendPoint] {
        let measured = entries.filter { !$0.isEstimated && $0.isValid }
        guard let windowStart = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: referenceDate)) else { return [] }

        // Agrupar por día calendario dentro de la ventana.
        var byDay: [Date: [Decimal]] = [:]
        for e in measured {
            let day = calendar.startOfDay(for: e.measurementDate)
            if day >= windowStart && day <= calendar.startOfDay(for: referenceDate) {
                byDay[day, default: []].append(e.kilograms)
            }
        }
        guard byDay.count >= 3 else { return [] }  // ≥3 fechas con medición

        return byDay
            .map { day, values in
                let sum = values.reduce(Decimal(0), +)
                return WeightTrendPoint(date: day, averageKilograms: sum / Decimal(values.count))
            }
            .sorted { $0.date < $1.date }
    }
}
