import Testing
import Foundation
@testable import ArcoCore

@Suite("Avisos: planificador por fechas concretas")
struct ReminderPlannerTests {
    let cal = testCalendar()
    let plan = WeeklyPlan.ownerDefault
    /// Lunes 2 de noviembre de 2026, 08:00.
    var monday8: Date { date(2026, 11, 2, 8, calendar: cal) }
    let review = ReminderRule(category: .review, weekday: nil, hour: 21, minute: 0, enabled: true)

    private func input(_ rules: [ReminderRule], now: Date? = nil, attended: Set<CivilDay> = [], resolved: Set<CivilDay> = [], active: CivilDay? = nil, overrides: [ReminderOverride] = [], horizon: Int = 7) -> ReminderPlanner.Input {
        .init(plan: plan, rules: rules, overrides: overrides, attendedDays: attended, resolvedDays: resolved, activeSessionDay: active, now: now ?? monday8, calendar: cal, horizonDays: horizon)
    }

    @Test("T38: jueves y domingo no reciben revisión ni recordatorio; el resto de días sí")
    func restDaysSkipped() {
        let training = Weekday.allCases.map { ReminderRule(category: .training, weekday: $0, hour: 18, minute: 0, enabled: true) }
        let planned = ReminderPlanner.plan(input(training + [review]))
        let days = Set(planned.map(\.day.day))
        #expect(days == [2, 3, 4, 6, 7])                      // lun, mar, mié, vie, sáb
        #expect(planned.filter { $0.category == .review }.count == 5)
        #expect(planned.filter { $0.category == .training }.count == 5)
    }

    @Test("Horario individual por día: la regla del día prevalece sobre la general")
    func perDayTimes() {
        let rules = [
            ReminderRule(category: .training, weekday: .monday, hour: 7, minute: 30, enabled: true),
            ReminderRule(category: .training, weekday: .friday, hour: 19, minute: 15, enabled: true),
            ReminderRule(category: .training, weekday: .tuesday, hour: 18, minute: 0, enabled: false)
        ]
        let planned = ReminderPlanner.plan(input(rules, now: date(2026, 11, 2, 6, calendar: cal)))
        #expect(planned.map { "\($0.day.day)-\($0.hour):\($0.minute)" } == ["2-7:30", "6-19:15"])
    }

    @Test("T41: asistencia registrada cancela la revisión de ese día, no la de los siguientes")
    func attendanceCancelsOnlyThatDay() {
        let today = CivilDay(year: 2026, month: 11, day: 2)
        let planned = ReminderPlanner.plan(input([review], attended: [today]))
        #expect(!planned.contains { $0.day == today })
        #expect(planned.contains { $0.day == CivilDay(year: 2026, month: 11, day: 3) })
        let rested = ReminderPlanner.plan(input([review], resolved: [today]))
        #expect(!rested.contains { $0.day == today })
    }

    @Test("T42: el identificador conserva la fecha original del aviso")
    func identifierRoundTrip() {
        let day = CivilDay(year: 2026, month: 12, day: 31)
        let id = ReminderPlanner.identifier(.review, day)
        #expect(id == "arco.review.2026-12-31")
        let parsed = ReminderPlanner.parse(id)
        #expect(parsed?.category == .review && parsed?.day == day)
        #expect(ReminderPlanner.parse("otra.cosa") == nil)
    }

    @Test("T43: posponer no cruza de fecha y no duplica avisos")
    func snooze() {
        let day = CivilDay(year: 2026, month: 11, day: 2)
        #expect(ReminderPlanner.snoozeTime(for: day, minutes: 60, now: date(2026, 11, 2, 21, calendar: cal), calendar: cal).map { "\($0.hour):\($0.minute)" } == "22:0")
        #expect(ReminderPlanner.snoozeTime(for: day, minutes: 120, now: date(2026, 11, 2, 23, calendar: cal), calendar: cal) == nil)
        let once = ReminderOverride(category: .review, day: day, hour: 22, minute: 0, enabled: true)
        let planned = ReminderPlanner.plan(input([review], now: date(2026, 11, 2, 21, 5, calendar: cal), overrides: [once]))
        let todays = planned.filter { $0.day == day }
        #expect(todays.count == 1 && todays[0].hour == 22)
        #expect(Set(planned.map(\.id)).count == planned.count)
    }

    @Test("T44: sesión activa o entrenamiento tardío evitan avisos contradictorios")
    func noContradictions() {
        let today = CivilDay(year: 2026, month: 11, day: 2)
        let active = ReminderPlanner.plan(input([review], active: today))
        #expect(!active.contains { $0.day == today && $0.category == .review })
        let late = ReminderRule(category: .training, weekday: .monday, hour: 21, minute: 0, enabled: true)
        let moved = ReminderPlanner.plan(input([review, late])).filter { $0.day == today }
        #expect(moved.first { $0.category == .review }.map { "\($0.hour):\($0.minute)" } == "23:0")
        let veryLate = ReminderRule(category: .training, weekday: .monday, hour: 22, minute: 30, enabled: true)
        #expect(!ReminderPlanner.plan(input([review, veryLate])).contains { $0.day == today && $0.category == .review })
    }

    @Test("Límite de avisos pendientes: prioriza los elegidos por el usuario")
    func limit() {
        let training = Weekday.allCases.map { ReminderRule(category: .training, weekday: $0, hour: 7, minute: 0, enabled: true) }
        var i = input(training + [review], now: date(2026, 11, 2, 6, calendar: cal), horizon: 28)
        i.limit = 25
        let planned = ReminderPlanner.plan(i)
        #expect(planned.count == 25)
        #expect(planned.filter { $0.category == .training }.count == 20)   // 5 por semana × 4
    }

    @Test("T45: cambio de año, día bisiesto y horario de verano")
    func calendarEdges() {
        let leap = WeeklyPlan(days: Weekday.allCases.map { .init(weekday: $0, isRest: false, groups: []) })
        let dates = leap.plannedTrainingDates(from: date(2028, 2, 27, calendar: cal), days: 5, calendar: cal)
        #expect(dates.map { CivilDay($0, calendar: cal).key } == ["2028-02-27", "2028-02-28", "2028-02-29", "2028-03-01", "2028-03-02"])
        let newYear = CivilDay(year: 2026, month: 12, day: 31).adding(days: 1, calendar: cal)
        #expect(newYear == CivilDay(year: 2027, month: 1, day: 1))
        // Madrid cambia a horario de invierno el 25-10-2026: las 21:00 siguen siendo 21:00 locales.
        let fire = CivilDay(year: 2026, month: 10, day: 26).date(hour: 21, minute: 0, in: cal)!
        #expect(cal.component(.hour, from: fire) == 21)
        #expect(Weekday.of(date(2026, 10, 25, calendar: cal), calendar: cal) == .sunday)
        // La fecha civil de un instante depende de la zona: un viaje no mueve días pasados si se
        // guarda la fecha civil asignada.
        let instant = date(2026, 11, 2, 23, 30, calendar: cal)
        #expect(CivilDay(instant, calendar: testCalendar("America/Bogota")).day == 2)
        #expect(CivilDay(instant, calendar: testCalendar("Asia/Tokyo")).day == 3)
    }
}

@Suite("Sugerencias explicables y seguimiento por músculo")
struct SuggestionProgressTests {
    private func set(_ id: String, _ when: Date) -> AttributedSet {
        AttributedSet(setID: UUID(), exerciseID: id, side: .bilateral, ruleSet: ExerciseCatalog.ruleSet(for: id)!, performedAt: when)
    }

    @Test("T19: la sugerencia del viernes explica las series y fechas que la originan")
    func explanationCitesData() throws {
        let monday = date(2026, 11, 2, 18)
        let recent = [set("shoulder_overhead_press", monday), set("shoulder_overhead_press", monday), set("shoulder_front_raise", monday)]
        let catalog = ["shoulder_lateral_raise", "shoulder_overhead_press", "shoulder_front_raise", "shoulder_reverse_pecdeck"].compactMap(ExerciseCatalog.definition)
        let result = SuggestionEngine.suggest(.init(plannedGroups: [.shoulders], recentSets: recent, availableExercises: catalog))
        let first = try #require(result.suggestions.first)
        #expect([Muscle.deltoidLateral, .deltoidPosterior].contains(first.targetMuscle))
        let anterior = try #require(first.evidence.first { $0.muscle == .deltoidAnterior })
        #expect(anterior.directSets == 3)
        #expect(anterior.lastDirect == monday)
        let text = SuggestionEngine.explanation(for: first, windowDays: 14, muscleName: \.displayName, exerciseName: ExerciseNames.localized, dateText: { _ in "2 nov" })
        #expect(text.contains("Deltoides anterior: 3 series directas, la última el 2 nov"))
        #expect(text.contains("no tiene series directas"))
        #expect(!text.lowercased().contains("desbalance") && !text.lowercased().contains("crecimiento"))
    }

    @Test("T22: sin trabajo previo del grupo no se sugiere ni se anuncia déficit")
    func noDataNoSuggestion() {
        let legsOnly = [set("legs_extension", Date())]
        let catalog = ["shoulder_lateral_raise", "shoulder_reverse_pecdeck"].compactMap(ExerciseCatalog.definition)
        let result = SuggestionEngine.suggest(.init(plannedGroups: [.shoulders], recentSets: legsOnly, availableExercises: catalog))
        #expect(result.suggestions.isEmpty && !result.noSuitableExercise)
    }

    @Test("Braquiorradial del curl invertido aparece en antebrazo sin duplicar en bíceps")
    func brachioradialisInForearm() {
        let groups = MuscleCounter.countByGroup([set("curl_reverse", Date())])
        #expect(groups[.forearm]?.direct == 1)
        #expect(groups[.biceps]?.direct == 1)
        #expect(Muscle.brachioradialis.group == .forearm)
    }

    @Test("Semana en curso marcada incompleta; última semana y 7 días se distinguen")
    func periods() {
        let cal = testCalendar()
        let wednesday = date(2026, 11, 4, 10, calendar: cal)
        let week = CountPeriod.currentWeek.interval(now: wednesday, calendar: cal)
        #expect(week.isPartial)
        #expect(CivilDay(week.start, calendar: cal) == CivilDay(year: 2026, month: 11, day: 2))
        let prev = CountPeriod.previousWeek.interval(now: wednesday, calendar: cal)
        #expect(CivilDay(prev.start, calendar: cal) == CivilDay(year: 2026, month: 10, day: 26) && !prev.isPartial)
        let last7 = CountPeriod.last7Days.interval(now: wednesday, calendar: cal)
        #expect(CivilDay(last7.start, calendar: cal) == CivilDay(year: 2026, month: 10, day: 29))
        let inside = set("shoulder_lateral_raise", date(2026, 11, 3, calendar: cal))
        let outside = set("shoulder_lateral_raise", date(2026, 11, 1, calendar: cal))
        #expect(MuscleWeek.filter([inside, outside], from: week.start, to: week.end).count == 1)
    }

    @Test("Objetivo: mismo método de conteo y mensajes sin promesas")
    func goals() {
        let count = MuscleCount(muscle: .deltoidLateral, direct: 8, indirect: 4, unknown: 0)
        #expect(MuscleWeek.goalMessage(count: count, method: .direct, target: 10) == "8 series directas; objetivo elegido: 10 (2 por debajo de tu meta configurada)")
        #expect(MuscleWeek.goalMessage(count: count, method: .fractional, target: 10) == "10 series (estimación fraccional); objetivo elegido: 10")
        #expect(GoalMethod.direct.isValid(10) && !GoalMethod.direct.isValid(Decimal(string: "9.5")!))
        #expect(GoalMethod.fractional.isValid(Decimal(string: "9.5")!) && !GoalMethod.fractional.isValid(Decimal(string: "9.3")!))
        #expect(!GoalMethod.direct.isValid(-1))
    }

    @Test("Última exposición directa e indirecta; sin registro = sin datos")
    func exposures() {
        let t = date(2026, 11, 2, 18)
        let e = MuscleWeek.exposures([set("chest_flat_barbell", t)])
        #expect(e[.pectoral]?.lastDirect == t)
        #expect(e[.triceps]?.lastIndirect == t && e[.triceps]?.lastDirect == nil)
        #expect(e[.calves] == nil)
        #expect(e[.pectoral]?.hoursSinceDirect(now: t.addingTimeInterval(36 * 3600)) == 36)
    }

    @Test("T58: el IMC histórico usa la altura vigente en cada fecha; sin altura previa es un supuesto")
    func bmiHistory() {
        let heights = [HeightRecord(date: date(2026, 6, 1), meters: Decimal(string: "1.70")!), HeightRecord(date: date(2026, 10, 1), meters: Decimal(string: "1.75")!)]
        let weights = [
            BodyWeightEntry(measurementDate: date(2026, 5, 1), enteredAt: Date(), amount: 70, unit: .kilograms, isEstimated: false),
            BodyWeightEntry(measurementDate: date(2026, 7, 1), enteredAt: Date(), amount: 70, unit: .kilograms, isEstimated: true),
            BodyWeightEntry(measurementDate: date(2026, 11, 1), enteredAt: Date(), amount: 70, unit: .kilograms, isEstimated: false),
            BodyWeightEntry(measurementDate: date(2026, 11, 2), enteredAt: Date(), amount: -3, unit: .kilograms, isEstimated: false)
        ]
        let points = BMIHistory.points(weights: weights, heights: heights)
        #expect(points.count == 3)                                      // el negativo se ignora
        #expect(points[0].usesLaterHeight)                              // antes de la primera altura
        #expect(points[1].bmi.displayValue == Decimal(string: "24.2")! && points[1].bmi.isEstimated)
        #expect(points[2].bmi.displayValue == Decimal(string: "22.9")! && !points[2].usesLaterHeight)
    }

    @Test("T57: la edad se deriva de la fecha real con el calendario")
    func age() {
        let cal = testCalendar()
        #expect(AgeCalculator.age(birthDate: date(2007, 11, 3, calendar: cal), on: date(2026, 11, 2, calendar: cal), calendar: cal) == 18)
        #expect(AgeCalculator.age(birthDate: date(2007, 11, 2, calendar: cal), on: date(2026, 11, 2, calendar: cal), calendar: cal) == 19)
        #expect(AgeCalculator.age(birthDate: date(2030, 1, 1, calendar: cal), on: date(2026, 11, 2, calendar: cal), calendar: cal) == nil)
    }

    @Test("Peso corporal: valores no positivos nunca son peso actual ni entran en tendencia")
    func weightValidity() {
        let cal = testCalendar()
        let entries = [
            BodyWeightEntry(measurementDate: date(2026, 11, 1, calendar: cal), enteredAt: Date(), amount: 70, unit: .kilograms, isEstimated: false),
            BodyWeightEntry(measurementDate: date(2026, 11, 2, calendar: cal), enteredAt: Date(), amount: 0, unit: .kilograms, isEstimated: false)
        ]
        #expect(BodyWeightAnalytics.currentWeight(from: entries)?.amount == 70)
        #expect(BodyWeightAnalytics.sevenDayTrend(from: entries, endingOn: date(2026, 11, 2, calendar: cal), calendar: cal).isEmpty)
    }
}
