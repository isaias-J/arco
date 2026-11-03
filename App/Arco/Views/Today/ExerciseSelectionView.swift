import SwiftUI
import SwiftData
import ArcoCore

/// Selección flexible de ejercicios (spec §8, §11): parte de la selección favorita o de la
/// última sesión del mismo día de rutina, muestra sugerencias explicables de énfasis muscular y
/// permite añadir, quitar y reordenar. Las sugerencias nunca editan la selección por sí solas.
struct ExerciseSelectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let template: RoutineTemplateModel?
    var onStart: (WorkoutSessionModel) -> Void

    @Query(sort: \ExerciseModel.name) private var allExercises: [ExerciseModel]
    @Query private var sessions: [WorkoutSessionModel]
    @State private var selected: [String] = []
    @State private var dismissedSuggestions: Set<Muscle> = []
    @State private var showPicker = false
    @State private var loaded = false

    static let suggestionWindowDays = 14

    private var dayGroups: [MuscleGroup] {
        guard let groups = template?.groupsJoined, !groups.isEmpty else { return [] }
        return groups.split(separator: ",").compactMap { MuscleGroup(rawValue: String($0)) }
    }

    private var active: [ExerciseModel] { allExercises.filter { !$0.archived } }

    /// Ejercicios cuyo músculo directo pertenece a los grupos del día.
    private var dayExercises: [ExerciseModel] {
        active.filter { model in
            guard let rs = ExerciseCatalog.ruleSet(for: model.id) else { return false }
            return rs.directMuscles.contains { dayGroups.contains($0.group) }
        }
    }

    private var recentSets: [AttributedSet] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -Self.suggestionWindowDays, to: Date()) ?? Date()
        return sessions.filter { $0.trainingDate >= cutoff }.flatMap { session in
            session.exercises.flatMap { se -> [AttributedSet] in
                guard let rules = ExerciseCatalog.ruleSet(for: se.exerciseID) else { return [] }
                return se.sets.compactMap { m in
                    let d = m.toDomain()
                    guard d.isEligibleForWorkCount else { return nil }
                    return AttributedSet(setID: d.id, exerciseID: se.exerciseID, side: d.side, ruleSet: rules, pairingKey: se.id.uuidString, performedAt: d.performedAt)
                }
            }
        }
    }

    private var suggestionResult: SuggestionEngine.Result? {
        guard !dayGroups.isEmpty else { return nil }
        let definitions = active.compactMap { ExerciseCatalog.definition($0.id) }
        return SuggestionEngine.suggest(.init(plannedGroups: dayGroups, recentSets: recentSets, availableExercises: definitions))
    }

    var body: some View {
        List {
            if let template {
                Section {
                    Text(template.isRestDay ? "Día de descanso planificado: entrenar es opcional." : "Grupos del día: \(dayGroups.map(\.displayName).joined(separator: ", "))")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            suggestionsSection
            if !selected.isEmpty {
                Section {
                    ForEach(selected, id: \.self) { id in
                        Text(name(id))
                    }
                    .onDelete { selected.remove(atOffsets: $0) }
                    .onMove { selected.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Tu selección (\(selected.count))")
                } footer: {
                    Text("Desliza para quitar; mantén pulsado para reordenar.")
                }
            }
            if !dayExercises.isEmpty {
                Section("Ejercicios del día") {
                    ForEach(dayExercises) { row($0) }
                }
            }
            Section {
                Button { showPicker = true } label: { Label("Buscar en todo el catálogo", systemImage: "magnifyingglass") }
                    .accessibilityIdentifier("selection.search")
            }
        }
        .environment(\.editMode, .constant(selected.isEmpty ? .inactive : .active))
        .navigationTitle("Elegir ejercicios")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Empezar", action: start)
                    .disabled(selected.isEmpty)
                    .accessibilityIdentifier("selection.start")
            }
        }
        .sheet(isPresented: $showPicker) {
            NavigationStack {
                ExercisePickerView(excluded: Set(selected)) { selected.append($0) }
            }
        }
        .onAppear(perform: preload)
    }

    // MARK: - Sugerencias (spec §11)

    @ViewBuilder
    private var suggestionsSection: some View {
        if let result = suggestionResult {
            let visible = result.suggestions.filter { !dismissedSuggestions.contains($0.targetMuscle) }
            if !visible.isEmpty {
                Section {
                    ForEach(visible, id: \.targetMuscle) { suggestion in
                        SuggestionCard(
                            suggestion: suggestion,
                            selected: selected,
                            name: name,
                            onAdd: { id in if !selected.contains(id) { selected.append(id) } },
                            onKeep: { dismissedSuggestions.insert(suggestion.targetMuscle) }
                        )
                    }
                } header: {
                    Text("Sugerencias de énfasis")
                } footer: {
                    Text("Calculadas en este iPhone con tus series de los últimos \(Self.suggestionWindowDays) días y la atribución v\(ExerciseCatalog.attributionVersion.description). Son una ayuda para repartir el trabajo, no una medida de crecimiento.")
                }
            } else if result.noSuitableExercise {
                Section("Sugerencias de énfasis") {
                    Text("Tu catálogo no tiene un ejercicio activo que trabaje directamente las regiones menos atendidas del día. Puedes crear uno personalizado.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ ex: ExerciseModel) -> some View {
        Button {
            if let i = selected.firstIndex(of: ex.id) { selected.remove(at: i) } else { selected.append(ex.id) }
        } label: {
            HStack {
                Text(ex.name).foregroundStyle(ArcoColor.textPrimary)
                Spacer()
                Image(systemName: selected.contains(ex.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(ex.id) ? ArcoColor.brand : .secondary)
            }
            .frame(minHeight: 44)
        }
        .accessibilityAddTraits(selected.contains(ex.id) ? [.isSelected] : [])
        .accessibilityIdentifier("exercise.\(ex.id)")
    }

    private func name(_ id: String) -> String {
        allExercises.first { $0.id == id }?.name ?? ExerciseNames.localized(id)
    }

    /// Selección inicial: favorita del día, o la de la última sesión con esta plantilla.
    private func preload() {
        guard !loaded else { return }
        loaded = true
        let activeIDs = Set(active.map(\.id))
        if let favorite = template?.preferredExerciseIDsJoined, !favorite.isEmpty {
            selected = favorite.split(separator: ",").map(String.init).filter { activeIDs.contains($0) }
        } else if let templateID = template?.id,
                  let last = sessions.filter({ $0.templateID == templateID }).max(by: { $0.startedAt < $1.startedAt }) {
            selected = last.exercises.sorted { $0.order < $1.order }.map(\.exerciseID).filter { activeIDs.contains($0) }
        }
    }

    private func start() {
        let session = appState.repository.startSession(
            trainingDate: Date(), timeZone: .current, templateID: template?.id, exerciseIDs: selected
        )
        onStart(session)
        Task { await appState.refreshReminders() }
    }
}

/// Tarjeta de una sugerencia con su explicación, opciones del catálogo y "Mantener mi elección".
private struct SuggestionCard: View {
    let suggestion: SuggestionEngine.Suggestion
    let selected: [String]
    let name: (String) -> String
    let onAdd: (String) -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("Prioridad posible: \(suggestion.targetMuscle.displayName)", systemImage: "lightbulb")
                .font(.subheadline.bold())
            Text(SuggestionEngine.explanation(
                for: suggestion,
                windowDays: ExerciseSelectionView.suggestionWindowDays,
                muscleName: \.displayName,
                exerciseName: name,
                dateText: { $0.formatted(.dateTime.day().month()) }
            ))
            .font(.footnote)
            .fixedSize(horizontal: false, vertical: true)
            ForEach(suggestion.suggestedExerciseIDs, id: \.self) { id in
                Button {
                    onAdd(id)
                } label: {
                    Label(selected.contains(id) ? "\(name(id)) (añadido)" : "Añadir \(name(id))", systemImage: selected.contains(id) ? "checkmark" : "plus")
                        .frame(minHeight: 36)
                }
                .buttonStyle(.bordered)
                .disabled(selected.contains(id))
            }
            Button("Mantener mi elección", action: onKeep)
                .font(.footnote)
                .frame(minHeight: 36)
        }
        .padding(.vertical, Spacing.xs)
    }
}

/// Buscador del catálogo completo con alta de ejercicios personalizados.
struct ExercisePickerView: View {
    let excluded: Set<String>
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \ExerciseModel.name) private var exercises: [ExerciseModel]
    @State private var search = ""
    @State private var showNew = false

    private var filtered: [ExerciseModel] {
        exercises.filter { !$0.archived && !excluded.contains($0.id) }
            .filter { search.isEmpty || $0.name.localizedStandardContains(search) || $0.aliasesJoined.localizedStandardContains(search) }
    }

    var body: some View {
        List {
            ForEach(filtered) { ex in
                Button {
                    onPick(ex.id)
                    dismiss()
                } label: {
                    VStack(alignment: .leading) {
                        Text(ex.name).foregroundStyle(ArcoColor.textPrimary)
                        if ex.originRaw == ExerciseOrigin.custom.rawValue {
                            Text("Personalizado · atribución muscular pendiente").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .frame(minHeight: 44)
                }
            }
        }
        .searchable(text: $search, prompt: "Buscar ejercicio")
        .navigationTitle("Catálogo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } }
            ToolbarItem(placement: .primaryAction) { Button("Nuevo") { showNew = true } }
        }
        .sheet(isPresented: $showNew) {
            NewExerciseView { id in onPick(id); dismiss() }
        }
    }
}

/// Alta de ejercicio personalizado (spec §6). Sin atribución automática: sus series aparecen
/// como "atribución pendiente" hasta que exista una regla, nunca con crédito inventado (T17).
struct NewExerciseView: View {
    let onCreate: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var exercises: [ExerciseModel]
    @State private var name = ""
    @State private var loadType: LoadType = .machine
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre", text: $name)
                Picker("Equipo", selection: $loadType) {
                    Text("Barra").tag(LoadType.barbell)
                    Text("Mancuernas").tag(LoadType.dumbbell)
                    Text("Máquina").tag(LoadType.machine)
                    Text("Polea").tag(LoadType.cable)
                    Text("Peso corporal").tag(LoadType.bodyweight)
                    Text("Mixto").tag(LoadType.mixed)
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                Text("Los ejercicios personalizados no reciben atribución muscular automática; sus series no se suman a ningún músculo para no inventar crédito.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .navigationTitle("Nuevo ejercicio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Crear", action: create) }
            }
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { error = "Escribe un nombre."; return }
        if exercises.contains(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            error = "Ya existe un ejercicio con ese nombre."
            return
        }
        let id = "custom_\(UUID().uuidString.prefix(8).lowercased())"
        context.insert(ExerciseModel(id: id, name: trimmed, loadTypeRaw: loadType.rawValue, patternRaw: MovementPattern.isolationOther.rawValue, originRaw: ExerciseOrigin.custom.rawValue, instructions: ""))
        try? context.save()
        onCreate(id)
        dismiss()
    }
}
