import Testing
import SwiftData
import Foundation
@testable import ArcoCore

/// Pruebas de la tercera revisión independiente (`PRUEBAS_TERCERA_REVISION_ARCO.swift`),
/// adaptadas a la política final: mismos escenarios, expectativas según lo que la app promete.
/// - Original 1 esperaba que "Reemplazar" borrase un ejercicio añadido después. Política final:
///   los ejercicios nunca se borran (pueden tener historial), y la previsión y el resultado lo
///   dicen nombrándolos.
/// - Original 2 esperaba que "Combinar" conservase un borrador local con datos. Se mantiene tal
///   cual: ahora pasa.
@MainActor
@Suite("Auditoría adicional (tercera revisión)", .serialized)
struct ThirdAuditTests {
    let pw = "password-seguro"

    @Test("Reemplazar conserva el ejercicio añadido después y lo nombra en la previsión y el resultado")
    func replaceKeepsLaterCustomExerciseAndSaysSo() throws {
        let tmp = TempDir()
        let source = try inMemoryContext()
        let file = tmp.url.appendingPathComponent("backup.arcobk")
        try ArchiveExporter(context: source, photos: nil).write(to: file, password: pw, includePhotos: false)
        let device = try inMemoryContext()
        device.insert(ExerciseModel(id: "custom_added_later", name: "Ejercicio posterior", loadTypeRaw: "machine", patternRaw: "isolationOther", originRaw: "custom", instructions: ""))
        try device.save()
        let importer = ArchiveImporter(context: device, photos: nil)
        let plan = try #require(try importer.preview(url: file, password: pw).plans[.replace])
        #expect(plan.onlyOnDevice["exercises"] == 1)
        #expect(plan.removed["exercises"] == nil)
        #expect(plan.keptExtraExercises == [.init(name: "Ejercicio posterior", isCustom: true, sessionsAfterRestore: 0)])
        let (report, _) = try importer.restore(url: file, password: pw, replaceProfileAndSettings: true, strategy: .replace)
        #expect(report.keptExtraExercises == plan.keptExtraExercises)
        #expect(try device.fetch(FetchDescriptor<ExerciseModel>()).contains { $0.id == "custom_added_later" })
    }

    @Test("Reemplazar: un ejercicio extra con historial en la copia se informa con sus sesiones")
    func replaceReportsExtraExerciseUsage() throws {
        let tmp = TempDir()
        let source = try inMemoryContext()
        source.insert(ExerciseModel(id: "custom_hip", name: "Hip thrust", loadTypeRaw: "machine", patternRaw: "isolationOther", originRaw: "custom", instructions: ""))
        try source.save()
        WorkoutRepository(context: source).startSession(trainingDate: date(2026, 11, 2), timeZone: .current, templateID: nil, exerciseIDs: ["custom_hip"])
        let file = tmp.url.appendingPathComponent("b.arcobk")
        try ArchiveExporter(context: source, photos: nil).write(to: file, password: pw, includePhotos: false)
        // Destino con el mismo ejercicio pero sin la copia: no es "extra".
        let device = try inMemoryContext()
        device.insert(ExerciseModel(id: "custom_extra", name: "Solo aquí", loadTypeRaw: "cable", patternRaw: "isolationOther", originRaw: "custom", instructions: ""))
        WorkoutRepository(context: device).startSession(trainingDate: date(2026, 11, 3), timeZone: .current, templateID: nil, exerciseIDs: ["custom_extra"])
        try device.save()
        let preview = try ArchiveImporter(context: device, photos: nil).preview(url: file, password: pw)
        // Al reemplazar, la sesión local que lo usa se elimina: el ejercicio queda sin sesiones.
        #expect(preview.plans[.replace]?.keptExtraExercises.first?.sessionsAfterRestore == 0)
        #expect(preview.plans[.replace]?.removed["sessions"] == 1)
        // Al combinar, la sesión local se conserva y el ejercicio sigue con su historial.
        #expect(preview.plans[.mergeKeepDevice]?.keptExtraExercises.first?.sessionsAfterRestore == 1)
    }

    @Test("Combinar no borra borradores locales aunque la copia cerró la sesión; reemplazar sí y lo dice")
    func mergeRetainsLocalDraft() throws {
        let tmp = TempDir()
        let source = try inMemoryContext()
        let repo = WorkoutRepository(context: source)
        let session = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["curl_hammer"])
        let open = tmp.url.appendingPathComponent("open.arcobk")
        try ArchiveExporter(context: source, photos: nil).write(to: open, password: pw, includePhotos: false)

        func deviceWithLocalDraft() throws -> (ModelContext, SetRecordModel) {
            let device = try inMemoryContext()
            try ArchiveImporter(context: device, photos: nil).restore(url: open, password: pw, replaceProfileAndSettings: false)
            let local = try #require(try device.fetch(FetchDescriptor<WorkoutSessionModel>()).first)
            let localExercise = try #require(local.exercises.first)
            let r = WorkoutRepository(context: device)
            let draft = try #require(r.addDraft(to: localExercise).first)
            r.updateDraft(draft, amount: 15, unit: .kilograms, reps: 9, type: .working, side: .bilateral, rir: .unknown)
            try device.save()
            return (device, draft)
        }
        let (device, localDraft) = try deviceWithLocalDraft()
        _ = repo.finish(session)
        let closed = tmp.url.appendingPathComponent("closed.arcobk")
        try ArchiveExporter(context: source, photos: nil).write(to: closed, password: pw, includePhotos: false)

        let importer = ArchiveImporter(context: device, photos: nil)
        let preview = try importer.preview(url: closed, password: pw)
        for strategy in [RestoreStrategy.mergeKeepDevice, .mergePreferArchive] {
            let plan = try #require(preview.plans[strategy])
            #expect(plan.removed["drafts"] == nil && plan.removed.isEmpty, "\(strategy)")
            #expect(plan.protectedDrafts == 2)                               // el de la copia antigua y el nuevo
            #expect(plan.onlyOnDevice["drafts"] == 2)
            #expect(plan.conflicts.contains { $0.category == "sessions" && $0.summary.contains("se conservan los borradores") })
        }
        let (report, _) = try importer.restore(url: closed, password: pw, replaceProfileAndSettings: false, strategy: .mergeKeepDevice)
        #expect(report == preview.plans[.mergeKeepDevice])
        let retained = try #require(try device.fetch(FetchDescriptor<SetRecordModel>()).first { $0.id == localDraft.id })
        #expect(retained.stateRaw == "pending" && retained.loadAmount == 15 && retained.reps == 9)
        #expect(try device.fetch(FetchDescriptor<WorkoutSessionModel>()).first?.stateRaw == "active", "La sesión sigue abierta")

        // Reemplazar sí descarta los borradores, y lo anuncia antes.
        let (device2, draft2) = try deviceWithLocalDraft()
        let importer2 = ArchiveImporter(context: device2, photos: nil)
        let plan2 = try #require(try importer2.preview(url: closed, password: pw).plans[.replace])
        #expect(plan2.removed["drafts"] == 2)
        let (replaced, _) = try importer2.restore(url: closed, password: pw, replaceProfileAndSettings: false, strategy: .replace)
        #expect(replaced.removed == plan2.removed)
        #expect(!(try device2.fetch(FetchDescriptor<SetRecordModel>()).contains { $0.id == draft2.id }))
        #expect(try device2.fetch(FetchDescriptor<WorkoutSessionModel>()).first?.stateRaw != "active")
    }
}
