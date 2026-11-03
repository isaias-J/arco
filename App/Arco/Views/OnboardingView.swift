import SwiftUI
import SwiftData
import ArcoCore

/// Configuración inicial breve, editable y reanudable (spec §3). No inventa datos personales:
/// fecha de nacimiento, altura y peso se piden aquí; se pueden omitir y completar luego.
struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    @State private var displayName = ""
    @State private var birthDate = Date(timeIntervalSince1970: 0)
    @State private var hasBirthDate = false
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
                        DatePicker("Fecha de nacimiento", selection: $birthDate, in: ...Date(), displayedComponents: .date)
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
            }
            .navigationTitle("Configuración")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Empezar", action: save)
                }
            }
        }
    }

    private func save() {
        let profile = UserProfileModel(
            displayName: displayName.isEmpty ? nil : displayName,
            birthDate: hasBirthDate ? birthDate : nil
        )
        appState.context.insert(profile)

        appState.settings.massUnitRaw = massUnit.rawValue
        appState.settings.lengthUnitRaw = lengthUnit.rawValue

        // Altura y peso si se indicaron (no se inventan).
        let decimalParser = DecimalParser(locale: .current)
        if let h = decimalParser.parse(heightText) {
            appState.context.insert(HeightModel(date: Date(), amount: h, unitRaw: lengthUnit.rawValue))
        }
        if let w = decimalParser.parse(weightText) {
            appState.context.insert(BodyWeightModel(measurementDate: Date(), enteredAt: Date(), amount: w, unitRaw: massUnit.rawValue, isEstimated: false))
        }

        appState.completeOnboarding()
    }
}
