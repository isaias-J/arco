import SwiftUI
import SwiftData
import Charts
import ArcoCore

// MARK: - Alta / edición de pesaje

/// Alta o edición de un pesaje (spec §18, T52–T54, hallazgo 11).
/// - Solo valores positivos: vacío, 0, negativos y texto ambiguo se rechazan.
/// - Cambio > 10 % respecto al peso actual válido: se pide confirmación, sin corregir el valor.
/// - Fecha de medición ≤ hoy; la fecha de ingreso se conserva aparte.
/// - Tras guardar un pesaje nuevo se ofrece "Añadir foto" / "Ahora no" (foto opcional).
struct WeightEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Query private var weights: [BodyWeightModel]

    /// `nil` = alta nueva.
    let editing: BodyWeightModel?

    @State private var amountText = ""
    @State private var isEstimated = false
    @State private var date = Date()
    @State private var showValidation = false
    @State private var confirmBigChange = false
    @State private var savedWeightID: UUID?
    @State private var saveFailed = false
    @State private var loaded = false

    init(editing: BodyWeightModel? = nil) {
        self.editing = editing
    }

    private var unit: MassUnit {
        editing.flatMap { MassUnit(rawValue: $0.unitRaw) } ?? appState.settings.massUnit
    }

    private var outcome: BodyValueValidation.Outcome { BodyValueValidation.validate(amountText) }

    /// Peso actual válido sin contar el registro que se edita.
    private var referenceWeight: BodyWeightEntry? {
        BodyWeightAnalytics.currentWeight(from: weights.filter { $0.id != editing?.id }.map { $0.toDomain() })
    }

    /// Diferencia relativa > 10 % respecto al peso actual válido (en kg, sin redondear).
    private func isBigChange(_ amount: Decimal) -> Bool {
        guard let ref = referenceWeight, ref.kilograms > 0 else { return false }
        let newKg = amount * unit.kilogramsPerUnit
        let diff = abs(newKg - ref.kilograms) / ref.kilograms
        return diff > Decimal(string: "0.1")!
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("Peso", text: $amountText)
                            .keyboardType(.decimalPad)
                            .accessibilityLabel("Peso en \(unit.rawValue)")
                        Text(unit.rawValue).foregroundStyle(.secondary)
                    }
                    DatePicker("Fecha de medición", selection: $date, in: ...Date(), displayedComponents: [.date])
                    Picker("Tipo", selection: $isEstimated) {
                        Text("Medido").tag(false)
                        Text("Estimado").tag(true)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if showValidation, let message = BodyValueValidation.message(for: outcome) {
                        Text(message).foregroundStyle(.red)
                    } else {
                        Text("El peso actual es la medición válida más reciente por fecha de medición.")
                    }
                }
            }
            .navigationTitle(editing == nil ? "Añadir pesaje" : "Editar pesaje")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: attemptSave)
                        .disabled(outcome == .empty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .alert("¿Guardar igualmente?", isPresented: $confirmBigChange) {
                Button("Guardar") { commit() }
                Button("Revisar", role: .cancel) {}
            } message: {
                if let ref = referenceWeight {
                    Text("Es un cambio grande respecto a \(ProfileFormat.massText(kilograms: ref.kilograms, unit: unit)); ¿guardar igualmente?")
                }
            }
            .alert("Pesaje guardado", isPresented: photoPromptBinding) {
                Button("Añadir foto") { addPhoto() }
                Button("Ahora no", role: .cancel) { dismiss() }
            } message: {
                Text("Puedes asociar una foto privada a este pesaje. Es opcional.")
            }
            .alert("No se pudo guardar", isPresented: $saveFailed) {
                Button("Aceptar", role: .cancel) {}
            } message: {
                Text("El valor sigue en pantalla. Inténtalo de nuevo.")
            }
            .onAppear(perform: load)
        }
    }

    private var photoPromptBinding: Binding<Bool> {
        Binding(get: { savedWeightID != nil }, set: { if !$0 { savedWeightID = nil } })
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let editing else { return }
        amountText = ProfileFormat.number(editing.amount, maxDecimals: 3)
        isEstimated = editing.isEstimated
        date = editing.measurementDate
    }

    private func attemptSave() {
        guard case .valid(let amount) = outcome else { showValidation = true; return }
        if isBigChange(amount) {
            confirmBigChange = true
        } else {
            commit()
        }
    }

    private func commit() {
        guard case .valid(let amount) = outcome else { showValidation = true; return }
        let measurementDate = min(date, Date())
        let id: UUID
        if let editing {
            editing.amount = amount
            editing.isEstimated = isEstimated
            editing.measurementDate = measurementDate
            id = editing.id
        } else {
            let model = BodyWeightModel(
                measurementDate: measurementDate, enteredAt: Date(),
                amount: amount, unitRaw: unit.rawValue, isEstimated: isEstimated
            )
            appState.context.insert(model)
            id = model.id
        }
        do {
            try appState.context.save()
        } catch {
            saveFailed = true
            return
        }
        if editing == nil {
            savedWeightID = id
        } else {
            dismiss()
        }
    }

    /// "Añadir foto": la sección Fotos consume el ID tras desbloquear la bóveda.
    private func addPhoto() {
        guard let id = savedWeightID else { return }
        appState.pendingPhotoWeightID = id
        appState.selectedTab = .photos
        savedWeightID = nil
        dismiss()
    }
}

// MARK: - Historial de pesajes

/// Historial con borrar (deslizar) y editar (toque). Al borrar el último, el peso actual vuelve
/// al anterior válido porque se recalcula desde los registros (T54).
struct WeightHistoryView: View {
    @Environment(AppState.self) private var appState
    @Query(sort: \BodyWeightModel.measurementDate, order: .reverse) private var weights: [BodyWeightModel]
    @State private var editing: BodyWeightModel?
    @State private var showAdd = false

    var body: some View {
        List {
            if weights.isEmpty {
                ContentUnavailableView {
                    Label("Sin pesajes", systemImage: "scalemass")
                } description: {
                    Text("Registra tu peso cuando quieras. No hace falta una foto.")
                } actions: {
                    Button("Añadir pesaje") { showAdd = true }
                }
            } else {
                Section {
                    ForEach(weights) { w in
                        Button { editing = w } label: {
                            WeightRow(weight: w, displayUnit: appState.settings.massUnit)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Toca para editar")
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Desliza para borrar. Toca un pesaje para editarlo.")
                }
            }
        }
        .navigationTitle("Historial de peso")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAdd = true } label: { Label("Añadir pesaje", systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { w in WeightEditorView(editing: w) }
        .sheet(isPresented: $showAdd) { WeightEditorView() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { appState.context.delete(weights[index]) }
        try? appState.context.save()
    }
}

private struct WeightRow: View {
    let weight: BodyWeightModel
    let displayUnit: MassUnit

    var body: some View {
        let entry = weight.toDomain()
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ProfileFormat.date(weight.measurementDate))
                if !Calendar.current.isDate(weight.enteredAt, inSameDayAs: weight.measurementDate) {
                    Text("Ingresado el \(ProfileFormat.date(weight.enteredAt))")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if weight.isEstimated {
                Text("estimado")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            if entry.isValid {
                Text(ProfileFormat.massText(kilograms: entry.kilograms, unit: displayUnit))
                    .monospacedDigit()
            } else {
                Text("valor no válido").foregroundStyle(.red).font(.caption)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Gráfico de peso

enum WeightChartPeriod: String, CaseIterable, Identifiable {
    case month, threeMonths, year, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .month: return "1 mes"
        case .threeMonths: return "3 meses"
        case .year: return "1 año"
        case .all: return "Todo"
        }
    }

    func cutoff(from now: Date, calendar: Calendar) -> Date? {
        switch self {
        case .month: return calendar.date(byAdding: .month, value: -1, to: now)
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: now)
        case .year: return calendar.date(byAdding: .year, value: -1, to: now)
        case .all: return nil
        }
    }
}

/// Gráfico de puntos de peso (spec §18): medidos y estimados con forma y leyenda distintas,
/// tendencia de 7 días solo si hay ≥3 fechas medidas. No rellena fechas vacías con cero.
struct WeightChartCard: View {
    let entries: [BodyWeightEntry]
    let unit: MassUnit
    let calendar: Calendar

    @State private var period: WeightChartPeriod = .threeMonths

    private struct Point: Identifiable {
        let id: UUID
        let date: Date
        let value: Double
        let isEstimated: Bool
        var kind: String { isEstimated ? "Estimado" : "Medido" }
    }

    private var points: [Point] {
        let now = Date()
        let cutoff = period.cutoff(from: now, calendar: calendar)
        return entries
            .filter { $0.isValid && (cutoff == nil || $0.measurementDate >= cutoff!) }
            .sorted { $0.measurementDate < $1.measurementDate }
            .map { e in
                Point(id: e.id, date: e.measurementDate,
                      value: NSDecimalNumber(decimal: ProfileFormat.mass(kilograms: e.kilograms, in: unit)).doubleValue,
                      isEstimated: e.isEstimated)
            }
    }

    /// Tendencia: media de las medias diarias medidas de los últimos 7 días (≥3 fechas).
    private var trend: (start: Date, end: Date, value: Double, days: Int)? {
        let now = Date()
        let daily = BodyWeightAnalytics.sevenDayTrend(from: entries, endingOn: now, calendar: calendar)
        guard !daily.isEmpty else { return nil }
        let sum = daily.reduce(Decimal(0)) { $0 + $1.averageKilograms }
        let mean = sum / Decimal(daily.count)
        let start = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now)) ?? now
        return (start, now, NSDecimalNumber(decimal: ProfileFormat.mass(kilograms: mean, in: unit)).doubleValue, daily.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Picker("Periodo", selection: $period) {
                ForEach(WeightChartPeriod.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if points.isEmpty {
                Text("Sin pesajes en este periodo.")
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(points) { p in
                        PointMark(
                            x: .value("Fecha", p.date, unit: .day),
                            y: .value("Peso (\(unit.rawValue))", p.value)
                        )
                        .symbol(by: .value("Tipo", p.kind))
                        .foregroundStyle(by: .value("Tipo", p.kind))
                        .accessibilityLabel(ProfileFormat.date(p.date))
                        .accessibilityValue("\(ProfileFormat.number(p.value)) \(unit.rawValue), \(p.kind.lowercased())")
                    }
                    if let trend {
                        RuleMark(
                            xStart: .value("Inicio", trend.start),
                            xEnd: .value("Fin", trend.end),
                            y: .value("Media de 7 días", trend.value)
                        )
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                        .foregroundStyle(ArcoColor.chartSecondary)
                        .accessibilityLabel("Media de 7 días")
                        .accessibilityValue("\(ProfileFormat.number(trend.value)) \(unit.rawValue)")
                    }
                }
                .chartForegroundStyleScale(["Medido": ArcoColor.chart, "Estimado": Color.orange])
                .chartSymbolScale(["Medido": .circle, "Estimado": .triangle])
                .chartXAxisLabel("Fecha de medición")
                .chartYAxisLabel("Peso (\(unit.rawValue))")
                .chartYScale(domain: .automatic(includesZero: false))
                .chartYAxis { AxisMarks(position: .leading) }
                .frame(height: 220)
                .accessibilityLabel("Gráfico de peso en \(unit.rawValue), \(points.count) pesajes")
            }

            if let trend {
                Text("Media de 7 días con \(trend.days) de 7 días medidos: \(ProfileFormat.number(trend.value)) \(unit.rawValue). Solo usa pesajes medidos; no imputa días sin dato.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("La media de 7 días aparece cuando hay al menos 3 fechas con peso medido en la última semana.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            if !points.isEmpty {
                DisclosureGroup("Ver como tabla") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(points.reversed()) { p in
                            HStack {
                                Text(ProfileFormat.date(p.date))
                                Spacer()
                                Text("\(ProfileFormat.number(p.value)) \(unit.rawValue)").monospacedDigit()
                                Text(p.kind.lowercased()).foregroundStyle(.secondary)
                            }
                            .font(.caption)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.top, Spacing.xs)
                }
                .font(.caption)
            }
        }
    }
}
