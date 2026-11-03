import SwiftUI
import SwiftData
import Charts
import ArcoCore

/// Gráfico por ejercicio y variante comparable (spec §12, §13, hallazgo 10, T25).
///
/// Las series se agrupan por comparabilidad = (variante del ejercicio en la sesión, convención de
/// carga de la serie). Un selector "Variante / convención" filtra TODO (gráfica, récords,
/// historial y e1RM) a una sola combinación: cambiar de máquina o variante produce otra serie,
/// nunca una sola línea mezclada.
/// - Mayor carga por sesión con puntos reales (sin ceros imputados — T32).
/// - La asistencia nunca aparece como récord ni como "mayor carga" (T26): solo historial.
/// - e1RM opcional y secundario (Epley con filtros conservadores); nunca "1RM real".
struct ExerciseProgressView: View {
    let exerciseID: String

    @Environment(AppState.self) private var appState
    @Query private var sessions: [WorkoutSessionModel]

    @State private var period: ChartPeriod = .threeMonths
    @State private var selectedKey: ComparableKey?
    /// Punto seleccionado en el gráfico (abre detalle de fecha/valor/series — spec §12).
    @State private var selectedDate: Date?

    init(exerciseID: String) {
        self.exerciseID = exerciseID
    }

    private var calendar: Calendar { appState.calendar }
    private var massUnit: MassUnit { appState.settings.massUnit }

    // MARK: - Datos derivados

    /// Todas las sesiones de este ejercicio, separadas por combinación comparable.
    private var seriesByKey: [ComparableKey: [ExerciseSessionData]] {
        var result: [ComparableKey: [UUID: ExerciseSessionData]] = [:]
        for session in sessions {
            for se in session.exercises where se.exerciseID == exerciseID {
                for model in se.sets {
                    let set = model.toDomain()
                    guard set.isEligibleForWorkCount else { continue }
                    let key = ComparableKey(variantKey: se.variantKey, convention: set.load.convention)
                    var data = result[key]?[session.id] ?? ExerciseSessionData(id: session.id, date: session.trainingDate, sets: [])
                    data.sets.append(set)
                    result[key, default: [:]][session.id] = data
                }
            }
        }
        return result.mapValues { dict in
            dict.values
                .map { ExerciseSessionData(id: $0.id, date: $0.date, sets: $0.sets.sorted { $0.performedAt < $1.performedAt }) }
                .sorted { $0.date < $1.date }
        }
    }

    /// Combinaciones existentes, la más reciente primero.
    private var options: [ComparableKey] {
        let all = seriesByKey
        return all.keys.sorted { a, b in
            let da = all[a]?.last?.date ?? .distantPast
            let db = all[b]?.last?.date ?? .distantPast
            return da == db ? a.id < b.id : da > db
        }
    }

    private var effectiveKey: ComparableKey? {
        if let selectedKey, options.contains(selectedKey) { return selectedKey }
        return options.first
    }

    private var unitLabel: String {
        (effectiveKey?.convention ?? .externalTotal).unitLabel(massUnit)
    }

    private var isLifted: Bool { effectiveKey?.convention.isLiftedLoad ?? true }

    /// Sesiones de la combinación elegida dentro del periodo.
    private var periodSessions: [ExerciseSessionData] {
        guard let key = effectiveKey, let all = seriesByKey[key] else { return [] }
        guard let cutoff = period.cutoff(from: Date(), calendar: calendar) else { return all }
        return all.filter { $0.date >= cutoff }
    }

    /// Mayor carga por sesión (T32: sin ceros imputados; asistencia excluida por el núcleo).
    private var maxLoadPoints: [ChartPoint] {
        guard isLifted else { return [] }
        return ChartAnalytics.maxLoadPerSession(periodSessions.map { (date: $0.date, sets: $0.sets) })
            .filter { $0.value != nil }
    }

    private var allPeriodSets: [SetRecord] { periodSessions.flatMap(\.sets) }

    /// Récord de carga: solo para cargas levantadas (nunca asistencia — T26).
    private var maxLoadRecord: PersonalRecord? {
        guard isLifted else { return nil }
        return RecordsEngine.maxLoadRecord(from: allPeriodSets.filter { $0.load.convention.isLiftedLoad })
    }

    private var repsRecord: PersonalRecord? {
        guard let kg = maxLoadRecord?.loadKilograms else { return nil }
        return RecordsEngine.repsRecord(from: allPeriodSets, atKilograms: kg)
    }

    /// e1RM opcional y secundario: solo puntos donde Epley es elegible.
    private var e1rmPoints: [ChartPoint] {
        guard isLifted else { return [] }
        return periodSessions.compactMap { data -> ChartPoint? in
            let estimates = data.sets.compactMap { set -> Decimal? in
                guard let reps = set.reps else { return nil }
                return EstimatedOneRM.epley(load: set.load, reps: reps, rir: set.rir)
            }
            guard let best = estimates.max() else { return nil }
            return ChartPoint(date: data.date, value: best)
        }
    }

    /// Semana en curso parcial (T33) — relevante para el periodo "Semana".
    private var weekIsPartial: Bool {
        let now = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        return ChartAnalytics.weekStatus(weekStart: weekStart, reference: now, calendar: calendar).isPartial
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                if options.isEmpty {
                    emptyState(title: "Sin series registradas", text: "Cuando registres series de trabajo de este ejercicio, aquí verás tu mayor carga por sesión, tus récords y el historial.")
                } else {
                    comparabilityCard
                    periodPicker
                    if periodSessions.isEmpty {
                        emptyState(title: "Sin series en este periodo", text: "Elige un periodo más amplio o registra una sesión de esta variante.")
                    } else if isLifted {
                        maxLoadCard
                        recordsCard
                        if !e1rmPoints.isEmpty { e1rmCard }
                        historyCard
                    } else {
                        nonLiftedNotice
                        historyCard
                    }
                }
            }
            .padding(Spacing.lg)
        }
        .background(ArcoColor.background)
        .navigationTitle(ExerciseNames.localized(exerciseID))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: selectedPointBinding) { detail in
            ExercisePointDetailSheet(detail: detail, massUnit: massUnit)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Selección → hoja de detalle

    private var selectedPointBinding: Binding<ExercisePointDetail?> {
        Binding(
            get: {
                guard let date = selectedDate,
                      let data = periodSessions.last(where: { calendar.isDate($0.date, inSameDayAs: date) })
                else { return nil }
                let maxKg = data.sets.filter { $0.load.convention.isLiftedLoad }.compactMap { $0.load.kilograms }.max()
                return ExercisePointDetail(id: data.id, date: data.date, maxKilograms: maxKg, unitLabel: unitLabel, sets: data.sets)
            },
            set: { newValue in
                if newValue == nil { selectedDate = nil }
            }
        )
    }

    // MARK: - Subvistas

    private var comparabilityCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Picker("Variante / convención", selection: Binding(
                    get: { effectiveKey },
                    set: { selectedKey = $0; selectedDate = nil }
                )) {
                    ForEach(options) { key in
                        Text(key.label).tag(Optional(key))
                    }
                }
                .pickerStyle(.menu)
                Text("Unidad: \(unitLabel)")
                    .font(.caption).foregroundStyle(.secondary)
                if options.count > 1 {
                    Text("Hay \(options.count) combinaciones de variante y convención. Se muestran por separado y no se comparan entre sí.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var periodPicker: some View {
        Picker("Periodo", selection: $period) {
            ForEach(ChartPeriod.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Periodo del gráfico")
    }

    private func emptyState(title: String, text: String) -> some View {
        ArcoCard {
            VStack(spacing: Spacing.sm) {
                Text(title).font(.headline)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var nonLiftedNotice: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                if effectiveKey?.convention == .assistance {
                    Label("Asistencia: más cifra = menos dificultad", systemImage: "info.circle")
                        .font(.subheadline.bold())
                    Text("Por eso no se calcula mayor carga ni récord de fuerza para esta convención. Solo se muestra el historial.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("Sin carga registrada", systemImage: "info.circle")
                        .font(.subheadline.bold())
                    Text("No hay carga que comparar; se muestra el historial de repeticiones.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var maxLoadCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Mayor carga por sesión")
                    .font(.headline)
                Text("Carga de trabajo más alta de cada sesión, en \(unitLabel). Es el peso más alto que registraste, no una prueba de máximo.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                MaxLoadChart(
                    points: maxLoadPoints,
                    massUnit: massUnit,
                    unitLabel: unitLabel,
                    selectedDate: $selectedDate,
                    calendar: calendar
                )
                .frame(height: 220)

                if period == .week && weekIsPartial {
                    Label("Semana en curso, incompleta", systemImage: "clock.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                DisclosureGroup("Ver como tabla") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(Array(maxLoadPoints.enumerated()), id: \.offset) { _, point in
                            HStack {
                                Text(ProfileFormat.date(point.date))
                                Spacer()
                                Text(point.value.map { "\(massText($0)) \(unitLabel)" } ?? "—")
                                    .monospacedDigit()
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

    private var recordsCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Récords")
                    .font(.headline)
                if let rec = maxLoadRecord {
                    recordRow(
                        title: "Mayor carga",
                        value: "\(massText(rec.loadKilograms)) \(unitLabel) × \(rec.reps) rep.",
                        date: rec.date,
                        side: rec.side
                    )
                }
                if let reps = repsRecord {
                    recordRow(
                        title: "Más repeticiones a esa carga",
                        value: "\(reps.reps) rep. a \(massText(reps.loadKilograms)) \(unitLabel)",
                        date: reps.date,
                        side: reps.side
                    )
                }
                if maxLoadRecord == nil {
                    Text("Todavía no hay récord en este periodo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Los récords se recalculan desde tus series: excluyen calentamientos, intentos y series eliminadas, y solo comparan esta variante y convención.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var e1rmCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Fuerza estimada (e1RM) · secundaria")
                    .font(.headline)
                Text(effectiveKey?.convention == .machineNominal
                     ? "Índice estimado de esta máquina con la fórmula de Epley (RIR 0–1, 2–10 rep.). No es fuerza general ni sustituye tus registros."
                     : "Estimación con la fórmula de Epley, solo en series elegibles (RIR 0–1, 2–10 rep., carga externa). No sustituye tus registros ni invita a probar máximos.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                E1RMChart(points: e1rmPoints, massUnit: massUnit, unitLabel: unitLabel)
                    .frame(height: 160)

                DisclosureGroup("Ver como tabla") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(Array(e1rmPoints.enumerated()), id: \.offset) { _, point in
                            HStack {
                                Text(ProfileFormat.date(point.date))
                                Spacer()
                                Text(point.value.map { "≈ \(massText($0)) \(unitLabel)" } ?? "—")
                                    .monospacedDigit()
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

    private var historyCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Historial de series")
                    .font(.headline)
                if effectiveKey?.convention == .assistance {
                    Text("Asistencia: más cifra = menos dificultad.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(periodSessions.reversed()) { data in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(data.date.formatted(.dateTime.weekday().day().month().year()))
                            .font(.subheadline.bold())
                        ForEach(Array(data.sets.enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text("Serie \(index + 1)")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(setSummary(set))
                                    .monospacedDigit()
                            }
                            .font(.caption)
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                    if data.id != periodSessions.first?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Helpers de presentación

    private func massText(_ kilograms: Decimal) -> String {
        ProfileFormat.number(ProfileFormat.mass(kilograms: kilograms, in: massUnit), maxDecimals: 2)
    }

    private func recordRow(title: String, value: String, date: Date, side: BodySide) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(ProfileFormat.date(date))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.subheadline.bold()).monospacedDigit()
                if side != .bilateral {
                    Text(ExerciseSideText.label(side)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value), \(ProfileFormat.date(date))")
    }

    private func setSummary(_ set: SetRecord) -> String {
        let load: String
        if let kg = set.load.kilograms {
            load = "\(massText(kg)) \(set.load.convention.unitLabel(massUnit))"
        } else if set.load.convention == .none {
            load = "sin carga"
        } else {
            load = "carga desconocida"
        }
        let reps = set.reps.map { "\($0) rep." } ?? "—"
        let side = set.side == .bilateral ? "" : " · \(ExerciseSideText.label(set.side))"
        return "\(load) × \(reps)\(side)"
    }
}

// MARK: - Modelos de apoyo (UI)

/// Combinación comparable: variante del ejercicio en la sesión + convención de carga (T25).
struct ComparableKey: Hashable, Identifiable {
    let variantKey: String?
    let convention: LoadConvention

    var id: String { "\(variantKey ?? "")|\(convention.rawValue)" }

    var variantLabel: String {
        let trimmed = (variantKey ?? "").trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Sin variante indicada" : trimmed
    }

    var label: String { "\(variantLabel) · \(convention.displayName)" }
}

enum ExerciseSideText {
    static func label(_ side: BodySide) -> String {
        switch side {
        case .bilateral: return "Bilateral"
        case .left: return "Izquierdo"
        case .right: return "Derecho"
        }
    }
}

/// Datos de una sesión para una combinación comparable (id estable = sesión).
private struct ExerciseSessionData: Identifiable {
    let id: UUID
    let date: Date
    var sets: [SetRecord]
}

/// Detalle de un punto seleccionado del gráfico (spec §12: fecha, valor y series originales).
struct ExercisePointDetail: Identifiable {
    let id: UUID
    let date: Date
    let maxKilograms: Decimal?
    let unitLabel: String
    let sets: [SetRecord]
}

/// Periodos del gráfico (spec §12): semana / mes / 3 meses / año / todo.
enum ChartPeriod: String, CaseIterable, Identifiable {
    case week, month, threeMonths, year, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .week: return "Semana"
        case .month: return "Mes"
        case .threeMonths: return "3 meses"
        case .year: return "Año"
        case .all: return "Todo"
        }
    }

    /// Fecha de corte inferior del periodo; `nil` para "todo".
    func cutoff(from reference: Date, calendar: Calendar) -> Date? {
        switch self {
        case .week: return calendar.date(byAdding: .day, value: -7, to: reference)
        case .month: return calendar.date(byAdding: .month, value: -1, to: reference)
        case .threeMonths: return calendar.date(byAdding: .month, value: -3, to: reference)
        case .year: return calendar.date(byAdding: .year, value: -1, to: reference)
        case .all: return nil
        }
    }
}

// MARK: - Gráficos (subvistas)

/// Gráfico de mayor carga por sesión. Puntos reales + línea de conexión visual lineal (sin
/// sobrepasos ni ceros imputados — T32).
private struct MaxLoadChart: View {
    let points: [ChartPoint]
    let massUnit: MassUnit
    let unitLabel: String
    @Binding var selectedDate: Date?
    let calendar: Calendar

    private struct Item: Identifiable {
        let id: Int
        let date: Date
        let value: Double
    }

    private var items: [Item] {
        points.enumerated().compactMap { index, p in
            guard let v = p.value else { return nil }
            return Item(id: index, date: p.date, value: NSDecimalNumber(decimal: ProfileFormat.mass(kilograms: v, in: massUnit)).doubleValue)
        }
    }

    var body: some View {
        Chart {
            ForEach(items) { item in
                LineMark(
                    x: .value("Fecha", item.date),
                    y: .value("Carga (\(unitLabel))", item.value)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(ArcoColor.chart)

                PointMark(
                    x: .value("Fecha", item.date),
                    y: .value("Carga (\(unitLabel))", item.value)
                )
                .foregroundStyle(ArcoColor.chart)
                .accessibilityLabel(ProfileFormat.date(item.date))
                .accessibilityValue("\(ProfileFormat.number(item.value, maxDecimals: 2)) \(unitLabel)")
            }

            if let selectedDate,
               let selected = items.last(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) }) {
                RuleMark(x: .value("Seleccionado", selected.date))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .center) {
                        Text("\(ProfileFormat.number(selected.value, maxDecimals: 2)) \(unitLabel)")
                            .font(.caption2)
                            .padding(4)
                            .background(ArcoColor.surface, in: RoundedRectangle(cornerRadius: Radius.control))
                    }
            }
        }
        .chartXAxisLabel("Fecha")
        .chartYAxisLabel("Carga (\(unitLabel))")
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks(position: .leading) }
        .chartXSelection(value: $selectedDate)
        .accessibilityLabel("Mayor carga por sesión, en \(unitLabel)")
    }
}

/// Gráfico secundario de e1RM estimado (puntos reales).
private struct E1RMChart: View {
    let points: [ChartPoint]
    let massUnit: MassUnit
    let unitLabel: String

    private struct Item: Identifiable {
        let id: Int
        let date: Date
        let value: Double
    }

    private var items: [Item] {
        points.enumerated().compactMap { index, p in
            guard let v = p.value else { return nil }
            return Item(id: index, date: p.date, value: NSDecimalNumber(decimal: ProfileFormat.mass(kilograms: v, in: massUnit)).doubleValue)
        }
    }

    var body: some View {
        Chart(items) { item in
            LineMark(
                x: .value("Fecha", item.date),
                y: .value("e1RM estimado (\(unitLabel))", item.value)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(ArcoColor.chartSecondary)

            PointMark(
                x: .value("Fecha", item.date),
                y: .value("e1RM estimado (\(unitLabel))", item.value)
            )
            .foregroundStyle(ArcoColor.chartSecondary)
            .accessibilityLabel(ProfileFormat.date(item.date))
            .accessibilityValue("aproximadamente \(ProfileFormat.number(item.value)) \(unitLabel)")
        }
        .chartXAxisLabel("Fecha")
        .chartYAxisLabel("e1RM estimado (\(unitLabel))")
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis { AxisMarks(position: .leading) }
        .accessibilityLabel("Fuerza máxima estimada por sesión, en \(unitLabel). Es una estimación secundaria.")
    }
}

/// Hoja de detalle de un punto seleccionado (spec §12: fecha, valor y series originales).
struct ExercisePointDetailSheet: View {
    let detail: ExercisePointDetail
    let massUnit: MassUnit
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Sesión") {
                    LabeledContent("Fecha", value: detail.date.formatted(.dateTime.weekday().day().month().year()))
                    if let kg = detail.maxKilograms {
                        LabeledContent("Mayor carga", value: "\(text(kg)) \(detail.unitLabel)")
                    }
                }
                Section("Series de ese día") {
                    ForEach(Array(detail.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("Serie \(index + 1)").foregroundStyle(.secondary)
                            Spacer()
                            Text(rowText(set)).monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Detalle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func text(_ kg: Decimal) -> String {
        ProfileFormat.number(ProfileFormat.mass(kilograms: kg, in: massUnit), maxDecimals: 2)
    }

    private func rowText(_ set: SetRecord) -> String {
        let load = set.load.kilograms.map { "\(text($0)) \(set.load.convention.unitLabel(massUnit))" } ?? "carga desconocida"
        let reps = set.reps.map { "\($0) rep." } ?? "—"
        let side = set.side == .bilateral ? "" : " · \(ExerciseSideText.label(set.side))"
        return "\(load) × \(reps)\(side)"
    }
}

// MARK: - Preview

#Preview("Progreso por ejercicio") {
    // Preview autocontenida con datos simulados en memoria (no son datos del propietario).
    let container = try! ModelContainer(
        for: WorkoutSessionModel.self, SessionExerciseModel.self, SetRecordModel.self, AppSettingsModel.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let calendar = Calendar.current
    for (offset, kg, variant) in [(-30, 60.0, "Máquina A"), (-20, 62.5, "Máquina A"), (-7, 40.0, "Máquina B")] {
        let date = calendar.date(byAdding: .day, value: offset, to: Date())!
        let set = SetRecordModel(
            loadAmount: Decimal(kg), loadUnitRaw: "kg", loadConventionRaw: "machineNominal",
            reps: 8, typeRaw: "working", stateRaw: "completed", sideRaw: "bilateral",
            rirKind: "exact", rirValue: 1, performedAt: date
        )
        let se = SessionExerciseModel(exerciseID: "chest_machine_press", variantKey: variant, order: 0, sets: [set])
        context.insert(WorkoutSessionModel(startedAt: date, trainingDate: date, originTimeZoneID: "UTC", exercises: [se]))
    }
    return NavigationStack {
        ExerciseProgressView(exerciseID: "chest_machine_press")
    }
    .environment(AppState(context: context))
    .modelContainer(container)
}
