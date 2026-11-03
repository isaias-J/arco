import SwiftUI
import SwiftData
import ArcoCore

/// Catálogo de ejercicios (spec §6, §7, §10.4, §13): activos y archivados, búsqueda por nombre
/// o alias y alta de ejercicios personalizados. Ningún cambio borra historial: los registros
/// apuntan al identificador estable del ejercicio.
struct CatalogView: View {
    @Query(sort: \ExerciseModel.name) private var exercises: [ExerciseModel]
    @Query private var customAttributions: [CustomAttributionModel]
    @State private var search = ""
    @State private var showNew = false

    private func matches(_ ex: ExerciseModel) -> Bool {
        let q = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return q.isEmpty || ex.name.localizedStandardContains(q) || ex.aliasesJoined.localizedStandardContains(q)
    }

    private var active: [ExerciseModel] { exercises.filter { !$0.archived && matches($0) } }
    private var archived: [ExerciseModel] { exercises.filter { $0.archived && matches($0) } }
    private var customized: Set<String> { Set(customAttributions.map(\.exerciseID)) }

    var body: some View {
        List {
            Section {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField("Buscar por nombre o alias", text: $search)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityLabel("Buscar ejercicio")
                        .accessibilityIdentifier("catalog.search")
                    if !search.isEmpty {
                        Button { search = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Borrar búsqueda")
                    }
                }
            }
            Section {
                if active.isEmpty {
                    Text(search.isEmpty ? "No hay ejercicios activos." : "Ningún ejercicio activo coincide con la búsqueda.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(active) { row($0) }
            } header: {
                Text("Activos (\(active.count))")
            }
            if !archived.isEmpty {
                Section {
                    ForEach(archived) { row($0) }
                } header: {
                    Text("Archivados")
                } footer: {
                    Text("Los archivados no aparecen al elegir ejercicios, pero conservan todo su historial.")
                }
            }
        }
        .navigationTitle("Catálogo")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Nuevo", systemImage: "plus") { showNew = true }
                    .accessibilityIdentifier("catalog.new")
            }
        }
        .sheet(isPresented: $showNew) {
            NewExerciseView { _ in }
        }
    }

    private func row(_ ex: ExerciseModel) -> some View {
        NavigationLink(value: TodayRoute.exercise(ex.id)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).foregroundStyle(ArcoColor.textPrimary)
                if let detail = subtitle(ex) {
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 44, alignment: .leading)
        }
        .accessibilityIdentifier("catalog.exercise.\(ex.id)")
    }

    private func subtitle(_ ex: ExerciseModel) -> String? {
        var parts: [String] = []
        if ex.originRaw == ExerciseOrigin.custom.rawValue {
            parts.append(customized.contains(ex.id) ? "Personalizado" : "Personalizado · sin atribución")
        } else if customized.contains(ex.id) {
            parts.append("Atribución personalizada")
        }
        let aliases = ex.aliasesJoined.split(separator: "\n").map(String.init)
        if !aliases.isEmpty { parts.append("Alias: \(aliases.joined(separator: ", "))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Detalle de un ejercicio

/// Edición de un ejercicio: nombre, alias, archivo, carga por defecto, incremento y barra,
/// doble progresión y atribución muscular.
struct ExerciseCatalogDetailView: View {
    let exerciseID: String

    @Environment(AppState.self) private var appState
    @Query private var models: [ExerciseModel]
    @Query private var customAttributions: [CustomAttributionModel]
    /// Observa las preferencias de carga para que el selector refleje el cambio al momento.
    @Query private var exerciseSettings: [ExerciseSettingsModel]

    @State private var loaded = false
    @State private var nameText = ""
    @State private var nameMessage: String?
    @State private var aliasesText = ""
    @State private var aliasesMessage: String?
    @State private var incrementText = ""
    @State private var barText = ""
    @State private var loadUnit: MassUnit = .kilograms
    @State private var loadMessage: String?
    @State private var progression = ProgressionDraft()
    @State private var progressionMessage: String?
    @State private var showAttributionEditor = false
    @State private var confirmArchive = false

    init(exerciseID: String) {
        self.exerciseID = exerciseID
        _models = Query(filter: #Predicate<ExerciseModel> { $0.id == exerciseID })
        _customAttributions = Query(filter: #Predicate<CustomAttributionModel> { $0.exerciseID == exerciseID })
        _exerciseSettings = Query(filter: #Predicate<ExerciseSettingsModel> { $0.exerciseID == exerciseID })
    }

    private var model: ExerciseModel? { models.first }
    private var catalog: CatalogRepository { appState.catalog }
    private var repo: WorkoutRepository { appState.repository }
    private var isCustomExercise: Bool { model?.originRaw == ExerciseOrigin.custom.rawValue }
    private var isCustomized: Bool { !customAttributions.isEmpty }

    /// Atribución efectiva: la personalizada si existe, si no la del catálogo.
    private var effectiveRules: AttributionRuleSet? {
        AttributionResolver.ruleSet(for: exerciseID, custom: AttributionResolver.customRuleSets(appState.context))
    }

    var body: some View {
        Form {
            if let model {
                nameSection
                aliasSection
                loadSection
                progressionSection
                attributionSection
                archiveSection(model)
            } else {
                Text("Este ejercicio no está en el catálogo.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(model?.name ?? appState.exerciseName(exerciseID))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .onAppear(perform: load)
        .sheet(isPresented: $showAttributionEditor) {
            AttributionEditorView(
                exerciseName: model?.name ?? appState.exerciseName(exerciseID),
                initial: effectiveRules,
                isCustomExercise: isCustomExercise
            ) { roles in
                try? catalog.setCustomAttribution(exerciseID, roles)
            }
        }
    }

    // MARK: Nombre y alias

    private var nameSection: some View {
        Section {
            TextField("Nombre", text: $nameText)
                .accessibilityIdentifier("catalog.detail.name")
            Button("Guardar nombre", action: saveName)
                .disabled(nameText.trimmingCharacters(in: .whitespacesAndNewlines) == model?.name)
            if let nameMessage { Text(nameMessage).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Nombre")
        } footer: {
            Text("Renombrar conserva todo el historial: las series siguen ligadas al mismo ejercicio.")
        }
    }

    private var aliasSection: some View {
        Section {
            TextField("Alias separados por comas", text: $aliasesText, axis: .vertical)
                .accessibilityIdentifier("catalog.detail.aliases")
            Button("Guardar alias", action: saveAliases)
            if let aliasesMessage { Text(aliasesMessage).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Alias")
        } footer: {
            Text("Otros nombres con los que lo buscas, p. ej. el de la máquina de tu gimnasio. Un alias no crea un ejercicio nuevo.")
        }
    }

    private func saveName() {
        do {
            try catalog.rename(exerciseID, to: nameText)
            nameText = model?.name ?? nameText
            nameMessage = "Nombre guardado."
            hideKeyboard()
        } catch CatalogRepository.CatalogError.emptyName {
            nameMessage = "El nombre no puede quedar vacío."
        } catch CatalogRepository.CatalogError.duplicateName {
            nameMessage = "Ya existe otro ejercicio con ese nombre. Elige uno distinto: Arco no fusiona historiales automáticamente."
        } catch {
            nameMessage = "No se pudo guardar el nombre. Inténtalo de nuevo."
        }
    }

    private func saveAliases() {
        let list = aliasesText.split(separator: ",").map(String.init)
        do {
            try catalog.setAliases(exerciseID, list)
            aliasesText = aliasList.joined(separator: ", ")
            aliasesMessage = aliasList.isEmpty ? "Sin alias." : "Alias guardados."
            hideKeyboard()
        } catch {
            aliasesMessage = "No se pudieron guardar los alias. Inténtalo de nuevo."
        }
    }

    private var aliasList: [String] {
        (model?.aliasesJoined ?? "").split(separator: "\n").map(String.init)
    }

    // MARK: Carga (spec §7)

    private var loadSection: some View {
        Section {
            Picker("Convención por defecto", selection: Binding(
                get: { repo.convention(for: exerciseID) },
                set: { repo.setConvention($0, for: exerciseID) }
            )) {
                ForEach(LoadConvention.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Unidad", selection: $loadUnit) {
                ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Unidad del incremento y de la barra")
            LabeledContent("Incremento disponible") {
                TextField("desconocido", text: $incrementText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Incremento disponible en \(loadUnit.rawValue)")
                    .accessibilityIdentifier("catalog.detail.increment")
            }
            LabeledContent("Peso de la barra") {
                TextField("desconocido", text: $barText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityLabel("Peso conocido de la barra en \(loadUnit.rawValue)")
                    .accessibilityIdentifier("catalog.detail.bar")
            }
            Button("Guardar carga", action: saveLoad)
            if let loadMessage { Text(loadMessage).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Carga")
        } footer: {
            Text("La convención se aplica a las series nuevas; las registradas conservan la suya. Deja vacío lo que no sepas: queda como desconocido. El peso de la barra solo se usa si lo conoces; Arco no supone 20 kg.")
        }
    }

    private func saveLoad() {
        let parser = DecimalParser(locale: .current)
        func parse(_ text: String) -> (ok: Bool, value: Decimal?) {
            let t = text.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { return (true, nil) }
            guard let v = parser.parse(t), v > 0 else { return (false, nil) }
            return (true, v)
        }
        let inc = parse(incrementText), bar = parse(barText)
        guard inc.ok, bar.ok else {
            loadMessage = "Usa un número mayor que 0 o deja el campo vacío (desconocido)."
            return
        }
        do {
            try catalog.setIncrement(exerciseID, amount: inc.value, unit: loadUnit, barWeight: bar.value)
            loadMessage = "Guardado."
            hideKeyboard()
        } catch {
            loadMessage = "No se pudo guardar. Inténtalo de nuevo."
        }
    }

    // MARK: Doble progresión (spec §13)

    private var progressionSection: some View {
        Section {
            Toggle("Usar doble progresión", isOn: $progression.enabled)
                .accessibilityIdentifier("catalog.detail.progression")
            if progression.enabled {
                integerField("Repeticiones mínimas del rango", id: "progression.lower", text: $progression.lower)
                integerField("Repeticiones máximas (techo)", id: "progression.upper", text: $progression.upper)
                integerField("Series de referencia", id: "progression.referenceSets", text: $progression.referenceSets)
                LabeledContent("Incremento a considerar") {
                    HStack {
                        TextField("p. ej. 2,5", text: $progression.increment)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .accessibilityLabel("Incremento a considerar")
                            .accessibilityIdentifier("progression.increment")
                        Picker("Unidad", selection: $progression.unit) {
                            ForEach(MassUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                    }
                }
                Picker("RIR mínimo (opcional)", selection: $progression.minimumRIR) {
                    Text("Sin criterio de esfuerzo").tag(Int?.none)
                    ForEach(0..<5, id: \.self) { Text("RIR \($0) o más").tag(Int?.some($0)) }
                }
            }
            if progression.enabled || progression.hasSavedRule {
                Button("Guardar regla", action: saveProgression)
                    .accessibilityIdentifier("catalog.detail.progression.save")
            }
            if let progressionMessage { Text(progressionMessage).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Doble progresión")
        } footer: {
            Text("Si en la última sesión comparable todas las series de referencia llegan al techo del rango (y al RIR elegido), Arco te dirá que cumpliste tu regla para considerar subir. Nunca cambia tus pesos sin que lo aceptes. No hay valores predeterminados: elige los tuyos.")
        }
    }

    private func integerField(_ title: String, id: String, text: Binding<String>) -> some View {
        LabeledContent(title) {
            TextField("—", text: text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .accessibilityLabel(title)
                .accessibilityIdentifier(id)
        }
    }

    private func saveProgression() {
        let lower = Int(progression.lower.trimmingCharacters(in: .whitespaces))
        let upper = Int(progression.upper.trimmingCharacters(in: .whitespaces))
        let refs = Int(progression.referenceSets.trimmingCharacters(in: .whitespaces))
        let increment = DecimalParser(locale: .current).parse(progression.increment.trimmingCharacters(in: .whitespaces))
        guard let lower, lower > 0 else { progressionMessage = "Las repeticiones mínimas deben ser un entero mayor que 0."; return }
        guard let upper, upper >= lower else { progressionMessage = "El techo debe ser igual o mayor que el mínimo del rango."; return }
        guard let refs, refs > 0 else { progressionMessage = "Indica cuántas series de referencia (1 o más)."; return }
        guard let increment, increment > 0 else { progressionMessage = "El incremento debe ser un número mayor que 0."; return }
        do {
            try catalog.setProgressionRule(exerciseID, enabled: progression.enabled, lower: lower, upper: upper, referenceSets: refs, increment: increment, unit: progression.unit, minimumRIR: progression.minimumRIR)
            progression.hasSavedRule = true
            progressionMessage = progression.enabled ? "Regla guardada." : "Regla desactivada; se conserva por si la reactivas."
            hideKeyboard()
        } catch {
            progressionMessage = "Revisa los valores de la regla."
        }
    }

    // MARK: Atribución muscular (spec §10.3, §10.4)

    private var attributionSection: some View {
        Section {
            if let rules = effectiveRules {
                if rules.userCustomized {
                    Label("Personalizada por ti (no es una regla científica revisada)", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.footnote)
                } else {
                    Label("Modelo inicial \(ExerciseCatalog.attributionVersion.description), estimación", systemImage: "info.circle")
                        .font(.footnote)
                }
                ForEach(rules.attributions, id: \.muscle) { a in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(a.muscle.displayName)
                            Spacer()
                            Text(AttributionText.role(a.role)).foregroundStyle(.secondary)
                        }
                        if !rules.userCustomized {
                            Text("Soporte: \(AttributionText.support(a.support))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } else {
                Text("Sin atribución: sus series no suman a ningún músculo.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button("Personalizar atribución") { showAttributionEditor = true }
                .accessibilityIdentifier("catalog.detail.customize")
            if isCustomized {
                Button(isCustomExercise ? "Quitar mi atribución" : "Volver a la del catálogo", role: .destructive) {
                    try? catalog.setCustomAttribution(exerciseID, [:])
                }
                .accessibilityIdentifier("catalog.detail.resetAttribution")
            }
        } header: {
            Text("Atribución muscular")
        } footer: {
            Text("Directo suma 1 serie; indirecto suma 1 en I y 0,5 en la estimación fraccional; pendiente se cuenta aparte (U). Es una convención para repartir el trabajo, no una medida exacta por persona. Cambiarla recalcula los conteos con la atribución vigente.")
        }
    }

    // MARK: Archivo

    private func archiveSection(_ model: ExerciseModel) -> some View {
        Section {
            if model.archived {
                Button("Recuperar ejercicio") { try? catalog.setArchived(exerciseID, false) }
                    .accessibilityIdentifier("catalog.detail.unarchive")
            } else {
                Button("Archivar ejercicio") { confirmArchive = true }
                    .accessibilityIdentifier("catalog.detail.archive")
                    .confirmationDialog("¿Archivar \(model.name)?", isPresented: $confirmArchive, titleVisibility: .visible) {
                        Button("Archivar") { try? catalog.setArchived(exerciseID, true) }
                    } message: {
                        Text("Dejará de aparecer al elegir ejercicios. No se borra su historial.")
                    }
            }
        } footer: {
            Text(model.archived
                 ? "Archivado: no aparece al elegir ejercicios. Su historial, gráficos y récords se conservan."
                 : "Archivar oculta el ejercicio al elegir ejercicios. No borra el historial: sus series, gráficos y récords se conservan y puedes recuperarlo cuando quieras.")
        }
    }

    // MARK: Carga inicial

    private func load() {
        guard !loaded, let model else { return }
        loaded = true
        nameText = model.name
        aliasesText = aliasList.joined(separator: ", ")
        let settings = repo.settings(for: exerciseID)
        loadUnit = settings?.unitRaw.flatMap(MassUnit.init(rawValue:)) ?? appState.settings.massUnit
        incrementText = settings?.incrementAmount.map(SetText.number) ?? ""
        barText = settings?.barWeight.map(SetText.number) ?? ""
        if let rule = catalog.progressionRule(exerciseID) {
            progression = ProgressionDraft(
                enabled: rule.enabled, lower: "\(rule.repLower)", upper: "\(rule.repUpper)",
                referenceSets: "\(rule.referenceSets)", increment: SetText.number(rule.increment),
                unit: MassUnit(rawValue: rule.unitRaw) ?? .kilograms, minimumRIR: rule.minimumRIR, hasSavedRule: true
            )
        } else {
            progression.unit = loadUnit
        }
    }
}

/// Valores de la regla en edición (texto para no convertir campos vacíos en cero).
private struct ProgressionDraft {
    var enabled = false
    var lower = ""
    var upper = ""
    var referenceSets = ""
    var increment = ""
    var unit: MassUnit = .kilograms
    var minimumRIR: Int?
    var hasSavedRule = false
}

enum AttributionText {
    static func role(_ role: AttributionRole) -> String {
        switch role {
        case .direct: return "Directo"
        case .indirect: return "Indirecto"
        case .unknown: return "Pendiente"
        case .notCounted: return "No contabilizado"
        }
    }

    static func support(_ level: SupportLevel) -> String {
        switch level {
        case .longitudinalSpecific: return "estudio longitudinal específico"
        case .longitudinalRelated: return "estudio longitudinal relacionado"
        case .biomechanical: return "razonamiento biomecánico"
        case .productInference: return "inferencia de producto (heurística)"
        }
    }
}

// MARK: - Editor de atribución personalizada (spec §10.4)

private struct AttributionEditorView: View {
    let exerciseName: String
    let initial: AttributionRuleSet?
    let isCustomExercise: Bool
    let onSave: ([Muscle: AttributionRole]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var roles: [Muscle: AttributionRole] = [:]
    @State private var loaded = false

    private static let choices: [AttributionRole] = [.notCounted, .direct, .indirect, .unknown]

    private var allNotCounted: Bool { roles.values.allSatisfy { $0 == .notCounted } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Elige el papel de cada músculo en \(exerciseName). Tu ajuste se marcará como personalizado: no es una regla científica revisada.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if allNotCounted {
                        Text(isCustomExercise
                             ? "Con todos en «no contabilizado», el ejercicio queda sin atribución y sus series no suman a ningún músculo."
                             : "Con todos en «no contabilizado» se vuelve a la atribución del catálogo.")
                            .font(.footnote)
                    }
                }
                ForEach(MuscleGroup.allCases, id: \.self) { group in
                    Section(group.displayName) {
                        ForEach(Muscle.allCases.filter { $0.group == group }, id: \.self) { muscle in
                            Picker(muscle.displayName, selection: Binding(
                                get: { roles[muscle] ?? .notCounted },
                                set: { roles[muscle] = $0 }
                            )) {
                                ForEach(Self.choices, id: \.self) { Text(AttributionText.role($0)).tag($0) }
                            }
                            .accessibilityIdentifier("attribution.\(muscle.rawValue)")
                        }
                    }
                }
            }
            .navigationTitle("Personalizar atribución")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        onSave(roles.filter { $0.value != .notCounted })
                        dismiss()
                    }
                    .accessibilityIdentifier("attribution.save")
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                var r: [Muscle: AttributionRole] = [:]
                for m in Muscle.allCases { r[m] = initial?.role(for: m) ?? .notCounted }
                roles = r
            }
        }
    }
}
