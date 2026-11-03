import Testing
import SwiftData
import Foundation
@testable import ArcoCore

/// Etapas de cierre (SEGUIMIENTO/08-ETAPAS.md): catálogo, rutina con historial, constancia,
/// sustitución y orden en sesión, doble progresión y resumen semanal.
@MainActor
@Suite("Etapas de cierre", .serialized)
struct StageClosureTests {
    let cal = testCalendar()

    // MARK: Etapa 1 — esquema v3

    @Test("Una base v2 se abre con v3 y conserva datos")
    func migrationV2toV3() throws {
        let tmp = TempDir()
        let url = tmp.url.appendingPathComponent("v2.store")
        do {
            let v2 = Schema(versionedSchema: ArcoSchemaV2.self)
            let c = try ModelContainer(for: v2, configurations: [ModelConfiguration(schema: v2, url: url, cloudKitDatabase: .none)])
            retainedContainers.append(c)
            c.mainContext.insert(AttendanceResolutionModel(dayKey: "2026-11-05", kindRaw: "rest"))
            c.mainContext.insert(BodyWeightModel(measurementDate: Date(), enteredAt: Date(), amount: 72, unitRaw: "kg", isEstimated: false))
            try c.mainContext.save()
        }
        let ctx = try diskContainer(url).mainContext
        #expect(try ctx.fetch(FetchDescriptor<AttendanceResolutionModel>()).count == 1)
        #expect(try ctx.fetch(FetchDescriptor<BodyWeightModel>()).first?.amount == 72)
        ctx.insert(DoubleProgressionModel(exerciseID: "x", repLower: 8, repUpper: 12, referenceSets: 3, increment: 2, unitRaw: "kg"))
        try ctx.save()
        #expect(try ctx.fetch(FetchDescriptor<DoubleProgressionModel>()).count == 1)
    }

    // MARK: Etapa 2 — catálogo

    @Test("Renombrar, alias y archivar no pierden registros")
    func catalogEdits() throws {
        let ctx = try inMemoryContext()
        let repo = WorkoutRepository(context: ctx)
        let catalog = CatalogRepository(context: ctx)
        let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["curl_hammer"])
        let d = s.exercises[0].sets[0]
        repo.updateDraft(d, amount: 14, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(d)

        try catalog.rename("curl_hammer", to: "  Martillo en cuerda ")
        try catalog.setAliases("curl_hammer", ["martillo", " Martillo ", "", "cuerda"])
        try catalog.setArchived("curl_hammer", true)
        let ex = try ctx.fetch(FetchDescriptor<ExerciseModel>()).first { $0.id == "curl_hammer" }!
        #expect(ex.name == "Martillo en cuerda")
        #expect(ex.aliasesJoined == "martillo\ncuerda")
        #expect(ex.archived)
        #expect(s.exercises[0].sets.first { $0.stateRaw == "completed" }?.loadAmount == 14)
        #expect(throws: CatalogRepository.CatalogError.duplicateName) { try catalog.rename("curl_reverse", to: "martillo EN cuerda") }
        #expect(throws: CatalogRepository.CatalogError.emptyName) { try catalog.rename("curl_reverse", to: "   ") }
    }

    @Test("Atribución personalizada: se usa en el conteo y queda marcada como personalización")
    func customAttribution() throws {
        let ctx = try inMemoryContext()
        let catalog = CatalogRepository(context: ctx)
        ctx.insert(ExerciseModel(id: "custom_x", name: "Hip thrust", loadTypeRaw: "machine", patternRaw: "isolationOther", originRaw: "custom", instructions: ""))
        try ctx.save()
        #expect(AttributionResolver.ruleSet(for: "custom_x", custom: AttributionResolver.customRuleSets(ctx)) == nil)  // T17
        try catalog.setCustomAttribution("custom_x", [.glutes: .direct, .hamstrings: .indirect])
        let custom = AttributionResolver.customRuleSets(ctx)
        let rules = try #require(AttributionResolver.ruleSet(for: "custom_x", custom: custom))
        #expect(rules.userCustomized)
        let counts = MuscleCounter.countByMuscle([AttributedSet(setID: UUID(), exerciseID: "custom_x", side: .bilateral, ruleSet: rules)])
        #expect(counts[.glutes]?.direct == 1 && counts[.hamstrings]?.indirect == 1)
        try catalog.setCustomAttribution("custom_x", [:])
        #expect(AttributionResolver.customRuleSets(ctx).isEmpty)
    }

    // MARK: Etapa 3 — rutina con historial y constancia

    @Test("T39: cambiar la rutina hoy no altera la adherencia de semanas anteriores")
    func planHistoryAdherence() throws {
        let ctx = try inMemoryContext()
        let catalog = CatalogRepository(context: ctx)
        catalog.ensureInitialPlanVersion(now: date(2026, 10, 1, calendar: cal), calendar: cal)
        let oct = CivilDay(year: 2026, month: 10, day: 26)      // lunes
        let octEnd = CivilDay(year: 2026, month: 11, day: 1)    // domingo
        let today = CivilDay(year: 2026, month: 11, day: 9)
        let before = Constancy.adherence(history: catalog.planHistory(), from: oct, to: octEnd, today: today, attended: [], completedSessions: [], calendar: cal)
        #expect(before.plannedDays == 5)

        // Desde el 9 de noviembre: solo 3 días de entrenamiento.
        var days = WeeklyPlan.ownerDefault.days
        days = days.map { d in [.tuesday, .saturday].contains(d.weekday) ? .init(weekday: d.weekday, isRest: true, groups: []) : d }
        try catalog.updatePlan(WeeklyPlan(days: days), effective: date(2026, 11, 9, calendar: cal), calendar: cal)

        let history = catalog.planHistory()
        let after = Constancy.adherence(history: history, from: oct, to: octEnd, today: today, attended: [], completedSessions: [], calendar: cal)
        #expect(after.plannedDays == 5)                                    // el pasado no cambia
        let nextWeek = Constancy.adherence(history: history, from: today, to: CivilDay(year: 2026, month: 11, day: 15), today: CivilDay(year: 2026, month: 11, day: 15), attended: [], completedSessions: [], calendar: cal)
        #expect(nextWeek.plannedDays == 3)
        // Las plantillas reflejan el plan vigente.
        let tue = try ctx.fetch(FetchDescriptor<RoutineTemplateModel>()).first { $0.weekday == Weekday.tuesday.rawValue }
        #expect(tue?.isRestDay == true)
        // Un segundo cambio el mismo día no apila versiones.
        try catalog.updatePlan(WeeklyPlan.ownerDefault, effective: date(2026, 11, 9, 18, calendar: cal), calendar: cal)
        #expect(try ctx.fetch(FetchDescriptor<PlanVersionModel>()).count == 2)
    }

    @Test("Días anteriores al inicio del seguimiento: no cuentan como planificados ni como 'sin registro'")
    func beforeTrackingStartIsNeutral() throws {
        let ctx = try inMemoryContext()
        let catalog = CatalogRepository(context: ctx)
        // Empieza a usar Arco el martes 3 de noviembre; el lunes 2 era día de entrenamiento.
        catalog.ensureInitialPlanVersion(now: date(2026, 11, 3, 9, calendar: cal), calendar: cal)
        let history = catalog.planHistory()
        let monday = CivilDay(year: 2026, month: 11, day: 2)
        let tuesday = CivilDay(year: 2026, month: 11, day: 3)
        let week = Constancy.adherence(history: history, from: monday, to: CivilDay(year: 2026, month: 11, day: 8), today: tuesday, attended: [], completedSessions: [], calendar: cal)
        #expect(week.plannedDays == 1)   // solo el martes, no el lunes previo a usar la app
        let mondayDate = try #require(monday.startDate(in: cal))
        #expect(CalendarStateResolver.state(of: monday, plan: history.plan(on: mondayDate), today: tuesday, calendar: cal, automaticDays: [], manualDays: [], resolutions: [:]) == .notTracked)
        #expect(Constancy.streak(history: history, today: tuesday, attended: [], restResolutions: [], calendar: cal) == 0)

        // Con una sesión previa (p. ej. importada), el seguimiento empieza en esa fecha.
        let ctx2 = try inMemoryContext()
        let repo = WorkoutRepository(context: ctx2)
        _ = repo.startSession(trainingDate: date(2026, 10, 20, 18, calendar: cal), timeZone: cal.timeZone, templateID: nil, exerciseIDs: [])
        let catalog2 = CatalogRepository(context: ctx2)
        catalog2.ensureInitialPlanVersion(now: date(2026, 11, 3, 9, calendar: cal), calendar: cal)
        #expect(catalog2.planHistory().versions.first?.validFrom == cal.startOfDay(for: date(2026, 10, 20, calendar: cal)))
    }

    @Test("Racha: los descansos no la rompen; un día planificado sin asistencia sí; hoy no cuenta en contra")
    func streak() {
        let history = PlanHistory(versions: [.init(validFrom: .distantPast, plan: .ownerDefault)])
        // Semana del 2 al 8 nov: lun, mar, mié, vie, sáb planificados; jue y dom descanso.
        let attended: Set<CivilDay> = [2, 3, 4, 6, 7].map { CivilDay(year: 2026, month: 11, day: $0) }.reduce(into: []) { $0.insert($1) }
        let monday9 = CivilDay(year: 2026, month: 11, day: 9)
        #expect(Constancy.streak(history: history, today: monday9, attended: attended, restResolutions: [], calendar: cal) == 5)
        // Faltar el miércoles rompe la racha en ese punto.
        var missing = attended; missing.remove(CivilDay(year: 2026, month: 11, day: 4))
        #expect(Constancy.streak(history: history, today: monday9, attended: missing, restResolutions: [], calendar: cal) == 2)
        // Un descanso puntual confirmado ese miércoles es neutro.
        #expect(Constancy.streak(history: history, today: monday9, attended: missing, restResolutions: [CivilDay(year: 2026, month: 11, day: 4)], calendar: cal) == 4)
    }

    // MARK: Etapa 4 — sesión

    @Test("Sustituir solo sin series realizadas; mover cambia el orden")
    func substituteAndMove() throws {
        let ctx = try inMemoryContext()
        let repo = WorkoutRepository(context: ctx)
        let s = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["chest_pecdeck", "chest_machine_press"])
        let ordered = { s.exercises.sorted { $0.order < $1.order }.map(\.exerciseID) }
        #expect(ordered() == ["chest_pecdeck", "chest_machine_press"])
        let pec = s.exercises.first { $0.exerciseID == "chest_pecdeck" }!
        repo.move(pec, by: 1)
        #expect(ordered() == ["chest_machine_press", "chest_pecdeck"])
        #expect(repo.substitute(pec, with: "chest_incline_barbell"))
        #expect(ordered() == ["chest_machine_press", "chest_incline_barbell"])
        #expect(pec.sets.allSatisfy { $0.stateRaw == "pending" } && !pec.sets.isEmpty)
        let d = pec.sets[0]
        repo.updateDraft(d, amount: 50, unit: .kilograms, reps: 8, type: .working, side: .bilateral, rir: nil)
        try repo.confirm(d)
        #expect(!repo.substitute(pec, with: "chest_flat_barbell"))        // conserva el trabajo
        #expect(pec.exerciseID == "chest_incline_barbell")
    }

    // MARK: Etapa 5 — doble progresión

    @Test("Doble progresión: todas las series de referencia en el techo; RIR exigido opcional")
    func doubleProgression() throws {
        let ctx = try inMemoryContext()
        let repo = WorkoutRepository(context: ctx)
        let catalog = CatalogRepository(context: ctx)
        try catalog.setProgressionRule("legs_extension", enabled: true, lower: 8, upper: 12, referenceSets: 2, increment: 5, unit: .kilograms, minimumRIR: nil)
        let s1 = repo.startSession(trainingDate: Date(), timeZone: .current, templateID: nil, exerciseIDs: ["legs_extension"])
        let se = s1.exercises[0]
        let a = se.sets[0]
        repo.updateDraft(a, amount: 40, unit: .kilograms, reps: 12, type: .working, side: .bilateral, rir: .exact(2))
        try repo.confirm(a)
        let b = repo.addDraft(to: se)[0]
        repo.updateDraft(b, amount: 40, unit: .kilograms, reps: 10, type: .working, side: .bilateral, rir: .exact(1))
        try repo.confirm(b)
        repo.finish(s1)
        #expect(catalog.evaluateProgression("legs_extension", variantKey: nil, excluding: nil) == .notMet(reached: 1, need: 2))  // T30

        try repo.edit(b, amount: 40, unit: .kilograms, convention: b.toDomain().load.convention, reps: 12, type: .working, side: .bilateral, rir: .exact(1))
        #expect(catalog.evaluateProgression("legs_extension", variantKey: nil, excluding: nil) == .met(incrementKilograms: 5))
        try catalog.setProgressionRule("legs_extension", enabled: true, lower: 8, upper: 12, referenceSets: 2, increment: 5, unit: .kilograms, minimumRIR: 2)
        #expect(catalog.evaluateProgression("legs_extension", variantKey: nil, excluding: nil) == .effortUnknown)
        try catalog.setProgressionRule("legs_extension", enabled: false, lower: 8, upper: 12, referenceSets: 2, increment: 5, unit: .kilograms, minimumRIR: nil)
        #expect(catalog.evaluateProgression("legs_extension", variantKey: nil, excluding: nil) == .disabled)
        // La sugerencia no cambia los pesos.
        #expect(b.loadAmount == 40)
    }

    // MARK: Etapa 6 — resumen semanal

    @Test("Mensajes del resumen semanal: solo datos, sin culpa, sin división por cero")
    func summaryMessages() {
        let empty = WeeklySummary(start: Date(), end: Date(), isPartial: true, sessions: 0, workingSets: 0, previousWeekWorkingSets: 0, attendedDays: 0, plannedDays: 2, topGroups: [], streak: 0)
        #expect(empty.messages.first == "Aún no hay sesiones registradas esta semana.")
        let full = WeeklySummary(start: Date(), end: Date(), isPartial: false, sessions: 4, workingSets: 52, previousWeekWorkingSets: 48, attendedDays: 4, plannedDays: 5, topGroups: [(.legs, 18)], streak: 3)
        #expect(full.messages.contains("4 sesiones y 52 series de trabajo."))
        #expect(full.messages.contains("Asistencia: 4 de 5 días planificados."))
        #expect(full.messages.contains("4 series más que la semana anterior."))
        let prevZero = WeeklySummary(start: Date(), end: Date(), isPartial: false, sessions: 1, workingSets: 10, previousWeekWorkingSets: 0, attendedDays: 1, plannedDays: 5, topGroups: [], streak: 1)
        #expect(prevZero.messages.contains("La semana anterior no tuvo series registradas."))
        let all = (empty.messages + full.messages).joined().lowercased()
        #expect(!all.contains("fallaste") && !all.contains("garantiz") && !all.contains("crecimiento"))
    }
}
