import Foundation
import SwiftData
import Observation
import ArcoCore

/// Estado global de la app, UI-bound. @Observable + @MainActor (skill de concurrencia:
/// estado de UI vive en el main actor). Da a las vistas acceso a ajustes y servicios.
@MainActor
@Observable
final class AppState {
    let context: ModelContext

    /// Ajustes vigentes (se crean en el seed).
    var settings: AppSettingsModel

    /// Bóveda de fotos (PIN + Face ID). Se bloquea al pasar a segundo plano.
    let vaultLock: VaultLock

    /// Servicio de notificaciones locales (avisos de entrenamiento y revisión de asistencia).
    let notifications = NotificationService()

    /// Archivo de respaldo cifrado portable (export/restore).
    let backup = BackupArchive()

    init(context: ModelContext) {
        self.context = context
        let fetched = (try? context.fetch(FetchDescriptor<AppSettingsModel>()))?.first
        let settings = fetched ?? AppSettingsModel()
        self.settings = settings
        self.vaultLock = VaultLock(pinAuth: PINAuth(), biometricAuth: BiometricAuth())
        if fetched == nil { context.insert(settings) }
    }

    var theme: AppTheme {
        AppTheme(rawValue: settings.themeRaw) ?? .system
    }

    var needsOnboarding: Bool {
        !settings.onboardingCompleted
    }

    var repository: WorkoutRepository {
        WorkoutRepository(context: context)
    }

    func completeOnboarding() {
        settings.onboardingCompleted = true
        try? context.save()
    }
}
