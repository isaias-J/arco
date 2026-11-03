//
//  PINAuth.swift
//  Arco
//
//  Autenticación por PIN de 4 dígitos de la bóveda de fotos (spec §17
//  "Autenticación", criterio T60).
//
//  DECISIONES LIGADAS A LA SPEC
//  ----------------------------
//  - El PIN NO se guarda en texto plano, logs ni UserDefaults (spec §17). Se
//    guarda un VERIFICADOR derivado: sal aleatoria de 32 bytes + hash derivado.
//  - Función de derivación: PBKDF2-HMAC-SHA256 vía CommonCrypto con un número de
//    iteraciones alto (210.000). Se elige PBKDF2 (diseñada para contraseñas, con
//    coste computacional ajustable) en lugar de HKDF, que es una KDF de
//    extracción/expansión pensada para material de clave ya de alta entropía y
//    NO para ralentizar ataques de fuerza bruta sobre secretos débiles como un
//    PIN de 4 dígitos.
//  - La sal y el hash se guardan en Keychain (no UserDefaults), con
//    `WhenUnlockedThisDeviceOnly` y sin sincronización, coherente con la clave
//    de cifrado de VaultCrypto.
//  - IMPORTANTE: este verificador NO es la clave de cifrado de las fotos. Un PIN
//    de 4 dígitos tiene baja entropía; su único papel es ser una barrera de
//    acceso de la app. La protección de almacenamiento la aporta VaultCrypto.
//
//  LIMITACIÓN DE INTENTOS (T60)
//  ----------------------------
//  - Esperas progresivas, PERSISTENTES tras reiniciar la app: el conteo de
//    fallos y la marca del próximo intento permitido se guardan en Keychain, no
//    en memoria.
//  - Coherente ante manipulación simple del reloj hacia atrás: guardamos la
//    marca de tiempo objetivo como fecha absoluta; si el reloj del sistema
//    retrocede, el bloqueo se mantiene (no se reduce la espera). Si el reloj se
//    adelanta artificialmente el bloqueo podría expirar antes, lo cual es un
//    límite conocido de cualquier esquema basado en el reloj del dispositivo sin
//    un reloj monotónico persistente fiable entre reinicios; no borramos fotos
//    automáticamente por fallos en ningún caso (spec §17).
//

import Foundation
import Security
import CommonCrypto

/// Errores del servicio de PIN.
enum PINError: Error, Equatable, Sendable {
    /// El PIN no cumple el formato (debe ser exactamente 4 dígitos numéricos).
    case invalidFormat
    /// Fallo al generar material aleatorio seguro (sal).
    case randomGenerationFailed
    /// Fallo de la función de derivación de clave.
    case derivationFailed
    /// Fallo de Keychain con el `OSStatus` subyacente.
    case keychainFailure(status: OSStatus)
    /// No hay PIN configurado para la operación solicitada.
    case notConfigured
}

/// Servicio de verificación de PIN con limitación de intentos persistente.
///
/// `Sendable` y `nonisolated`: no mantiene estado mutable en memoria; todo el
/// estado (verificador y contador de intentos) vive en Keychain, que es
/// thread-safe. Esto evita carreras de datos sin locks (concurrencia Swift 6).
final class PINAuth: Sendable {

    // MARK: - Configuración

    /// Número de iteraciones de PBKDF2. Alto para encarecer ataques de fuerza
    /// bruta sobre el PIN, aun sabiendo que su espacio es pequeño.
    private let iterations: Int

    /// Longitud de la sal en bytes.
    private let saltLength = 32
    /// Longitud del hash derivado en bytes (SHA-256 → 32).
    private let derivedKeyLength = 32

    private let keychainService: String
    /// Cuenta del verificador (sal + hash).
    private let verifierAccount: String
    /// Cuenta del estado de limitación de intentos.
    private let attemptsAccount: String

    /// Reloj inyectable para pruebas de la limitación temporal.
    private let now: @Sendable () -> Date

    /// Escalado de espera por número de fallos consecutivos, en segundos.
    /// Índice = número de fallos ya acumulados. Progresivo y acotado.
    private let backoffSchedule: [TimeInterval]

    /// - Parameters:
    ///   - keychainService: servicio de Keychain para los elementos del PIN.
    ///   - iterations: iteraciones de PBKDF2 (por defecto 210.000).
    ///   - now: proveedor de la fecha actual (inyectable para pruebas).
    init(
        keychainService: String = "com.arco.vault.pin",
        iterations: Int = 210_000,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.keychainService = keychainService
        self.verifierAccount = "pin-verifier"
        self.attemptsAccount = "pin-attempts"
        self.iterations = iterations
        self.now = now
        // Esperas progresivas: sin espera en los primeros intentos, creciente
        // después, con tope. Los fallos no borran fotos (spec §17).
        self.backoffSchedule = [0, 0, 0, 5, 15, 30, 60, 120, 300]
    }

    // MARK: - Estado de configuración

    /// Indica si existe un PIN configurado.
    var isConfigured: Bool {
        (try? readVerifier()) != nil
    }

    // MARK: - Alta y restablecimiento

    /// Crea o sustituye el PIN.
    ///
    /// Genera una sal aleatoria nueva, deriva el verificador con PBKDF2 y lo
    /// guarda en Keychain. Restablece el contador de intentos.
    func setPIN(_ pin: String) throws {
        guard isValidFormat(pin) else { throw PINError.invalidFormat }

        let salt = try randomBytes(count: saltLength)
        let hash = try deriveHash(pin: pin, salt: salt)

        // Verificador serializado: [saltLength bytes de sal][hash].
        var verifier = Data()
        verifier.append(salt)
        verifier.append(hash)

        try storeVerifier(verifier)
        resetAttempts()
    }

    /// Restablece (elimina) el PIN. Para el flujo de recuperación autorizado
    /// (spec §17 "Recuperación", T64), que debe estar precedido por
    /// autenticación del propietario del dispositivo (gestionada en la capa de
    /// presentación/VaultLock). Aquí solo borra el verificador y los intentos.
    func reset() {
        deleteItem(account: verifierAccount)
        resetAttempts()
    }

    // MARK: - Verificación

    /// Verifica un PIN contra el verificador almacenado.
    ///
    /// Devuelve `false` (sin lanzar) ante cualquier condición de error para no
    /// filtrar información por la vía de excepciones y para que la UI trate todo
    /// fallo igual. La gestión de la limitación de intentos (incremento del
    /// contador, bloqueo) corresponde a quien orquesta (VaultLock): este método
    /// solo compara de forma segura.
    func verify(_ pin: String) -> Bool {
        guard isValidFormat(pin) else { return false }
        guard let verifier = try? readVerifier(), verifier.count == saltLength + derivedKeyLength else {
            return false
        }

        let salt = verifier.prefix(saltLength)
        let storedHash = verifier.suffix(derivedKeyLength)

        guard let candidate = try? deriveHash(pin: pin, salt: Data(salt)) else {
            return false
        }

        // Comparación en tiempo constante para no revelar coincidencias
        // parciales por canal temporal.
        return constantTimeEquals(Data(storedHash), candidate)
    }

    // MARK: - Limitación de intentos (persistente)

    /// Tiempo restante hasta el próximo intento permitido. 0 si se puede
    /// intentar ya.
    func timeUntilNextAttempt() -> TimeInterval {
        guard let state = readAttemptState() else { return 0 }
        let remaining = state.nextAllowedAttempt.timeIntervalSince(now())
        // Nunca negativo. Si el reloj se adelanta, el bloqueo simplemente expira.
        return max(0, remaining)
    }

    /// Registra un intento fallido: incrementa el contador y fija la marca del
    /// próximo intento permitido según el escalado progresivo.
    ///
    /// La persistencia en Keychain garantiza coherencia tras reiniciar la app
    /// (T60). No se borran fotos por fallos.
    func recordFailedAttempt() {
        let previous = readAttemptState()
        let failures = (previous?.failureCount ?? 0) + 1

        let delay = backoffDelay(forFailureCount: failures)
        let candidateNext = now().addingTimeInterval(delay)

        // Coherencia ante reloj manipulado hacia atrás: el próximo intento
        // permitido nunca puede adelantarse respecto al valor ya almacenado.
        // Si el reloj retrocedió, conservamos el bloqueo previo (el mayor).
        let nextAllowed: Date
        if let previousNext = previous?.nextAllowedAttempt {
            nextAllowed = max(candidateNext, previousNext)
        } else {
            nextAllowed = candidateNext
        }

        let newState = AttemptState(failureCount: failures, nextAllowedAttempt: nextAllowed)
        writeAttemptState(newState)
    }

    /// Reinicia el contador de intentos tras un desbloqueo correcto o un
    /// restablecimiento autorizado.
    func resetAttempts() {
        deleteItem(account: attemptsAccount)
    }

    // MARK: - Derivación PBKDF2 (CommonCrypto)

    /// Deriva un hash de 32 bytes del PIN con la sal dada usando
    /// PBKDF2-HMAC-SHA256.
    private func deriveHash(pin: String, salt: Data) throws -> Data {
        let pinBytes = Array(pin.utf8)
        var derived = [UInt8](repeating: 0, count: derivedKeyLength)

        // Enlazamos explícitamente el PIN como bytes UTF-8 y la sal como bytes,
        // sin depender del puente implícito String -> C string.
        let status = pinBytes.withUnsafeBytes { pinPtr -> Int32 in
            salt.withUnsafeBytes { saltPtr -> Int32 in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pinPtr.bindMemory(to: CChar.self).baseAddress, pinBytes.count,
                    saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derived, derived.count
                )
            }
        }

        guard status == kCCSuccess else {
            throw PINError.derivationFailed
        }
        return Data(derived)
    }

    // MARK: - Utilidades

    /// Valida que el PIN sea exactamente 4 dígitos numéricos.
    private func isValidFormat(_ pin: String) -> Bool {
        pin.count == 4 && pin.allSatisfy { $0.isNumber && $0.isASCII }
    }

    /// Genera `count` bytes aleatorios criptográficamente seguros.
    private func randomBytes(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw PINError.randomGenerationFailed
        }
        return Data(bytes)
    }

    /// Comparación en tiempo constante de dos `Data` del mismo origen de tamaño.
    private func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for (a, b) in zip(lhs, rhs) {
            difference |= a ^ b
        }
        return difference == 0
    }

    /// Calcula el retardo para un número dado de fallos consecutivos.
    private func backoffDelay(forFailureCount count: Int) -> TimeInterval {
        guard count > 0 else { return 0 }
        let index = min(count, backoffSchedule.count - 1)
        return backoffSchedule[index]
    }

    // MARK: - Estado de intentos (modelo + serialización)

    /// Estado persistente de la limitación de intentos.
    private struct AttemptState: Sendable {
        var failureCount: Int
        var nextAllowedAttempt: Date
    }

    /// Serializa a JSON estable para Keychain.
    private func encodeAttemptState(_ state: AttemptState) -> Data? {
        let payload: [String: Double] = [
            "failureCount": Double(state.failureCount),
            "nextAllowedAttempt": state.nextAllowedAttempt.timeIntervalSince1970
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    private func decodeAttemptState(_ data: Data) -> AttemptState? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Double],
            let failureCount = object["failureCount"],
            let next = object["nextAllowedAttempt"]
        else {
            return nil
        }
        return AttemptState(
            failureCount: Int(failureCount),
            nextAllowedAttempt: Date(timeIntervalSince1970: next)
        )
    }

    private func readAttemptState() -> AttemptState? {
        guard let data = try? readItem(account: attemptsAccount) else { return nil }
        return decodeAttemptState(data)
    }

    private func writeAttemptState(_ state: AttemptState) {
        guard let data = encodeAttemptState(state) else { return }
        try? storeItem(data, account: attemptsAccount)
    }

    // MARK: - Keychain (operaciones genéricas)

    private func readVerifier() throws -> Data? {
        try readItem(account: verifierAccount)
    }

    private func storeVerifier(_ data: Data) throws {
        try storeItem(data, account: verifierAccount)
    }

    /// Lee un elemento de Keychain. `nil` si no existe.
    private func readItem(account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw PINError.keychainFailure(status: status)
        }
    }

    /// Inserta o actualiza un elemento de Keychain (upsert).
    private func storeItem(_ data: Data, account: String) throws {
        let query = baseQuery(account: account)

        // ¿Existe ya? Si es así, actualizamos; si no, insertamos.
        let existsStatus = SecItemCopyMatching(query as CFDictionary, nil)

        if existsStatus == errSecSuccess {
            let attributesToUpdate: [String: Any] = [kSecValueData as String: data]
            let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            guard status == errSecSuccess else {
                throw PINError.keychainFailure(status: status)
            }
        } else if existsStatus == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let status = SecItemAdd(attributes as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw PINError.keychainFailure(status: status)
            }
        } else {
            throw PINError.keychainFailure(status: existsStatus)
        }
    }

    /// Elimina un elemento de Keychain; ignora "no encontrado".
    private func deleteItem(account: String) {
        let query = baseQuery(account: account)
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound es aceptable: ya no existía.
        _ = status
    }

    /// Consulta base común. No sincronizable, coherente con el resto de la bóveda.
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }
}
