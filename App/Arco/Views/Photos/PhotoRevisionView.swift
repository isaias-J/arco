//
//  PhotoRevisionView.swift
//  Arco
//
//  Revisión fotográfica (spec §16 "Poses" y "Peso y foto"; T49, T50, T51).
//
//  - Una revisión admite UNA o VARIAS poses; ninguna es obligatoria.
//  - Peso opcional, elegido antes o después de las fotos:
//      · "Introducir peso de hoy": crea una medición (valor > 0, medido o estimado).
//      · "Vincular último peso": usa la medición existente y muestra su fecha; NO crea
//        una medición nueva (T51).
//      · "Sin peso": las fotos quedan sin peso (T50).
//  - Todas las fotos de la revisión comparten el MISMO `bodyWeightID` (T49). Cambiar el
//    peso después actualiza todas las fotos ya capturadas.
//  - Si Perfil dejó `pendingPhotoWeightID`, la revisión arranca con ese peso vinculado.
//

import SwiftUI
import SwiftData
import ArcoCore

/// Petición para abrir una revisión (permite `.sheet(item:)` con un peso inicial).
struct PhotoRevisionRequest: Identifiable, Equatable {
    let id = UUID()
    var initialWeightID: UUID?
}

/// Hoja de revisión fotográfica. Conserva el nombre histórico usado por la galería.
struct CapturePosePickerView: View {
    /// Peso con el que arranca la revisión (p. ej. el recién guardado en Perfil).
    var initialWeightID: UUID?

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \BodyWeightModel.measurementDate, order: .reverse)
    private var weights: [BodyWeightModel]

    @Query(sort: \PhotoCheckInModel.date, order: .reverse)
    private var checkIns: [PhotoCheckInModel]

    /// Fotos guardadas en ESTA revisión, en orden de captura.
    @State private var capturedPhotoIDs: [UUID] = []
    @State private var decision: WeightDecision = .undecided
    /// Medición creada en esta revisión: si el usuario corrige el valor se edita esta misma,
    /// en lugar de crear otra.
    @State private var createdWeightID: UUID?
    @State private var didApplyInitialWeight = false

    @State private var cameraPose: Pose?
    @State private var customName = ""

    @State private var showWeightForm = false
    @State private var weightText = ""
    @State private var weightIsEstimated = false
    @State private var weightError: String?
    @State private var operationError: String?

    enum WeightDecision: Equatable {
        case undecided
        case none
        case linked(UUID)

        var weightID: UUID? {
            if case .linked(let id) = self { return id }
            return nil
        }
    }

    var body: some View {
        NavigationStack {
            List {
                weightSection
                Section("Poses base") {
                    ForEach(Pose.base, id: \.id) { poseRow($0) }
                }
                Section("Poses opcionales") {
                    ForEach(Pose.optional, id: \.id) { poseRow($0) }
                }
                customPoseSection
                if let operationError {
                    Section {
                        Text(operationError).font(.footnote).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Revisión de fotos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(capturedPhotoIDs.isEmpty ? "Cerrar" : "Terminar") { dismiss() }
                }
            }
        }
        .onAppear(perform: applyInitialWeightIfNeeded)
        .fullScreenCover(item: $cameraPose) { pose in
            CameraCaptureView(
                pose: pose,
                bodyWeightID: decision.weightID,
                previousFileName: previousFileName(for: pose)
            ) { photoID in
                capturedPhotoIDs.append(photoID)
                syncWeight()
            }
            .vaultPrivacyScreen()
        }
    }

    // MARK: - Peso

    private var weightSection: some View {
        Section {
            LabeledContent("Peso", value: decisionSummary)
                .accessibilityElement(children: .combine)

            if decision == .undecided && !capturedPhotoIDs.isEmpty {
                Text("¿Quieres añadir tu peso a esta revisión? Es opcional.")
                    .font(.footnote)
                    .foregroundStyle(ArcoColor.textPrimary)
            }

            Button {
                prepareWeightForm()
            } label: {
                Label(createdWeight == nil ? "Introducir peso de hoy" : "Corregir el peso introducido", systemImage: "scalemass")
            }

            if showWeightForm {
                weightForm
            }

            if let latest = latestWeight, decision.weightID != latest.id {
                Button {
                    choose(.linked(latest.id))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Vincular último peso", systemImage: "link")
                        Text("\(latest.photoLabel) · \(latest.measurementDate.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityHint("Usa la medición existente; no crea una nueva")
            }

            if decision != .none {
                Button {
                    choose(.none)
                } label: {
                    Label("Sin peso", systemImage: "xmark.circle")
                }
            }
        } header: {
            Text("Peso de esta revisión")
        } footer: {
            Text("Todas las fotos de esta revisión comparten un único pesaje. Puedes elegirlo antes o después de las fotos. Un peso que introduzcas se guarda en tu historial aunque después elijas «Sin peso».")
        }
    }

    private var weightForm: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                TextField("Peso", text: $weightText)
                    .keyboardType(.decimalPad)
                    .accessibilityLabel("Peso de hoy en \(unit.rawValue)")
                Text(unit.rawValue).foregroundStyle(.secondary)
            }
            Picker("Tipo", selection: $weightIsEstimated) {
                Text("Medido").tag(false)
                Text("Estimado").tag(true)
            }
            .pickerStyle(.segmented)
            if let weightError {
                Text(weightError).font(.footnote).foregroundStyle(.red)
            }
            HStack {
                Button("Guardar peso") { saveWeight() }
                    .buttonStyle(.borderedProminent)
                Button("Cancelar") {
                    showWeightForm = false
                    weightError = nil
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Poses

    private func poseRow(_ pose: Pose) -> some View {
        let done = capturedPoseRaws.contains(pose.rawValue)
        return Button {
            cameraPose = pose
        } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: pose.referenceSymbol)
                    .foregroundStyle(ArcoColor.brand)
                    .accessibilityHidden(true)
                VStack(alignment: .leading) {
                    Text(pose.displayName).font(.body).foregroundStyle(ArcoColor.textPrimary)
                    Text(pose.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityLabel(done ? "\(pose.displayName), ya capturada en esta revisión. Capturar otra vez" : "Capturar pose \(pose.displayName)")
    }

    private var customPoseSection: some View {
        Section("Pose personalizada") {
            TextField("Nombre de la pose", text: $customName)
            let name = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                poseRow(.custom(name))
            }
        }
    }

    // MARK: - Datos derivados

    private var unit: MassUnit { appState.settings.massUnit }

    private var capturedPoseRaws: Set<String> {
        let ids = Set(capturedPhotoIDs)
        return Set(checkIns.filter { ids.contains($0.id) }.map(\.poseRaw))
    }

    /// Peso actual según fecha de medición (no la última fila editada).
    private var latestWeight: BodyWeightModel? {
        guard let entry = BodyWeightAnalytics.currentWeight(from: weights.map { $0.toDomain() }) else { return nil }
        return weights.first { $0.id == entry.id }
    }

    private var createdWeight: BodyWeightModel? {
        guard let createdWeightID else { return nil }
        return weights.first { $0.id == createdWeightID }
    }

    private var decisionSummary: String {
        switch decision {
        case .undecided:
            return "Sin elegir"
        case .none:
            return "Sin peso"
        case .linked(let id):
            guard let weight = weights.first(where: { $0.id == id }) else { return "Sin peso" }
            return "\(weight.photoLabel) · \(weight.measurementDate.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    /// Foto anterior más reciente de la misma pose, para la superposición opcional.
    private func previousFileName(for pose: Pose) -> String? {
        checkIns.first { $0.poseRaw == pose.rawValue }?.encryptedFileName
    }

    // MARK: - Acciones

    private func applyInitialWeightIfNeeded() {
        guard !didApplyInitialWeight else { return }
        didApplyInitialWeight = true
        guard let initialWeightID, weights.contains(where: { $0.id == initialWeightID }) else { return }
        decision = .linked(initialWeightID)
    }

    private func prepareWeightForm() {
        if let createdWeight {
            weightText = createdWeight.amount.formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
            weightIsEstimated = createdWeight.isEstimated
        }
        weightError = nil
        showWeightForm = true
    }

    private func saveWeight() {
        switch PhotoWeightInput.parse(weightText, unit: unit) {
        case .failure(let problem):
            weightError = problem.message
        case .success(let amount):
            do {
                if let createdWeight {
                    // Corrección de la medición de esta revisión: no se crea otra.
                    createdWeight.amount = amount
                    createdWeight.unitRaw = unit.rawValue
                    createdWeight.isEstimated = weightIsEstimated
                    try modelContext.save()
                    choose(.linked(createdWeight.id))
                } else {
                    let model = try PhotoVaultOperations.createWeight(amount: amount, unit: unit, isEstimated: weightIsEstimated, context: modelContext)
                    createdWeightID = model.id
                    choose(.linked(model.id))
                }
                weightError = nil
                showWeightForm = false
                weightText = ""
            } catch {
                weightError = "No se pudo guardar el peso."
            }
        }
    }

    private func choose(_ newDecision: WeightDecision) {
        decision = newDecision
        syncWeight()
    }

    /// Propaga la decisión de peso a todas las fotos ya capturadas en la revisión.
    private func syncWeight() {
        guard !capturedPhotoIDs.isEmpty else { return }
        do {
            try PhotoVaultOperations.applyWeight(decision.weightID, toPhotos: capturedPhotoIDs, context: modelContext)
            operationError = nil
        } catch {
            operationError = "No se pudo actualizar el peso de las fotos."
        }
    }
}
