import Foundation

/// Punto de una serie de gráfico. Distingue ausencia de dato de un cero confirmado (spec §12).
public struct ChartPoint: Sendable, Equatable {
    public let date: Date
    /// Valor observado. `nil` = sin registro (NO se dibuja como cero — T32).
    public let value: Decimal?
    public init(date: Date, value: Decimal?) {
        self.date = date
        self.value = value
    }
}

/// Estado de un periodo para etiquetar parciales (spec §12, T33).
public struct PeriodStatus: Sendable, Equatable {
    public let isPartial: Bool
    public let label: String
}

public enum ChartAnalytics {

    /// Serie de mayor carga por sesión. No rellena fechas ausentes con cero (T32): las fechas
    /// sin dato simplemente no aparecen como puntos de valor 0.
    ///
    /// Solo cuentan cargas que representan peso movido: la asistencia (más cifra = menos
    /// dificultad) y "sin carga" se excluyen para no mostrarlas como peso levantado (spec §7,
    /// T26). El llamador debe pasar series de una misma variante/convención comparable.
    public static func maxLoadPerSession(_ sessions: [(date: Date, sets: [SetRecord])]) -> [ChartPoint] {
        sessions.map { session in
            let eligible = session.sets.filter {
                $0.isEligibleForWorkCount
                    && $0.load.kilograms != nil
                    && $0.load.convention.isLiftedLoad
            }
            let maxKg = eligible.compactMap { $0.load.kilograms }.max()
            return ChartPoint(date: session.date, value: maxKg)
        }
        .sorted { $0.date < $1.date }
    }

    /// Comparación porcentual segura (spec §12, T31): si el valor anterior es 0 o ausente,
    /// no divide (devuelve nil para evitar porcentaje infinito).
    public static func percentChange(previous: Decimal?, current: Decimal?) -> Decimal? {
        guard let previous, previous != 0, let current else { return nil }
        return (current - previous) / previous * 100
    }

    /// Determina si la semana en curso es parcial respecto a la fecha de referencia (T33).
    public static func weekStatus(weekStart: Date, reference: Date, calendar: Calendar) -> PeriodStatus {
        guard let weekEnd = calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: weekStart)) else {
            return PeriodStatus(isPartial: true, label: "period.partial")
        }
        let isPartial = calendar.startOfDay(for: reference) < calendar.startOfDay(for: weekEnd)
        return PeriodStatus(isPartial: isPartial, label: isPartial ? "period.partial" : "period.complete")
    }
}
