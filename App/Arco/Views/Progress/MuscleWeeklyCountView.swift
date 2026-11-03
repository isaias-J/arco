import SwiftUI
import SwiftData
import ArcoCore

// MARK: - Datos

/// Construye las series atribuidas a partir de las sesiones (spec §10.1). Solo series de trabajo
/// elegibles; `pairingKey` = sesión-ejercicio para emparejar lados (T12) y `performedAt` real.
enum MuscleProgressData {
    static func attributedSets(_ sessions: [WorkoutSessionModel]) -> [AttributedSet] {
        sessions.flatMap { session in
            session.exercises.flatMap { se -> [AttributedSet] in
                guard let rules = ExerciseCatalog.ruleSet(for: se.exerciseID) else { return [] }
                return se.sets.compactMap { model -> AttributedSet? in
                    let set = model.toDomain()
                    guard set.isEligibleForWorkCount else { return nil }
                    return AttributedSet(
                        setID: set.id, exerciseID: se.exerciseID, side: set.side, ruleSet: rules,
                        pairingKey: se.id.uuidString, performedAt: set.performedAt
                    )
                }
            }
        }
    }

    /// Meta vigente de un músculo en `date` (la de inicio más reciente).
    static func activeGoal(for muscle: Muscle, in goals: [WeeklyGoalModel], at date: Date = Date()) -> WeeklyGoalModel? {
        goals
            .filter { $0.muscleRaw == muscle.rawValue && $0.validFrom <= date && ($0.validTo.map { $0 > date } ?? true) }
            .max { $0.validFrom < $1.validFrom }
    }

    /// Comparación con la meta usando el MISMO método (spec §10.5). Sin registros se dice
    /// "sin datos" en lugar de presentar un 0 como fracaso.
    static func goalText(count: MuscleCount?, method: GoalMethod, target: Decimal) -> String {
        guard let count else {
            return "Sin datos; objetivo elegido: \(ProfileFormat.number(target)) (\(method.displayName.lowercased()))"
        }
        return MuscleWeek.goalMessage(count: count, method: method, target: target)
    }

    static func methodNote() -> String {
        "Método: D = series directas, I = indirectas, F = D + 0,5 × I (estimación fraccional, convención agregada, no una medida exacta por ejercicio), U = pendientes de atribución. Atribución v\(ExerciseCatalog.attributionVersion.description)."
    }
}

// MARK: - Tarjeta del panel

/// Conteo semanal por músculo y subregión (spec §10, §12, hallazgo 8). Agrupa por MuscleGroup
/// y lista cada músculo con D, I, F y U. Sin datos se muestra como "sin datos", nunca como 0.
struct MuscleWeeklyCountCard: View {
    let sessions: [WorkoutSessionModel]
    @Environment(AppState.self) private var appState
    @Query private var goals: [WeeklyGoalModel]
    @State private var period: CountPeriod = .currentWeek

    var body: some View {
        let interval = period.interval(now: Date(), calendar: appState.calendar)
        let sets = MuscleWeek.filter(MuscleProgressData.attributedSets(sessions), from: interval.start, to: interval.end)
        let counts = MuscleCounter.countByMuscle(sets)
        let groupCounts = MuscleCounter.countByGroup(sets)

        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Series por músculo")
                        .font(.headline)
                    Spacer()
                    Picker("Periodo", selection: $period) {
                        ForEach(CountPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.menu)
                }
                Text("\(ProfileFormat.date(interval.start)) – \(ProfileFormat.date(interval.end.addingTimeInterval(-1)))")
                    .font(.caption).foregroundStyle(.secondary)
                if interval.isPartial {
                    Label("Semana en curso, incompleta", systemImage: "clock.badge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if counts.isEmpty {
                    Text("Sin datos en este periodo.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    MuscleGroupBlock(
                        group: group,
                        groupCount: groupCounts[group],
                        counts: counts,
                        goals: goals,
                        period: period,
                        isPartial: interval.isPartial
                    )
                }

                Text(MuscleProgressData.methodNote())
                    .font(.caption2).foregroundStyle(.secondary)
                Text("El total de un grupo usa la unión de series (el mayor papel por serie), no la suma de sus subregiones.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct MuscleGroupBlock: View {
    let group: MuscleGroup
    let groupCount: MuscleGroupCount?
    let counts: [Muscle: MuscleCount]
    let goals: [WeeklyGoalModel]
    let period: CountPeriod
    let isPartial: Bool

    private var muscles: [Muscle] { Muscle.allCases.filter { $0.group == group } }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(group.displayName).font(.subheadline.bold())
                Spacer()
                if let g = groupCount {
                    Text("D \(g.direct) · I \(g.indirect)\(g.unknown > 0 ? " · U \(g.unknown)" : "")")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text("sin datos").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            ForEach(muscles, id: \.self) { muscle in
                NavigationLink {
                    MuscleDetailView(muscle: muscle, period: period)
                } label: {
                    MuscleCountRow(
                        muscle: muscle,
                        count: counts[muscle],
                        goal: MuscleProgressData.activeGoal(for: muscle, in: goals),
                        period: period,
                        isPartial: isPartial
                    )
                }
                .buttonStyle(.plain)
            }
            Divider()
        }
    }
}

/// Fila de un músculo: D, I, F (estimación) y U, más la comparación con su meta del MISMO método.
struct MuscleCountRow: View {
    let muscle: Muscle
    let count: MuscleCount?
    let goal: WeeklyGoalModel?
    let period: CountPeriod
    let isPartial: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(muscle.displayName).font(.footnote)
                if let goal, let method = GoalMethod(rawValue: goal.methodRaw) {
                    Text(goalText(goal: goal, method: method))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let c = count {
                Text("D \(c.direct) · I \(c.indirect) · F≈\(ProfileFormat.number(c.fractional)) · U \(c.unknown)")
                    .font(.caption).monospacedDigit()
            } else {
                Text("sin datos").font(.caption).foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Abre el detalle del músculo")
    }

    private func goalText(goal: WeeklyGoalModel, method: GoalMethod) -> String {
        guard period != .last14Days else { return "La meta es semanal; elige un periodo de 7 días para compararla." }
        let message = MuscleProgressData.goalText(count: count, method: method, target: goal.target)
        return isPartial ? "\(message) · semana incompleta" : message
    }

    private var accessibilityText: String {
        guard let c = count else { return "\(muscle.displayName): sin datos" }
        return "\(muscle.displayName): \(c.direct) directas, \(c.indirect) indirectas, estimación fraccional \(ProfileFormat.number(c.fractional)), \(c.unknown) pendientes de atribución"
    }
}

// MARK: - Detalle por músculo

/// Detalle de un músculo (spec §11.5, §12): ejercicios que aportan, última exposición directa
/// e indirecta con horas transcurridas (tiempo, no recuperación) y su meta.
struct MuscleDetailView: View {
    let muscle: Muscle
    @State private var period: CountPeriod

    init(muscle: Muscle, period: CountPeriod) {
        self.muscle = muscle
        _period = State(initialValue: period)
    }

    @Environment(AppState.self) private var appState
    @Query private var sessions: [WorkoutSessionModel]
    @Query private var goals: [WeeklyGoalModel]
    @State private var showGoalEditor = false

    var body: some View {
        let now = Date()
        let all = MuscleProgressData.attributedSets(sessions)
        let interval = period.interval(now: now, calendar: appState.calendar)
        let periodSets = MuscleWeek.filter(all, from: interval.start, to: interval.end)
        let count = MuscleCounter.countByMuscle(periodSets)[muscle]
        let contributors = MuscleWeek.contributors(periodSets, muscle: muscle)
        let exposure = MuscleWeek.exposures(all)[muscle]
        let goal = MuscleProgressData.activeGoal(for: muscle, in: goals)

        List {
            Section {
                Picker("Periodo", selection: $period) {
                    ForEach(CountPeriod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if interval.isPartial {
                    Label("Semana en curso, incompleta", systemImage: "clock.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let c = count {
                    LabeledContent("Series directas (D)", value: "\(c.direct)")
                    LabeledContent("Series indirectas (I)", value: "\(c.indirect)")
                    LabeledContent("Estimación fraccional (F)", value: "≈ \(ProfileFormat.number(c.fractional))")
                    LabeledContent("Pendientes de atribución (U)", value: "\(c.unknown)")
                } else {
                    Text("Sin datos en este periodo.").foregroundStyle(.secondary)
                }
            } header: {
                Text("Conteo")
            } footer: {
                Text(MuscleProgressData.methodNote())
            }

            Section("Ejercicios que aportan") {
                if contributors.isEmpty {
                    Text("Sin datos en este periodo.").foregroundStyle(.secondary)
                } else {
                    ForEach(contributors, id: \.exerciseID) { item in
                        HStack {
                            Text(ExerciseNames.localized(item.exerciseID))
                            Spacer()
                            Text("\(roleLabel(item.role)) · \(item.count) \(item.count == 1 ? "exposición" : "exposiciones")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }

            Section {
                exposureRow(title: "Última exposición directa", date: exposure?.lastDirect, now: now)
                exposureRow(title: "Última exposición indirecta", date: exposure?.lastIndirect, now: now)
            } header: {
                Text("Tiempo desde el último trabajo")
            } footer: {
                Text("Son horas transcurridas desde tus registros; no miden el estado del músculo.")
            }

            Section("Meta semanal") {
                if let goal, let method = GoalMethod(rawValue: goal.methodRaw) {
                    Text(period == .last14Days
                         ? "La meta es semanal; elige un periodo de 7 días para compararla."
                         : MuscleProgressData.goalText(count: count, method: method, target: goal.target))
                    Text("Método: \(method.displayName) · \(goal.sourceRaw == "professional" ? "indicada por un profesional" : "elegida por ti") · desde el \(ProfileFormat.date(goal.validFrom))")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Observando primero: sin meta configurada.")
                        .foregroundStyle(.secondary)
                }
                Button(goal == nil ? "Configurar meta" : "Cambiar meta") { showGoalEditor = true }
            }
        }
        .navigationTitle(muscle.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showGoalEditor) {
            WeeklyGoalEditorView(muscle: muscle, current: goal)
        }
    }

    private func roleLabel(_ role: AttributionRole) -> String {
        switch role {
        case .direct: return "directo"
        case .indirect: return "indirecto"
        case .unknown: return "pendiente"
        case .notCounted: return "no contabilizado"
        }
    }

    @ViewBuilder
    private func exposureRow(title: String, date: Date?, now: Date) -> some View {
        if let date {
            let hours = Int(now.timeIntervalSince(date) / 3600)
            LabeledContent(title) {
                VStack(alignment: .trailing) {
                    Text(date.formatted(.dateTime.day().month().hour().minute()))
                    Text("hace \(hours) h").font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            LabeledContent(title, value: "sin datos")
        }
    }
}

// MARK: - Editor de meta semanal

/// Editor de meta por músculo (spec §10.5). "Observar primero" es la opción por defecto; no se
/// propone ningún número. La meta guarda método, procedencia y vigencia desde hoy.
struct WeeklyGoalEditorView: View {
    let muscle: Muscle
    let current: WeeklyGoalModel?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var observeFirst = true
    @State private var method: GoalMethod = .direct
    @State private var targetText = ""
    @State private var source = "owner"
    @State private var showValidation = false
    @State private var loaded = false

    private var parsedTarget: Decimal? {
        DecimalParser(locale: .current).parse(targetText)
    }

    private var isTargetValid: Bool {
        guard let t = parsedTarget else { return false }
        return method.isValid(t)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Modo", selection: $observeFirst) {
                        Text("Observar primero").tag(true)
                        Text("Configurar meta").tag(false)
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("Puedes observar tu rutina habitual antes de fijar una meta. Arco no impone ningún número.")
                }

                if !observeFirst {
                    Section {
                        Picker("Método de conteo", selection: $method) {
                            ForEach(GoalMethod.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        TextField(method == .direct ? "Series directas por semana" : "Series (múltiplos de 0,5)", text: $targetText)
                            .keyboardType(.decimalPad)
                        Picker("Procedencia", selection: $source) {
                            Text("Propia").tag("owner")
                            Text("Profesional").tag("professional")
                        }
                    } header: {
                        Text("Meta para \(muscle.displayName)")
                    } footer: {
                        if showValidation && !isTargetValid {
                            Text(method == .direct
                                 ? "Introduce un número entero mayor o igual que 0."
                                 : "Introduce un valor mayor o igual que 0 en múltiplos de 0,5.")
                                .foregroundStyle(.red)
                        } else {
                            Text("Solo se compara con el mismo método. Vigente desde hoy.")
                        }
                    }
                }
            }
            .navigationTitle("Meta semanal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar", action: save)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let current else { return }
        observeFirst = false
        method = GoalMethod(rawValue: current.methodRaw) ?? .direct
        targetText = ProfileFormat.number(current.target)
        source = current.sourceRaw
    }

    private func save() {
        let now = Date()
        if observeFirst {
            current?.validTo = now
            try? appState.context.save()
            dismiss()
            return
        }
        guard let target = parsedTarget, method.isValid(target) else {
            showValidation = true
            return
        }
        current?.validTo = now
        appState.context.insert(WeeklyGoalModel(
            muscleRaw: muscle.rawValue,
            methodRaw: method.rawValue,
            target: target,
            validFrom: now,
            sourceRaw: source
        ))
        try? appState.context.save()
        dismiss()
    }
}
