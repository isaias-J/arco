import Foundation
import CryptoKit
import CommonCrypto

/// Archivo portable cifrado, formato 2 (spec §19).
///
/// Diseño:
/// - Clave derivada de la contraseña de exportación (PBKDF2-HMAC-SHA256, sal aleatoria),
///   independiente del PIN y de la clave del dispositivo. La contraseña no se guarda.
/// - El contenido se divide en fragmentos cifrados por separado con AES-GCM: el fragmento 0
///   es el JSON de datos; cada foto es un fragmento propio. Así se escribe y lee una foto cada
///   vez, sin cargar la galería entera en memoria ni escribir un ZIP sin cifrar.
/// - Cada fragmento autentica (AAD) el identificador del archivo, su índice, el total y el
///   resumen SHA-256 de la cabecera: reordenar, truncar o editar la cabecera se detecta.
///
/// Estructura: `"ARCOBK2\n"` · UInt32 BE longitud de cabecera · cabecera JSON ·
/// por fragmento: UInt32 BE longitud · nonce‖cifrado‖etiqueta.
public enum PortableArchive {
    public static let magic = Data("ARCOBK2\n".utf8)
    public static let formatVersion = 2
    public static let minimumPasswordLength = 8
    public static let iterations = 210_000

    /// Límites de recursos (protección frente a archivos malformados, no límites biológicos).
    static let maxHeaderBytes = 1 << 20
    static let maxChunkBytes = 80 << 20
    static let maxChunks = 100_000

    struct Header: Codable {
        var version: Int
        var archiveID: UUID
        var iterations: Int
        var salt: Data
        var chunkCount: Int
        var manifest: ArchiveManifest
    }

    static func aad(archiveID: UUID, index: Int, total: Int, headerDigest: Data) -> Data {
        var d = Data("ARCOBK2|\(archiveID.uuidString)|\(index)|\(total)|".utf8)
        d.append(headerDigest)
        return d
    }

    static func deriveKey(password: String, salt: Data, iterations: Int) throws -> SymmetricKey {
        let pw = Data(password.utf8)
        var derived = [UInt8](repeating: 0, count: 32)
        let status: Int32 = pw.withUnsafeBytes { p in
            salt.withUnsafeBytes { s in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    p.bindMemory(to: Int8.self).baseAddress, pw.count,
                    s.bindMemory(to: UInt8.self).baseAddress, salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    UInt32(iterations), &derived, 32
                )
            }
        }
        defer { for i in derived.indices { derived[i] = 0 } }
        guard status == kCCSuccess else { throw BackupError.keyDerivationFailed }
        return SymmetricKey(data: Data(derived))
    }

    static func bigEndian(_ value: UInt32) -> Data {
        var be = value.bigEndian
        return withUnsafeBytes(of: &be) { Data($0) }
    }

    static func readUInt32(_ data: Data) -> UInt32 {
        data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}

/// Escritor secuencial de un archivo portable. Escribe en un archivo temporal del contenedor
/// de la app (ya cifrado: nunca hay datos en claro en disco) que el usuario exporta después.
public final class PortableArchiveWriter {
    private let handle: FileHandle
    public let url: URL
    private let key: SymmetricKey
    private let header: PortableArchive.Header
    private let headerDigest: Data
    private var written = 0

    public init(url: URL, password: String, manifest: ArchiveManifest, chunkCount: Int) throws {
        guard password.count >= PortableArchive.minimumPasswordLength else { throw BackupError.weakPassword }
        guard chunkCount >= 1, chunkCount <= PortableArchive.maxChunks else { throw BackupError.corrupted }
        let salt = SymmetricKey(size: .bits128).withUnsafeBytes { Data($0) }
        self.key = try PortableArchive.deriveKey(password: password, salt: salt, iterations: PortableArchive.iterations)
        self.header = PortableArchive.Header(
            version: PortableArchive.formatVersion, archiveID: UUID(),
            iterations: PortableArchive.iterations, salt: salt,
            chunkCount: chunkCount, manifest: manifest
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let headerData = try encoder.encode(header)
        self.headerDigest = Data(SHA256.hash(data: headerData))
        self.url = url
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
        var prefix = PortableArchive.magic
        prefix.append(PortableArchive.bigEndian(UInt32(headerData.count)))
        prefix.append(headerData)
        try handle.write(contentsOf: prefix)
    }

    /// Cifra y añade el siguiente fragmento.
    public func append(_ plaintext: Data) throws {
        guard written < header.chunkCount else { throw BackupError.corrupted }
        let aad = PortableArchive.aad(archiveID: header.archiveID, index: written, total: header.chunkCount, headerDigest: headerDigest)
        guard let sealed = try AES.GCM.seal(plaintext, using: key, authenticating: aad).combined else {
            throw BackupError.corrupted
        }
        try handle.write(contentsOf: PortableArchive.bigEndian(UInt32(sealed.count)) + sealed)
        written += 1
    }

    /// Cierra el archivo. Falla si no se escribieron todos los fragmentos anunciados.
    public func finish() throws {
        try handle.close()
        guard written == header.chunkCount else { throw BackupError.corrupted }
    }

    /// Cierra y elimina el temporal tras un error.
    public func abort() {
        try? handle.close()
        try? FileManager.default.removeItem(at: url)
    }
}

/// Lector de un archivo portable. Valida estructura, versión y contraseña antes de entregar
/// datos; cada fragmento se autentica al leerlo.
public final class PortableArchiveReader {
    private let handle: FileHandle
    private let key: SymmetricKey
    private let header: PortableArchive.Header
    private let headerDigest: Data
    private var nextIndex = 0
    public var manifest: ArchiveManifest { header.manifest }
    public var chunkCount: Int { header.chunkCount }

    /// Indica si el archivo tiene el formato 2.
    public static func isPortableArchive(_ url: URL) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        return (try? h.read(upToCount: PortableArchive.magic.count)) == PortableArchive.magic
    }

    public init(url: URL, password: String) throws {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            guard try handle.read(upToCount: 8) == PortableArchive.magic,
                  let lengthData = try handle.read(upToCount: 4), lengthData.count == 4 else {
                throw BackupError.corrupted
            }
            let length = Int(PortableArchive.readUInt32(lengthData))
            guard length > 0, length <= PortableArchive.maxHeaderBytes,
                  let headerData = try handle.read(upToCount: length), headerData.count == length else {
                throw BackupError.corrupted
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let header = try? decoder.decode(PortableArchive.Header.self, from: headerData) else {
                throw BackupError.corrupted
            }
            guard header.version == PortableArchive.formatVersion else {
                throw BackupError.unsupportedVersion(found: header.version, supported: PortableArchive.formatVersion)
            }
            guard header.chunkCount >= 1, header.chunkCount <= PortableArchive.maxChunks,
                  header.iterations >= 100_000, header.iterations <= 10_000_000, header.salt.count >= 16 else {
                throw BackupError.corrupted
            }
            self.header = header
            self.headerDigest = Data(SHA256.hash(data: headerData))
            self.key = try PortableArchive.deriveKey(password: password, salt: header.salt, iterations: header.iterations)
            self.handle = handle
        } catch {
            try? handle.close()
            throw error
        }
    }

    deinit { try? handle.close() }

    /// Lee y descifra el siguiente fragmento. Contraseña incorrecta → `invalidPassword` en el
    /// primer fragmento; un fragmento alterado → `corrupted`.
    public func next() throws -> Data {
        guard nextIndex < header.chunkCount else { throw BackupError.corrupted }
        guard let lengthData = try handle.read(upToCount: 4), lengthData.count == 4 else { throw BackupError.corrupted }
        let length = Int(PortableArchive.readUInt32(lengthData))
        guard length >= 28, length <= PortableArchive.maxChunkBytes,
              let sealed = try handle.read(upToCount: length), sealed.count == length else {
            throw BackupError.corrupted
        }
        let aad = PortableArchive.aad(archiveID: header.archiveID, index: nextIndex, total: header.chunkCount, headerDigest: headerDigest)
        do {
            let box = try AES.GCM.SealedBox(combined: sealed)
            let plain = try AES.GCM.open(box, using: key, authenticating: aad)
            nextIndex += 1
            return plain
        } catch {
            throw nextIndex == 0 ? BackupError.invalidPassword : BackupError.corrupted
        }
    }

    /// Comprueba que no queden bytes tras el último fragmento.
    public func assertAtEnd() throws {
        guard nextIndex == header.chunkCount else { throw BackupError.corrupted }
        if let extra = try handle.read(upToCount: 1), !extra.isEmpty { throw BackupError.corrupted }
    }
}
