import SwiftUI
import SwiftData
import ArcoCore

/// Perfil: datos personales, peso, altura, IMC, medidas y ajustes (spec §18, §20).
/// Desde aquí se gestionan los ajustes (sin pestaña extra de configuración).
struct ProfileView: View {
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfileModel]
    @Query(sort: \BodyWeightModel.measurementDate, order: .reverse) private var weights: [BodyWeightModel]
    @Query(sort: \HeightModel.date, order: .reverse) private var heights: [HeightModel]

    @State private var showAddWeight = false

    private var profile: UserProfileModel? { profiles.first }

    private var weightEntries: [BodyWeightEntry] { weights.map { $0.toDomain() } }

    /// Peso actual: medición válida más reciente por fecha (T52, T54).
    private var currentWeight: BodyWeightEntry? {
        BodyWeightAnalytics.currentWeight(from: weightEntries)
    }

    private var heightRecords: [HeightRecord] {
        heights.compactMap { h in
            guard h.amount > 0 else { return nil }
            let unit = LengthUnit(rawValue: h.unitRaw) ?? .centimeters
            return HeightRecord(date: h.date, meters: UnitConverter.meters(h.amount, from: unit))
        }
    }

    /// IMC actual con la altura vigente en la fecha del peso actual (T58).
    private var currentBMI: (result: BMIResult, assumed: Bool)? {
        guard let w = currentWeight,
              let h = BMIHistory.height(at: w.measurementDate, in: heightRecords),
              let bmi = BMICalculator.bmi(massKilograms: w.kilograms, heightMeters: h.meters, isEstimated: w.isEstimated)
        else { return nil }
        return (bmi, h.assumed)
    }

    private var age: Int? {
        guard let b = profile?.birthDate else { return nil }
        return AgeCalculator.age(birthDate: b, on: Date(), calendar: appState.calendar)
    }

    private var bmiPolicy: BMIInterpretationPolicy { .policy(age: age) }

    var body: some View {
        NavigationStack {
            List {
                personalSection
                weightSection
                weightChartSection
                heightSection
                if let currentBMI {
                    BMICurrentSection(bmi: currentBMI.result, usesAssumedHeight: currentBMI.assumed, policy: bmiPolicy)
                    bmiHistorySection
                }
                measurementsSection
                ProfileSettingsSection()
                linksSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background(ArcoBackdrop())
            .navigationTitle("Perfil")
            .sheet(isPresented: $showAddWeight) {
                WeightEditorView()
            }
        }
    }

    // MARK: - Secciones

    private var personalSection: some View {
        Section("Datos personales") {
            NavigationLink {
                PersonalDataView()
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.displayName ?? "Sin nombre indicado")
                    Text(age.map { "\($0) años" } ?? "Edad desconocida")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("profile.personal")
        }
    }

    private var weightSection: some View {
        Section("Peso") {
            if let w = currentWeight {
                HStack {
                    Text("Peso actual")
                    Spacer()
                    Text(ProfileFormat.massText(kilograms: w.kilograms, unit: appState.settings.massUnit))
                        .monospacedDigit()
                    if w.isEstimated {
                        Text("estimado")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                Text("\(ProfileFormat.age(of: w.measurementDate, calendar: appState.calendar).capitalizedFirst) · \(ProfileFormat.date(w.measurementDate))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Peso desconocido: sin pesaje registrado").foregroundStyle(.secondary)
            }
            Button("Añadir pesaje") { showAddWeight = true }
            NavigationLink("Historial de peso") { WeightHistoryView() }
        }
    }

    @ViewBuilder
    private var weightChartSection: some View {
        if !weights.isEmpty {
            Section("Gráfico de peso") {
                WeightChartCard(entries: weightEntries, unit: appState.settings.massUnit, calendar: appState.calendar)
            }
        }
    }

    private var heightSection: some View {
        Section("Altura") {
            if let h = heights.first {
                let unit = LengthUnit(rawValue: h.unitRaw) ?? .centimeters
                let shown = ProfileFormat.length(h.amount, from: unit, to: appState.settings.lengthUnit)
                LabeledContent("Altura más reciente", value: "\(ProfileFormat.number(shown)) \(appState.settings.lengthUnit.rawValue)")
                Text("Registrada el \(ProfileFormat.date(h.date))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Altura desconocida").foregroundStyle(.secondary)
            }
            NavigationLink("Historial de altura") { HeightHistoryView() }
        }
    }

    private var bmiHistorySection: some View {
        Section("IMC histórico") {
            BMIHistoryChart(
                points: BMIHistory.points(weights: weightEntries, heights: heightRecords),
                showsReferenceLines: bmiPolicy.showsInterpretation
            )
        }
    }

    private var measurementsSection: some View {
        Section("Medidas corporales") {
            NavigationLink("Ver medidas") { BodyMeasurementsView() }
        }
    }

    @ViewBuilder
    private var linksSection: some View {
        Section("Privacidad y datos") {
            NavigationLink("Recordatorios") { NotificationSettingsView() }
            NavigationLink("Copia de seguridad") { BackupView() }
            NavigationLink("Bóveda de fotos") { VaultSettingsView() }
            NavigationLink("Privacidad") { PrivacySettingsView() }
        }
        Section("Información") {
            NavigationLink("Fuentes y método") { EvidenceLibraryView() }
                .accessibilityIdentifier("profile.evidence")
        }
    }

    private var aboutSection: some View {
        Section {
            Text("Tus datos se guardan en este dispositivo. Para conservar una copia independiente puedes exportar un archivo cifrado.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
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
