import Testing
import SwiftData
import Foundation
@testable import ArcoCore

@MainActor
@Suite("Auditoría independiente de restauración")
struct IndependentRestoreAuditTests {
    @Test("Una copia posterior incorpora nuevas series de una sesión ya restaurada")
    func mergesUpdatedSession() throws {
        let tmp = TempDir()
        let source = try inMemoryContext()
        let repository = WorkoutRepository(context: source)
        let session = repository.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["curl_hammer"])
        let oldFile = tmp.url.appendingPathComponent("old.arcobk")
        try ArchiveExporter(context: source, photos: nil).write(to: oldFile, password: "password-seguro", includePhotos: false)
        let draft = try #require(session.exercises.first?.sets.first)
        repository.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repository.confirm(draft)
        let newFile = tmp.url.appendingPathComponent("new.arcobk")
        try ArchiveExporter(context: source, photos: nil).write(to: newFile, password: "password-seguro", includePhotos: false)
        let destination = try inMemoryContext()
        let importer = ArchiveImporter(context: destination, photos: nil)
        try importer.restore(url: oldFile, password: "password-seguro", replaceProfileAndSettings: true)
        try importer.restore(url: newFile, password: "password-seguro", replaceProfileAndSettings: false)
        let restored = try #require(try destination.fetch(FetchDescriptor<SetRecordModel>()).first { $0.id == draft.id })
        #expect(restored.stateRaw == "completed")
        #expect(restored.reps == 10)
    }
    @Test("Una instalación limpia recupera el nombre y archivado de ejercicios preinstalados")
    func restoresEditedSeededExercise() throws {
        let tmp = TempDir()
        let source = try inMemoryContext()
        let exercise = try #require(try source.fetch(FetchDescriptor<ExerciseModel>()).first { $0.id == "curl_hammer" })
        exercise.name = "Mi curl personalizado"
        exercise.archived = true
        try source.save()
        let file = tmp.url.appendingPathComponent("audit.arcobk")
        try ArchiveExporter(context: source, photos: nil).write(to: file, password: "password-seguro", includePhotos: false)
        let destination = try inMemoryContext()
        try ArchiveImporter(context: destination, photos: nil).restore(url: file, password: "password-seguro", replaceProfileAndSettings: true)
        let restored = try #require(try destination.fetch(FetchDescriptor<ExerciseModel>()).first { $0.id == "curl_hammer" })
        #expect(restored.name == "Mi curl personalizado")
        #expect(restored.archived == true)
    }
}
