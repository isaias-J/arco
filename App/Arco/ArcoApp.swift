import SwiftUI
import SwiftData
import ArcoCore

@main
struct ArcoApp: App {
    /// Contenedor SwiftData compartido. Los modelos viven en la capa Persistence del target.
    let container: ModelContainer

    @State private var appState: AppState

    /// Detecta ejecución bajo pruebas unitarias para no montar el almacenamiento en disco
    /// (que el host de pruebas no necesita y cuya inicialización no debe abortar la app).
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.environment["XCTestBundlePath"] != nil
    }

    init() {
        do {
            let container = try PersistenceController.makeContainer(inMemory: Self.isRunningTests)
            self.container = container
            _appState = State(initialValue: AppState(context: container.mainContext))
        } catch {
            // No recrear la base ante un error de migración (spec §4). Se informa y se usa
            // un contenedor en memoria para no perder la posibilidad de diagnosticar.
            fatalError("No se pudo iniciar el almacenamiento: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .modelContainer(container)
        }
    }
}
