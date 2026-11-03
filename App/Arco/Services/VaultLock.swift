//
//  VaultLock.swift
//  Arco
//
//  Estado y orquestación del bloqueo de la bóveda de fotos (spec §17
//  "Autenticación" y "Privacidad de la interfaz", criterios T60, T61, T62, T63).
//
//  DECISIONES LIGADAS A LA SPEC
//  ----------------------------
//  - Mantiene el estado `isUnlocked` de la bóveda, único punto de verdad por el
//    que deben pasar TODAS las rutas a fotos (galería, cámara con superposición,
//    comparación, perfil, enlaces internos) — spec §17, T62.
//  - Bloquea al pasar la escena a segundo plano / al bloquearse el dispositivo
//    (spec §17 "Privacidad de la interfaz", T63). La cobertura visual inmediata
//    de la imagen en el selector de apps corresponde a la capa de vistas; aquí
//    se garantiza que el estado lógico vuelve a "bloqueado".
//  - Orquesta PINAuth + BiometricAuth. La limitación de intentos del PIN es
//    persistente (T60): este orquestador consulta/actualiza el estado de
//    intentos de PINAuth, que vive en Keychain.
//  - Face ID cancelado, denegado o no configurado NO desbloquea (T61).
//

import Foundation
import Observation

/// Orquestador observable del bloqueo de la bóveda.
///
/// `@Observable @MainActor final class`: es estado de UI (lo observan las vistas
/// de SwiftUI), por eso vive en el actor principal. La isolación a `@MainActor`
/// es correcta aquí porque `isUnlocked` dirige directamente la presentación y
/// porque coordina a `BiometricAuth`, que también es `@MainActor`
/// (requisito transversal de concurrencia Swift 6).
@MainActor
@Observable
final class VaultLock {

    /// Estado de desbloqueo de la bóveda. Setter privado: solo se cambia a
    /// través de los métodos de desbloqueo/bloqueo, nunca directamente desde la
    /// UI. Así el control de acceso queda centralizado (T62).
    private(set) var isUnlocked: Bool = false

    /// Indica si existe un PIN configurado (para que la UI muestre configuración
    /// inicial o la pantalla de desbloqueo).
    var isPINConfigured: Bool { pinAuth.isConfigured }

    /// Tiempo restante de bloqueo por limitación de intentos (0 si se puede
    /// intentar ya). La UI lo usa para deshabilitar la entrada y mostrar cuenta.
    var lockoutRemaining: TimeInterval { pinAuth.timeUntilNextAttempt() }

    /// Indica si la biometría puede usarse ahora (para mostrar el botón Face ID).
    var canUseBiometrics: Bool { biometricAuth.canUseBiometrics() }

    // MARK: - Dependencias inyectadas

    private let pinAuth: PINAuth
    private let biometricAuth: BiometricAuth

    /// Inyección por `init` para poder testear la orquestación con dobles de
    /// PINAuth y BiometricAuth (requisito de testabilidad del encargo).
    init(pinAuth: PINAuth, biometricAuth: BiometricAuth) {
        self.pinAuth = pinAuth
        self.biometricAuth = biometricAuth
    }

    // MARK: - Desbloqueo por PIN

    /// Intenta desbloquear con PIN.
    ///
    /// Respeta la limitación de intentos persistente: si aún hay bloqueo
    /// temporal activo, no evalúa el PIN y devuelve `false` (T60). Ante acierto,
    /// reinicia el contador y desbloquea; ante fallo, registra el intento fallido
    /// (que persiste en Keychain) y mantiene bloqueada la bóveda. Nunca borra
    /// fotos por fallos.
    @discardableResult
    func unlockWithPIN(_ pin: String) -> Bool {
        // Si estamos en periodo de espera, rechazamos sin consumir un intento.
        guard pinAuth.timeUntilNextAttempt() <= 0 else {
            return false
        }

        if pinAuth.verify(pin) {
            pinAuth.resetAttempts()
            isUnlocked = true
            return true
        } else {
            pinAuth.recordFailedAttempt()
            isUnlocked = false
            return false
        }
    }

    // MARK: - Desbloqueo por biometría

    /// Intenta desbloquear con Face ID / Touch ID.
    ///
    /// Solo desbloquea ante éxito confirmado por el sistema. Cancelación,
    /// denegación, no configurada o petición de fallback mantienen la bóveda
    /// bloqueada (T61). La biometría NO consume intentos de PIN.
    @discardableResult
    func unlockWithBiometrics() async -> Bool {
        let reason = "Desbloquea tu bóveda de fotos privadas"
        let result = await biometricAuth.authenticate(reason: reason)
        switch result {
        case .success:
            // Un desbloqueo biométrico correcto también limpia el bloqueo del
            // PIN: el propietario demostró su identidad por una ruta admitida.
            pinAuth.resetAttempts()
            isUnlocked = true
            return true
        case .failure:
            // Cualquier fallo (cancelado, denegado, no configurado, fallback):
            // la bóveda permanece bloqueada.
            isUnlocked = false
            return false
        }
    }

    // MARK: - Configuración del PIN

    /// Comprueba el PIN actual (p. ej. antes de cambiarlo) sin alterar el estado de
    /// desbloqueo. Respeta y alimenta la misma limitación de intentos persistente (T60).
    func verifyPIN(_ pin: String) -> Bool {
        guard pinAuth.timeUntilNextAttempt() <= 0 else { return false }
        if pinAuth.verify(pin) {
            pinAuth.resetAttempts()
            return true
        }
        pinAuth.recordFailedAttempt()
        return false
    }

    /// Crea o cambia el PIN de la bóveda. La UI valida longitud/confirmación antes de llamar.
    func configurePIN(_ pin: String) throws {
        try pinAuth.setPIN(pin)
    }

    /// Restablece el PIN (flujo "Olvidé el PIN"). La capa de presentación DEBE autenticar al
    /// propietario del dispositivo antes de invocarlo (spec §17, T64).
    func resetPINAfterOwnerAuthentication() {
        pinAuth.reset()
    }

    // MARK: - Bloqueo

    /// Bloquea la bóveda. Debe invocarse al pasar la escena a segundo plano o al
    /// bloquearse el dispositivo (spec §17, T63), y tras cualquier operación que
    /// requiera reautenticación.
    func lock() {
        isUnlocked = false
    }
}
