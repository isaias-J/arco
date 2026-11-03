import SwiftUI

/// Raíz de la app. Muestra onboarding la primera vez; después, la navegación de 5 destinos
/// (spec §20): Hoy, Progreso, Fotos, Asistencia, Perfil.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.needsOnboarding {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .preferredColorScheme(appState.theme.colorScheme)
        .tint(ArcoColor.brand)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            Tab("Hoy", systemImage: "figure.strengthtraining.traditional") {
                TodayView()
            }
            Tab("Progreso", systemImage: "chart.line.uptrend.xyaxis") {
                ProgressDashboardView()
            }
            Tab("Fotos", systemImage: "lock.rectangle.on.rectangle") {
                PhotosView()
            }
            Tab("Asistencia", systemImage: "calendar") {
                AttendanceView()
            }
            Tab("Perfil", systemImage: "person.crop.circle") {
                ProfileView()
            }
        }
    }
}
