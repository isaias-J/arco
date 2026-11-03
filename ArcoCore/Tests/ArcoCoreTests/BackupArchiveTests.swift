import Testing
import Foundation
@testable import ArcoCore

/// Pruebas del archivo de respaldo cifrado (T70-T72). Corren con `swift test` (solo CryptoKit
/// y CommonCrypto). Face ID, cámara y Keychain real se prueban en iPhone.
@Suite("Archivo de respaldo cifrado")
struct BackupArchiveTests {

    @Test("T70: export + restore con la contraseña correcta recupera el payload")
    func roundTrip() throws {
        let archive = BackupArchive()
        let payload = Data("{\"version\":1,\"sessions\":[]}".utf8)
        let data = try archive.export(payload: payload, password: "clave-fuerte-123", includesPhotos: false, counts: ["sessions": 0])
        let restored = try archive.restore(archive: data, password: "clave-fuerte-123")
        #expect(restored.payload == payload)
        #expect(restored.manifest.includesPhotos == false)
    }

    @Test("T70: contraseña incorrecta no entrega datos")
    func wrongPassword() throws {
        let archive = BackupArchive()
        let data = try archive.export(payload: Data("x".utf8), password: "correcta-123", includesPhotos: false)
        #expect(throws: BackupError.self) {
            _ = try archive.restore(archive: data, password: "incorrecta-999")
        }
    }

    @Test("T70: archivo corrupto se rechaza")
    func corruptedRejected() throws {
        let archive = BackupArchive()
        var data = try archive.export(payload: Data("x".utf8), password: "correcta-123", includesPhotos: false)
        // Corromper la mitad del contenedor.
        data[data.count / 2] ^= 0xFF
        #expect(throws: BackupError.self) {
            _ = try archive.restore(archive: data, password: "correcta-123")
        }
    }

    @Test("Contraseña débil se rechaza al exportar")
    func weakPassword() {
        let archive = BackupArchive()
        #expect(throws: BackupError.self) {
            _ = try archive.export(payload: Data("x".utf8), password: "123", includesPhotos: false)
        }
    }
}
