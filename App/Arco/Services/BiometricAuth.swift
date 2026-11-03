//
//  BiometricAuth.swift
//  Arco
//
//  Autenticación biométrica opcional (Face ID / Touch ID) para la bóveda
//  (spec §17 "Autenticación", [A04], criterio T61).
//
//  DECISIONES LIGADAS A LA SPEC
//  ----------------------------
//  - Face ID es OPCIONAL y complementa al PIN; nunca lo sustituye como único
//    método.
//  - Face ID cancelado, denegado o no configurado => la bóveda PERMANECE
//    BLOQUEADA. Toda ruta de error devuelve `failure` y nunca desbloquea por
//    error (spec §17, T61).
//  - `LAContext` requiere aislamiento de hilo cuidadoso. Marcamos el servicio
//    como `@MainActor` porque `LAContext` está pensado para usarse desde un
//    contexto coherente y su `evaluatePolicy` invoca su callback en un hilo
//    arbitrario; envolvemos esa API basada en callback en `async/await` con una
//    `CheckedContinuation` que se reanuda EXACTAMENTE una vez (sin fugas).
//

import Foundation
import LocalAuthentication

/// Errores de la autenticación biométrica.
enum BiometricError: Error, Equatable, Sendable {
    /// La biometría no está disponible o no está configurada en el dispositivo.
    case notAvailable
    /// El usuario canceló la autenticación (o el sistema la canceló).
    case canceled
    /// El sistema denegó o la autenticación falló (p. ej. rostro no reconocido).
    case failed
    /// El usuario optó por usar otro método (p. ej. "Introducir PIN"), lo que en
    /// nuestra política NO desbloquea por biometría: la UI debe pasar al PIN.
    case fallbackRequested
}

/// Servicio de autenticación biométrica.
///
/// `@MainActor`: `LAContext` es un objeto con estado que conviene crear y usar
/// desde un contexto de aislamiento coherente; al estar ligado al flujo de UI de
/// desbloqueo de la bóveda, el actor principal es la ubicación natural y evita
/// compartir el contexto entre hilos (concurrencia Swift 6, requisito de
/// "@MainActor solo para lo UI-bound / cosas con LAContext").
@MainActor
final class BiometricAuth {

    /// Fábrica de `LAContext` inyectable para pruebas (permite sustituir por un
    /// doble en tests sin depender del hardware).
    private let contextFactory: @MainActor () -> LAContext

    init(contextFactory: @escaping @MainActor () -> LAContext = { LAContext() }) {
        self.contextFactory = contextFactory
    }

    /// Indica si el dispositivo puede usar biometría ahora mismo.
    ///
    /// Comprueba `deviceOwnerAuthenticationWithBiometrics`: devuelve `false` si
    /// Face ID/Touch ID no está configurado o no está disponible, en cuyo caso
    /// la bóveda no debe ofrecer el botón biométrico (debe quedarse en el PIN).
    func canUseBiometrics() -> Bool {
        let context = contextFactory()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &error
        )
        return canEvaluate
    }

    /// Solicita autenticación biométrica.
    ///
    /// Devuelve `.success` solo cuando el sistema confirma la identidad. Cualquier
    /// otra situación (cancelación, denegación, no configurada, petición de
    /// fallback) devuelve `.failure`, manteniendo la bóveda bloqueada (T61).
    ///
    /// - Parameter reason: texto mostrado al usuario explicando por qué se pide
    ///   autenticación (debe ser claro y en español, spec §17 [A04]).
    func authenticate(reason: String) async -> Result<Void, BiometricError> {
        let context = contextFactory()

        // Primero validamos disponibilidad para dar un error claro y no lanzar
        // la hoja del sistema cuando no hay biometría configurada.
        var policyError: NSError?
        guard context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics,
            error: &policyError
        ) else {
            return .failure(.notAvailable)
        }

        // Envolvemos la API basada en callback en async/await. La continuation se
        // reanuda EXACTAMENTE una vez: `evaluatePolicy` invoca su reply una sola
        // vez, así que no hay doble reanudación ni fuga de la continuation.
        return await withCheckedContinuation { (continuation: CheckedContinuation<Result<Void, BiometricError>, Never>) in
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            ) { success, evaluationError in
                if success {
                    continuation.resume(returning: .success(()))
                    return
                }
                let mapped = Self.mapEvaluationError(evaluationError)
                continuation.resume(returning: .failure(mapped))
            }
        }
    }

    /// Traduce el error de `evaluatePolicy` a nuestro `BiometricError`.
    ///
    /// `nonisolated static` porque es una función pura sobre un `Error`; no toca
    /// estado del actor y puede ejecutarse desde el callback sin saltos de
    /// aislamiento.
    nonisolated private static func mapEvaluationError(_ error: Error?) -> BiometricError {
        guard let laError = error as? LAError else {
            return .failed
        }
        switch laError.code {
        case .userCancel, .systemCancel, .appCancel:
            return .canceled
        case .userFallback:
            // El usuario pidió el método alternativo (PIN). No desbloqueamos por
            // biometría; la UI debe encaminar al flujo de PIN.
            return .fallbackRequested
        case .biometryNotAvailable, .biometryNotEnrolled, .passcodeNotSet:
            return .notAvailable
        case .biometryLockout:
            // Demasiados intentos biométricos: tratado como no disponible para
            // esta sesión; el usuario debe usar el PIN.
            return .notAvailable
        default:
            return .failed
        }
    }
}
