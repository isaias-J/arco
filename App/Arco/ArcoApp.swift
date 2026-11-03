import SwiftUI
import SwiftData
import UserNotifications
import ArcoCore

@main
struct ArcoApp: App {
    let container: ModelContainer
    @State private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    /// Pruebas de interfaz: `-arco-uitest-reset` borra la base aislada del simulador de pruebas
    /// antes de arrancar. Nunca se usa en una instalación normal.
    private static var resetForUITests: Bool {
        ProcessInfo.processInfo.arguments.contains("-arco-uitest-reset")
    }

    init() {
        if Self.resetForUITests {
            let url = PersistenceController.defaultStoreURL
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
            // Instalación limpia de pruebas: sin PIN, sin intentos fallidos, sin fotos ni preferencias.
            PINAuth().reset()
            try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "Vault"))
            for key in [Preferences.rirModeKey, Preferences.useFaceIDKey, Preferences.reviewOnboardedKey] {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        do {
            let container = try PersistenceController.makeContainer()
            self.container = container
            _appState = State(initialValue: AppState(context: container.mainContext))
        } catch {
            // No se recrea ni se borra la base ante un error (spec §4): se detiene para no
            // sobrescribir datos que podrían recuperarse.
            fatalError("No se pudo abrir el almacenamiento local de Arco.")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .modelContainer(container)
                .task {
                    NotificationCoordinator.shared.appState = appState
                    UNUserNotificationCenter.current().delegate = NotificationCoordinator.shared
                    appState.notifications.registerCategories()
                    appState.seedDefaultReminderRulesIfNeeded()
                    await appState.refreshReminders()
                }
                .sheet(item: Binding(
                    get: { appState.snoozeRequestDay.map(SnoozeRequest.init) },
                    set: { appState.snoozeRequestDay = $0?.day }
                )) { request in
                    SnoozeSheet(day: request.day)
                        .environment(appState)
                        .presentationDetents([.medium])
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await appState.refreshReminders() }
                try? BackupExclusion.apply(toStoreAt: PersistenceController.defaultStoreURL)
            }
        }
    }
}

struct SnoozeRequest: Identifiable {
    let day: CivilDay
    var id: String { day.key }
}

/// "Voy más tarde": elegir 30, 60 o 120 minutos sin cruzar de fecha (spec §15, T43).
struct SnoozeSheet: View {
    let day: CivilDay
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach([30, 60, 120], id: \.self) { minutes in
                        Button("En \(minutes) minutos") {
                            Task {
                                let ok = await appState.snoozeReview(day: day, minutes: minutes)
                                if ok { dismiss() } else {
                                    message = "Ese aplazamiento pasaría al día siguiente. La revisión de hoy queda sin confirmar."
                                }
                            }
                        }
                    }
                } footer: {
                    if let message { Text(message) }
                }
                Section {
                    Button("Sí fui") { Task { await appState.handleAttendanceAction(.didAttend, day: day); dismiss() } }
                    Button("Hoy descansé") { Task { await appState.handleAttendanceAction(.didRest, day: day); dismiss() } }
                }
            }
            .navigationTitle("¿Cuándo te lo recuerdo?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
}
