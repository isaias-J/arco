import SwiftUI
import SwiftData
import Charts
import ArcoCore

/// Panel de progreso (spec §12). Gráficos por ejercicio y músculo. Más llamativo que Hoy.
struct ProgressDashboardView: View {
    @Query private var sessions: [WorkoutSessionModel]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    MuscleVolumeCard(sessions: sessions)
                    ExerciseProgressLinksCard(sessions: sessions)
                    if sessions.isEmpty {
                        ArcoCard {
                            VStack(spacing: Spacing.sm) {
                                Text("Aún no hay entrenamientos")
                                    .font(.headline)
                                Text("Cuando registres tus primeras series, aquí verás tus gráficos de carga, repeticiones y series por músculo.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .background(ArcoColor.background)
            .navigationTitle("Progreso")
        }
    }
}

/// Conteo de series por grupo muscular en los últimos 14 días (D/I/F con etiqueta honesta).
struct MuscleVolumeCard: View {
    let sessions: [WorkoutSessionModel]

    private var groupCounts: [MuscleGroupCount] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        let attributed: [AttributedSet] = sessions
            .filter { $0.trainingDate >= cutoff }
            .flatMap { session in
                session.exercises.flatMap { se -> [AttributedSet] in
                    guard let rs = ExerciseCatalog.ruleSet(for: se.exerciseID) else { return [] }
                    return se.sets
                        .filter { $0.toDomain().isEligibleForWorkCount }
                        .map { AttributedSet(setID: $0.id, exerciseID: se.exerciseID, side: $0.toDomain().side, ruleSet: rs) }
                }
            }
        return MuscleCounter.countByGroup(attributed)
            .values
            .sorted { $0.fractional > $1.fractional }
    }

    var body: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Series por grupo · últimos 14 días")
                    .font(.headline)
                if groupCounts.isEmpty {
                    Text("Sin datos en este periodo.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Chart(groupCounts, id: \.group) { item in
                        BarMark(
                            x: .value("Series (fraccional)", item.fractional),
                            y: .value("Grupo", groupLabel(item.group))
                        )
                        .foregroundStyle(ArcoColor.chart)
                    }
                    .frame(height: CGFloat(groupCounts.count) * 32 + 20)
                    Text("Fraccional = directas + 0,5 × indirectas. Es una convención agregada, no una garantía por ejercicio.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func groupLabel(_ g: MuscleGroup) -> String {
        [
            MuscleGroup.chest: "Pecho", .shoulders: "Hombros", .back: "Espalda",
            .biceps: "Bíceps", .triceps: "Tríceps", .forearm: "Antebrazo",
            .legs: "Pierna", .core: "Abdomen"
        ][g] ?? g.rawValue
    }
}

/// Sección "Por ejercicio" (spec §12): lista de ejercicios con registros de trabajo, cada uno
/// con NavigationLink al gráfico por ejercicio. La lista se deriva recorriendo las sesiones del
/// @Query; solo aparecen ejercicios con al menos una serie de trabajo elegible.
struct ExerciseProgressLinksCard: View {
    let sessions: [WorkoutSessionModel]

    /// Ejercicios con registros, ordenados por el entrenamiento más reciente.
    private var exercises: [ExerciseWithRecords] {
        var lastDate: [String: Date] = [:]
        for session in sessions {
            for se in session.exercises where se.sets.contains(where: { $0.toDomain().isEligibleForWorkCount }) {
                let current = lastDate[se.exerciseID]
                if current == nil || session.trainingDate > current! {
                    lastDate[se.exerciseID] = session.trainingDate
                }
            }
        }
        return lastDate
            .map { ExerciseWithRecords(exerciseID: $0.key, lastTrained: $0.value) }
            .sorted { $0.lastTrained > $1.lastTrained }
    }

    var body: some View {
        if !exercises.isEmpty {
            ArcoCard {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text("Por ejercicio")
                        .font(.headline)
                    Text("Toca un ejercicio para ver su mayor carga por sesión, récords e historial.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(exercises) { item in
                        NavigationLink {
                            ExerciseProgressView(exerciseID: item.exerciseID)
                        } label: {
                            HStack {
                                Text(ExerciseNames.localized(item.exerciseID))
                                Spacer()
                                Text(item.lastTrained.formatted(.dateTime.day().month()))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ver progreso de \(ExerciseNames.localized(item.exerciseID))")
                        if item.id != exercises.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }
}

/// Ejercicio con registros + fecha del último entrenamiento (id estable = exerciseID).
private struct ExerciseWithRecords: Identifiable {
    let exerciseID: String
    let lastTrained: Date
    var id: String { exerciseID }
}
