import SwiftUI
import Charts
import ArcoCore

/// Contexto de interpretación del IMC según la edad conocida (spec §18, T57).
enum BMIInterpretationPolicy: Equatable {
    /// Edad ≥ 18: referencia adulta NHS/NICE.
    case adult
    /// Edad desconocida: se muestra la referencia adulta indicando que aplica desde los 18.
    case unknownAge
    /// Menor de 18: no se interpreta (esta versión no usa percentiles pediátricos).
    case minor

    static func policy(age: Int?) -> BMIInterpretationPolicy {
        guard let age else { return .unknownAge }
        return age >= 18 ? .adult : .minor
    }

    var showsInterpretation: Bool { self != .minor }
}

extension BMIBand {
    /// Etiquetas estándar traducidas, con el rango de referencia (presentación neutral).
    var referenceLabel: String {
        switch self {
        case .underweight: return "Bajo peso (menos de 18,5)"
        case .healthy: return "Rango saludable (18,5 a menos de 25)"
        case .overweight: return "Sobrepeso (25 a menos de 30)"
        case .obese: return "Obesidad (30 o más)"
        }
    }
}

/// Sección de IMC actual (spec §18). El valor se calcula con la altura vigente en la fecha del
/// peso actual (`BMIHistory.height(at:)`).
struct BMICurrentSection: View {
    let bmi: BMIResult
    let usesAssumedHeight: Bool
    let policy: BMIInterpretationPolicy

    var body: some View {
        Section {
            HStack {
                Text("IMC")
                Spacer()
                Text(ProfileFormat.number(bmi.displayValue))
                    .font(.title3.bold()).monospacedDigit()
                if bmi.isEstimated {
                    Text("estimado").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            switch policy {
            case .adult, .unknownAge:
                Text(bmi.band.referenceLabel)
                if bmi.displayCrossesBoundary {
                    Text("Valor sin redondear: \(ProfileFormat.number(bmi.rawValue, maxDecimals: 3)). La categoría se calcula con este valor.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(policy == .adult
                     ? "Referencia adulta NHS/NICE (18+)."
                     : "Referencia adulta NHS/NICE, aplicable desde los 18 años. Indica tu fecha de nacimiento en Datos personales para confirmarlo.")
                    .font(.caption2).foregroundStyle(.secondary)
            case .minor:
                Text("No se muestra interpretación: la referencia adulta aplica desde los 18 años y esta versión no usa percentiles pediátricos.")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            if usesAssumedHeight {
                Text("Se usa una altura registrada después de este pesaje (supuesto).")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if bmi.isEstimated {
                Text("El peso actual es estimado, así que este IMC también lo es.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            DisclosureGroup("Limitaciones del IMC") {
                Text("El IMC = peso (kg) / altura (m)². No distingue músculo de grasa, no cambia por género y no hace predicciones. Las bandas son una referencia general, no una evaluación individual de riesgo: existen ajustes por población y situaciones clínicas que Arco no modela.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .font(.footnote)
        } header: {
            Text(policy == .minor ? "IMC" : "IMC · referencia adulta NHS/NICE (18+)")
        }
    }
}

/// Gráfico de IMC histórico (spec §18, T58). Cada punto usa la altura vigente en su fecha; los
/// estimados y los que usan una altura posterior se distinguen por forma y leyenda.
struct BMIHistoryChart: View {
    let points: [BMIHistory.Point]
    let showsReferenceLines: Bool

    private struct Item: Identifiable {
        let id: Int
        let date: Date
        let value: Double
        let kind: String
    }

    private static func kind(_ p: BMIHistory.Point) -> String {
        switch (p.bmi.isEstimated, p.usesLaterHeight) {
        case (false, false): return "Medido"
        case (true, false): return "Estimado"
        case (false, true): return "Altura supuesta"
        case (true, true): return "Estimado, altura supuesta"
        }
    }

    private var items: [Item] {
        points.enumerated().map { index, p in
            Item(id: index, date: p.date, value: NSDecimalNumber(decimal: p.bmi.rawValue).doubleValue, kind: Self.kind(p))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if items.isEmpty {
                Text("Sin datos: hace falta al menos un pesaje y una altura.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart {
                    if showsReferenceLines {
                        ForEach([18.5, 25.0, 30.0], id: \.self) { boundary in
                            RuleMark(y: .value("Frontera", boundary))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                                .foregroundStyle(.secondary)
                                .annotation(position: .top, alignment: .leading) {
                                    Text(ProfileFormat.number(boundary)).font(.caption2).foregroundStyle(.secondary)
                                }
                                .accessibilityHidden(true)
                        }
                    }
                    ForEach(items) { item in
                        PointMark(
                            x: .value("Fecha", item.date, unit: .day),
                            y: .value("IMC", item.value)
                        )
                        .symbol(by: .value("Tipo", item.kind))
                        .foregroundStyle(by: .value("Tipo", item.kind))
                        .accessibilityLabel(ProfileFormat.date(item.date))
                        .accessibilityValue("IMC \(ProfileFormat.number(item.value)), \(item.kind.lowercased())")
                    }
                }
                .chartForegroundStyleScale([
                    "Medido": ArcoColor.chart, "Estimado": Color.orange,
                    "Altura supuesta": ArcoColor.chartSecondary, "Estimado, altura supuesta": Color.pink
                ])
                .chartSymbolScale([
                    "Medido": .circle, "Estimado": .triangle,
                    "Altura supuesta": .square, "Estimado, altura supuesta": .diamond
                ])
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxisLabel("Fecha del pesaje")
                .chartYAxisLabel("IMC (kg/m²)")
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 200)
                .accessibilityLabel("IMC histórico, \(items.count) puntos")

                DisclosureGroup("Ver como tabla") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(items.reversed()) { item in
                            HStack {
                                Text(ProfileFormat.date(item.date))
                                Spacer()
                                Text(ProfileFormat.number(item.value)).monospacedDigit()
                                Text(item.kind.lowercased()).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, Spacing.xs)
                }
                .font(.caption)
            }
            Text("Cada punto usa la altura vigente en la fecha del pesaje. Una altura nueva no recalcula el pasado.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
