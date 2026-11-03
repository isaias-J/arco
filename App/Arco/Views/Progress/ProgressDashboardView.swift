import SwiftUI
import SwiftData
import ArcoCore

/// Panel de progreso (spec §12). Gráficos por ejercicio y músculo. Más llamativo que Hoy.
struct ProgressDashboardView: View {
    @Query private var sessions: [WorkoutSessionModel]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    WeeklySummaryCard()
                    MuscleWeeklyCountCard(sessions: sessions)
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

/// Sección "Por ejercicio" (spec §12): lista de ejercicios con registros de trabajo, cada uno
/// con NavigationLink al gráfico por ejercicio. La lista se deriva recorriendo las sesiones del
/// @Query; solo aparecen ejercicios con al menos una serie de trabajo elegible.
struct ExerciseProgressLinksCard: View {
    let sessions: [WorkoutSessionModel]
    @Environment(AppState.self) private var appState

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
                                Text(appState.exerciseName(item.exerciseID))
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
                        .accessibilityLabel("Ver progreso de \(appState.exerciseName(item.exerciseID))")
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
