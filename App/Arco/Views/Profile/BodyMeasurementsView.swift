import SwiftUI
import SwiftData
import Charts
import ArcoCore

/// Medidas corporales (spec §18). Tipos iniciales (cintura, pecho, cadera, brazo, muslo,
/// pantorrilla) + personalizadas; lado izquierdo/derecho cuando aplique. Cada medida guarda
/// fecha, unidad y protocolo breve. Gráfico por medida con cambio absoluto y periodo.
///
/// Honestidad (spec §18, §9):
/// - Un cambio de protocolo se identifica en el gráfico y no se mezcla con otro protocolo (T59).
/// - No se mezclan izquierdo/derecho como una misma serie (T59).
/// - No se deriva porcentaje de grasa ni metas de peso automáticas.
struct BodyMeasurementsView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \BodyMeasurementModel.date, order: .reverse) private var measurements: [BodyMeasurementModel]

    @State private var showAdd = false

    /// Agrupa por clave de tipo para mostrar una tarjeta por medida.
    private var groupedTypes: [MeasurementTypeGroup] {
        let grouped = Dictionary(grouping: measurements) { $0.typeKey }
        return grouped
            .map { key, items in
                MeasurementTypeGroup(
                    typeKey: key,
                    latestDate: items.map(\.date).max() ?? .distantPast,
                    measurements: items
                )
            }
            .sorted { $0.latestDate > $1.latestDate }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if groupedTypes.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedTypes) { group in
                        MeasurementTypeCard(group: group, displayUnit: appState.settings.lengthUnit, onDelete: delete)
                    }
                }
                disclaimerCard
            }
            .padding(Spacing.lg)
        }
        .background(ArcoColor.background)
        .navigationTitle("Medidas corporales")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: {
                    Label("Añadir medida", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAdd) {
            AddBodyMeasurementView()
        }
    }

    private func delete(_ measurement: BodyMeasurementModel) {
        appState.context.delete(measurement)
        try? appState.context.save()
    }

    private var emptyState: some View {
        ArcoCard {
            VStack(spacing: Spacing.sm) {
                Text("Sin medidas registradas")
                    .font(.headline)
                Text("Añade un perímetro (cintura, pecho, brazo…). Cada medida guarda su fecha, unidad y un protocolo breve para que compares lo comparable.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Añadir medida") { showAdd = true }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var disclaimerCard: some View {
        ArcoCard {
            Text("Un aumento de perímetro no equivale a músculo puro ni una reducción implica pérdida muscular. Esta sección no estima porcentaje de grasa ni fija metas de peso.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Tarjeta por tipo de medida

/// Tarjeta de una medida concreta. Separa series por lado y por protocolo (T59): nunca mezcla
/// izquierdo/derecho ni protocolos distintos en una sola línea.
private struct MeasurementTypeCard: View {
    let group: MeasurementTypeGroup
    /// Unidad de longitud configurada: todos los valores se convierten a ella antes de graficar
    /// o calcular cambios (hallazgo 12: nunca se mezclan cm y pulgadas sin convertir).
    let displayUnit: LengthUnit
    let onDelete: (BodyMeasurementModel) -> Void

    /// Series separadas por (lado, protocolo). Cada combinación es una línea distinta (T59).
    private var series: [MeasurementSeries] {
        let grouped = Dictionary(grouping: group.measurements) { m in
            MeasurementSeriesKey(side: BodySide(rawValue: m.sideRaw) ?? .bilateral, protocolNote: m.protocolNote)
        }
        return grouped
            .map { key, items in
                MeasurementSeries(
                    key: key,
                    points: items.sorted { $0.date < $1.date }
                )
            }
            .sorted { $0.seriesLabel < $1.seriesLabel }
    }

    var body: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(MeasurementType.displayName(for: group.typeKey))
                    .font(.headline)

                ForEach(series) { s in
                    MeasurementSeriesSection(series: s, displayUnit: displayUnit, onDelete: onDelete)
                    if s.id != series.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

/// Una serie (lado + protocolo): gráfico de puntos, cambio absoluto y periodo comparable.
/// Todos los valores se convierten a la unidad configurada (vía metros) antes de graficar o
/// restar; la tabla muestra además el valor original si se registró en otra unidad.
private struct MeasurementSeriesSection: View {
    let series: MeasurementSeries
    let displayUnit: LengthUnit
    let onDelete: (BodyMeasurementModel) -> Void

    @State private var pendingDelete: BodyMeasurementModel?

    private var unitLabel: String { displayUnit.rawValue }

    private func converted(_ m: BodyMeasurementModel) -> Decimal {
        ProfileFormat.length(m.amount, from: LengthUnit(rawValue: m.unitRaw) ?? .centimeters, to: displayUnit)
    }

    private var values: [(id: UUID, date: Date, value: Double)] {
        series.points.map { ($0.id, $0.date, NSDecimalNumber(decimal: converted($0)).doubleValue) }
    }

    /// Cambio absoluto entre la primera y la última observación (spec §18), en la unidad
    /// configurada. No es porcentaje ni se proclama "crecimiento": es la diferencia observada.
    private var absoluteChange: Decimal? {
        guard series.points.count >= 2,
              let first = series.points.first,
              let last = series.points.last else { return nil }
        return converted(last) - converted(first)
    }

    private var periodLabel: String? {
        guard let first = series.points.first?.date,
              let last = series.points.last?.date,
              series.points.count >= 2 else { return nil }
        return "\(ProfileFormat.date(first)) – \(ProfileFormat.date(last))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Etiqueta de serie: lado + protocolo. El protocolo se identifica (T59).
            Text(series.seriesLabel)
                .font(.subheadline.bold())

            if values.count >= 2 {
                Chart(values, id: \.id) { item in
                    LineMark(
                        x: .value("Fecha", item.date),
                        y: .value("Medida (\(unitLabel))", item.value)
                    )
                    .interpolationMethod(.linear)
                    .foregroundStyle(ArcoColor.chart)
                    PointMark(
                        x: .value("Fecha", item.date),
                        y: .value("Medida (\(unitLabel))", item.value)
                    )
                    .foregroundStyle(ArcoColor.chart)
                    .accessibilityLabel(ProfileFormat.date(item.date))
                    .accessibilityValue("\(ProfileFormat.number(item.value)) \(unitLabel)")
                }
                .frame(height: 160)
                .chartXAxisLabel("Fecha")
                .chartYAxisLabel("Medida (\(unitLabel))")
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks(position: .leading) }
                .accessibilityLabel("Evolución de \(series.seriesLabel), en \(unitLabel)")
            } else {
                Text("Una sola observación: añade otra para ver la evolución.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let change = absoluteChange, let period = periodLabel {
                HStack {
                    Text("Cambio absoluto")
                    Spacer()
                    Text("\(signedString(change)) \(unitLabel)")
                        .monospacedDigit()
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
                Text(period)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Alternativa textual al gráfico (accesibilidad, spec §18/§12) y borrado.
            DisclosureGroup("Ver como tabla") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(series.points, id: \.id) { m in
                        HStack {
                            Text(ProfileFormat.date(m.date))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(ProfileFormat.number(converted(m), maxDecimals: 2)) \(unitLabel)")
                                    .monospacedDigit()
                                if m.unitRaw != displayUnit.rawValue {
                                    Text("registrado: \(ProfileFormat.number(m.amount, maxDecimals: 2)) \(m.unitRaw)")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Button(role: .destructive) {
                                pendingDelete = m
                            } label: {
                                Image(systemName: "trash")
                                    .frame(minWidth: 44, minHeight: 44)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Borrar medida del \(ProfileFormat.date(m.date))")
                        }
                        .font(.caption)
                    }
                }
                .padding(.top, Spacing.xs)
            }
            .font(.caption)
        }
        .confirmationDialog(
            "¿Borrar esta medida?",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Borrar", role: .destructive) {
                if let m = pendingDelete { onDelete(m) }
                pendingDelete = nil
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("Se elimina solo este registro; el resto del historial se conserva.")
        }
    }

    private func signedString(_ value: Decimal) -> String {
        let s = ProfileFormat.number(value, maxDecimals: 2)
        return value > 0 ? "+\(s)" : s
    }
}

// MARK: - Alta de medida

/// Alta de medida (spec §18): tipo (inicial o personalizado), lado si aplica, valor, unidad,
/// fecha y protocolo breve. No se registra una medición futura como realizada (fecha ≤ hoy).
struct AddBodyMeasurementView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: MeasurementType = .waist
    @State private var customName = ""
    @State private var side: BodySide = .bilateral
    @State private var amountText = ""
    @State private var protocolNote = ""
    @State private var date = Date()
    @State private var showValidation = false

    private var resolvedTypeKey: String? {
        if selectedType == .custom {
            let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return "custom:\(trimmed)"
        }
        return selectedType.typeKey
    }

    /// Valor > 0 (spec §7): vacío, 0, negativos y textos ambiguos se rechazan.
    private var outcome: BodyValueValidation.Outcome { BodyValueValidation.validate(amountText) }

    private var canSave: Bool {
        resolvedTypeKey != nil && outcome != .empty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tipo de medida") {
                    Picker("Medida", selection: $selectedType) {
                        ForEach(MeasurementType.allCases) { Text($0.displayName).tag($0) }
                    }
                    if selectedType == .custom {
                        TextField("Nombre de la medida", text: $customName)
                    }
                    if selectedType.supportsSides {
                        Picker("Lado", selection: $side) {
                            Text("Bilateral").tag(BodySide.bilateral)
                            Text("Izquierdo").tag(BodySide.left)
                            Text("Derecho").tag(BodySide.right)
                        }
                    }
                }

                Section {
                    HStack {
                        TextField("Medida", text: $amountText)
                            .keyboardType(.decimalPad)
                        Text(appState.settings.lengthUnit.rawValue)
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: .date)
                } header: {
                    Text("Valor")
                } footer: {
                    if showValidation, let message = BodyValueValidation.message(for: outcome) {
                        Text(message).foregroundStyle(.red)
                    }
                }

                Section("Protocolo") {
                    TextField("Punto de medición, relajado/contraído…", text: $protocolNote, axis: .vertical)
                        .lineLimit(1...3)
                    Text("Un cambio de protocolo se identifica en el gráfico y no se compara como si fuera idéntico.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Añadir medida")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let typeKey = resolvedTypeKey else { return }
        guard case .valid(let amount) = outcome else { showValidation = true; return }
        let effectiveSide: BodySide = selectedType.supportsSides ? side : .bilateral
        appState.context.insert(BodyMeasurementModel(
            typeKey: typeKey,
            sideRaw: effectiveSide.rawValue,
            protocolNote: protocolNote.trimmingCharacters(in: .whitespacesAndNewlines),
            amount: amount,
            unitRaw: appState.settings.lengthUnit.rawValue,
            date: min(date, Date())
        ))
        try? appState.context.save()
        dismiss()
    }
}

// MARK: - Modelos de apoyo (UI)

/// Tipos iniciales de medida (spec §18) + personalizada. `typeKey` es la clave estable guardada.
enum MeasurementType: String, CaseIterable, Identifiable {
    case waist, chest, hip, arm, thigh, calf, custom
    var id: String { rawValue }

    var typeKey: String { rawValue }

    var displayName: String {
        switch self {
        case .waist: return "Cintura"
        case .chest: return "Pecho"
        case .hip: return "Cadera"
        case .arm: return "Brazo"
        case .thigh: return "Muslo"
        case .calf: return "Pantorrilla"
        case .custom: return "Personalizada"
        }
    }

    /// Lados izquierdo/derecho aplican a extremidades (spec §18).
    var supportsSides: Bool {
        switch self {
        case .arm, .thigh, .calf: return true
        case .waist, .chest, .hip, .custom: return false
        }
    }

    /// Nombre en español a partir de una `typeKey` almacenada (incluye "custom:Nombre").
    static func displayName(for typeKey: String) -> String {
        if typeKey.hasPrefix("custom:") {
            return String(typeKey.dropFirst("custom:".count))
        }
        return MeasurementType(rawValue: typeKey)?.displayName ?? typeKey
    }
}

/// Grupo de medidas de un mismo tipo.
private struct MeasurementTypeGroup: Identifiable {
    let typeKey: String
    let latestDate: Date
    let measurements: [BodyMeasurementModel]
    var id: String { typeKey }
}

/// Clave de una serie: lado + protocolo. Distingue series que no deben mezclarse (T59).
private struct MeasurementSeriesKey: Hashable {
    let side: BodySide
    let protocolNote: String
}

/// Una serie homogénea (mismo lado y mismo protocolo).
private struct MeasurementSeries: Identifiable {
    let key: MeasurementSeriesKey
    let points: [BodyMeasurementModel]
    var id: String { "\(key.side.rawValue)|\(key.protocolNote)" }

    var seriesLabel: String {
        let sideText: String
        switch key.side {
        case .bilateral: sideText = ""
        case .left: sideText = "Izquierdo"
        case .right: sideText = "Derecho"
        }
        let proto = key.protocolNote.isEmpty ? "Sin protocolo indicado" : key.protocolNote
        if sideText.isEmpty {
            return proto
        }
        return "\(sideText) · \(proto)"
    }
}

// MARK: - Preview

#Preview("Medidas corporales") {
    let container = try! ModelContainer(
        for: BodyMeasurementModel.self, AppSettingsModel.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let calendar = Calendar.current

    // Cintura (bilateral) con dos protocolos distintos → dos series separadas (T59).
    for (offset, cm, proto) in [(-40, 82.0, "relajado"), (-20, 81.0, "relajado"), (-10, 79.0, "contraído")] {
        let date = calendar.date(byAdding: .day, value: offset, to: Date())!
        context.insert(BodyMeasurementModel(
            typeKey: "waist", sideRaw: "bilateral", protocolNote: proto,
            amount: Decimal(cm), unitRaw: "cm", date: date
        ))
    }
    // Brazo por lados → izquierdo y derecho no se mezclan (T59).
    for (offset, cm, sideRaw) in [(-30, 34.0, "left"), (-30, 35.0, "right"), (-5, 34.5, "left"), (-5, 35.5, "right")] {
        let date = calendar.date(byAdding: .day, value: offset, to: Date())!
        context.insert(BodyMeasurementModel(
            typeKey: "arm", sideRaw: sideRaw, protocolNote: "contraído",
            amount: Decimal(cm), unitRaw: "cm", date: date
        ))
    }

    return NavigationStack {
        BodyMeasurementsView()
    }
    .environment(AppState(context: context))
    .modelContainer(container)
}
