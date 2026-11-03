import SwiftUI
import SwiftData
import Charts
import ArcoCore

/// Gráfico por ejercicio (spec §12). Recibe un `exerciseID` y muestra la evolución de las
/// series de trabajo de ESE ejercicio a lo largo del tiempo:
/// - Mayor carga por sesión (puntos reales, sin rellenar fechas ausentes con cero — T32).
/// - Récord de carga y récord de repeticiones a una carga (spec §13).
/// - e1RM opcional y SECUNDARIO solo si se puede calcular (EstimatedOneRM.epley), etiquetado
///   como estimación. Nunca se llama "1RM real" a la carga máxima (spec §12).
/// - Historial completo de series.
/// Periodos: semana / mes / 3 meses / año / todo (T33: la semana en curso se marca parcial).
struct ExerciseProgressView: View {
    let exerciseID: String

    @Environment(AppState.self) private var appState
    @Query private var sessions: [WorkoutSessionModel]

    @State private var period: ChartPeriod = .threeMonths
    /// Punto seleccionado en el gráfico (abre detalle de fecha/valor/series — spec §12).
    @State private var selectedDate: Date?

    init(exerciseID: String) {
        self.exerciseID = exerciseID
    }

    private var calendar: Calendar {
        var c = Calendar.current
        // Inicio de semana: lunes por defecto, configurable desde ajustes (spec §12).
        c.firstWeekday = appState.settings.weekStartsMonday ? 2 : c.firstWeekday
        return c
    }

    // MARK: - Datos derivados (solo lectura de @Query, main actor)

    /// Sesiones que contienen al menos una serie elegible de este ejercicio, con sus series
    /// de dominio ya convertidas (toDomain()). No se rellenan fechas ausentes (T32).
    private var sessionsWithSets: [ExerciseSessionData] {
        sessions
            .compactMap { session -> ExerciseSessionData? in
                // Series de trabajo elegibles de ESTE ejercicio en esta sesión.
                let domainSets = session.exercises
                    .filter { $0.exerciseID == exerciseID }
                    .flatMap { $0.sets.map { $0.toDomain() } }
                    .filter { $0.isEligibleForWorkCount }
                guard !domainSets.isEmpty else { return nil }
                return ExerciseSessionData(date: session.trainingDate, sets: domainSets)
            }
            .sorted { $0.date < $1.date }
    }

    /// Series dentro del periodo elegido.
    private var periodSessions: [ExerciseSessionData] {
        guard let cutoff = period.cutoff(from: Date(), calendar: calendar) else {
            return sessionsWithSets // "todo"
        }
        return sessionsWithSets.filter { $0.date >= cutoff }
    }

    /// Mayor carga por sesión (T32: sin ceros imputados; fechas ausentes simplemente no existen).
    private var maxLoadPoints: [ChartPoint] {
        ChartAnalytics.maxLoadPerSession(periodSessions.map { (date: $0.date, sets: $0.sets) })
            .filter { $0.value != nil } // puntos reales observados
    }

    /// Todas las series de trabajo elegibles del periodo (para récords e historial).
    private var allPeriodSets: [SetRecord] {
        periodSessions.flatMap { $0.sets }
    }

    private var maxLoadRecord: PersonalRecord? {
        RecordsEngine.maxLoadRecord(from: allPeriodSets)
    }

    /// Récord de repeticiones a la carga del récord de carga (misma convención/lado).
    private var repsRecord: PersonalRecord? {
        guard let kg = maxLoadRecord?.loadKilograms else { return nil }
        return RecordsEngine.repsRecord(from: allPeriodSets, atKilograms: kg)
    }

    /// e1RM opcional y secundario (T58): solo puntos donde epley es elegible.
    /// Se etiqueta como estimación; la carga máxima nunca se presenta como "1RM real".
    private var e1rmPoints: [ChartPoint] {
        periodSessions.compactMap { data -> ChartPoint? in
            let estimates = data.sets.compactMap { set -> Decimal? in
                guard let reps = set.reps else { return nil }
                return EstimatedOneRM.epley(load: set.load, reps: reps, rir: set.rir)
            }
            guard let best = estimates.max() else { return nil }
            return ChartPoint(date: data.date, value: best)
        }
    }

    /// Estado del periodo en curso (T33): marca la semana actual como parcial.
    private var weekPartialStatus: PeriodStatus {
        let now = Date()
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start
            ?? calendar.startOfDay(for: now)
        return ChartAnalytics.weekStatus(weekStart: weekStart, reference: now, calendar: calendar)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                periodPicker
                if maxLoadPoints.isEmpty {
                    emptyState
                } else {
                    maxLoadCard
                    recordsCard
                    if !e1rmPoints.isEmpty {
                        e1rmCard
                    }
                    historyCard
                }
            }
            .padding(Spacing.lg)
        }
        .background(ArcoColor.background)
        .navigationTitle(ExerciseNames.localized(exerciseID))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: selectedPointBinding) { detail in
            ExercisePointDetailSheet(detail: detail)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Selección → hoja de detalle

    /// Convierte la fecha seleccionada en un detalle presentable (fecha/valor/series del día).
    private var selectedPointBinding: Binding<ExercisePointDetail?> {
        Binding(
            get: {
                guard let date = selectedDate,
                      let data = periodSessions.first(where: { calendar.isDate($0.date, inSameDayAs: date) })
                else { return nil }
                let maxKg = data.sets.compactMap { $0.load.kilograms }.max()
                return ExercisePointDetail(date: data.date, maxKilograms: maxKg, sets: data.sets)
            },
            set: { newValue in
                if newValue == nil { selectedDate = nil }
            }
        )
    }

    // MARK: - Subvistas

    private var periodPicker: some View {
        Picker("Periodo", selection: $period) {
            ForEach(ChartPeriod.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Periodo del gráfico")
    }

    private var emptyState: some View {
        ArcoCard {
            VStack(spacing: Spacing.sm) {
                Text("Sin series en este periodo")
                    .font(.headline)
                Text("Cuando registres series de trabajo de este ejercicio, aquí verás tu mayor carga por sesión, tus récords y el historial.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var maxLoadCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Mayor carga por sesión")
                    .font(.headline)
                Text("Carga máxima de trabajo de cada día, en kg. No es un \"1RM real\": es el peso más alto que registraste.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                MaxLoadChart(
                    points: maxLoadPoints,
                    selectedDate: $selectedDate,
                    calendar: calendar
                )
                .frame(height: 220)

                if weekPartialStatus.isPartial {
                    Label("La semana en curso aún está incompleta.", systemImage: "clock.badge.exclamationmark")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Alternativa textual al gráfico (accesibilidad, spec §12).
                DisclosureGroup("Ver como tabla") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(maxLoadPoints, id: \.date) { point in
                            HStack {
                                Text(point.date.formatted(.dateTime.day().month().year()))
                                Spacer()
                                Text(point.value.map { "\(decimalString($0)) kg" } ?? "—")
                                    .monospacedDigit()
                            }
                            .font(.caption)
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
                        value: "\(decimalString(rec.loadKilograms)) kg × \(rec.reps) rep.",
                        date: rec.date,
                        side: rec.side
                    )
                }
                if let reps = repsRecord {
                    recordRow(
                        title: "Más repeticiones a esa carga",
                        value: "\(reps.reps) rep. a \(decimalString(reps.loadKilograms)) kg",
                        date: reps.date,
                        side: reps.side
                    )
                }
                if maxLoadRecord == nil {
                    Text("Todavía no hay récord en este periodo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Los récords excluyen calentamientos, intentos y series eliminadas. Mayor asistencia no genera récord de fuerza.")
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
                Text("Estimación con la fórmula de Epley, solo en series elegibles (RIR 0–1, 2–10 rep., carga externa). Es un índice estimado, no una medida de fuerza real; no sustituye tus registros ni invita a probar máximos.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                E1RMChart(points: e1rmPoints)
                    .frame(height: 160)

                DisclosureGroup("Ver como tabla") {
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ForEach(e1rmPoints, id: \.date) { point in
                            HStack {
                                Text(point.date.formatted(.dateTime.day().month().year()))
                                Spacer()
                                Text(point.value.map { "≈ \(decimalString($0)) kg" } ?? "—")
                                    .monospacedDigit()
                            }
                            .font(.caption)
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
                // Orden cronológico descendente (más reciente primero).
                ForEach(periodSessions.reversed(), id: \.date) { data in
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
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                    if data.date != periodSessions.first?.date {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Helpers de presentación

    private func recordRow(title: String, value: String, date: Date, side: BodySide) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                Text(date.formatted(.dateTime.day().month().year()))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value).font(.subheadline.bold()).monospacedDigit()
                if side != .bilateral {
                    Text(sideLabel(side)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value), \(date.formatted(.dateTime.day().month().year()))")
    }

    private func setSummary(_ set: SetRecord) -> String {
        let load: String
        if let kg = set.load.kilograms {
            load = "\(decimalString(kg)) kg"
        } else {
            load = "carga desconocida"
        }
        let reps = set.reps.map { "\($0) rep." } ?? "—"
        let side = set.side == .bilateral ? "" : " · \(sideLabel(set.side))"
        return "\(load) × \(reps)\(side)"
    }

    private func sideLabel(_ side: BodySide) -> String {
        switch side {
        case .bilateral: return "Bilateral"
        case .left: return "Izquierdo"
        case .right: return "Derecho"
        }
    }

    private func decimalString(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}

// MARK: - Modelos de apoyo (UI)

/// Datos de una sesión para este ejercicio (fecha civil + series de dominio elegibles).
private struct ExerciseSessionData: Identifiable {
    let date: Date
    let sets: [SetRecord]
    var id: Date { date }
}

/// Detalle de un punto seleccionado del gráfico (spec §12: fecha, valor y series originales).
struct ExercisePointDetail: Identifiable {
    let date: Date
    let maxKilograms: Decimal?
    let sets: [SetRecord]
    var id: Date { date }
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

/// Gráfico de mayor carga por sesión. Puntos reales + línea de conexión visual (T32:
/// no se imputan ceros; solo se dibujan observaciones). Interpolación lineal para no
/// inventar picos (spec §12: no sobrepasos entre datos).
private struct MaxLoadChart: View {
    let points: [ChartPoint]
    @Binding var selectedDate: Date?
    let calendar: Calendar

    private var values: [(date: Date, value: Double)] {
        points.compactMap { p in
            guard let v = p.value else { return nil }
            return (p.date, NSDecimalNumber(decimal: v).doubleValue)
        }
    }

    var body: some View {
        Chart {
            ForEach(values, id: \.date) { item in
                LineMark(
                    x: .value("Fecha", item.date),
                    y: .value("Carga (kg)", item.value)
                )
                .interpolationMethod(.linear)
                .foregroundStyle(ArcoColor.chart)

                PointMark(
                    x: .value("Fecha", item.date),
                    y: .value("Carga (kg)", item.value)
                )
                .foregroundStyle(ArcoColor.chart)
            }

            if let selectedDate,
               let selected = values.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) }) {
                RuleMark(x: .value("Seleccionado", selected.date))
                    .foregroundStyle(.secondary)
                    .annotation(position: .top, alignment: .center) {
                        Text("\(Int(selected.value.rounded())) kg")
                            .font(.caption2)
                            .padding(4)
                            .background(ArcoColor.surface, in: RoundedRectangle(cornerRadius: Radius.control))
                    }
            }
        }
        .chartXAxisLabel("Fecha")
        .chartYAxisLabel("Carga (kg)")
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .chartXSelection(value: $selectedDate)
        .accessibilityLabel("Mayor carga por sesión, en kilogramos")
    }
}

/// Gráfico secundario de e1RM estimado (puntos reales).
private struct E1RMChart: View {
    let points: [ChartPoint]

    private var values: [(date: Date, value: Double)] {
        points.compactMap { p in
            guard let v = p.value else { return nil }
            return (p.date, NSDecimalNumber(decimal: v).doubleValue)
        }
    }

    var body: some View {
        Chart(values, id: \.date) { item in
            LineMark(
                x: .value("Fecha", item.date),
                y: .value("e1RM estimado (kg)", item.value)
            )
            .interpolationMethod(.linear)
            .foregroundStyle(ArcoColor.chartSecondary)

            PointMark(
                x: .value("Fecha", item.date),
                y: .value("e1RM estimado (kg)", item.value)
            )
            .foregroundStyle(ArcoColor.chartSecondary)
        }
        .chartXAxisLabel("Fecha")
        .chartYAxisLabel("e1RM estimado (kg)")
        .chartYAxis { AxisMarks(position: .leading) }
        .accessibilityLabel("Fuerza máxima estimada por sesión, en kilogramos. Es una estimación secundaria.")
    }
}

/// Hoja de detalle de un punto seleccionado (spec §12: fecha, valor y series originales).
struct ExercisePointDetailSheet: View {
    let detail: ExercisePointDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Sesión") {
                    LabeledContent("Fecha", value: detail.date.formatted(.dateTime.weekday().day().month().year()))
                    if let kg = detail.maxKilograms {
                        LabeledContent("Mayor carga", value: "\(NSDecimalNumber(decimal: kg).stringValue) kg")
                    }
                }
                Section("Series de ese día") {
                    ForEach(Array(detail.sets.enumerated()), id: \.element.id) { index, set in
                        HStack {
                            Text("Serie \(index + 1)").foregroundStyle(.secondary)
                            Spacer()
                            Text(rowText(set)).monospacedDigit()
                        }
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

    private func rowText(_ set: SetRecord) -> String {
        let load = set.load.kilograms.map { "\(NSDecimalNumber(decimal: $0).stringValue) kg" } ?? "desconocida"
        let reps = set.reps.map { "\($0) rep." } ?? "—"
        return "\(load) × \(reps)"
    }
}

// MARK: - Preview

#Preview("Progreso por ejercicio") {
    // Preview autocontenida con datos mock en memoria (spec: sin servicios vivos).
    let container = try! ModelContainer(
        for: WorkoutSessionModel.self, SessionExerciseModel.self, SetRecordModel.self, AppSettingsModel.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext

    // Tres sesiones con progreso de carga en press plano.
    let calendar = Calendar.current
    for (offset, kg) in [(-30, 60), (-20, 62.5), (-7, 65)] {
        let date = calendar.date(byAdding: .day, value: offset, to: Date())!
        let set = SetRecordModel(
            loadAmount: Decimal(kg), loadUnitRaw: "kg", loadConventionRaw: "externalTotal",
            reps: 8, typeRaw: "working", stateRaw: "completed", sideRaw: "bilateral",
            rirKind: "exact", rirValue: 1, performedAt: date
        )
        let se = SessionExerciseModel(exerciseID: "chest_flat_barbell", order: 0, sets: [set])
        let session = WorkoutSessionModel(startedAt: date, trainingDate: date, originTimeZoneID: "UTC", exercises: [se])
        context.insert(session)
    }

    return NavigationStack {
        ExerciseProgressView(exerciseID: "chest_flat_barbell")
    }
    .environment(AppState(context: context))
    .modelContainer(container)
}
