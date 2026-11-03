import SwiftUI
import SwiftData
import Charts
import ArcoCore

/// Curva histórica de series por grupo muscular o subregión (spec §12): semanas, meses o años,
/// con el método de conteo visible. Los periodos sin series registradas se distinguen de un cero
/// y los incompletos se marcan. Todo se recalcula desde los registros.
struct MuscleHistoryView: View {
    @Environment(AppState.self) private var appState
    @Query private var sessions: [WorkoutSessionModel]
    @Query private var events: [AttendanceEventModel]
    @Query private var customAttributions: [CustomAttributionModel]

    @State private var group: MuscleGroup = .chest
    /// nil = todo el grupo (unión de series); un músculo = esa subregión.
    @State private var muscle: Muscle?
    @State private var scale: HistoryScale = .week
    @State private var method: MuscleHistoryMethod = .direct

    init(initialGroup: MuscleGroup = .chest) {
        _group = State(initialValue: initialGroup)
    }

    private var target: MuscleTarget { muscle.map { .muscle($0) } ?? .group(group) }
    private var subregions: [Muscle] { Muscle.allCases.filter { $0.group == group } }

    private var buckets: [MuscleHistoryBucket] {
        let sets = MuscleProgressData.attributedSets(sessions, context: appState.context)
        let workDates = sessions.flatMap { $0.exercises.flatMap(\.sets) }
            .map { $0.toDomain() }
            .filter(\.isEligibleForWorkCount)
            .map(\.performedAt)
        let manual = events.filter { $0.sourceRaw == AttendanceSource.manual.rawValue }.map(\.trainingDate)
        return MuscleHistory.buckets(sets, target: target, scale: scale, workDates: workDates,
                                     manualAttendanceDays: manual, now: Date(), calendar: appState.calendar)
    }

    var body: some View {
        let data = buckets
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                controls
                if data.isEmpty {
                    ArcoCard {
                        VStack(spacing: Spacing.sm) {
                            Text("Aún no hay series registradas").font(.headline)
                            Text("Cuando confirmes series de trabajo, aquí verás cómo cambia el número de series de cada músculo por semana, mes o año.")
                                .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .accessibilityIdentifier("muscleHistory.empty")
                } else {
                    chartCard(data)
                    tableCard(data)
                }
                methodCard
            }
            .padding(Spacing.lg)
        }
        .background(ArcoColor.background)
        .navigationTitle("Series en el tiempo")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Controles

    private var controls: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Picker("Grupo", selection: Binding(get: { group }, set: { group = $0; muscle = nil })) {
                    ForEach(MuscleGroup.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("muscleHistory.group")
                if subregions.count > 1 {
                    Picker("Región", selection: $muscle) {
                        Text("Todo el grupo").tag(Muscle?.none)
                        ForEach(subregions, id: \.self) { Text($0.displayName).tag(Muscle?.some($0)) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("muscleHistory.region")
                }
                Picker("Escala", selection: $scale) {
                    ForEach(HistoryScale.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("muscleHistory.scale")
                Picker("Método", selection: $method) {
                    ForEach(MuscleHistoryMethod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("muscleHistory.method")
            }
        }
    }

    // MARK: Gráfico

    private func label(_ b: MuscleHistoryBucket) -> String {
        switch scale {
        case .week: return b.start.formatted(.dateTime.day().month(.abbreviated))
        case .month: return b.start.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        case .year: return b.start.formatted(.dateTime.year())
        }
    }

    private func valueText(_ v: Double) -> String { ProfileFormat.number(v) }

    private func chartCard(_ data: [MuscleHistoryBucket]) -> some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("\(target.displayName) · \(method.displayName)").font(.headline)
                Text(method.explanation).font(.caption2).foregroundStyle(.secondary)
                Chart {
                    ForEach(data) { b in
                        let x = label(b)
                        if b.hasWorkRecords {
                            if method == .directAndIndirect {
                                BarMark(x: .value("Periodo", x), y: .value("Series", b.direct))
                                    .foregroundStyle(by: .value("Tipo", "Directas"))
                                    .opacity(b.isPartial ? 0.45 : 1)
                                BarMark(x: .value("Periodo", x), y: .value("Series", b.indirect))
                                    .foregroundStyle(by: .value("Tipo", "Indirectas"))
                                    .opacity(b.isPartial ? 0.45 : 1)
                            } else {
                                BarMark(x: .value("Periodo", x), y: .value("Series", b.value(method) ?? 0))
                                    .foregroundStyle(ArcoColor.brand.opacity(b.isPartial ? 0.45 : 1))
                            }
                        } else {
                            // Sin registros: marca neutra en la base, nunca una barra de cero.
                            PointMark(x: .value("Periodo", x), y: .value("Series", 0))
                                .symbol { Image(systemName: "minus").font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                }
                .chartForegroundStyleScale(["Directas": ArcoColor.brand, "Indirectas": ArcoColor.chartSecondary])
                .chartLegend(method == .directAndIndirect ? .visible : .hidden)
                .chartYAxisLabel("Series")
                .frame(height: 220)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(chartSummary(data))
                .accessibilityIdentifier("muscleHistory.chart")
                HStack(spacing: Spacing.md) {
                    Label("Atenuado: periodo incompleto", systemImage: "circle.lefthalf.filled")
                    Label("Raya: sin registros", systemImage: "minus")
                }
                .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func chartSummary(_ data: [MuscleHistoryBucket]) -> String {
        let parts = data.map { b -> String in
            guard let v = b.value(method) else { return "\(label(b)): sin registros" }
            return "\(label(b)): \(valueText(v))\(b.isPartial ? ", incompleto" : "")"
        }
        return "Series de \(target.displayName), \(method.displayName). " + parts.joined(separator: "; ")
    }

    // MARK: Tabla

    private func tableCard(_ data: [MuscleHistoryBucket]) -> some View {
        ArcoCard {
            DisclosureGroup("Ver como tabla") {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(data.reversed()) { b in
                        HStack(alignment: .firstTextBaseline) {
                            Text(label(b))
                            if b.isPartial { Text("incompleto").font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                            if b.hasWorkRecords {
                                Text("D \(b.direct) · I \(b.indirect) · F≈\(valueText(b.fractional))\(b.unknown > 0 ? " · U \(b.unknown)" : "")")
                                    .monospacedDigit()
                            } else if b.attendanceWithoutSets > 0 {
                                Text("asistencia sin series").foregroundStyle(.secondary)
                            } else {
                                Text("sin registros").foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption)
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(.top, Spacing.xs)
            }
            .font(.footnote)
            .accessibilityIdentifier("muscleHistory.table")
        }
    }

    private var methodCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Cómo se cuenta").font(.subheadline.bold())
                Text(MuscleProgressData.methodNote()).font(.caption2).foregroundStyle(.secondary)
                Text("Un par izquierda + derecha cuenta como una exposición. El total de un grupo usa la unión de series (el mayor papel de cada serie), no la suma de sus regiones. \"Sin registros\" significa que no hay series guardadas en ese periodo: Arco no sabe si entrenaste, así que no lo muestra como cero. Un cero indica que registraste entrenamiento sin series para este músculo.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Acceso desde el panel de Progreso.
struct MuscleHistoryLinkCard: View {
    var body: some View {
        ArcoCard {
            NavigationLink {
                MuscleHistoryView()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Series por músculo en el tiempo").font(.headline)
                        Text("Evolución por semana, mes o año, por grupo o región.")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("progress.muscleHistory")
        }
    }
}
