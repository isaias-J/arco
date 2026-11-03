import Testing
import SwiftData
import Foundation
@testable import ArcoCore

/// Pruebas de integración sobre SwiftData real (en memoria o en disco aislado).
@MainActor
@Suite("Integración: registro de entrenamiento y persistencia", .serialized)
struct RepositoryIntegrationTests {

    private func memory() throws -> ModelContext { try inMemoryContext() }

    private func load(_ kg: Decimal, _ c: LoadConvention = .externalTotal) -> Load {
        Load(amount: kg, unit: .kilograms, convention: c)
    }

    @Test("Seed: 27 ejercicios y rutina con jueves y domingo de descanso")
    func seedAndWeekdays() throws {
        let ctx = try memory()
        #expect(try ctx.fetch(FetchDescriptor<ExerciseModel>()).count == 27)
        let plan = PersistenceController.weeklyPlan(ctx)
        let cal = testCalendar()
        // Semana del 2 al 8 de noviembre de 2026 (lunes a domingo).
        let expected: [(Int, Bool)] = [(2, true), (3, true), (4, true), (5, false), (6, true), (7, true), (8, false)]
        for (day, training) in expected {
            let d = date(2026, 11, day, calendar: cal)
            #expect(plan.isPlannedTraining(d, calendar: cal) == training, "día \(day)")
            #expect(plan.isPlannedRest(d, calendar: cal) == !training, "día \(day)")
        }
        #expect(plan.day(for: .monday)?.groups == [.chest, .shoulders, .triceps])
        #expect(plan.day(for: .friday)?.groups.contains(.forearm) == true)
    }

    @Test("Seed idempotente: no duplica ni pisa ejercicios renombrados")
    func seedIdempotent() throws {
        let ctx = try memory()
        let ex = try ctx.fetch(FetchDescriptor<ExerciseModel>()).first { $0.id == "curl_hammer" }!
        ex.name = "Martillo en cuerda"
        PersistenceController.seedIfNeeded(ctx)
        let all = try ctx.fetch(FetchDescriptor<ExerciseModel>())
        #expect(all.count == 27)
        #expect(all.first { $0.id == "curl_hammer" }?.name == "Martillo en cuerda")
    }

    @Test("T01: la sesión precargada no tiene series realizadas hasta confirmar")
    func draftsAreNotDone() throws {
        let ctx = try memory()
        let repo = WorkoutRepository(context: ctx)
        let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: "mon_push", exerciseIDs: ["chest_flat_barbell"])
        let sets = repo.allDomainSets(in: s)
        #expect(!sets.isEmpty)                                      // hay borrador
        #expect(sets.allSatisfy { $0.state == .pending })
        #expect(!sets.contains { $0.isEligibleForWorkCount })
        #expect(try ctx.fetch(FetchDescriptor<AttendanceEventModel>()).isEmpty)
    }

    @Test("Precarga desde la última sesión comparable (misma variante y convención)")
    func prefillFromPrevious() throws {
        let ctx = try memory()
        let clock = TestClock(date(2026, 11, 2, 18))
        let repo = WorkoutRepository(context: ctx, now: { clock.now })
        let s1 = repo.startSession(trainingDate: clock.now, timeZone: .current, templateID: nil, exerciseIDs: ["chest_flat_barbell"])
        let se1 = s1.exercises[0]
        let d1 = se1.sets[0]
        repo.updateDraft(d1, amount: 60, unit: .kilograms, reps: 8, type: .working, side: .bilateral, rir: .exact(2))
        try repo.confirm(d1)
        let d2 = repo.addDraft(to: se1)[0]
        repo.updateDraft(d2, amount: 60, unit: .kilograms, reps: 7, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(d2)
        // Otra variante del mismo ejercicio no debe usarse como comparable.
        repo.finish(s1)

        clock.advance(3600 * 24 * 2)
        let s2 = repo.startSession(trainingDate: clock.now, timeZone: .current, templateID: nil, exerciseIDs: ["chest_flat_barbell"])
        let drafts = repo.orderedSets(s2.exercises[0])
        #expect(drafts.count == 2)
        #expect(drafts.map(\.loadAmount) == [60, 60])
        #expect(drafts.map(\.reps) == [8, 7])
        #expect(drafts.allSatisfy { $0.stateRaw == SetState.pending.rawValue })
        #expect(drafts.allSatisfy { $0.rirKind == "none" })          // el RIR no se copia

        let previous = repo.previousComparable(exerciseID: "chest_flat_barbell", variantKey: "agarre cerrado", excluding: s2)
        #expect(previous == nil)                                      // T25: variante distinta
    }

    @Test("T02/T04: confirmar dos veces no duplica; un fallo de guardado conserva el borrador y el reintento no duplica")
    func confirmIdempotentAndFailure() throws {
        let ctx = try memory()
        var failNext = false
        let repo = WorkoutRepository(context: ctx, saver: { c in
            if failNext { failNext = false; throw CocoaError(.fileWriteUnknown) }
            try c.save()
        })
        let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["triceps_pushdown"])
        let draft = s.exercises[0].sets[0]
        repo.updateDraft(draft, amount: 25, unit: .kilograms, reps: 12, type: .working, side: .bilateral, rir: nil)

        failNext = true
        #expect(throws: RepositoryError.saveFailed) { try repo.confirm(draft) }
        #expect(draft.stateRaw == SetState.pending.rawValue)          // sin guardado falso
        #expect(draft.loadAmount == 25 && draft.reps == 12)            // borrador intacto

        try repo.confirm(draft)                                        // reintento
        try repo.confirm(draft)                                        // callback repetido
        let completed = s.exercises[0].sets.filter { $0.stateRaw == SetState.completed.rawValue }
        #expect(completed.count == 1)
        #expect(try ctx.fetch(FetchDescriptor<SetRecordModel>()).count == 1)
    }

    @Test("T03: cerrar y reabrir la base en disco recupera sesión, series y borradores")
    func persistsOnDisk() throws {
        let tmp = TempDir()
        let url = tmp.url.appendingPathComponent("arco.store")
        var sessionID: UUID?
        do {
            let container = try diskContainer(url)
            let repo = WorkoutRepository(context: container.mainContext)
            let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["back_pulldown"])
            let d = s.exercises[0].sets[0]
            repo.updateDraft(d, amount: 50, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: nil)
            try repo.confirm(d)
            let next = repo.addDraft(to: s.exercises[0])[0]
            repo.updateDraft(next, amount: 52.5, unit: .kilograms, reps: 8, type: .working, side: .bilateral, rir: nil)
            sessionID = s.id
        }
        let reopened = try diskContainer(url)
        let repo = WorkoutRepository(context: reopened.mainContext)
        let active = try #require(repo.activeSession())
        #expect(active.id == sessionID)
        let sets = repo.orderedSets(active.exercises[0])
        #expect(sets.map(\.stateRaw) == [SetState.completed.rawValue, SetState.pending.rawValue])
        #expect(sets.last?.loadAmount == Decimal(string: "52.5"))
        // No se inicia otra sesión automáticamente.
        #expect(repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil).id == sessionID)
    }

    @Test("T05/T29: editar o borrar una serie recalcula récord y gráfica")
    func editRecalculates() throws {
        let ctx = try memory()
        let repo = WorkoutRepository(context: ctx)
        let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["legs_extension"])
        let se = s.exercises[0]
        let a = se.sets[0]
        repo.updateDraft(a, amount: 50, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(a)
        let b = repo.addDraft(to: se)[0]
        repo.updateDraft(b, amount: 70, unit: .kilograms, reps: 6, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(b)
        #expect(RecordsEngine.maxLoadRecord(from: se.sets.map { $0.toDomain() })?.loadKilograms == 70)

        try repo.edit(b, amount: 55, unit: .kilograms, convention: .machineNominal, reps: 6, type: .working, side: .bilateral, rir: .atLeast(4))
        #expect(RecordsEngine.maxLoadRecord(from: se.sets.map { $0.toDomain() })?.loadKilograms == 55)
        #expect(b.toDomain().rir == .atLeast(4))

        let previous = repo.delete(b)
        #expect(RecordsEngine.maxLoadRecord(from: se.sets.map { $0.toDomain() })?.loadKilograms == 50)
        let point = ChartAnalytics.maxLoadPerSession([(date: s.trainingDate, sets: se.sets.map { $0.toDomain() })]).first
        #expect(point?.value == 50)
        repo.undoDelete(b, previous: previous)
        #expect(RecordsEngine.maxLoadRecord(from: se.sets.map { $0.toDomain() })?.loadKilograms == 55)
    }

    @Test("T06: cambiar la plantilla no altera la sesión histórica")
    func templateChangeKeepsHistory() throws {
        let ctx = try memory()
        let repo = WorkoutRepository(context: ctx)
        let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: "mon_push", exerciseIDs: ["chest_pecdeck"])
        let d = s.exercises[0].sets[0]
        repo.updateDraft(d, amount: 40, unit: .kilograms, reps: 12, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(d)
        repo.finish(s)
        let t = try ctx.fetch(FetchDescriptor<RoutineTemplateModel>()).first { $0.id == "mon_push" }!
        t.groupsJoined = "legs"
        t.preferredExerciseIDsJoined = "legs_extension"
        try ctx.save()
        #expect(s.exercises.map(\.exerciseID) == ["chest_pecdeck"])
        #expect(s.exercises[0].sets[0].loadAmount == 40)
    }

    @Test("T07/T34: calentamiento no crea asistencia; la primera serie de trabajo sí")
    func warmupAndAttendance() throws {
        let ctx = try memory()
        let repo = WorkoutRepository(context: ctx)
        let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["chest_flat_barbell"])
        let w = s.exercises[0].sets[0]
        repo.updateDraft(w, amount: 20, unit: .kilograms, reps: 10, type: .warmup, side: .bilateral, rir: nil)
        try repo.confirm(w)
        #expect(try ctx.fetch(FetchDescriptor<AttendanceEventModel>()).isEmpty)
        let counted = MuscleCounter.countByMuscle(s.exercises.flatMap { se in
            se.sets.filter { $0.toDomain().isEligibleForWorkCount }.map { AttributedSet(setID: $0.id, exerciseID: se.exerciseID, side: .bilateral, ruleSet: ExerciseCatalog.ruleSet(for: se.exerciseID)!) }
        })
        #expect(counted[.pectoral] == nil)

        let work = repo.addDraft(to: s.exercises[0])[0]
        repo.updateDraft(work, amount: 60, unit: .kilograms, reps: 8, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(work)
        let events = try ctx.fetch(FetchDescriptor<AttendanceEventModel>())
        #expect(events.count == 1 && events[0].sourceRaw == "automatic")
    }

    @Test("T36: finalizar con borradores pendientes marca la sesión parcial y conserva la asistencia")
    func partialSession() throws {
        let ctx = try memory()
        let repo = WorkoutRepository(context: ctx)
        let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["back_pulldown", "curl_preacher"])
        let d = s.exercises[0].sets[0]
        repo.updateDraft(d, amount: 45, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(d)
        let summary = repo.finish(s)
        #expect(summary.isPartial)
        #expect(summary.workingSets == 1)
        #expect(summary.exerciseIDs == ["back_pulldown"])
        #expect(s.stateRaw == "partial")
        #expect(!s.exercises.flatMap(\.sets).contains { $0.stateRaw == SetState.pending.rawValue })
        let events = try ctx.fetch(FetchDescriptor<AttendanceEventModel>())
        #expect(events.count == 1 && events[0].isPartial)
    }

    @Test("T35/T37: varias sesiones y 'Sí fui' el mismo día = un día; borrar la serie conserva la confirmación manual")
    func attendanceConsolidation() throws {
        let ctx = try memory()
        let cal = Calendar.current
        let repo = WorkoutRepository(context: ctx)
        let attendance = AttendanceRepository(context: ctx, calendar: cal)
        let today = CivilDay(Date(), calendar: cal)

        let s1 = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["legs_extension"])
        let d1 = s1.exercises[0].sets[0]
        repo.updateDraft(d1, amount: 40, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(d1)
        repo.finish(s1)
        let s2 = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["legs_seated_curl"])
        let d2 = s2.exercises[0].sets[0]
        repo.updateDraft(d2, amount: 30, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(d2)
        attendance.markAttended(today)
        attendance.markAttended(today)          // idempotente

        let events = try ctx.fetch(FetchDescriptor<AttendanceEventModel>())
        #expect(events.count == 3)              // 2 automáticas + 1 manual
        let days = AttendanceEngine.consolidate(events: events.map { (date: $0.trainingDate, source: AttendanceSource(rawValue: $0.sourceRaw)!, partial: $0.isPartial) }, calendar: cal)
        #expect(days.count == 1)

        repo.delete(d2)
        let remaining = try ctx.fetch(FetchDescriptor<AttendanceEventModel>())
        #expect(remaining.contains { $0.sourceRaw == "manual" })
        #expect(remaining.filter { $0.sessionID == s2.id }.isEmpty)
        #expect(attendance.attendedDays().contains(today))
    }

    @Test("'Hoy descansé' guarda un descanso puntual confirmado; 'Sí fui' lo sustituye")
    func restResolution() throws {
        let ctx = try memory()
        let cal = testCalendar()
        let attendance = AttendanceRepository(context: ctx, calendar: cal)
        let plan = PersistenceController.weeklyPlan(ctx)
        let monday = CivilDay(year: 2026, month: 11, day: 2)
        let today = CivilDay(year: 2026, month: 11, day: 3)
        #expect(attendance.state(of: monday, plan: plan, today: today) == .plannedUnconfirmed)
        attendance.markResolution(.rest, on: monday)
        attendance.markResolution(.rest, on: monday)
        #expect(try ctx.fetch(FetchDescriptor<AttendanceResolutionModel>()).count == 1)
        #expect(attendance.state(of: monday, plan: plan, today: today) == .confirmedRest)
        attendance.markAttended(monday)
        #expect(try ctx.fetch(FetchDescriptor<AttendanceResolutionModel>()).isEmpty)
        let manual = Set([monday])
        #expect(attendance.state(of: monday, plan: plan, today: today, manualDays: manual) == .manualAttendance)
        // Jueves y domingo: descanso planificado, nunca ausencia por falta de datos.
        #expect(attendance.state(of: CivilDay(year: 2026, month: 11, day: 5), plan: plan, today: CivilDay(year: 2026, month: 11, day: 9)) == .plannedRest)
        #expect(attendance.state(of: CivilDay(year: 2026, month: 11, day: 8), plan: plan, today: CivilDay(year: 2026, month: 11, day: 9)) == .plannedRest)
        #expect(attendance.state(of: CivilDay(year: 2026, month: 11, day: 20), plan: plan, today: today) == .future)
    }

    @Test("T12/T13: tres pares por lados cuentan 3 en el músculo y 3 por lado; un solo lado no imputa el otro")
    func unilateralThroughRepository() throws {
        let ctx = try memory()
        let repo = WorkoutRepository(context: ctx)
        let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["curl_dumbbell"])
        let se = s.exercises[0]
        repo.setSideMode(.perSide, for: se)
        #expect(se.sets.map(\.sideRaw).sorted() == ["left", "right"])
        for _ in 0..<2 { repo.addDraft(to: se) }
        for draft in repo.orderedSets(se) {
            repo.updateDraft(draft, amount: 12, unit: .kilograms, reps: 10, type: .working, side: BodySide(rawValue: draft.sideRaw)!, rir: nil)
            try repo.confirm(draft)
        }
        let rules = ExerciseCatalog.ruleSet(for: "curl_dumbbell")!
        let attributed = se.sets.map { AttributedSet(setID: $0.id, exerciseID: se.exerciseID, side: BodySide(rawValue: $0.sideRaw)!, ruleSet: rules, pairingKey: se.id.uuidString) }
        #expect(MuscleCounter.countByMuscle(attributed)[.elbowFlexors]?.direct == 3)
        #expect(MuscleCounter.countByGroup(attributed)[.biceps]?.direct == 3)
        #expect(MuscleCounter.countByMuscle(attributed, side: .left)[.elbowFlexors]?.direct == 3)
        #expect(MuscleCounter.countByMuscle(attributed, side: .right)[.elbowFlexors]?.direct == 3)
        #expect(repo.convention(for: "curl_dumbbell") == .perDumbbell)   // T24
        // Solo izquierda: 2 series → 2, y el lado derecho queda sin registro.
        let onlyLeft = attributed.filter { $0.side == .left }.prefix(2)
        #expect(MuscleCounter.countByMuscle(Array(onlyLeft))[.elbowFlexors]?.direct == 2)
        #expect(MuscleCounter.countByMuscle(Array(onlyLeft), side: .right)[.elbowFlexors] == nil)
    }

    @Test("Quitar un ejercicio con series realizadas no borra ese trabajo")
    func removeExerciseKeepsWork() throws {
        let ctx = try memory()
        let repo = WorkoutRepository(context: ctx)
        let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["abs_machine_crunch", "abs_leg_raise"])
        let crunch = s.exercises.first { $0.exerciseID == "abs_machine_crunch" }!
        let d = crunch.sets[0]
        repo.updateDraft(d, amount: 30, unit: .kilograms, reps: 15, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(d)
        #expect(repo.removeExercise(crunch) == false)
        let raise = s.exercises.first { $0.exerciseID == "abs_leg_raise" }!
        #expect(repo.removeExercise(raise) == true)
        #expect(s.exercises.map(\.exerciseID) == ["abs_machine_crunch"])
    }

    @Test("T73: una base creada con el esquema v1 se abre con v2 y conserva los datos")
    func migrationFromV1() throws {
        let tmp = TempDir()
        let url = tmp.url.appendingPathComponent("v1.store")
        do {
            let v1 = Schema(versionedSchema: ArcoSchemaV1.self)
            let c = try ModelContainer(for: v1, configurations: [ModelConfiguration(schema: v1, url: url, cloudKitDatabase: .none)])
            retainedContainers.append(c)
            let ctx = c.mainContext
            let session = WorkoutSessionModel(startedAt: Date(), trainingDate: Date(), originTimeZoneID: "Europe/Madrid")
            ctx.insert(session)
            let se = SessionExerciseModel(exerciseID: "chest_flat_barbell", order: 0)
            ctx.insert(se); se.session = session; session.exercises.append(se)
            let set = SetRecordModel(loadAmount: 60, loadUnitRaw: "kg", loadConventionRaw: "externalTotal", reps: 8, typeRaw: "working", stateRaw: "completed", sideRaw: "bilateral", performedAt: Date())
            ctx.insert(set); set.sessionExercise = se; se.sets.append(set)
            ctx.insert(BodyWeightModel(measurementDate: Date(), enteredAt: Date(), amount: 71, unitRaw: "kg", isEstimated: false))
            try ctx.save()
        }
        let migrated = try diskContainer(url)
        let ctx = migrated.mainContext
        let sessions = try ctx.fetch(FetchDescriptor<WorkoutSessionModel>())
        #expect(sessions.count == 1)
        #expect(sessions[0].exercises.first?.sets.first?.loadAmount == 60)
        #expect(try ctx.fetch(FetchDescriptor<BodyWeightModel>()).first?.amount == 71)
        // Las entidades nuevas de v2 funcionan sobre la base migrada.
        ctx.insert(AttendanceResolutionModel(dayKey: "2026-11-05", kindRaw: "rest"))
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<AttendanceResolutionModel>()).count == 1)
    }

    @Test("La base y sus auxiliares quedan excluidos de la copia automática")
    func storeExcludedFromBackup() throws {
        let tmp = TempDir()
        let url = tmp.url.appendingPathComponent("arco.store")
        let c = try diskContainer(url)
        try c.mainContext.save()
        try BackupExclusion.apply(toStoreAt: url)
        #expect(BackupExclusion.isExcluded(url))
        for suffix in ["-wal", "-shm"] {
            let aux = URL(fileURLWithPath: url.path + suffix)
            if FileManager.default.fileExists(atPath: aux.path) {
                #expect(BackupExclusion.isExcluded(aux), "\(suffix)")
            }
        }
    }
}
