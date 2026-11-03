import SwiftUI
import SwiftData
import ArcoCore

/// Configuración inicial breve, editable y reanudable (spec §3). No inventa datos personales:
/// fecha de nacimiento, altura y peso se piden aquí; se pueden omitir y completar luego.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var displayName = ""
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -20, to: Date()) ?? Date()
    @State private var hasBirthDate = false
    @State private var hasTrainingStart = false
    @State private var trainingStart = Date()
    @State private var heightText = ""
    @State private var weightText = ""
    @State private var massUnit: MassUnit = .kilograms
    @State private var lengthUnit: LengthUnit = .centimeters

    var body: some View {
        NavigationStack {
            Form {
                Section("Bienvenido a Arco") {
                    Text("Registra tu entrenamiento, observa tu progreso y mantén la constancia. Puedes completar o cambiar estos datos cuando quieras.")
                        .foregroundStyle(.secondary)
                }

                Section("Perfil") {
                    TextField("Nombre o apodo (opcional)", text: $displayName)
                    Toggle("Indicar fecha de nacimiento", isOn: $hasBirthDate)
                    if hasBirthDate {
                        DatePicker("Fecha de nacimiento", selection: $birthDate, in: ...Date().addingTimeInterval(-86400), displayedComponents: .date)
                    }
                    Toggle("Indicar cuándo empezaste a entrenar", isOn: $hasTrainingStart)
                        .accessibilityIdentifier("onboarding.trainingStart")
                    if hasTrainingStart {
                        DatePicker("Empecé a entrenar", selection: $trainingStart, in: ...Date(), displayedComponents: .date)
                    }
                }

                Section("Unidades") {
                    Picker("Peso", selection: $massUnit) {
                        Text("Kilogramos (kg)").tag(MassUnit.kilograms)
                        Text("Libras (lb)").tag(MassUnit.pounds)
                    }
                    Picker("Longitud", selection: $lengthUnit) {
                        Text("Centímetros (cm)").tag(LengthUnit.centimeters)
                        Text("Pulgadas (in)").tag(LengthUnit.inches)
                    }
                }

                Section("Medidas (opcional)") {
                    HStack {
                        Text("Altura")
                        TextField("—", text: $heightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(lengthUnit.rawValue).foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Peso")
                        TextField("—", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                        Text(massUnit.rawValue).foregroundStyle(.secondary)
                    }
                    Text("Si lo dejas vacío, podrás añadirlo más tarde desde Perfil.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                restoreSection
            }
            .navigationTitle("Configuración")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Empezar", action: save)
                        .accessibilityIdentifier("onboarding.start")
                }
            }
            .alert("Revisa los datos", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("Entendido", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    @State private var error: String?

    private var restoreSection: some View {
        Section {
            NavigationLink("Restaurar desde una copia de Arco") { BackupView() }
        } footer: {
            Text("Si tienes un archivo .arcobk exportado antes, puedes recuperarlo aquí.")
        }
    }

    private func save() {
        let decimalParser = DecimalParser(locale: .current)
        let heightTrimmed = heightText.trimmingCharacters(in: .whitespaces)
        let weightTrimmed = weightText.trimmingCharacters(in: .whitespaces)
        let height = decimalParser.parse(heightTrimmed)
        let weight = decimalParser.parse(weightTrimmed)
        // Vacío = desconocido (válido). Escrito pero no positivo o ambiguo = error.
        if !heightTrimmed.isEmpty && (height == nil || height! <= 0) {
            error = "La altura debe ser un número mayor que 0 o quedar vacía."
            return
        }
        if !weightTrimmed.isEmpty && (weight == nil || weight! <= 0) {
            error = "El peso debe ser un número mayor que 0 o quedar vacío."
            return
        }
        if hasBirthDate && birthDate >= Date() {
            error = "La fecha de nacimiento debe ser una fecha pasada."
            return
        }

        let profile = UserProfileModel(
            displayName: displayName.trimmingCharacters(in: .whitespaces).isEmpty ? nil : displayName.trimmingCharacters(in: .whitespaces),
            birthDate: hasBirthDate ? birthDate : nil
        )
        appState.context.insert(profile)

        appState.settings.massUnitRaw = massUnit.rawValue
        appState.settings.lengthUnitRaw = lengthUnit.rawValue
        Preferences.trainingStart = hasTrainingStart ? CivilDay(min(trainingStart, Date()), calendar: appState.calendar) : nil

        if let h = height {
            appState.context.insert(HeightModel(date: Date(), amount: h, unitRaw: lengthUnit.rawValue))
        }
        if let w = weight {
            appState.context.insert(BodyWeightModel(measurementDate: Date(), enteredAt: Date(), amount: w, unitRaw: massUnit.rawValue, isEstimated: false))
        }

        appState.completeOnboarding()
    }
}
