import Testing
import SwiftData
import Foundation
@testable import ArcoCore

/// Copia cifrada completa y restauración en una instalación limpia con otra clave local.
@MainActor
@Suite("Integración: copia cifrada completa con fotos", .serialized)
struct ArchiveIntegrationTests {

    let password = "contraseña-de-prueba-ñ"

    /// "Dispositivo A" con datos de entrenamiento, perfil, peso vinculado a dos fotos, etc.
    private func populatedDevice(_ tmp: TempDir) throws -> (ModelContext, TestPhotoStore) {
        let ctx = try inMemoryContext()
        let store = TestPhotoStore(dir: tmp.url.appendingPathComponent("vaultA"))
        let repo = WorkoutRepository(context: ctx)

        let s = repo.startSession(trainingDate: date(2026, 11, 2), timeZone: .current, templateID: "mon_push", exerciseIDs: ["chest_flat_barbell", "curl_dumbbell"])
        let bench = s.exercises.first { $0.exerciseID == "chest_flat_barbell" }!
        let d = bench.sets[0]
        repo.updateDraft(d, amount: 60, unit: .kilograms, reps: 8, type: .working, side: .bilateral, rir: .exact(1))
        try repo.confirm(d)
        repo.finish(s)

        ctx.insert(UserProfileModel(displayName: "Persona de prueba", birthDate: date(2000, 1, 1)))
        let settings = try ctx.fetch(FetchDescriptor<AppSettingsModel>()).first!
        settings.massUnitRaw = "lb"
        settings.onboardingCompleted = true
        ctx.insert(HeightModel(date: date(2026, 10, 1), amount: 175, unitRaw: "cm"))
        ctx.insert(BodyMeasurementModel(typeKey: "arm", sideRaw: "left", protocolNote: "contraído", amount: 34, unitRaw: "cm", date: date(2026, 11, 1)))
        ctx.insert(WeeklyGoalModel(muscleRaw: "deltoidLateral", methodRaw: "direct", target: 8, validFrom: date(2026, 11, 2)))
        ctx.insert(ExerciseModel(id: "custom_hip_thrust", name: "Hip thrust en máquina", loadTypeRaw: "machine", patternRaw: "isolationOther", originRaw: "custom", instructions: ""))
        AttendanceRepository(context: ctx, calendar: testCalendar()).markResolution(.rest, on: CivilDay(year: 2026, month: 11, day: 3))
        let catalog = CatalogRepository(context: ctx)
        try catalog.setProgressionRule("legs_extension", enabled: true, lower: 8, upper: 12, referenceSets: 3, increment: 5, unit: .kilograms, minimumRIR: 1)
        try catalog.setCustomAttribution("custom_hip_thrust", [.glutes: .direct])
        // Rutina cambiada al día siguiente del primer entrenamiento: dos versiones de plan.
        try catalog.updatePlan(WeeklyPlan.ownerDefault, effective: date(2026, 11, 3), calendar: testCalendar())

        let weight = BodyWeightModel(measurementDate: date(2026, 11, 2), enteredAt: date(2026, 11, 2), amount: 72, unitRaw: "kg", isEstimated: false)
        ctx.insert(weight)
        for (i, pose) in ["frontRelaxed", "side"].enumerated() {
            let name = "checkin-\(i).enc"
            try store.writePhoto(Data("JPEG-\(pose)-\(String(repeating: "x", count: 5000))".utf8), named: name)
            let photo = PhotoCheckInModel(date: date(2026, 11, 2, 9, i), poseRaw: pose, encryptedFileName: name, bodyWeightID: weight.id)
            ctx.insert(photo)
            weight.photoCheckInID = photo.id
        }
        try ctx.save()
        return (ctx, store)
    }

    @Test("T71: restaurar en una instalación limpia recupera datos, fotos y vínculos con la nueva clave local")
    func fullRoundTrip() throws {
        let tmp = TempDir()
        let (ctxA, storeA) = try populatedDevice(tmp)
        let file = tmp.url.appendingPathComponent("respaldo.arcobk")
        let exported = try ArchiveExporter(context: ctxA, photos: storeA, preferences: ["arco.rirMode": "lastSet"])
            .write(to: file, password: password, includePhotos: true)
        #expect(exported.photos.count == 2)

        // El archivo no contiene la imagen ni el nombre en claro.
        let raw = try Data(contentsOf: file)
        #expect(raw.range(of: Data("JPEG-frontRelaxed".utf8)) == nil)
        #expect(raw.range(of: Data("Persona de prueba".utf8)) == nil)

        // Dispositivo B: instalación limpia, otra clave de bóveda.
        let ctxB = try inMemoryContext()
        let storeB = TestPhotoStore(dir: tmp.url.appendingPathComponent("vaultB"))
        let importer = ArchiveImporter(context: ctxB, photos: storeB)
        let preview = try importer.preview(url: file, password: password)
        #expect(preview.includesPhotos)
        #expect(preview.counts["photos"] == 2 && preview.counts["sessions"] == 1)
        #expect(try ctxB.fetch(FetchDescriptor<WorkoutSessionModel>()).isEmpty)   // la vista previa no modifica

        let (report, prefs) = try importer.restore(url: file, password: password, replaceProfileAndSettings: true)
        #expect(report.inserted["photos"] == 2)
        #expect(prefs["arco.rirMode"] == "lastSet")

        let photos = try ctxB.fetch(FetchDescriptor<PhotoCheckInModel>()).sorted { $0.date < $1.date }
        #expect(photos.map(\.poseRaw) == ["frontRelaxed", "side"])
        for p in photos {
            let data = try storeB.readPhoto(named: p.encryptedFileName)   // se descifra con la clave de B
            #expect(String(decoding: data, as: UTF8.self).hasPrefix("JPEG-\(p.poseRaw)"))
            #expect(throws: (any Error).self) { try storeA.readPhotoRaw(storeB.rawFile(p.encryptedFileName)) }
        }
        let weight = try #require(try ctxB.fetch(FetchDescriptor<BodyWeightModel>()).first)
        #expect(photos.allSatisfy { $0.bodyWeightID == weight.id })      // un pesaje, dos poses (T49)
        #expect(photos.map(\.id).contains(weight.photoCheckInID!))

        let session = try #require(try ctxB.fetch(FetchDescriptor<WorkoutSessionModel>()).first)
        #expect(session.exercises.flatMap(\.sets).first { $0.stateRaw == "completed" }?.loadAmount == 60)
        #expect(try ctxB.fetch(FetchDescriptor<UserProfileModel>()).first?.displayName == "Persona de prueba")
        #expect(try ctxB.fetch(FetchDescriptor<AppSettingsModel>()).first?.massUnitRaw == "lb")
        #expect(try ctxB.fetch(FetchDescriptor<AttendanceEventModel>()).count == 1)
        #expect(try ctxB.fetch(FetchDescriptor<AttendanceResolutionModel>()).first?.dayKey == "2026-11-03")
        #expect(try ctxB.fetch(FetchDescriptor<WeeklyGoalModel>()).count == 1)
        #expect(try ctxB.fetch(FetchDescriptor<HeightModel>()).count == 1)
        #expect(try ctxB.fetch(FetchDescriptor<BodyMeasurementModel>()).first?.sideRaw == "left")
        #expect(try ctxB.fetch(FetchDescriptor<ExerciseModel>()).contains { $0.id == "custom_hip_thrust" })
        #expect(try ctxB.fetch(FetchDescriptor<ExerciseModel>()).count == 28)
        #expect(try ctxB.fetch(FetchDescriptor<DoubleProgressionModel>()).first?.minimumRIR == 1)
        #expect(try ctxB.fetch(FetchDescriptor<CustomAttributionModel>()).first?.muscleRaw == "glutes")
        #expect(try ctxB.fetch(FetchDescriptor<PlanVersionModel>()).count == 2)
    }

    @Test("T72: reimportar el mismo archivo no duplica registros ni fotos")
    func reimportDoesNotDuplicate() throws {
        let tmp = TempDir()
        let (ctxA, storeA) = try populatedDevice(tmp)
        let file = tmp.url.appendingPathComponent("r.arcobk")
        try ArchiveExporter(context: ctxA, photos: storeA).write(to: file, password: password, includePhotos: true)
        let ctxB = try inMemoryContext()
        let storeB = TestPhotoStore(dir: tmp.url.appendingPathComponent("vaultB"))
        let importer = ArchiveImporter(context: ctxB, photos: storeB)
        try importer.restore(url: file, password: password, replaceProfileAndSettings: true)
        let (second, _) = try importer.restore(url: file, password: password, replaceProfileAndSettings: false)
        #expect(second.inserted["sessions"] == nil && second.inserted["photos"] == nil)
        #expect(second.skippedExisting["photos"] == 2)
        #expect(try ctxB.fetch(FetchDescriptor<WorkoutSessionModel>()).count == 1)
        #expect(try ctxB.fetch(FetchDescriptor<SetRecordModel>()).count == 1)
        #expect(try ctxB.fetch(FetchDescriptor<PhotoCheckInModel>()).count == 2)
        #expect(try ctxB.fetch(FetchDescriptor<BodyWeightModel>()).count == 1)
        #expect(storeB.fileCount == 2)
        // Restaurar en el mismo dispositivo de origen tampoco duplica.
        try ArchiveImporter(context: ctxA, photos: storeA).restore(url: file, password: password, replaceProfileAndSettings: false)
        #expect(try ctxA.fetch(FetchDescriptor<PhotoCheckInModel>()).count == 2)
    }

    @Test("T70: contraseña incorrecta no modifica datos ni escribe fotos")
    func wrongPassword() throws {
        let tmp = TempDir()
        let (ctxA, storeA) = try populatedDevice(tmp)
        let file = tmp.url.appendingPathComponent("r.arcobk")
        try ArchiveExporter(context: ctxA, photos: storeA).write(to: file, password: password, includePhotos: true)
        let ctxB = try inMemoryContext()
        let storeB = TestPhotoStore(dir: tmp.url.appendingPathComponent("vaultB"))
        #expect(throws: BackupError.invalidPassword) {
            try ArchiveImporter(context: ctxB, photos: storeB).restore(url: file, password: "otra-contraseña", replaceProfileAndSettings: true)
        }
        #expect(try ctxB.fetch(FetchDescriptor<WorkoutSessionModel>()).isEmpty)
        #expect(storeB.fileCount == 0)
    }

    @Test("T70: un fragmento de foto dañado se detecta antes de modificar nada")
    func corruptedPhotoChunk() throws {
        let tmp = TempDir()
        let (ctxA, storeA) = try populatedDevice(tmp)
        let file = tmp.url.appendingPathComponent("r.arcobk")
        try ArchiveExporter(context: ctxA, photos: storeA).write(to: file, password: password, includePhotos: true)
        var bytes = try Data(contentsOf: file)
        bytes[bytes.count - 40] ^= 0x01      // dentro del último fragmento (una foto)
        try bytes.write(to: file)

        let ctxB = try inMemoryContext()
        let storeB = TestPhotoStore(dir: tmp.url.appendingPathComponent("vaultB"))
        let importer = ArchiveImporter(context: ctxB, photos: storeB)
        #expect(throws: BackupError.corrupted) { try importer.preview(url: file, password: password) }
        #expect(throws: BackupError.corrupted) {
            try importer.restore(url: file, password: password, replaceProfileAndSettings: true)
        }
        #expect(try ctxB.fetch(FetchDescriptor<WorkoutSessionModel>()).isEmpty)
        #expect(try ctxB.fetch(FetchDescriptor<PhotoCheckInModel>()).isEmpty)
        #expect(storeB.fileCount == 0)
    }

    @Test("Archivo truncado o con cabecera alterada se rechaza")
    func truncatedOrTampered() throws {
        let tmp = TempDir()
        let (ctxA, storeA) = try populatedDevice(tmp)
        let file = tmp.url.appendingPathComponent("r.arcobk")
        try ArchiveExporter(context: ctxA, photos: storeA).write(to: file, password: password, includePhotos: true)
        let original = try Data(contentsOf: file)

        let truncated = tmp.url.appendingPathComponent("t.arcobk")
        try original.prefix(original.count - 200).write(to: truncated)
        let ctxB = try inMemoryContext()
        let importer = ArchiveImporter(context: ctxB, photos: TestPhotoStore(dir: tmp.url.appendingPathComponent("vB")))
        #expect(throws: BackupError.corrupted) { try importer.preview(url: truncated, password: password) }

        // Cambiar el número de fotos anunciado en la cabecera en claro.
        let tampered = tmp.url.appendingPathComponent("h.arcobk")
        let text = String(decoding: original, as: UTF8.self)
        let modified = text.replacingOccurrences(of: "\"photos\":2", with: "\"photos\":9")
        #expect(modified != text)
        try Data(modified.utf8).write(to: tampered)
        #expect(throws: (any Error).self) { try importer.preview(url: tampered, password: password) }
        #expect(try ctxB.fetch(FetchDescriptor<WorkoutSessionModel>()).isEmpty)
    }

    @Test("Sin incluir fotos: no hay imágenes en el archivo ni vínculos colgantes; con fotos se exige la bóveda")
    func withoutPhotos() throws {
        let tmp = TempDir()
        let (ctxA, storeA) = try populatedDevice(tmp)
        #expect(throws: ArchiveError.photosRequireUnlockedVault) {
            try ArchiveExporter(context: ctxA, photos: nil).write(to: tmp.url.appendingPathComponent("x"), password: password, includePhotos: true)
        }
        let file = tmp.url.appendingPathComponent("d.arcobk")
        let content = try ArchiveExporter(context: ctxA, photos: nil).write(to: file, password: password, includePhotos: false)
        #expect(content.photos.isEmpty && !content.includesPhotos)
        #expect(content.bodyWeights.allSatisfy { $0.photoCheckInID == nil })
        let ctxB = try inMemoryContext()
        let preview = try ArchiveImporter(context: ctxB, photos: nil).preview(url: file, password: password)
        #expect(preview.includesPhotos == false && preview.counts["photos"] == 0)
        try ArchiveImporter(context: ctxB, photos: nil).restore(url: file, password: password, replaceProfileAndSettings: true)
        #expect(try ctxB.fetch(FetchDescriptor<PhotoCheckInModel>()).isEmpty)
        #expect(try ctxB.fetch(FetchDescriptor<WorkoutSessionModel>()).count == 1)
        _ = storeA
    }

    @Test("Contraseña de exportación débil se rechaza y no deja archivo")
    func weakPassword() throws {
        let tmp = TempDir()
        let ctx = try inMemoryContext()
        let file = tmp.url.appendingPathComponent("w.arcobk")
        #expect(throws: BackupError.weakPassword) {
            try ArchiveExporter(context: ctx, photos: nil).write(to: file, password: "corta", includePhotos: false)
        }
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}

extension TestPhotoStore {
    /// Intenta descifrar un archivo ajeno con la clave de ESTA bóveda (debe fallar).
    func readPhotoRaw(_ data: Data) throws -> Data {
        let tmp = dir.appendingPathComponent("foreign-\(UUID().uuidString)")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try readPhoto(named: tmp.lastPathComponent)
    }
}
