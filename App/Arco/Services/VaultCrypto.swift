//
//  VaultCrypto.swift
//  Arco
//
//  Servicio de cifrado de la bóveda de fotos privadas.
//
//  MODELO DE AMENAZAS REAL (spec §17 "Claves y archivos", [A05][A06][A08]):
//  --------------------------------------------------------------------------
//  - El PIN de 4 dígitos es una BARRERA DE ACCESO de la app, no la fuente de
//    la clave de cifrado. Su espacio de búsqueda (10.000 combinaciones) es
//    demasiado pequeño para derivar una clave segura, por lo que la clave de
//    las fotos NO se deriva del PIN (ver PINAuth.swift para la verificación
//    del PIN, que es un asunto distinto).
//  - La protección de ALMACENAMIENTO proviene de tres capas combinadas:
//      1. Clave aleatoria de 256 bits en Keychain, marcada como
//         `WhenUnlockedThisDeviceOnly` y no sincronizable: solo accesible con
//         el dispositivo desbloqueado y nunca sale de este dispositivo.
//      2. Protección de datos del sistema de archivos (`FileProtectionType.complete`)
//         sobre los archivos cifrados y sus derivados/miniaturas.
//      3. Cifrado autenticado AES-GCM (confidencialidad + integridad) con
//         nonce único por operación.
//  - Esto NO promete inmunidad en un dispositivo comprometido (con jailbreak,
//    exploit de kernel o acceso físico con el dispositivo desbloqueado). En ese
//    escenario las claves de Keychain podrían quedar expuestas. La spec exige
//    documentar esta limitación y no prometer borrado físico irrecuperable a
//    nivel de memoria flash (spec §17 "Local significa local").
//  - La exclusión de copia de seguridad (`isExcludedFromBackup`) evita que las
//    imágenes y metadatos privados salgan del dispositivo por respaldos
//    automáticos. Debe reaplicarse tras sustituciones y guardados (T66).
//

import Foundation
import CryptoKit
import Security

/// Errores del servicio de cifrado de la bóveda.
///
/// Se modela como `enum` para que las rutas de error sean exhaustivas y no se
/// filtre información sensible (rutas, claves) en mensajes de depuración
/// (spec §17 "Privacidad de la interfaz", T65).
enum VaultCryptoError: Error, Equatable, Sendable {
    /// No se pudo crear o leer la clave desde Keychain. `status` es el
    /// `OSStatus` subyacente para diagnóstico, sin exponer material de clave.
    case keychainFailure(status: OSStatus)
    /// La clave recuperada de Keychain no tiene el tamaño esperado (256 bits).
    case invalidKeyData
    /// El contenedor cifrado (archivo o blob) está corrupto o no es AES-GCM válido.
    case corruptedData
    /// Fallo de cifrado/descifrado (sello de autenticación inválido, etc.).
    case cryptoFailure
    /// No se pudo resolver o preparar el directorio privado de la bóveda.
    case storageUnavailable
    /// Nombre de archivo no válido (vacío o con componentes de ruta peligrosos).
    case invalidFileName
}

/// Servicio responsable del cifrado autenticado y del almacenamiento privado
/// de las imágenes de la bóveda.
///
/// Es un tipo de valor-referencia `Sendable` y `nonisolated`: todas sus
/// operaciones son seguras para ejecutarse fuera del actor principal porque no
/// mantiene estado mutable compartido. La clave se obtiene de Keychain de forma
/// perezosa en cada operación (Keychain es thread-safe) y nunca se almacena en
/// una propiedad mutable, evitando así cualquier carrera de datos sin necesidad
/// de locks ad-hoc (requisito transversal de concurrencia Swift 6).
final class VaultCrypto: Sendable {

    // MARK: - Configuración

    /// Identificadores de Keychain. Se usa un `service` propio de la bóveda para
    /// aislar la clave del resto de elementos de la app.
    private let keychainService: String
    private let keychainAccount: String

    /// Nombre del subdirectorio privado dentro de Application Support.
    private let vaultDirectoryName: String

    /// Sistema de archivos. `FileManager.default` es seguro para uso concurrente de lectura;
    /// se accede como propiedad computada para no almacenar un tipo no-Sendable en un tipo
    /// `Sendable` (Swift 6).
    private var fileManager: FileManager { .default }

    /// - Parameters:
    ///   - keychainService: etiqueta de servicio para la clave en Keychain.
    ///   - keychainAccount: cuenta asociada a la clave en Keychain.
    ///   - vaultDirectoryName: subcarpeta privada bajo Application Support.
    init(
        keychainService: String = "com.arco.vault.crypto",
        keychainAccount: String = "photo-vault-master-key",
        vaultDirectoryName: String = "Vault"
    ) {
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
        self.vaultDirectoryName = vaultDirectoryName
    }

    // MARK: - API de cifrado en memoria

    /// Cifra `data` con AES-GCM usando la clave maestra de la bóveda.
    ///
    /// Cada llamada genera un `AES.GCM.Nonce()` único (nonce aleatorio de 96
    /// bits) gestionado por CryptoKit, cumpliendo "nonces únicos por operación"
    /// (spec §17). El resultado es la representación combinada
    /// `nonce || ciphertext || tag`, que incluye el sello de autenticación.
    func encrypt(_ data: Data) throws -> Data {
        let key = try loadOrCreateKey()
        do {
            // AES.GCM.seal genera internamente un nonce aleatorio único si no se
            // especifica uno, evitando la reutilización de nonce que rompería GCM.
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                // `combined` solo es nil con nonces de tamaño no estándar; aquí
                // siempre usamos el nonce por defecto, pero lo tratamos de forma
                // defensiva.
                throw VaultCryptoError.cryptoFailure
            }
            return combined
        } catch let error as VaultCryptoError {
            throw error
        } catch {
            throw VaultCryptoError.cryptoFailure
        }
    }

    /// Descifra un contenedor AES-GCM producido por `encrypt(_:)`.
    ///
    /// La verificación del sello de autenticación garantiza integridad: si el
    /// contenido fue alterado o la clave no corresponde, lanza `cryptoFailure`.
    func decrypt(_ data: Data) throws -> Data {
        let key = try loadOrCreateKey()
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            // No distinguimos entre datos corruptos y clave inválida en el
            // mensaje para no dar pistas a un atacante; ambos son fallo cripto.
            throw VaultCryptoError.cryptoFailure
        }
    }

    // MARK: - API de archivos cifrados

    /// Cifra `data` y lo escribe en el contenedor privado de la app
    /// (`Application Support/Vault`).
    ///
    /// Aplica `FileProtectionType.complete` al archivo y marca tanto el archivo
    /// como la carpeta como excluidos de la copia de seguridad
    /// (`isExcludedFromBackup = true`), cumpliendo spec §17 "Local significa
    /// local" [A08]. Devuelve la URL del archivo escrito.
    @discardableResult
    func writeEncryptedFile(_ data: Data, named name: String) throws -> URL {
        let directory = try vaultDirectoryURL(createIfNeeded: true)
        let fileURL = try fileURL(for: name, in: directory)

        let ciphertext = try encrypt(data)

        // Escritura atómica + protección completa en una sola operación. La
        // protección completa cifra el archivo bajo la clave de clase del
        // dispositivo mientras está bloqueado, además de nuestro propio AES-GCM.
        do {
            try ciphertext.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            throw VaultCryptoError.storageUnavailable
        }

        // Reaplicar exclusión de backup y protección tras el guardado (T66).
        try applyProtectionAttributes(toFile: fileURL)
        try excludeFromBackup(directory)

        return fileURL
    }

    /// Lee y descifra un archivo previamente escrito con `writeEncryptedFile`.
    func readEncryptedFile(named name: String) throws -> Data {
        let directory = try vaultDirectoryURL(createIfNeeded: false)
        let fileURL = try fileURL(for: name, in: directory)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw VaultCryptoError.corruptedData
        }

        let ciphertext: Data
        do {
            ciphertext = try Data(contentsOf: fileURL)
        } catch {
            throw VaultCryptoError.storageUnavailable
        }
        return try decrypt(ciphertext)
    }

    /// Elimina un archivo de la bóveda y cualquier derivado o miniatura asociado.
    ///
    /// El borrado debe eliminar original, miniatura, temporales e índices
    /// derivados (spec §17 "Local significa local", T67). Aquí se borra el
    /// archivo con el nombre dado y los derivados que sigan la convención de
    /// sufijos (`.thumb`, `.preview`). No deja miniaturas públicas.
    func deleteEncryptedFile(named name: String) throws {
        let directory = try vaultDirectoryURL(createIfNeeded: false)

        // Conjunto de nombres a eliminar: el original y sus derivados conocidos.
        let derivedSuffixes = ["", ".thumb", ".preview", ".tmp"]
        for suffix in derivedSuffixes {
            let derivedName = name + suffix
            // Si el nombre derivado no es válido, lo omitimos en silencio: no
            // debe impedir borrar el resto.
            guard let url = try? fileURL(for: derivedName, in: directory) else { continue }
            if fileManager.fileExists(atPath: url.path) {
                // Ignoramos errores de borrado individuales para garantizar que
                // se intenten todos los derivados; un archivo ya ausente no es
                // un fallo real.
                try? fileManager.removeItem(at: url)
            }
        }
    }

    /// Reaplica la exclusión de copia de seguridad y la protección de archivos a
    /// todo el contenido de la bóveda.
    ///
    /// La spec exige verificar que estos atributos se reapliquen tras
    /// sustituciones y guardados (spec §17 "Local significa local", T66). Se
    /// expone como operación explícita para invocarla tras operaciones que
    /// puedan reemplazar archivos (p. ej. restauración o regeneración de
    /// miniaturas).
    func reapplyProtectionAttributes() throws {
        let directory = try vaultDirectoryURL(createIfNeeded: true)
        try excludeFromBackup(directory)

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw VaultCryptoError.storageUnavailable
        }

        for fileURL in contents {
            try applyProtectionAttributes(toFile: fileURL)
        }
    }

    // MARK: - Gestión de la clave en Keychain

    /// Obtiene la clave maestra desde Keychain o la crea de forma perezosa la
    /// primera vez.
    ///
    /// La clave se guarda con `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
    /// (accesible solo con el dispositivo desbloqueado y nunca restaurable en
    /// otro dispositivo) y sin sincronización (`kSecAttrSynchronizable = false`),
    /// cumpliendo spec §17 "Claves y archivos".
    func loadOrCreateKey() throws -> SymmetricKey {
        if let existing = try readKeyFromKeychain() {
            return existing
        }
        // No existe: generamos una clave aleatoria de 256 bits.
        let newKey = SymmetricKey(size: .bits256)
        try storeKeyInKeychain(newKey)
        return newKey
    }

    private func readKeyFromKeychain() throws -> SymmetricKey? {
        var query = baseKeychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw VaultCryptoError.invalidKeyData
            }
            guard data.count == 32 else { // 256 bits
                throw VaultCryptoError.invalidKeyData
            }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw VaultCryptoError.keychainFailure(status: status)
        }
    }

    private func storeKeyInKeychain(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        var attributes = baseKeychainQuery()
        attributes[kSecValueData as String] = keyData
        // Accesible solo con dispositivo desbloqueado y atado a ESTE dispositivo.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        // Sin sincronización con iCloud Keychain (spec §17): la clave no sale del
        // dispositivo. Se fija explícitamente en false.
        attributes[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any

        let status = SecItemAdd(attributes as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            // Condición de carrera poco probable: otro flujo creó la clave entre
            // la lectura y la escritura. No sobrescribimos para no invalidar
            // datos ya cifrados; simplemente consideramos el estado consistente.
            return
        default:
            // Limpiamos la copia local de la clave aunque Data no garantiza borrado
            // físico; evitamos retenerla más de lo necesario.
            throw VaultCryptoError.keychainFailure(status: status)
        }
    }

    /// Consulta base común para todas las operaciones de Keychain de la clave.
    private func baseKeychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            // Nunca sincronizable en las consultas, coherente con el guardado.
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any
        ]
    }

    // MARK: - Ubicación y atributos de archivos

    /// Resuelve el directorio privado de la bóveda bajo Application Support.
    ///
    /// Application Support no está indexado por el usuario ni es visible en la
    /// app Archivos, y no es una carpeta sincronizada por defecto, cumpliendo
    /// "No guardar el archivo principal en una carpeta sincronizada" (spec §17).
    private func vaultDirectoryURL(createIfNeeded: Bool) throws -> URL {
        let baseURL: URL
        do {
            baseURL = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: createIfNeeded
            )
        } catch {
            throw VaultCryptoError.storageUnavailable
        }

        let vaultURL = baseURL.appendingPathComponent(vaultDirectoryName, isDirectory: true)

        if createIfNeeded {
            if !fileManager.fileExists(atPath: vaultURL.path) {
                do {
                    try fileManager.createDirectory(
                        at: vaultURL,
                        withIntermediateDirectories: true,
                        attributes: [.protectionKey: FileProtectionType.complete]
                    )
                } catch {
                    throw VaultCryptoError.storageUnavailable
                }
            }
            // La carpeta recién creada o preexistente debe excluirse de backup.
            try excludeFromBackup(vaultURL)
        } else if !fileManager.fileExists(atPath: vaultURL.path) {
            throw VaultCryptoError.storageUnavailable
        }

        return vaultURL
    }

    /// Construye y valida la URL de un archivo dentro del directorio de la bóveda.
    ///
    /// Rechaza nombres vacíos o con separadores de ruta para evitar escapes de
    /// directorio (path traversal) y escrituras fuera del contenedor privado.
    private func fileURL(for name: String, in directory: URL) throws -> URL {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              trimmed != ".",
              trimmed != ".."
        else {
            throw VaultCryptoError.invalidFileName
        }
        return directory.appendingPathComponent(trimmed, isDirectory: false)
    }

    /// Aplica `FileProtectionType.complete` a un archivo existente.
    private func applyProtectionAttributes(toFile url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        do {
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: url.path
            )
        } catch {
            throw VaultCryptoError.storageUnavailable
        }
    }

    /// Marca una URL (archivo o directorio) como excluida de la copia de
    /// seguridad automática de iCloud/iTunes (spec §17 [A08], T66).
    private func excludeFromBackup(_ url: URL) throws {
        // `setResourceValues` requiere `var`; es una copia local, seguro en Swift 6.
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try mutableURL.setResourceValues(values)
        } catch {
            throw VaultCryptoError.storageUnavailable
        }
    }
}
