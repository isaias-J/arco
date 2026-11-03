import SwiftUI
import SwiftData
import ArcoCore

/// Pantalla Hoy (spec §8): fecha, rutina sugerida por el plan, sesión activa si existe y
/// acceso principal a empezar/reanudar. Más tranquila que el panel de progreso.
struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var context

    @Query private var templates: [RoutineTemplateModel]
    @State private var activeSession: WorkoutSessionModel?

    private var todayTemplate: RoutineTemplateModel? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return templates.first { $0.weekday == weekday }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header

                    if let session = activeSession {
                        ArcoCard {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Label("Sesión en curso", systemImage: "play.circle.fill")
                                    .font(.headline)
                                NavigationLink("Reanudar entrenamiento") {
                                    SessionView(session: session)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    } else {
                        planCard
                    }
                }
                .padding(Spacing.lg)
            }
            .background(ArcoColor.background)
            .navigationTitle("Hoy")
            .onAppear { activeSession = appState.repository.activeSession() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.title2.bold())
            if let t = todayTemplate {
                Text(t.isRestDay ? "Descanso planificado" : t.name)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var planCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.md) {
                if let t = todayTemplate, t.isRestDay {
                    Text("Hoy es un día de descanso planificado.")
                        .foregroundStyle(.secondary)
                    Text("Puedes entrenar igualmente si quieres.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                NavigationLink {
                    ExerciseSelectionView(template: todayTemplate) { session in
                        activeSession = session
                    }
                } label: {
                    Label("Empezar entrenamiento", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }
}
