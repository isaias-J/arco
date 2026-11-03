import Testing
import SwiftData
import Foundation
@testable import ArcoCore

/// Restauración sobre datos existentes (segunda revisión independiente): catálogo, sesiones,
/// series, conflictos, borrados, reemplazo, copias antiguas, fallos e idempotencia.
@MainActor
@Suite("Restauración: combinación y conflictos", .serialized)
struct RestoreMergeTests {
    let pw = "password-seguro"
    struct InjectedFailure: Error {}

    // MARK: Utilidades

    private func export(_ ctx: ModelContext, _ tmp: TempDir, _ name: String, photos: PhotoFileStore? = nil) throws -> URL {
        let url = tmp.url.appendingPathComponent(name)
        try ArchiveExporter(context: ctx, photos: photos).write(to: url, password: pw, includePhotos: photos != nil)
        return url
    }

    @discardableResult
    private func restore(_ ctx: ModelContext, _ url: URL, _ strategy: RestoreStrategy = .mergeKeepDevice, photos: PhotoFileStore? = nil, profile: Bool = false) throws -> RestoreReport {
        try ArchiveImporter(context: ctx, photos: photos).restore(url: url, password: pw, replaceProfileAndSettings: profile, strategy: strategy).0
    }

    private func exercise(_ ctx: ModelContext, _ id: String) throws -> ExerciseModel {
        try #require(try ctx.fetch(FetchDescriptor<ExerciseModel>()).first { $0.id == id })
    }

    private func setRow(_ ctx: ModelContext, _ id: UUID) throws -> SetRecordModel {
        try #require(try ctx.fetch(FetchDescriptor<SetRecordModel>()).first { $0.id == id })
    }

    private func count<T: PersistentModel>(_ ctx: ModelContext, _ t: T.Type) throws -> Int {
        try ctx.fetch(FetchDescriptor<T>()).count
    }

    /// Origen con una sesión abierta de curl martillo y su primer borrador.
    private func sourceWithDraft(_ clock: TestClock) throws -> (ModelContext, WorkoutRepository, WorkoutSessionModel, SetRecordModel) {
        let ctx = try inMemoryContext()
        let repo = WorkoutRepository(context: ctx, now: { clock.now })
        let s = repo.startSession(trainingDate: date(2026, 11, 2), timeZone: .current, templateID: nil, exerciseIDs: ["curl_hammer"])
        let draft = try #require(s.exercises.first?.sets.first)
        return (ctx, repo, s, draft)
    }

    // MARK: 1. Catálogo

    @Test("Instalación limpia (catálogo ya sembrado): recupera nombre, alias, instrucciones, equipo, patrón y archivado")
    func cleanInstallRestoresCatalogEdits() throws {
        let tmp = TempDir()
        let source = try inMemoryContext()
        let curl = try exercise(source, "curl_hammer")
        curl.name = "Martillo en cuerda"; curl.aliasesJoined = "Cuerda\nMartillo polea"; curl.instructions = "Codos pegados."
        curl.loadTypeRaw = LoadType.cable.rawValue; curl.patternRaw = MovementPattern.isolationOther.rawValue; curl.archived = true
        let press = try exercise(source, "chest_machine_press")
        press.archived = true
        source.insert(ExerciseModel(id: "custom_hip", name: "Hip thrust en máquina", loadTypeRaw: "machine", patternRaw: "isolationOther", originRaw: "custom", instructions: "Mi nota"))
        try source.save()
        let file = try export(source, tmp, "c.arcobk")

        let clean = try inMemoryContext()          // ya contiene el catálogo inicial
        #expect(try exercise(clean, "curl_hammer").name != "Martillo en cuerda")
        let report = try restore(clean, file)
        let restored = try exercise(clean, "curl_hammer")
        #expect(restored.name == "Martillo en cuerda")
        #expect(restored.aliasesJoined == "Cuerda\nMartillo polea")
        #expect(restored.instructions == "Codos pegados.")
        #expect(restored.loadTypeRaw == LoadType.cable.rawValue)
        #expect(restored.archived)
        #expect(try exercise(clean, "chest_machine_press").archived)
        #expect(try exercise(clean, "custom_hip").instructions == "Mi nota")
        #expect(report.updated["exercises"] == 2 && report.inserted["exercises"] == 1)
        #expect(report.conflicts.isEmpty)
    }

    @Test("Conflicto de catálogo: cada estrategia hace lo que dice y lo informa")
    func catalogConflict() throws {
        let tmp = TempDir()
        let source = try inMemoryContext()
        try exercise(source, "curl_hammer").name = "Nombre de la copia"
        try source.save()
        let file = try export(source, tmp, "c.arcobk")

        for (strategy, expected) in [(RestoreStrategy.mergeKeepDevice, "Nombre de este iPhone"), (.mergePreferArchive, "Nombre de la copia"), (.replace, "Nombre de la copia")] {
            let device = try inMemoryContext()
            try exercise(device, "curl_hammer").name = "Nombre de este iPhone"
            try device.save()
            let report = try restore(device, file, strategy)
            #expect(try exercise(device, "curl_hammer").name == expected, "\(strategy)")
            let conflict = try #require(report.conflicts.first { $0.category == "exercises" })
            #expect(conflict.summary.contains("Nombre de este iPhone") && conflict.summary.contains("Nombre de la copia"))
            #expect(conflict.resolution == (strategy == .mergeKeepDevice ? .keptDevice : .usedArchive))
        }
    }

    @Test("Si la copia trae el valor de fábrica y este iPhone lo cambió, se conserva el cambio local sin conflicto")
    func catalogLocalChangeKept() throws {
        let tmp = TempDir()
        let file = try export(try inMemoryContext(), tmp, "c.arcobk")
        let device = try inMemoryContext()
        let curl = try exercise(device, "curl_hammer")
        curl.name = "Cambio posterior"; curl.archived = true
        try device.save()
        let report = try restore(device, file)
        #expect(try exercise(device, "curl_hammer").name == "Cambio posterior")
        #expect(try exercise(device, "curl_hammer").archived)
        #expect(report.keptDevice["exercises"] == 1 && report.conflicts.isEmpty)
    }

    @Test("Un nombre de la copia que aquí ya usa otro ejercicio no se aplica (no se fusionan historiales)")
    func catalogNameClash() throws {
        let tmp = TempDir()
        let source = try inMemoryContext()
        try exercise(source, "curl_hammer").name = "Curl favorito"
        try source.save()
        let file = try export(source, tmp, "c.arcobk")
        let device = try inMemoryContext()
        device.insert(ExerciseModel(id: "custom_x", name: "Curl favorito", loadTypeRaw: "cable", patternRaw: "isolationOther", originRaw: "custom", instructions: ""))
        try device.save()
        let report = try restore(device, file, .mergePreferArchive)
        #expect(try exercise(device, "curl_hammer").name == ExerciseNames.localized("curl_hammer"))
        #expect(report.conflicts.contains { $0.category == "exercises" && $0.resolution == .keptDevice })
    }

    // MARK: 2. Sesiones y series

    @Test("Copia antigua y después reciente: la serie confirmada se incorpora; en orden inverso no retrocede")
    func olderThenNewerAndReverse() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18))
        let (source, repo, _, draft) = try sourceWithDraft(clock)
        let old = try export(source, tmp, "old.arcobk")
        clock.advance(120)
        repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(draft)
        let new = try export(source, tmp, "new.arcobk")

        let a = try inMemoryContext()
        try restore(a, old)
        let report = try restore(a, new)
        #expect(try setRow(a, draft.id).stateRaw == "completed" && setRow(a, draft.id).reps == 10)
        #expect(report.updated["sets"] == 1 && report.conflicts.isEmpty)
        #expect(try count(a, AttendanceEventModel.self) == 1)          // asistencia derivada, sin duplicar

        let b = try inMemoryContext()
        try restore(b, new)
        let back = try restore(b, old)
        #expect(try setRow(b, draft.id).stateRaw == "completed" && setRow(b, draft.id).reps == 10)
        #expect(back.keptDevice["sets"] == 1 && back.conflicts.isEmpty)
        #expect(try count(b, AttendanceEventModel.self) == 1)
    }

    @Test("Restaurar repetidamente no duplica ni genera conflictos")
    func repeatedRestoreIsIdempotent() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18))
        let (source, repo, session, draft) = try sourceWithDraft(clock)
        clock.advance(60)
        repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(draft)
        repo.finish(session)
        try exercise(source, "curl_hammer").name = "Martillo"
        try source.save()
        let file = try export(source, tmp, "f.arcobk")
        let device = try inMemoryContext()
        try restore(device, file)
        let counts = (try count(device, WorkoutSessionModel.self), try count(device, SetRecordModel.self), try count(device, AttendanceEventModel.self), try count(device, ExerciseModel.self))
        for _ in 0..<2 {
            let again = try restore(device, file)
            #expect(again.inserted.isEmpty && again.updated.isEmpty && again.conflicts.isEmpty)
        }
        #expect((try count(device, WorkoutSessionModel.self), try count(device, SetRecordModel.self), try count(device, AttendanceEventModel.self), try count(device, ExerciseModel.self)) == counts)
        // Restaurar la copia sobre el propio origen tampoco cambia nada.
        let own = try restore(source, file)
        #expect(own.inserted.isEmpty && own.updated.isEmpty && own.conflicts.isEmpty)
    }

    @Test("Una misma serie editada de forma distinta en cada lado es un conflicto; la estrategia decide")
    func editedSetConflict() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18))
        let (source, repo, _, draft) = try sourceWithDraft(clock)
        clock.advance(60)
        repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(draft)
        let base = try export(source, tmp, "base.arcobk")
        try repo.edit(draft, amount: 12, unit: .kilograms, convention: .perDumbbell, reps: 11, type: .working, side: .bilateral, rir: nil)
        let edited = try export(source, tmp, "edited.arcobk")

        for (strategy, reps) in [(RestoreStrategy.mergeKeepDevice, 9), (.mergePreferArchive, 11), (.replace, 11)] {
            let device = try inMemoryContext()
            try restore(device, base)
            let local = try setRow(device, draft.id)
            try WorkoutRepository(context: device).edit(local, amount: 12, unit: .kilograms, convention: .perDumbbell, reps: 9, type: .working, side: .bilateral, rir: nil)
            let report = try restore(device, edited, strategy)
            #expect(try setRow(device, draft.id).reps == reps, "\(strategy)")
            let conflict = try #require(report.conflicts.first { $0.category == "sets" })
            #expect(conflict.summary.contains("9 rep.") && conflict.summary.contains("11 rep."))
        }
    }

    @Test("Series nuevas en la copia se añaden; las que solo tiene este iPhone se conservan")
    func addedSetsBothSides() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18))
        let (source, repo, session, draft) = try sourceWithDraft(clock)
        clock.advance(60)
        repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(draft)
        let base = try export(source, tmp, "base.arcobk")

        let device = try inMemoryContext()
        try restore(device, base)
        let deviceSE = try #require(try device.fetch(FetchDescriptor<SessionExerciseModel>()).first)
        let localRepo = WorkoutRepository(context: device, now: { clock.now.addingTimeInterval(500) })
        let localNew = localRepo.addDraft(to: deviceSE)[0]
        localRepo.updateDraft(localNew, amount: 14, unit: .kilograms, reps: 8, type: .working, side: .bilateral, rir: .unknown)
        try localRepo.confirm(localNew)

        clock.advance(60)
        let se = try #require(session.exercises.first)
        let remoteNew = repo.addDraft(to: se)[0]
        repo.updateDraft(remoteNew, amount: 12, unit: .kilograms, reps: 9, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(remoteNew)
        let newer = try export(source, tmp, "newer.arcobk")

        let report = try restore(device, newer)
        #expect(try setRow(device, remoteNew.id).reps == 9)
        #expect(try setRow(device, localNew.id).reps == 8)
        #expect(report.inserted["sets"] == 1 && report.onlyOnDevice["sets"] == 1)
    }

    @Test("Si la copia cerró la sesión: se adopta el cierre y se descartan los borradores locales, sin duplicar asistencia")
    func archiveFinishedSession() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18))
        let (source, repo, session, draft) = try sourceWithDraft(clock)
        let open = try export(source, tmp, "open.arcobk")
        clock.advance(60)
        repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(draft)
        repo.finish(session)
        let closed = try export(source, tmp, "closed.arcobk")

        let device = try inMemoryContext()
        try restore(device, open)
        let report = try restore(device, closed)
        let restored = try #require(try device.fetch(FetchDescriptor<WorkoutSessionModel>()).first)
        #expect(Set(["finished", "partial"]).contains(restored.stateRaw))
        #expect(restored.exercises.flatMap(\.sets).allSatisfy { $0.stateRaw != "pending" })
        #expect(report.updated["sessions"] == 1)
        #expect(try count(device, AttendanceEventModel.self) == 1)
    }

    @Test("Borradores de la copia no se añaden a una sesión ya cerrada aquí")
    func draftsNotAddedToClosedSession() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18))
        let (source, sourceRepo, sourceSession, _) = try sourceWithDraft(clock)
        sourceRepo.addDraft(to: try #require(sourceSession.exercises.first))     // segundo borrador
        let open = try export(source, tmp, "open.arcobk")
        let device = try inMemoryContext()
        try restore(device, open)
        let local = try #require(try device.fetch(FetchDescriptor<WorkoutSessionModel>()).first)
        let localRepo = WorkoutRepository(context: device, now: { clock.now.addingTimeInterval(30) })
        let d = try #require(local.exercises.first?.sets.first)
        localRepo.updateDraft(d, amount: 10, unit: .kilograms, reps: 12, type: .working, side: .bilateral, rir: .unknown)
        try localRepo.confirm(d)
        localRepo.finish(local)                    // descarta aquí el segundo borrador
        #expect(try device.fetch(FetchDescriptor<SetRecordModel>()).filter { $0.stateRaw == "pending" }.isEmpty)

        let report = try restore(device, open)
        #expect(try device.fetch(FetchDescriptor<SetRecordModel>()).filter { $0.stateRaw == "pending" }.isEmpty)
        #expect(report.skippedDrafts == 1 && report.conflicts.isEmpty)
        #expect(report.keptDevice["sets"] == 1 && report.keptDevice["sessions"] == 1)
        #expect(try setRow(device, d.id).stateRaw == "completed")
    }

    @Test("Borrado en un lado: una serie eliminada aquí no revive al combinar; reemplazar deja exactamente la copia")
    func deletionsAndReplace() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18))
        let (source, repo, session, draft) = try sourceWithDraft(clock)
        clock.advance(60)
        repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(draft)
        repo.finish(session)
        source.insert(BodyWeightModel(measurementDate: date(2026, 11, 1), enteredAt: date(2026, 11, 1), amount: 70, unitRaw: "kg", isEstimated: false))
        try source.save()
        let file = try export(source, tmp, "f.arcobk")

        let device = try inMemoryContext()
        try restore(device, file)
        WorkoutRepository(context: device).delete(try setRow(device, draft.id))       // borrado lógico local
        let extra = WorkoutRepository(context: device).startSession(trainingDate: date(2026, 11, 3), timeZone: .current, templateID: nil, exerciseIDs: [])
        device.insert(HeightModel(date: date(2026, 11, 3), amount: 180, unitRaw: "cm"))
        try device.save()

        // Combinar: la serie sigue eliminada (conflicto conservando este iPhone) y lo local se queda.
        let merged = try restore(device, file)
        #expect(try setRow(device, draft.id).stateRaw == "deleted")
        #expect(merged.conflicts.contains { $0.category == "sets" && $0.resolution == .keptDevice })
        #expect(merged.onlyOnDevice["sessions"] == 1 && merged.onlyOnDevice["heights"] == 1)

        // La previsión del reemplazo dice lo que se eliminará; aplicarlo coincide con la previsión.
        let preview = try ArchiveImporter(context: device, photos: nil).preview(url: file, password: pw)
        let plan = try #require(preview.plans[.replace])
        #expect(plan.removed["sessions"] == 1 && plan.removed["heights"] == 1)
        #expect(try count(device, WorkoutSessionModel.self) == 2)                    // la previsión no modifica
        let replaced = try restore(device, file, .replace)
        #expect(replaced.removed == plan.removed)
        #expect(try setRow(device, draft.id).stateRaw == "completed")
        #expect(try device.fetch(FetchDescriptor<WorkoutSessionModel>()).map(\.id) == [session.id])
        #expect(!(try device.fetch(FetchDescriptor<WorkoutSessionModel>()).contains { $0.id == extra.id }))
        #expect(try count(device, HeightModel.self) == 0)
        #expect(try count(device, BodyWeightModel.self) == 1)
    }

    @Test("Reemplazar nunca borra fotos de este iPhone y limpia vínculos a pesajes eliminados")
    func replaceKeepsPhotos() throws {
        let tmp = TempDir()
        let file = try export(try inMemoryContext(), tmp, "empty.arcobk")
        let device = try inMemoryContext()
        let store = TestPhotoStore(dir: tmp.url.appendingPathComponent("vault"))
        let weight = BodyWeightModel(measurementDate: date(2026, 11, 1), enteredAt: date(2026, 11, 1), amount: 70, unitRaw: "kg", isEstimated: false)
        device.insert(weight)
        try store.writePhoto(Data("foto".utf8), named: "p.enc")
        let photo = PhotoCheckInModel(date: date(2026, 11, 1), poseRaw: "frontRelaxed", encryptedFileName: "p.enc", bodyWeightID: weight.id)
        device.insert(photo)
        weight.photoCheckInID = photo.id
        try device.save()
        let report = try restore(device, file, .replace, photos: store)
        #expect(try count(device, PhotoCheckInModel.self) == 1 && store.fileCount == 1)
        #expect(report.onlyOnDevice["photos"] == 1 && report.removed["photos"] == nil)
        #expect(try device.fetch(FetchDescriptor<PhotoCheckInModel>()).first?.bodyWeightID == nil)
    }

    @Test("Cada lado con su propia asistencia automática de la misma sesión: no se duplica el día")
    func attendanceNotDuplicated() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18))
        let (source, repo, _, draft) = try sourceWithDraft(clock)
        let base = try export(source, tmp, "base.arcobk")
        let device = try inMemoryContext()
        try restore(device, base)
        let local = WorkoutRepository(context: device, now: { clock.now.addingTimeInterval(30) })
        let d = try setRow(device, draft.id)
        local.updateDraft(d, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try local.confirm(d)
        clock.advance(90)
        repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(draft)
        let newer = try export(source, tmp, "newer.arcobk")
        try restore(device, newer, .mergePreferArchive)
        #expect(try count(device, AttendanceEventModel.self) == 1)
        #expect(AttendanceRepository(context: device).attendedDays().count == 1)
    }

    // MARK: 3. Compatibilidad, errores y transacción

    @Test("Copias anteriores (fechas en segundos, sin campos v3) se siguen restaurando y comparando bien")
    func legacyFormatCompatibility() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18).addingTimeInterval(0.4))
        let (source, repo, session, draft) = try sourceWithDraft(clock)
        clock.advance(60)
        repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(draft)
        repo.finish(session)
        try exercise(source, "curl_hammer").archived = true
        try source.save()

        var payload = ArchiveExporter(context: source, photos: nil).payload(includePhotos: false)
        payload.datePrecision = nil
        payload.progressionRules = nil
        payload.planVersions = nil
        payload.customAttributions = nil
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601                         // formato anterior
        let url = tmp.url.appendingPathComponent("legacy.arcobk")
        let manifest = ArchiveManifest(version: PortableArchive.formatVersion, createdAt: payload.exportedAt, includesPhotos: false, counts: payload.counts)
        let writer = try PortableArchiveWriter(url: url, password: pw, manifest: manifest, chunkCount: 1)
        try writer.append(try encoder.encode(payload))
        try writer.finish()

        let clean = try inMemoryContext()
        let first = try restore(clean, url)
        #expect(first.inserted["sessions"] == 1)
        #expect(try setRow(clean, draft.id).reps == 10)
        #expect(try exercise(clean, "curl_hammer").archived)
        // Sobre el propio origen (fechas con fracción de segundo) no aparecen conflictos falsos.
        let own = try restore(source, url)
        #expect(own.conflicts.isEmpty && own.updated.isEmpty)
    }

    @Test("Un fallo al guardar a mitad de restauración no deja datos ni fotos a medias")
    func failureRollsBack() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18))
        let (source, repo, _, draft) = try sourceWithDraft(clock)
        let storeA = TestPhotoStore(dir: tmp.url.appendingPathComponent("a"))
        let base = try export(source, tmp, "base.arcobk", photos: storeA)
        clock.advance(60)
        repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(draft)
        try storeA.writePhoto(Data("nueva".utf8), named: "n.enc")
        source.insert(PhotoCheckInModel(date: date(2026, 11, 2), poseRaw: "side", encryptedFileName: "n.enc"))
        try exercise(source, "curl_hammer").name = "Otro nombre"
        try source.save()
        let newer = try export(source, tmp, "newer.arcobk", photos: storeA)

        let device = try inMemoryContext()
        let storeB = TestPhotoStore(dir: tmp.url.appendingPathComponent("b"))
        try restore(device, base, photos: storeB)
        let files = storeB.fileCount
        let failing = ArchiveImporter(context: device, photos: storeB, saver: { _ in throw InjectedFailure() })
        #expect(throws: InjectedFailure.self) {
            try failing.restore(url: newer, password: pw, replaceProfileAndSettings: true, strategy: .replace)
        }
        #expect(try setRow(device, draft.id).stateRaw == "pending")
        #expect(try exercise(device, "curl_hammer").name == ExerciseNames.localized("curl_hammer"))
        #expect(try count(device, PhotoCheckInModel.self) == 0)
        #expect(storeB.fileCount == files)
        // Contraseña incorrecta sobre datos existentes: nada cambia.
        #expect(throws: BackupError.invalidPassword) {
            try ArchiveImporter(context: device, photos: storeB).restore(url: newer, password: "incorrecta-123", replaceProfileAndSettings: true, strategy: .replace)
        }
        #expect(try setRow(device, draft.id).stateRaw == "pending")
        #expect(storeB.fileCount == files)
    }

    @Test("La previsión no modifica nada y coincide con el resultado de restaurar")
    func previewMatchesRestore() throws {
        let tmp = TempDir()
        let clock = TestClock(date(2026, 11, 2, 18))
        let (source, repo, _, draft) = try sourceWithDraft(clock)
        let old = try export(source, tmp, "old.arcobk")
        clock.advance(60)
        repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .unknown)
        try repo.confirm(draft)
        let new = try export(source, tmp, "new.arcobk")
        let device = try inMemoryContext()
        try restore(device, old)
        let preview = try ArchiveImporter(context: device, photos: nil).preview(url: new, password: pw)
        #expect(try setRow(device, draft.id).stateRaw == "pending")
        let result = try restore(device, new)
        #expect(preview.plans[.mergeKeepDevice] == result)
    }
}
