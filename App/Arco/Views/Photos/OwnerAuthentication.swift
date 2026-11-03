//
//  OwnerAuthentication.swift
//  Arco
//
//  Autenticación del PROPIETARIO del dispositivo para el flujo "Olvidé mi PIN"
//  (spec §17 "Recuperación", T64).
//
//  - Usa la política `.deviceOwnerAuthentication`: Face ID / Touch ID o, como
//    alternativa del sistema, el código del dispositivo. No es una pregunta de
//    seguridad ni un botón que restablezca sin autenticación.
//  - Solo un `.success` confirmado por el sistema autoriza restablecer el PIN.
//    Cancelar o fallar deja la bóveda bloqueada.
//  - La clave de cifrado de las fotos vive en Keychain y no depende del PIN, por
//    lo que restablecer el PIN no pierde fotos.
//

import Foundation
import LocalAuthentication

/// Resultado de la autenticación del propietario.
enum OwnerAuthenticationResult: Equatable, Sendable {
    case success
    case canceled
    case failed
    /// El dispositivo no tiene código configurado: no hay autenticación del sistema posible.
    case passcodeNotSet
    case unavailable
}

@MainActor
enum OwnerAuthentication {

    /// Solicita al sistema que autentique al propietario del dispositivo.
    static func authenticate(reason: String) async -> OwnerAuthenticationResult {
        let context = LAContext()
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            if let policyError, policyError.code == LAError.Code.passcodeNotSet.rawValue {
                return .passcodeNotSet
            }
            return .unavailable
        }

        // La continuation se reanuda exactamente una vez: `evaluatePolicy` llama a su
        // respuesta una sola vez.
        return await withCheckedContinuation { (continuation: CheckedContinuation<OwnerAuthenticationResult, Never>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: .success)
                } else {
                    continuation.resume(returning: Self.map(error))
                }
            }
        }
    }

    nonisolated private static func map(_ error: Error?) -> OwnerAuthenticationResult {
        guard let laError = error as? LAError else { return .failed }
        switch laError.code {
        case .userCancel, .systemCancel, .appCancel:
            return .canceled
        case .passcodeNotSet:
            return .passcodeNotSet
        default:
            return .failed
        }
    }

    /// Mensaje legible para cada resultado no exitoso.
    static func message(for result: OwnerAuthenticationResult) -> String? {
        switch result {
        case .success:
            return nil
        case .canceled:
            return "Autenticación cancelada. La bóveda sigue bloqueada y tu PIN no ha cambiado."
        case .failed:
            return "No se pudo verificar que eres el propietario del dispositivo. La bóveda sigue bloqueada."
        case .passcodeNotSet:
            return "Este dispositivo no tiene código configurado. Sin la autenticación del sistema no es posible restablecer el PIN."
        case .unavailable:
            return "La autenticación del sistema no está disponible ahora. La bóveda sigue bloqueada."
        }
    }
}
