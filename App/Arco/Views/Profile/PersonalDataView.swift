import SwiftUI
import SwiftData
import ArcoCore

/// "Datos personales" (spec §18, hallazgo 12). Todos los campos son opcionales: ninguno es
/// necesario para registrar series ni para calcular la fórmula del IMC. La edad se deriva de la
/// fecha real con `AgeCalculator`; nunca se fija una constante.
struct PersonalDataView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [UserProfileModel]

    @State private var displayName = ""
    @State private var hasBirthDate = false
    @State private var birthDate = Date()
    @State private var hasTrainingStart = false
    @State private var trainingStart = Date()
    @State private var experience = ""
    @State private var goalDescription = ""
    @State private var gender = ""
    @State private var loaded = false
    @State private var saveFailed = false

    private static let experienceOptions = ["Principiante", "Intermedio", "Avanzado"]

    private var derivedAge: Int? {
        guard hasBirthDate else { return nil }
        return AgeCalculator.age(birthDate: birthDate, on: Date(), calendar: appState.calendar)
    }

    private var trainingWeeks: Int? {
        guard hasTrainingStart else { return nil }
        let cal = appState.calendar
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: trainingStart), to: cal.startOfDay(for: Date())).day ?? 0
        return max(0, days) / 7
    }

    var body: some View {
        Form {
            Section {
                TextField("Nombre o apodo (opcional)", text: $displayName)
                    .textContentType(.nickname)
            } header: {
                Text("Nombre")
            }

            Section {
                Toggle("Indicar fecha de nacimiento", isOn: $hasBirthDate.animation())
                if hasBirthDate {
                    DatePicker("Fecha de nacimiento", selection: $birthDate, in: ...Date(), displayedComponents: .date)
                    if let age = derivedAge {
                        LabeledContent("Edad calculada", value: "\(age) años")
                    }
                }
            } header: {
                Text("Fecha de nacimiento")
            } footer: {
                Text("La edad se calcula con la fecha de hoy. Si no la indicas, aparece como desconocida.")
            }

            Section {
                Toggle("Indicar cuándo empezaste a entrenar", isOn: $hasTrainingStart.animation())
                if hasTrainingStart {
                    DatePicker("Empecé a entrenar", selection: $trainingStart, in: ...Date(), displayedComponents: .date)
                    if let weeks = trainingWeeks {
                        LabeledContent("Tiempo entrenando", value: weeks == 1 ? "1 semana" : "\(weeks) semanas")
                    }
                }
                Picker("Experiencia", selection: $experience) {
                    Text("Sin indicar").tag("")
                    ForEach(experienceChoices, id: \.self) { Text($0).tag($0) }
                }
                TextField("Intención general (opcional)", text: $goalDescription, axis: .vertical)
                    .lineLimit(1...3)
            } header: {
                Text("Entrenamiento")
            } footer: {
                Text("Experiencia y fecha de inicio autodeclaradas. Arco no las usa para imponer metas ni para calcular tu asistencia.")
            }

            Section {
                TextField("Género (opcional)", text: $gender)
            } footer: {
                Text("Nunca es obligatorio y no cambia ningún cálculo.")
            }
        }
        .navigationTitle("Datos personales")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Guardar") { save() }
            }
        }
        .alert("No se pudo guardar", isPresented: $saveFailed) {
            Button("Aceptar", role: .cancel) {}
        } message: {
            Text("Tus cambios siguen en pantalla. Inténtalo de nuevo.")
        }
        .onAppear(perform: load)
    }

    /// Opciones fijas + el valor guardado si es distinto (no se pierde texto previo).
    private var experienceChoices: [String] {
        var options = Self.experienceOptions
        if !experience.isEmpty && !options.contains(experience) { options.append(experience) }
        return options
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let p = profiles.first else { return }
        displayName = p.displayName ?? ""
        if let b = p.birthDate { hasBirthDate = true; birthDate = b }
        if let start = Preferences.trainingStart?.startDate(in: appState.calendar) { hasTrainingStart = true; trainingStart = start }
        experience = p.experience ?? ""
        goalDescription = p.goalDescription ?? ""
        gender = p.gender ?? ""
    }

    private func save() {
        let profile: UserProfileModel
        if let existing = profiles.first {
            profile = existing
        } else {
            profile = UserProfileModel()
            appState.context.insert(profile)
        }
        profile.displayName = Self.cleaned(displayName)
        profile.birthDate = hasBirthDate ? min(birthDate, Date()) : nil
        profile.experience = Self.cleaned(experience)
        profile.goalDescription = Self.cleaned(goalDescription)
        profile.gender = Self.cleaned(gender)
        Preferences.trainingStart = hasTrainingStart ? CivilDay(min(trainingStart, Date()), calendar: appState.calendar) : nil
        do {
            try appState.context.save()
            dismiss()
        } catch {
            saveFailed = true
        }
    }

    /// Recorta espacios; vacío = desconocido (nil), nunca un valor inventado.
    private static func cleaned(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

/// Ajustes editables desde Perfil (spec §20: sin pestaña extra de configuración).
/// Cada cambio se guarda al momento; las unidades solo cambian la visualización.
struct ProfileSettingsSection: View {
    @Environment(AppState.self) private var appState
    /// `rirMode` vive en UserDefaults (no observable): se refleja en estado local.
    @State private var rirMode: RIRMode = .off

    var body: some View {
        Section {
            Picker("Unidad de masa", selection: binding(\.massUnitRaw)) {
                Text("Kilogramos (kg)").tag(MassUnit.kilograms.rawValue)
                Text("Libras (lb)").tag(MassUnit.pounds.rawValue)
            }
            Picker("Unidad de longitud", selection: binding(\.lengthUnitRaw)) {
                Text("Centímetros (cm)").tag(LengthUnit.centimeters.rawValue)
                Text("Pulgadas (in)").tag(LengthUnit.inches.rawValue)
            }
            Picker("La semana empieza", selection: binding(\.weekStartsMonday, refreshReminders: true)) {
                Text("Lunes").tag(true)
                Text("Domingo").tag(false)
            }
            Picker("Tema", selection: binding(\.themeRaw)) {
                ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker("Pedir RIR", selection: Binding(
                get: { rirMode },
                set: { rirMode = $0; appState.rirMode = $0 }
            )) {
                ForEach(RIRMode.allCases) { Text($0.label).tag($0) }
            }
            .task { rirMode = appState.rirMode }
            Toggle("Respuesta háptica", isOn: binding(\.hapticsEnabled))
        } header: {
            Text("Ajustes")
        } footer: {
            Text("Cambiar la unidad solo cambia cómo se muestran los datos; cada registro conserva su unidad original.")
        }
    }

    /// Binding a un ajuste persistente que guarda en cuanto cambia.
    private func binding<T>(_ keyPath: ReferenceWritableKeyPath<AppSettingsModel, T>, refreshReminders: Bool = false) -> Binding<T> {
        let state = appState
        return Binding(
            get: { state.settings[keyPath: keyPath] },
            set: { newValue in
                state.settings[keyPath: keyPath] = newValue
                try? state.context.save()
                if refreshReminders {
                    Task { await state.refreshReminders() }
                }
            }
        )
    }
}
