import SwiftUI
import SwiftData
import ArcoCore

/// Perfil: peso, altura, IMC, medidas y ajustes (spec §18, §20). Desde aquí se gestionan ajustes.
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfileModel]
    @Query(sort: \BodyWeightModel.measurementDate, order: .reverse) private var weights: [BodyWeightModel]
    @Query(sort: \HeightModel.date, order: .reverse) private var heights: [HeightModel]

    @State private var showAddWeight = false

    private var profile: UserProfileModel? { profiles.first }

    private var currentWeight: BodyWeightEntry? {
        BodyWeightAnalytics.currentWeight(from: weights.map { $0.toDomain() })
    }

    private var bmi: BMIResult? {
        guard let w = currentWeight, let h = heights.first else { return nil }
        return BMICalculator.bmi(
            mass: w.amount, massUnit: w.unit,
            height: h.amount, heightUnit: LengthUnit(rawValue: h.unitRaw) ?? .centimeters,
            isEstimated: w.isEstimated
        )
    }

    var body: some View {
        NavigationStack {
            List {
                weightSection
                bmiSection
                measurementsSection
                settingsSection
                aboutSection
            }
            .navigationTitle("Perfil")
            .sheet(isPresented: $showAddWeight) {
                AddWeightView()
            }
        }
    }

    private var weightSection: some View {
        Section("Peso") {
            if let w = currentWeight {
                HStack {
                    Text("Peso actual")
                    Spacer()
                    Text("\(NSDecimalNumber(decimal: w.amount).stringValue) \(w.unit.rawValue)")
                        .monospacedDigit()
                    if w.isEstimated {
                        Text("estimado").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("Medido el \(w.measurementDate.formatted(.dateTime.day().month().year()))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Sin pesaje registrado").foregroundStyle(.secondary)
            }
            Button("Añadir pesaje") { showAddWeight = true }
        }
    }

    @ViewBuilder
    private var bmiSection: some View {
        if let bmi {
            Section("IMC (referencia adulta NHS/NICE, 18+)") {
                HStack {
                    Text("IMC")
                    Spacer()
                    Text(NSDecimalNumber(decimal: bmi.displayValue).stringValue)
                        .font(.title3.bold()).monospacedDigit()
                    if bmi.isEstimated {
                        Text("estimado").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(bandLabel(bmi.band))
                    .foregroundStyle(.secondary)
                if bmi.displayCrossesBoundary {
                    Text("Valor exacto: \(NSDecimalNumber(decimal: bmi.rawValue).stringValue)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text("El IMC no distingue músculo de grasa y es una referencia general, no una evaluación individual.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var measurementsSection: some View {
        Section("Medidas corporales") {
            NavigationLink("Ver medidas") { BodyMeasurementsView() }
        }
    }

    private var settingsSection: some View {
        Section("Ajustes") {
            Picker("Tema", selection: Binding(
                get: { appState.theme },
                set: { appState.settings.themeRaw = $0.rawValue; try? appState.context.save() }
            )) {
                ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
            }
            NavigationLink("Recordatorios") { NotificationSettingsView() }
            NavigationLink("Copia de seguridad") { BackupView() }
            NavigationLink("Bóveda y privacidad") { PrivacySettingsView() }
        }
    }

    private var aboutSection: some View {
        Section {
            Text("Tus datos se guardan en este dispositivo. Para conservar una copia independiente puedes exportar un archivo cifrado.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func bandLabel(_ b: BMIBand) -> String {
        switch b {
        case .underweight: return "Por debajo del rango de referencia"
        case .healthy: return "Dentro del rango de referencia"
        case .overweight: return "Por encima del rango de referencia"
        case .obese: return "Muy por encima del rango de referencia"
        }
    }
}

/// Alta de pesaje (spec §18): peso sin foto es válido; medido/estimado explícito.
struct AddWeightView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var isEstimated = false
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField("Peso", text: $amountText).keyboardType(.decimalPad)
                    Text(appState.settings.massUnit.rawValue).foregroundStyle(.secondary)
                }
                DatePicker("Fecha de medición", selection: $date, in: ...Date(), displayedComponents: .date)
                Toggle("Marcar como estimado", isOn: $isEstimated)
            }
            .navigationTitle("Añadir pesaje")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { save() }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }
    }

    private func save() {
        guard let amount = DecimalParser(locale: .current).parse(amountText) else { return }
        appState.context.insert(BodyWeightModel(
            measurementDate: date, enteredAt: Date(),
            amount: amount, unitRaw: appState.settings.massUnit.rawValue,
            isEstimated: isEstimated
        ))
        try? appState.context.save()
        dismiss()
    }
}

struct PrivacySettingsView: View {
    var body: some View {
        List {
            Section("Almacenamiento") {
                Text("Tus datos y fotos se guardan solo en este dispositivo, sin sincronización automática ni envío a servidores.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Copia de seguridad") {
                Text("Puedes exportar un archivo cifrado con contraseña. Una copia local no sustituye a un respaldo si pierdes el teléfono.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacidad")
    }
}
