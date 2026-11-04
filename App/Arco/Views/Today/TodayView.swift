import SwiftUI
import SwiftData
import ArcoCore

/// Rutas de la pila de Hoy (valor explícito: evita mezclar enlaces por destino y por valor).
enum TodayRoute: Hashable {
    case selection
    case session(UUID)
    case catalog
    case exercise(String)
    case routine
}

/// Pantalla Hoy (spec §8): fecha, rutina del plan para hoy, sesión activa si existe y acceso
/// principal a empezar o reanudar. Más tranquila que el panel de progreso.
struct TodayView: View {
    @Environment(AppState.self) private var appState
    @Query private var templates: [RoutineTemplateModel]
    @Query(filter: #Predicate<WorkoutSessionModel> { $0.stateRaw == "active" }, sort: \WorkoutSessionModel.startedAt, order: .reverse)
    private var activeSessions: [WorkoutSessionModel]
    @State private var path: [TodayRoute] = []

    /// Plantilla del día según la convención única de weekday (Calendar: 1 = domingo).
    private var todayTemplate: RoutineTemplateModel? {
        let weekday = Weekday.of(Date(), calendar: appState.calendar)
        return templates.first { $0.weekday == weekday.rawValue }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    if let session = activeSessions.first {
                        ArcoCard {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                Label("Sesión en curso", systemImage: "play.circle.fill").font(.headline)
                                Text("Empezada \(session.startedAt.formatted(date: .omitted, time: .shortened)) · \(session.exercises.count) ejercicios")
                                    .font(.footnote).foregroundStyle(.secondary)
                                NavigationLink(value: TodayRoute.session(session.id)) {
                                    Text("Reanudar entrenamiento").frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("today.resume")
                            }
                        }
                    } else {
                        planCard
                    }
                    WeeklySummaryCompactCard()
                }
                .padding(Spacing.lg)
            }
            .background(ArcoBackdrop())
            .navigationTitle("Hoy")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink(value: TodayRoute.routine) {
                        Label("Editar rutina", systemImage: "calendar.badge.clock")
                    }
                    .accessibilityIdentifier("today.routine.edit")
                    NavigationLink(value: TodayRoute.catalog) {
                        Label("Catálogo", systemImage: "books.vertical")
                    }
                    .accessibilityIdentifier("today.catalog")
                }
            }
            .navigationDestination(for: TodayRoute.self) { route in
                switch route {
                case .selection:
                    ExerciseSelectionView(template: todayTemplate) { session in
                        // Sustituye la selección por la sesión: volver atrás lleva a Hoy.
                        path = [.session(session.id)]
                    }
                case .session(let id):
                    if let session = activeSessions.first(where: { $0.id == id }) ?? fetchSession(id) {
                        SessionView(session: session)
                    }
                case .catalog:
                    CatalogView()
                case .exercise(let id):
                    ExerciseCatalogDetailView(exerciseID: id)
                case .routine:
                    RoutineEditorView()
                }
            }
        }
    }

    private func fetchSession(_ id: UUID) -> WorkoutSessionModel? {
        let predicate = #Predicate<WorkoutSessionModel> { $0.id == id }
        return (try? appState.context.fetch(FetchDescriptor(predicate: predicate)))?.first
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ArcoEyebrow(title: "Tu espacio de entrenamiento")
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
            if let t = todayTemplate {
                Text(t.isRestDay ? "Descanso planificado" : t.name)
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                    .accessibilityIdentifier("today.routine")
            } else {
                Text("Sin rutina para hoy")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Spacing.sm)
    }

    private var planCard: some View {
        ArcoCard {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    Image(systemName: todayTemplate?.isRestDay == true ? "moon.stars.fill" : "figure.strengthtraining.traditional")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(ArcoColor.brandText)
                        .frame(width: 48, height: 48)
                        .background(ArcoColor.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 15))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        ArcoEyebrow(title: "Tu próximo paso")
                        Text(todayTemplate?.isRestDay == true ? "Día de descanso" : "Haz espacio para progresar")
                            .font(.title3.weight(.semibold))
                    }
                    Spacer(minLength: 0)
                }
                if let t = todayTemplate, t.isRestDay {
                    Text("Hoy es un día de descanso planificado. Puedes entrenar igualmente si quieres.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Registra tus series a tu ritmo y sigue tu evolución.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                NavigationLink(value: TodayRoute.selection) {
                    Label("Empezar entrenamiento", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("today.start")
            }
        }
    }
}
