//
//  BackupArchive.swift
//  Arco
//
//  Archivo de respaldo cifrado portable (spec §19 "Exportación, archivo cifrado y
//  restauración"). El usuario puede crear un archivo cifrado con datos y, opcionalmente,
//  fotografías. La contraseña de exportación es SEPARADA del PIN, con confirmación en la UI,
//  derivación de clave estándar con sal aleatoria y cifrado autenticado. No se almacena la
//  contraseña ni se reutiliza una clave ligada al dispositivo como única clave del archivo
//  portable.
//
//  Criterios de aceptación cubiertos (§22):
//   - T70: una contraseña incorrecta o un archivo corrupto NO modifican los datos actuales.
//          `restore` valida versión e integridad y lanza un error ANTES de entregar nada; el
//          descifrado AES-GCM falla de forma autenticada si la contraseña es incorrecta o el
//          contenido está alterado.
//
//  Límite explícito de esta capa (spec §19 "Restauración", T72/T73):
//   - Aquí SOLO ciframos/desciframos y validamos el formato. La RESTAURACIÓN real —insertar
//     en SwiftData sin duplicar por ID y de forma transaccional, con migración desde esquemas
//     anteriores— la realiza otra capa de persistencia. `restore` únicamente entrega el
//     payload descifrado y validado (JSON versionado de los datos) más su manifiesto.
//
//  Dependencias: solo Foundation, CryptoKit y CommonCrypto. Sin red ni paquetes externos.
//

import Foundation
import CryptoKit
import CommonCrypto

// MARK: - Errores

/// Errores del archivo cifrado. Se distinguen para que la UI pueda dar un mensaje claro y
/// para no revelar más de lo necesario (una contraseña incorrecta y un archivo corrupto se
/// tratan como causas separadas, pero ambas rechazan antes de tocar datos — T70).
public enum BackupError: Error, Equatable, Sendable {
    /// La estructura del contenedor no es la esperada (cabecera ausente o ilegible).
    case corrupted
    /// La versión del formato no está soportada por esta build.
    case unsupportedVersion(found: Int, supported: Int)
    /// El descifrado autenticado falló: contraseña incorrecta o contenido manipulado.
    case invalidPassword
    /// La contraseña propuesta no cumple el mínimo de robustez exigido en la exportación.
    case weakPassword
    /// Error al derivar la clave con PBKDF2.
    case keyDerivationFailed
}

// MARK: - Manifiesto y resultado

/// Metadatos del archivo. Viaja en claro dentro de la cabecera para poder mostrar un resumen
/// antes de descifrar, pero NO contiene secretos ni la contraseña (spec §19).
public struct ArchiveManifest: Codable, Equatable, Sendable {
    /// Versión del formato de archivo (no del esquema de datos interno).
    public let version: Int
    /// Instante de creación del archivo.
    public let createdAt: Date
    /// Si el payload incluye fotografías (requiere bóveda desbloqueada aguas arriba).
    public let includesPhotos: Bool
    /// Conteos informativos por tipo de registro (p. ej. ["sessions": 42, "photos": 10]).
    public let counts: [String: Int]

    public init(version: Int, createdAt: Date, includesPhotos: Bool, counts: [String: Int]) {
        self.version = version
        self.createdAt = createdAt
        self.includesPhotos = includesPhotos
        self.counts = counts
    }
}

/// Resultado de una restauración validada: manifiesto + payload descifrado.
/// El payload es el JSON versionado de los datos; su interpretación e inserción transaccional
/// pertenecen a la capa de persistencia (spec §19, T72/T73).
public struct RestoredArchive: Sendable {
    public let manifest: ArchiveManifest
    public let payload: Data
}

// MARK: - Servicio

/// Cifra y descifra archivos de respaldo portables.
///
/// `nonisolated` de facto: no toca UI, así que no se marca `@MainActor`. Es un tipo sin estado
/// mutable compartido (`Sendable`), por lo que puede usarse desde cualquier contexto de
/// concurrencia sin riesgo de data race (skill de Swift Concurrency). Las operaciones son
/// síncronas y acotadas en memoria; el llamante puede invocarlas dentro de un `Task`
/// `@concurrent` si no quiere ocupar el main actor.
public struct BackupArchive: Sendable {

    /// Versión actual del formato de contenedor.
    public static let currentVersion = 1

    /// Iteraciones de PBKDF2. >= 210_000 según el encargo (spec §19). Viaja en la cabecera
    /// para permitir subir el coste en el futuro sin romper archivos antiguos.
    private let pbkdf2Iterations: Int

    /// Longitud de clave derivada (AES-256 => 32 bytes).
    private let keyByteCount = 32

    /// Longitud de la sal aleatoria.
    private let saltByteCount = 16

    /// Longitud mínima de contraseña de exportación (robustez básica, spec §19
    /// "contraseña … suficientemente fuerte").
    private let minimumPasswordLength = 8

    public init(iterations: Int = 210_000) {
        // Nunca por debajo del mínimo del encargo aunque se pase un valor menor.
        self.pbkdf2Iterations = max(210_000, iterations)
    }

    // MARK: - Cabecera del contenedor

    /// Cabecera JSON en claro que precede al ciphertext. Contiene todo lo necesario para
    /// re-derivar la clave y descifrar, salvo la contraseña (nunca se almacena, spec §19).
    private struct ArchiveHeader: Codable {
        var version: Int
        var iterations: Int
        var salt: Data          // Codable base64 por defecto para Data en JSONEncoder.
        var nonce: Data         // 12 bytes del nonce de AES-GCM.
        var manifest: ArchiveManifest
    }

    // MARK: - Exportación

    /// Cifra el `payload` (ya serializado como JSON versionado de los datos) y devuelve el
    /// contenedor portable en memoria. No se escribe ningún ZIP sin cifrar ni temporales sin
    /// proteger (spec §19): todo el cifrado ocurre en memoria.
    ///
    /// - Parameters:
    ///   - payload: datos ya serializados por la capa superior.
    ///   - password: contraseña de exportación (separada del PIN; la confirmación se hace en UI).
    ///   - includesPhotos: si el payload incluye fotografías.
    ///   - counts: conteos informativos para el manifiesto.
    /// - Returns: `Data` del contenedor cifrado listo para que el usuario elija destino.
    public func export(
        payload: Data,
        password: String,
        includesPhotos: Bool,
        counts: [String: Int] = [:]
    ) throws -> Data {
        guard password.count >= minimumPasswordLength else {
            throw BackupError.weakPassword
        }

        // 1. Sal aleatoria por archivo. NO reutilizamos una clave de dispositivo (spec §19).
        //    `SymmetricKey(size:)` usa el generador aleatorio seguro de CryptoKit, de modo que
        //    no necesitamos importar el framework Security para obtener bytes aleatorios.
        let salt = Self.randomBytes(count: saltByteCount)

        // 2. Derivación de clave estándar (PBKDF2-HMAC-SHA256).
        let key = try deriveKey(password: password, salt: salt, iterations: pbkdf2Iterations)
        // La clave simétrica se descarta al salir del scope; no se persiste.

        // 3. Cifrado autenticado AES-GCM. CryptoKit genera un nonce único por sellado.
        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(payload, using: key)
        } catch {
            throw BackupError.corrupted
        }
        let nonceData = Data(sealed.nonce)
        guard nonceData.count == 12 else {
            throw BackupError.corrupted
        }

        // El cuerpo cifrado almacenado = ciphertext + tag (combined sin el nonce, que viaja
        // aparte en la cabecera para dejar el formato explícito y versionado).
        let ciphertext = sealed.ciphertext + sealed.tag

        let manifest = ArchiveManifest(
            version: Self.currentVersion,
            createdAt: Date(),
            includesPhotos: includesPhotos,
            counts: counts
        )

        let header = ArchiveHeader(
            version: Self.currentVersion,
            iterations: pbkdf2Iterations,
            salt: salt,
            nonce: nonceData,
            manifest: manifest
        )

        return try encodeContainer(header: header, ciphertext: ciphertext)
    }

    // MARK: - Restauración

    /// Valida y descifra un contenedor. RECHAZA antes de entregar nada si la versión no está
    /// soportada, el contenedor está corrupto o la contraseña es incorrecta (T70).
    ///
    /// No modifica ningún dato de la app: la inserción transaccional en SwiftData la hace otra
    /// capa (spec §19, T72/T73). Aquí solo se devuelve el payload descifrado y su manifiesto.
    public func restore(archive: Data, password: String) throws -> RestoredArchive {
        // 1. Decodifica la estructura del contenedor (cabecera + cuerpo).
        let (header, ciphertext) = try decodeContainer(from: archive)

        // 2. Valida versión ANTES de intentar descifrar.
        guard header.version <= Self.currentVersion, header.version >= 1 else {
            throw BackupError.unsupportedVersion(found: header.version, supported: Self.currentVersion)
        }

        guard header.nonce.count == 12 else {
            throw BackupError.corrupted
        }
        // El cuerpo debe tener al menos el tag de GCM (16 bytes).
        guard ciphertext.count >= 16 else {
            throw BackupError.corrupted
        }

        // 3. Re-deriva la clave con la sal e iteraciones del archivo.
        let key = try deriveKey(
            password: password,
            salt: header.salt,
            iterations: header.iterations
        )

        // 4. Descifrado autenticado. Si la contraseña es incorrecta o el contenido fue
        //    alterado, AES-GCM falla la verificación del tag y lanzamos `invalidPassword`
        //    sin tocar datos (T70).
        let payload: Data
        do {
            let nonce = try AES.GCM.Nonce(data: header.nonce)
            let tagStart = ciphertext.count - 16
            let actualCiphertext = ciphertext.prefix(tagStart)
            let tag = ciphertext.suffix(16)
            let sealed = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: actualCiphertext,
                tag: tag
            )
            payload = try AES.GCM.open(sealed, using: key)
        } catch is CryptoKitError {
            throw BackupError.invalidPassword
        } catch {
            // Un nonce/tag con longitud válida pero contenido imposible cae aquí.
            throw BackupError.invalidPassword
        }

        return RestoredArchive(manifest: header.manifest, payload: payload)
    }

    // MARK: - Derivación de clave (PBKDF2-HMAC-SHA256 vía CommonCrypto)

    /// Deriva una `SymmetricKey` de 256 bits a partir de la contraseña y la sal.
    /// Usa `CCKeyDerivationPBKDF`, una implementación estándar y revisada; no inventamos
    /// criptografía (spec §17 "no inventar criptografía").
    private func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let passwordData = Data(password.utf8)
        var derived = [UInt8](repeating: 0, count: keyByteCount)

        let status: Int32 = passwordData.withUnsafeBytes { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    passwordBytes.bindMemory(to: Int8.self).baseAddress,
                    passwordData.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations),
                    &derived,
                    keyByteCount
                )
            }
        }

        guard status == kCCSuccess else {
            // Limpia el buffer parcial antes de propagar el error.
            Self.zeroize(&derived)
            throw BackupError.keyDerivationFailed
        }

        let key = SymmetricKey(data: Data(derived))
        // Limpia el material intermedio en memoria tras construir la clave.
        Self.zeroize(&derived)
        return key
    }

    // MARK: - (De)serialización del contenedor

    /// Formato de contenedor, versionado y autodescriptivo:
    ///   [ magic: "ARCOBK1\n" (8 bytes) ]
    ///   [ headerLength: UInt32 big-endian (4 bytes) ]
    ///   [ header JSON (headerLength bytes) ]
    ///   [ ciphertext (resto) ]
    /// El `magic` incluye el número de versión del layout para detectar corrupción temprana.
    private static let magic = Data("ARCOBK1\n".utf8)

    private func encodeContainer(header: ArchiveHeader, ciphertext: Data) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let headerData = try encoder.encode(header)

        guard headerData.count <= UInt32.max else {
            throw BackupError.corrupted
        }

        var container = Data()
        container.append(Self.magic)
        var length = UInt32(headerData.count).bigEndian
        withUnsafeBytes(of: &length) { container.append(contentsOf: $0) }
        container.append(headerData)
        container.append(ciphertext)
        return container
    }

    private func decodeContainer(from data: Data) throws -> (ArchiveHeader, Data) {
        let magicCount = Self.magic.count
        let prefixCount = magicCount + 4 // magic + UInt32 de longitud

        guard data.count >= prefixCount else {
            throw BackupError.corrupted
        }

        // Validación del magic (detecta un archivo equivocado o corrupto antes de nada, T70).
        let magicSlice = data.subdata(in: data.startIndex ..< data.startIndex + magicCount)
        guard magicSlice == Self.magic else {
            throw BackupError.corrupted
        }

        // Longitud de la cabecera (UInt32 big-endian, leída byte a byte para no depender de
        // la alineación del buffer).
        let lengthStart = data.startIndex + magicCount
        let lengthData = data.subdata(in: lengthStart ..< lengthStart + 4)
        let headerLength = Int(
            (UInt32(lengthData[lengthData.startIndex]) << 24) |
            (UInt32(lengthData[lengthData.startIndex + 1]) << 16) |
            (UInt32(lengthData[lengthData.startIndex + 2]) << 8) |
            UInt32(lengthData[lengthData.startIndex + 3])
        )

        let headerStart = lengthStart + 4
        guard headerLength > 0, data.count >= headerStart + headerLength else {
            throw BackupError.corrupted
        }

        let headerData = data.subdata(in: headerStart ..< headerStart + headerLength)
        let ciphertext = data.subdata(in: (headerStart + headerLength) ..< data.endIndex)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header: ArchiveHeader
        do {
            header = try decoder.decode(ArchiveHeader.self, from: headerData)
        } catch {
            throw BackupError.corrupted
        }

        return (header, ciphertext)
    }

    // MARK: - Utilidades

    /// Bytes aleatorios criptográficamente seguros, obtenidos del generador de CryptoKit
    /// (evita depender del framework Security solo para esto).
    private static func randomBytes(count: Int) -> Data {
        // `SymmetricKey(size:)` rellena su contenido con bytes aleatorios seguros.
        let key = SymmetricKey(size: .init(bitCount: count * 8))
        return key.withUnsafeBytes { Data($0) }
    }

    /// Sobrescribe un buffer sensible en memoria tras usarlo (limpieza incluida en error).
    private static func zeroize(_ bytes: inout [UInt8]) {
        for index in bytes.indices { bytes[index] = 0 }
    }
}
