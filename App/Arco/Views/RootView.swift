import SwiftUI

/// Raíz: onboarding la primera vez; después, cinco destinos (spec §20).
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
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        TabView(selection: $state.selectedTab) {
            Tab("Hoy", systemImage: "figure.strengthtraining.traditional", value: AppTab.today) {
                TodayView()
            }
            Tab("Progreso", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.progress) {
                ProgressDashboardView()
            }
            Tab("Fotos", systemImage: "lock.rectangle.on.rectangle", value: AppTab.photos) {
                PhotosView()
            }
            Tab("Asistencia", systemImage: "calendar", value: AppTab.attendance) {
                AttendanceView()
            }
            Tab("Perfil", systemImage: "person.crop.circle", value: AppTab.profile) {
                ProfileView()
            }
        }
    }
}
