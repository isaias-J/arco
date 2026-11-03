import SwiftUI
import ArcoCore

/// Biblioteca de fuentes (spec §9, §24): tipos de información que muestra Arco, método de
/// conteo fraccional con sus límites y cada fuente con alcance, enlace y fecha de revisión.
struct EvidenceLibraryView: View {
    var body: some View {
        List {
            Section {
                InfoKindRow(title: "Dato observado", detail: "Lo que registras tú: carga, repeticiones, series, fechas, medidas y fotos.", symbol: "eye")
                InfoKindRow(title: "Dato calculado", detail: "Resultado directo de tus datos: IMC, conteos de series, conversiones de unidad y tendencias.", symbol: "function")
                InfoKindRow(title: "Estimación", detail: "Aproximaciones con incertidumbre: aporte indirecto, fuerza máxima estimada (Epley) y cobertura por región.", symbol: "plusminus")
                InfoKindRow(title: "Heurística de producto", detail: "Decisiones de diseño de Arco: orden de las sugerencias, umbrales para una observación y tu regla de progresión.", symbol: "lightbulb")
            } header: {
                Text("Qué tipo de información ves")
            } footer: {
                Text("Ninguna cifra de Arco es un diagnóstico ni una medida directa de crecimiento muscular. La fuerza registrada mide rendimiento, no hipertrofia (E05).")
            }

            Section {
                Text("Cada serie de trabajo cuenta 1 como directa (D) o 1 como indirecta (I) para cada músculo según la atribución del ejercicio. La estimación fraccional es F = D + 0,5 × I; las series sin atribución resuelta se muestran aparte (U).")
                    .font(.footnote)
                Text("El factor 0,5 es una convención respaldada como modelo agregado (E02). No garantiza que cada ejercicio aporte media serie a cada músculo de cada persona: depende del movimiento y de la evidencia disponible (E06), y la activación EMG no se traduce en crecimiento (E07). La atribución inicial es la \(ExerciseCatalog.attributionVersion.description); las personalizadas por ti se marcan como tales.")
                    .font(.footnote).foregroundStyle(.secondary)
            } header: {
                Text("Método fraccional")
            }

            ForEach(EvidenceSource.Kind.allCases, id: \.self) { kind in
                Section(kind.displayName) {
                    ForEach(EvidenceLibrary.sources(of: kind)) { source in
                        SourceRow(source: source)
                    }
                }
            }

            Section {
                Text("Las fuentes orientan el producto en adultos sanos; no prueban una dosis óptima individual. Fecha de revisión de la biblioteca: \(EvidenceLibrary.reviewDate).")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Fuentes y método")
        .accessibilityIdentifier("evidence.list")
    }
}

private struct InfoKindRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.footnote).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: symbol).foregroundStyle(ArcoColor.brand)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SourceRow: View {
    let source: EvidenceSource

    private var heading: String {
        [source.id, source.authors, source.year.map(String.init)].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(heading).font(.caption.bold()).foregroundStyle(.secondary)
            Text(source.title).font(.subheadline)
            Text(source.scope).font(.footnote).foregroundStyle(.secondary)
            Text("Revisado: \(source.reviewed)").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: Spacing.md) {
                if let url = URL(string: source.url) {
                    Link("Abrir enlace", destination: url)
                        .font(.footnote)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Abrir enlace de \(source.id)")
                }
                ForEach(Array(source.additionalURLs.enumerated()), id: \.offset) { index, link in
                    if let url = URL(string: link) {
                        Link("Enlace \(index + 2)", destination: url)
                            .font(.footnote)
                            .frame(minHeight: 44)
                            .accessibilityLabel("Abrir enlace adicional \(index + 1) de \(source.id)")
                    }
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityIdentifier("evidence.\(source.id)")
    }
}
