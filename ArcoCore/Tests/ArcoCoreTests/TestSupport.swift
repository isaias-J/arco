import Foundation
import SwiftData
import CryptoKit
@testable import ArcoCore

/// Calendario fijo para pruebas deterministas (Madrid, gregoriano, semana desde lunes).
func testCalendar(_ tz: String = "Europe/Madrid") -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: tz)!
    c.firstWeekday = 2
    return c
}

func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0, calendar: Calendar = testCalendar()) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

/// Directorio temporal aislado que se borra al terminar.
final class TempDir {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("arco-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

/// Bóveda de pruebas: cifra con SU PROPIA clave aleatoria (simula la clave local de un
/// dispositivo). Dos instancias = dos dispositivos con claves distintas.
final class TestPhotoStore: PhotoFileStore {
    let dir: URL
    let key = SymmetricKey(size: .bits256)

    init(dir: URL) {
        self.dir = dir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func readPhoto(named name: String) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: try Data(contentsOf: dir.appendingPathComponent(name)))
        return try AES.GCM.open(box, using: key)
    }

    func writePhoto(_ data: Data, named name: String) throws {
        try AES.GCM.seal(data, using: key).combined!.write(to: dir.appendingPathComponent(name), options: .atomic)
    }

    func deletePhoto(named name: String) throws {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
    }

    func photoExists(named name: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path)
    }

    func rawFile(_ name: String) throws -> Data { try Data(contentsOf: dir.appendingPathComponent(name)) }

    var fileCount: Int { ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).count }
}

/// Reloj controlable.
final class TestClock: @unchecked Sendable {
    // Solo se usa desde el actor principal en las pruebas.
    var now: Date
    init(_ now: Date) { self.now = now }
    func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds) }
}

/// SwiftData detiene el proceso si un `ModelContext` sobrevive a su `ModelContainer`.
/// Las pruebas retienen aquí cada contenedor que crean.
@MainActor var retainedContainers: [ModelContainer] = []

@MainActor
func inMemoryContext() throws -> ModelContext {
    let c = try PersistenceController.makeContainer(inMemory: true)
    retainedContainers.append(c)
    return c.mainContext
}

@MainActor
func diskContainer(_ url: URL) throws -> ModelContainer {
    let c = try PersistenceController.makeContainer(url: url)
    retainedContainers.append(c)
    return c
}
