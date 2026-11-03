import SwiftUI
import SwiftData
import ArcoCore

/// Selección flexible de ejercicios para la sesión (spec §8). Presenta ejercicios del catálogo
/// pertinentes al día; se pueden añadir, quitar y reordenar. No interroga antes de entrenar.
struct ExerciseSelectionView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let template: RoutineTemplateModel?
    var onStart: (WorkoutSessionModel) -> Void

    @Query(sort: \ExerciseModel.name) private var allExercises: [ExerciseModel]
    @State private var selected: [String] = []

    private var dayGroups: Set<MuscleGroup> {
        guard let groups = template?.groupsJoined, !groups.isEmpty else { return Set(MuscleGroup.allCases) }
        return Set(groups.split(separator: ",").compactMap { MuscleGroup(rawValue: String($0)) })
    }

    /// Ejercicios cuyo músculo directo pertenece a los grupos del día.
    private var suggestedForDay: [ExerciseModel] {
        allExercises.filter { model in
            guard !model.archived, let rs = ExerciseCatalog.ruleSet(for: model.id) else { return false }
            return rs.directMuscles.contains { dayGroups.contains($0.group) }
        }
    }

    var body: some View {
        List {
            Section("Ejercicios del día") {
                ForEach(suggestedForDay) { ex in
                    row(ex)
                }
            }
            Section("Otros del catálogo") {
                ForEach(allExercises.filter { !suggestedForDay.contains($0) && !$0.archived }) { ex in
                    row(ex)
                }
            }
        }
        .navigationTitle("Elegir ejercicios")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Empezar") { start() }
                    .disabled(selected.isEmpty)
            }
        }
    }

    private func row(_ ex: ExerciseModel) -> some View {
        Button {
            toggle(ex.id)
        } label: {
            HStack {
                Text(ex.name)
                    .foregroundStyle(ArcoColor.textPrimary)
                Spacer()
                if selected.contains(ex.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ArcoColor.brand)
                }
            }
        }
        .accessibilityAddTraits(selected.contains(ex.id) ? [.isSelected] : [])
    }

    private func toggle(_ id: String) {
        if let idx = selected.firstIndex(of: id) {
            selected.remove(at: idx)
        } else {
            selected.append(id)
        }
    }

    private func start() {
        let repo = appState.repository
        let session = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: template?.id)
        for id in selected {
            repo.addExercise(to: session, exerciseID: id, variantKey: nil)
        }
        onStart(session)
        dismiss()
    }
}
