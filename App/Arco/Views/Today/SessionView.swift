import SwiftUI
import SwiftData
import ArcoCore

/// Sesión activa (spec §8): registro rápido por serie con borradores precargados de la sesión
/// comparable anterior, confirmación en un toque, edición, borrado con deshacer, calentamiento,
/// RIR opcional, lados y convención de carga por ejercicio. Sin temporizador de descanso.
struct SessionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkoutSessionModel

    @State private var showAddExercise = false
    @State private var summary: SessionSummary?
    @State private var saveFavorite = false
    @State private var undo: UndoAction?

    private var exercises: [SessionExerciseModel] {
        session.exercises.sorted { $0.order < $1.order }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Spacing.lg) {
                ForEach(exercises) { exercise in
                    ExerciseLogCard(sessionExercise: exercise, onUndoable: { undo = $0 })
                }
                Button {
                    showAddExercise = true
                } label: {
                    Label("Añadir ejercicio", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("session.addExercise")
            }
            .padding(Spacing.lg)
        }
        .background(ArcoColor.background)
        .navigationTitle("Entrenamiento")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Finalizar") { finish() }
                    .accessibilityIdentifier("session.finish")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Listo") { hideKeyboard() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let undo {
                UndoBanner(action: undo) { self.undo = nil }
                    .padding(Spacing.lg)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: undo?.id)
        .sheet(isPresented: $showAddExercise) {
            NavigationStack {
                ExercisePickerView(excluded: Set(exercises.map(\.exerciseID))) { id in
                    appState.repository.addExercise(to: session, exerciseID: id, variantKey: nil)
                }
            }
        }
        .sheet(item: $summary, onDismiss: { dismiss() }) { summary in
            SessionSummaryView(summary: summary, canSaveFavorite: session.templateID != nil) { favorite in
                if favorite { appState.repository.saveSelectionAsFavorite(session) }
            }
        }
    }

    private func finish() {
        hideKeyboard()
        summary = appState.repository.finish(session)
        Task { await appState.refreshReminders() }
    }
}

@MainActor func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

// MARK: - Deshacer

struct UndoAction: Identifiable {
    let id = UUID()
    let message: String
    let perform: () -> Void
}

private struct UndoBanner: View {
    let action: UndoAction
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(action.message).font(.subheadline)
            Spacer()
            Button("Deshacer") {
                action.perform()
                onClose()
            }
            .bold()
            .accessibilityIdentifier("session.undo")
        }
        .padding(Spacing.md)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
        .task(id: action.id) {
            try? await Task.sleep(for: .seconds(6))
            onClose()
        }
    }
}

// MARK: - Tarjeta de ejercicio

struct ExerciseLogCard: View {
    @Environment(AppState.self) private var appState
    @Bindable var sessionExercise: SessionExerciseModel
    let onUndoable: (UndoAction) -> Void

    @State private var editing: SetRecordModel?
    @State private var showVariant = false
    @State private var variantText = ""
    @State private var removalBlocked = false
    @State private var showSubstitute = false
    @State private var pendingSubstituteID: String?
    @State private var showSubstituteBlocked = false
    /// Cambia al aplicar el incremento para que las filas de borrador relean sus valores.
    @State private var draftsRevision = 0
    private var repo: WorkoutRepository { appState.repository }
    private var convention: LoadConvention { repo.convention(for: sessionExercise.exerciseID) }
    private var sideMode: SideMode { repo.sideMode(for: sessionExercise.exerciseID) }

    private var visibleSets: [SetRecordModel] {
        WorkoutRepository.workOrder(sessionExercise.sets).filter {
            $0.stateRaw == SetState.completed.rawValue || $0.stateRaw == SetState.pending.rawValue
        }
    }

    private var lastPendingID: UUID? {
        visibleSets.last { $0.stateRaw == SetState.pending.rawValue }?.id
    }

    private var exerciseName: String {
        appState.exerciseName(sessionExercise.exerciseID)
    }

    var body: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                header
                progressionLine
                previousLine
                ForEach(visibleSets) { set in
                    if set.stateRaw == SetState.completed.rawValue {
                        CompletedSetRow(set: set, index: index(of: set)) { editing = set }
                    } else {
                        DraftSetRow(
                            draft: set,
                            index: index(of: set),
                            convention: convention,
                            askRIR: appState.rirMode == .allSets || (appState.rirMode == .lastSet && set.id == lastPendingID),
                            onConfirmed: { confirmed in
                                onUndoable(UndoAction(message: "Serie guardada") { repo.unconfirm(confirmed) })
                            }
                        )
                        .id("\(set.id.uuidString)-\(draftsRevision)")
                    }
                }
                HStack {
                    Button {
                        repo.addDraft(to: sessionExercise)
                    } label: {
                        Label(sideMode == .perSide ? "Añadir par de series" : "Añadir serie", systemImage: "plus.circle")
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("session.addSet")
                    Spacer()
                }
            }
        }
        .sheet(item: $editing) { set in
            SetEditorView(set: set) { deleted, previous in
                onUndoable(UndoAction(message: "Serie eliminada") { repo.undoDelete(deleted, previous: previous) })
            }
        }
        .alert("Variante o máquina", isPresented: $showVariant) {
            TextField("p. ej. agarre cerrado, máquina 2", text: $variantText)
            Button("Guardar") { repo.setVariant(sessionExercise, to: variantText) }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Una variante distinta se compara por separado en el historial y los gráficos.")
        }
        .alert("No se puede quitar", isPresented: $removalBlocked) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("Este ejercicio ya tiene series realizadas. Para conservar tu trabajo, elimina antes esas series si de verdad no las hiciste.")
        }
        .sheet(isPresented: $showSubstitute, onDismiss: {
            if pendingSubstituteID != nil { showSubstituteBlocked = true }
        }) {
            NavigationStack {
                ExercisePickerView(excluded: Set(sessionExercise.session?.exercises.map(\.exerciseID) ?? [sessionExercise.exerciseID])) { id in
                    if !repo.substitute(sessionExercise, with: id) { pendingSubstituteID = id }
                }
            }
        }
        .alert("No se puede sustituir", isPresented: $showSubstituteBlocked) {
            Button("Añadir aparte") {
                if let id = pendingSubstituteID, let session = sessionExercise.session {
                    repo.addExercise(to: session, exerciseID: id, variantKey: nil)
                }
                pendingSubstituteID = nil
            }
            Button("Cancelar", role: .cancel) { pendingSubstituteID = nil }
        } message: {
            Text("Ya registraste series de este ejercicio. Se añadirá el nuevo como ejercicio aparte.")
        }
    }

    private var orderedSiblings: [SessionExerciseModel] {
        (sessionExercise.session?.exercises ?? []).sorted { $0.order < $1.order }
    }

    // MARK: - Doble progresión (spec §13): solo informa; nunca cambia pesos sin aceptación.

    @ViewBuilder
    private var progressionLine: some View {
        let catalog = appState.catalog
        let id = sessionExercise.exerciseID
        switch catalog.evaluateProgression(id, variantKey: sessionExercise.variantKey, excluding: sessionExercise.session) {
        case .met:
            if let rule = catalog.progressionRule(id) {
                let unit = MassUnit(rawValue: rule.unitRaw) ?? .kilograms
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Label("Cumpliste tu regla para considerar subir +\(SetText.number(rule.increment)) \(unit.rawValue)", systemImage: "arrow.up.forward.circle")
                        .font(.caption.bold())
                        .foregroundStyle(ArcoColor.brandText)
                    if !incrementableDrafts.isEmpty {
                        Button("Aplicar a los borradores") { applyIncrement(rule.increment, unit: unit) }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .frame(minHeight: 44)
                            .accessibilityHint("Suma el incremento solo a las series de trabajo pendientes; puedes cambiarlas antes de confirmar.")
                            .accessibilityIdentifier("session.applyIncrement")
                    }
                }
                .accessibilityElement(children: .contain)
            }
        case .notMet(let reached, let need):
            Text("Regla de progresión: \(reached) de \(need) series en el techo la última vez")
                .font(.caption).foregroundStyle(.secondary)
        case .effortUnknown:
            Text("Falta el RIR que pide tu regla")
                .font(.caption).foregroundStyle(.secondary)
        case .notEnoughSets, .disabled:
            EmptyView()
        }
    }

    /// Borradores pendientes de trabajo con carga conocida y convención de peso movido.
    private var incrementableDrafts: [SetRecordModel] {
        sessionExercise.sets.filter {
            $0.stateRaw == SetState.pending.rawValue
                && $0.typeRaw == SetType.working.rawValue
                && $0.loadAmount != nil
                && (LoadConvention(rawValue: $0.loadConventionRaw)?.isLiftedLoad ?? false)
        }
    }

    private func applyIncrement(_ increment: Decimal, unit: MassUnit) {
        for draft in incrementableDrafts {
            guard let amount = draft.loadAmount else { continue }
            let draftUnit = MassUnit(rawValue: draft.loadUnitRaw) ?? unit
            let delta = draftUnit == unit ? increment : increment * unit.kilogramsPerUnit / draftUnit.kilogramsPerUnit
            draft.loadAmount = amount + delta
        }
        try? appState.context.save()
        draftsRevision += 1
    }

    private func index(of set: SetRecordModel) -> Int {
        (visibleSets.firstIndex { $0.id == set.id } ?? 0) + 1
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(exerciseName).font(.headline)
                Text([sessionExercise.variantKey, convention.displayName, sideMode == .perSide ? "por lados" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Variante o máquina…") {
                    variantText = sessionExercise.variantKey ?? ""
                    showVariant = true
                }
                Picker("Convención de carga", selection: Binding(
                    get: { convention },
                    set: { repo.setConvention($0, for: sessionExercise.exerciseID); updateDraftConvention($0) }
                )) {
                    ForEach(LoadConvention.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker("Lados", selection: Binding(
                    get: { sideMode },
                    set: { repo.setSideMode($0, for: sessionExercise) }
                )) {
                    Text("Bilateral").tag(SideMode.bilateral)
                    Text("Izquierda y derecha").tag(SideMode.perSide)
                }
                Divider()
                Button("Subir", systemImage: "arrow.up") { repo.move(sessionExercise, by: -1) }
                    .disabled(orderedSiblings.first?.id == sessionExercise.id)
                Button("Bajar", systemImage: "arrow.down") { repo.move(sessionExercise, by: 1) }
                    .disabled(orderedSiblings.last?.id == sessionExercise.id)
                Button("Sustituir por…", systemImage: "arrow.left.arrow.right") {
                    pendingSubstituteID = nil
                    showSubstitute = true
                }
                Divider()
                Button("Quitar de la sesión", role: .destructive) {
                    if !repo.removeExercise(sessionExercise) { removalBlocked = true }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Opciones de \(exerciseName)")
        }
    }

    @ViewBuilder
    private var previousLine: some View {
        if let previous = repo.previousComparable(exerciseID: sessionExercise.exerciseID, variantKey: sessionExercise.variantKey, excluding: sessionExercise.session) {
            let text = previous.sets.prefix(6).map { SetText.short($0) }.joined(separator: ", ")
            Text("Anterior (\(previous.date.formatted(.dateTime.day().month()))): \(text)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Sesión anterior comparable del \(previous.date.formatted(date: .long, time: .omitted)): \(text)")
        } else {
            Text("Sin sesión comparable anterior para esta variante.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func updateDraftConvention(_ c: LoadConvention) {
        for d in sessionExercise.sets where d.stateRaw == SetState.pending.rawValue {
            d.loadConventionRaw = c.rawValue
        }
        try? appState.context.save()
    }
}

// MARK: - Fila de borrador (registro rápido)

struct DraftSetRow: View {
    @Environment(AppState.self) private var appState
    @Bindable var draft: SetRecordModel
    let index: Int
    let convention: LoadConvention
    let askRIR: Bool
    let onConfirmed: (SetRecordModel) -> Void

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var error: String?
    @State private var loaded = false
    @FocusState private var focused: Field?

    private enum Field { case weight, reps }

    private var repo: WorkoutRepository { appState.repository }
    private var unit: MassUnit { MassUnit(rawValue: draft.loadUnitRaw) ?? appState.settings.massUnit }
    private var type: SetType { SetType(rawValue: draft.typeRaw) ?? .working }
    private var side: BodySide { BodySide(rawValue: draft.sideRaw) ?? .bilateral }
    private var increment: Decimal {
        repo.settings(for: draft.sessionExercise?.exerciseID ?? "")?.incrementAmount ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.sm) {
                Text(label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                if convention != .none {
                    numberField(convention.unitLabel(unit), text: $weightText, field: .weight, step: increment)
                }
                numberField("reps", text: $repsText, field: .reps, step: 1)
                Spacer(minLength: 0)
                Button(action: confirm) {
                    Image(systemName: "checkmark")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Confirmar serie \(index)")
                .accessibilityIdentifier("set.confirm")
            }
            HStack(spacing: Spacing.sm) {
                Menu {
                    Button("Trabajo") { setType(.working) }
                    Button("Calentamiento") { setType(.warmup) }
                    Button("Omitir esta serie") { repo.skip(draft) }
                    Button("Eliminar fila", role: .destructive) { repo.delete(draft) }
                } label: {
                    Label(type == .warmup ? "Calentamiento" : "Trabajo", systemImage: type == .warmup ? "flame" : "dumbbell")
                        .font(.caption)
                        .frame(minHeight: 32)
                }
                .accessibilityIdentifier("set.typeMenu")
                if askRIR {
                    RIRPicker(rir: Binding(get: { draft.toDomain().rir }, set: { save(rir: $0) }))
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .onAppear(perform: load)
    }

    private var label: String {
        switch side {
        case .left: return "\(index) Izq"
        case .right: return "\(index) Der"
        case .bilateral: return "\(index)"
        }
    }

    private func numberField(_ title: String, text: Binding<String>, field: Field, step: Decimal) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            HStack(spacing: 2) {
                Button { adjust(text, by: -step, field: field) } label: {
                    Image(systemName: "minus").frame(width: 28, height: 36)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Restar \(title)")
                TextField("—", text: text)
                    .keyboardType(field == .weight ? .decimalPad : .numberPad)
                    .multilineTextAlignment(.center)
                    .monospacedDigit()
                    .frame(minWidth: 44, maxWidth: 64, minHeight: 36)
                    .background(ArcoColor.background, in: RoundedRectangle(cornerRadius: 8))
                    .focused($focused, equals: field)
                    .onChange(of: text.wrappedValue) { _, _ in save(rir: draft.toDomain().rir) }
                    .accessibilityLabel(title)
                    .accessibilityIdentifier(field == .weight ? "set.weight" : "set.reps")
                Button { adjust(text, by: step, field: field) } label: {
                    Image(systemName: "plus").frame(width: 28, height: 36)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Sumar \(title)")
            }
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        weightText = draft.loadAmount.map(SetText.number) ?? ""
        repsText = draft.reps.map(String.init) ?? ""
    }

    private func adjust(_ text: Binding<String>, by step: Decimal, field: Field) {
        let parser = DecimalParser(locale: .current)
        let current = parser.parse(text.wrappedValue) ?? 0
        let next = max(0, current + step)
        text.wrappedValue = field == .reps ? "\(NSDecimalNumber(decimal: next).intValue)" : SetText.number(next)
    }

    private func setType(_ t: SetType) {
        draft.typeRaw = t.rawValue
        try? appState.context.save()
    }

    private func save(rir: RIR?) {
        let parser = DecimalParser(locale: .current)
        let amount = convention == .none ? nil : parser.parse(weightText)
        let reps = Int(repsText.trimmingCharacters(in: .whitespaces))
        repo.updateDraft(draft, amount: amount, unit: unit, reps: reps, type: type, side: side, rir: rir)
    }

    private func confirm() {
        save(rir: draft.toDomain().rir)
        if convention != .none && !weightText.isEmpty && DecimalParser(locale: .current).parse(weightText) == nil {
            error = "El peso no es un número válido."
            return
        }
        do {
            try repo.confirm(draft)
            error = nil
            focused = nil
            if appState.settings.hapticsEnabled {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
            onConfirmed(draft)
            Task { await appState.refreshReminders() }
        } catch RepositoryError.invalidSet(let problems) {
            error = SetText.message(for: problems)
        } catch {
            // T04: el borrador se conserva y se puede reintentar sin duplicar.
            self.error = "No se pudo guardar. Tus valores siguen aquí; vuelve a intentarlo."
        }
    }
}

// MARK: - Fila de serie realizada

struct CompletedSetRow: View {
    let set: SetRecordModel
    let index: Int
    let onEdit: () -> Void
    @Environment(AppState.self) private var appState

    var body: some View {
        Button(action: onEdit) {
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(ArcoColor.brand)
                Text(SetText.full(set, unit: appState.settings.massUnit))
                    .monospacedDigit()
                    .foregroundStyle(ArcoColor.textPrimary)
                Spacer()
                Image(systemName: "pencil").font(.caption).foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Serie \(index): \(SetText.full(set, unit: appState.settings.massUnit)). Toca para editar")
        .accessibilityIdentifier("set.completed")
    }
}

// MARK: - RIR opcional

struct RIRPicker: View {
    @Binding var rir: RIR?

    var body: some View {
        Menu {
            Button("Sin indicar") { rir = nil }
            ForEach(0..<4, id: \.self) { v in Button("RIR \(v)") { rir = .exact(v) } }
            Button("4 o más") { rir = .atLeast(4) }
            Button("No sé") { rir = .unknown }
        } label: {
            Label(SetText.rir(rir) ?? "RIR", systemImage: "gauge.with.dots.needle.33percent")
                .font(.caption)
                .frame(minHeight: 32)
        }
        .accessibilityLabel("Repeticiones en reserva: \(SetText.rir(rir) ?? "sin indicar")")
    }
}

// MARK: - Edición de una serie realizada

struct SetEditorView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Bindable var set: SetRecordModel
    let onDeleted: (SetRecordModel, SetState) -> Void

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var unit: MassUnit = .kilograms
    @State private var convention: LoadConvention = .externalTotal
    @State private var type: SetType = .working
    @State private var side: BodySide = .bilateral
    @State private var rir: RIR?
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Carga") {
                    Picker("Convención", selection: $convention) {
                        ForEach(LoadConvention.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    if convention != .none {
                        HStack {
                            TextField("Carga", text: $weightText).keyboardType(.decimalPad)
                            Picker("Unidad", selection: $unit) {
                                ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .labelsHidden()
                        }
                    }
                    if convention == .assistance {
                        Text("En asistencia, más cifra significa menos dificultad.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Serie") {
                    TextField("Repeticiones", text: $repsText).keyboardType(.numberPad)
                    Picker("Tipo", selection: $type) {
                        Text("Trabajo").tag(SetType.working)
                        Text("Calentamiento").tag(SetType.warmup)
                        Text("Intento").tag(SetType.attempt)
                    }
                    Picker("Lado", selection: $side) {
                        Text("Bilateral").tag(BodySide.bilateral)
                        Text("Izquierdo").tag(BodySide.left)
                        Text("Derecho").tag(BodySide.right)
                    }
                    RIRPicker(rir: $rir)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button("Eliminar serie", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Editar serie")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Guardar", action: save) }
            }
            .confirmationDialog("¿Eliminar esta serie?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar", role: .destructive) {
                    let previous = appState.repository.delete(set)
                    onDeleted(set, previous)
                    dismiss()
                }
            } message: {
                Text("Los récords y gráficos se recalcularán. Podrás deshacerlo.")
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        let d = set.toDomain()
        weightText = d.load.amount.map(SetText.number) ?? ""
        repsText = d.reps.map(String.init) ?? ""
        unit = d.load.unit
        convention = d.load.convention
        type = d.type
        side = d.side
        rir = d.rir
    }

    private func save() {
        let amount = convention == .none ? nil : DecimalParser(locale: .current).parse(weightText)
        if convention != .none && !weightText.isEmpty && amount == nil {
            error = "La carga no es un número válido."
            return
        }
        do {
            try appState.repository.edit(set, amount: amount, unit: unit, convention: convention, reps: Int(repsText), type: type, side: side, rir: rir)
            dismiss()
        } catch RepositoryError.invalidSet(let problems) {
            error = SetText.message(for: problems)
        } catch {
            self.error = "No se pudo guardar el cambio. Inténtalo de nuevo."
        }
    }
}

// MARK: - Resumen al finalizar

extension SessionSummary: @retroactive Identifiable {
    public var id: String { "\(workingSets)-\(warmupSets)-\(exerciseIDs.joined())-\(isPartial)" }
}

struct SessionSummaryView: View {
    let summary: SessionSummary
    let canSaveFavorite: Bool
    let onClose: (Bool) -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var favorite = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Series de trabajo", value: "\(summary.workingSets)")
                    if summary.warmupSets > 0 {
                        LabeledContent("Calentamientos y otras", value: "\(summary.warmupSets)")
                    }
                    if summary.isPartial {
                        Label("Sesión parcial: las series sin confirmar no se guardaron.", systemImage: "info.circle")
                            .font(.footnote)
                    }
                }
                if !summary.exerciseIDs.isEmpty {
                    Section("Ejercicios realizados") {
                        ForEach(summary.exerciseIDs, id: \.self) { Text(appState.exerciseName($0)) }
                    }
                }
                if !summary.newLoadRecords.isEmpty {
                    Section("Récords de carga comprobados") {
                        ForEach(summary.newLoadRecords, id: \.self) { Label(appState.exerciseName($0), systemImage: "rosette") }
                    }
                }
                if canSaveFavorite {
                    Section {
                        Toggle("Guardar esta selección para este tipo de día", isOn: $favorite)
                    }
                }
            }
            .navigationTitle("Sesión finalizada")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hecho") {
                        onClose(favorite)
                        dismiss()
                    }
                    .accessibilityIdentifier("summary.done")
                }
            }
        }
    }
}

// MARK: - Textos

enum SetText {
    static func number(_ d: Decimal) -> String {
        d.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    static func short(_ s: SetRecordModel) -> String {
        let d = s.toDomain()
        let load = d.load.amount.map(number) ?? "—"
        let reps = d.reps.map(String.init) ?? "—"
        let side = d.side == .left ? " izq" : d.side == .right ? " der" : ""
        return d.load.convention == .none ? "\(reps) rep\(side)" : "\(load)×\(reps)\(side)"
    }

    static func full(_ s: SetRecordModel, unit: MassUnit) -> String {
        let d = s.toDomain()
        var parts: [String] = []
        if d.load.convention != .none {
            parts.append("\(d.load.amount.map(number) ?? "—") \(d.load.convention.unitLabel(d.load.unit))")
        }
        parts.append("\(d.reps.map(String.init) ?? "—") rep")
        if let r = rir(d.rir) { parts.append(r) }
        if d.type == .warmup { parts.append("calentamiento") }
        if d.type == .attempt { parts.append("intento") }
        if d.side == .left { parts.append("izquierdo") }
        if d.side == .right { parts.append("derecho") }
        return parts.joined(separator: " · ")
    }

    static func rir(_ r: RIR?) -> String? {
        switch r {
        case .exact(let v): return "RIR \(v)"
        case .atLeast(let v): return "RIR \(v)+"
        case .unknown: return "RIR ?"
        case nil: return nil
        }
    }

    static func message(for problems: [SetValidationError]) -> String {
        if problems.contains(.missingReps) || problems.contains(.nonPositiveReps) {
            return "Indica las repeticiones (un número mayor que 0)."
        }
        if problems.contains(.negativeLoad) { return "La carga no puede ser negativa." }
        if problems.contains(.negativeRIR) { return "El RIR no puede ser negativo." }
        return "Revisa los valores de la serie."
    }
}
