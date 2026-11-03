import SwiftUI
import SwiftData
import ArcoCore

/// Sesión activa (spec §8): registro rápido por serie, persistencia inmediata, confirmación
/// en un toque cuando los valores están precargados. Sin temporizador de descanso (spec §25).
struct SessionView: View {
    @Environment(AppState.self) private var appState
    @Bindable var session: WorkoutSessionModel

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                ForEach(session.exercises.sorted(by: { $0.order < $1.order })) { exercise in
                    ExerciseLogCard(sessionExercise: exercise)
                }
            }
            .padding(Spacing.lg)
        }
        .background(ArcoColor.background)
        .navigationTitle("Entrenamiento")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Finalizar") { finish() }
            }
        }
    }

    private func finish() {
        session.endedAt = Date()
        session.stateRaw = "finished"
        try? appState.context.save()
    }
}

/// Tarjeta de registro de un ejercicio dentro de la sesión.
struct ExerciseLogCard: View {
    @Environment(AppState.self) private var appState
    @Bindable var sessionExercise: SessionExerciseModel

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var saveError = false

    private var exerciseName: String {
        ExerciseNames.localized(sessionExercise.exerciseID)
    }

    private var massUnit: MassUnit { appState.settings.massUnit }

    /// Último valor usado en esta sesión, como borrador para la siguiente serie.
    private var lastConfirmed: SetRecordModel? {
        sessionExercise.sets
            .filter { $0.stateRaw == SetState.completed.rawValue }
            .max { $0.performedAt < $1.performedAt }
    }

    var body: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text(exerciseName)
                    .font(.headline)

                // Series ya registradas.
                ForEach(confirmedSets) { set in
                    confirmedRow(set)
                }

                Divider()

                // Fila de entrada rápida.
                HStack(spacing: Spacing.md) {
                    inputField(title: massUnit.rawValue, text: $weightText)
                    inputField(title: "reps", text: $repsText)
                    Button {
                        confirm()
                    } label: {
                        Image(systemName: "checkmark")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Confirmar serie")
                }
            }
        }
        .onAppear(perform: prefill)
        .alert("No se pudo guardar la serie", isPresented: $saveError) {
            Button("Reintentar") { confirm() }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Tu borrador se conservó. Vuelve a intentarlo.")
        }
    }

    private var confirmedSets: [SetRecordModel] {
        sessionExercise.sets
            .filter { $0.stateRaw != SetState.deleted.rawValue }
            .sorted { $0.performedAt < $1.performedAt }
    }

    private func confirmedRow(_ set: SetRecordModel) -> some View {
        HStack {
            Text("\(decimalString(set.loadAmount)) \(set.loadUnitRaw)")
                .monospacedDigit()
            Text("×")
                .foregroundStyle(.secondary)
            Text(set.reps.map(String.init) ?? "—")
                .monospacedDigit()
            Spacer()
            if set.typeRaw == SetType.warmup.rawValue {
                Text("calent.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }

    private func inputField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 90)
        }
    }

    private func prefill() {
        guard weightText.isEmpty, repsText.isEmpty, let last = lastConfirmed else { return }
        weightText = decimalString(last.loadAmount)
        repsText = last.reps.map(String.init) ?? ""
    }

    private func confirm() {
        let parser = DecimalParser(locale: .current)
        let amount = parser.parse(weightText)
        guard let reps = Int(repsText.trimmingCharacters(in: .whitespaces)), reps > 0 else {
            saveError = true
            return
        }
        let load = Load(amount: amount, unit: massUnit, convention: .externalTotal)
        do {
            try appState.repository.confirmSet(
                in: sessionExercise,
                setID: UUID(),
                load: load,
                reps: reps,
                type: .working,
                side: .bilateral,
                rir: nil
            )
            // Mantener valores como borrador para la siguiente serie (no limpiar reps/peso).
            saveError = false
        } catch {
            saveError = true
        }
    }

    private func decimalString(_ d: Decimal?) -> String {
        guard let d else { return "—" }
        return NSDecimalNumber(decimal: d).stringValue
    }
}
