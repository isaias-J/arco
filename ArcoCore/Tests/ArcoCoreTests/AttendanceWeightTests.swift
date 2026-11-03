import Testing
import Foundation
@testable import ArcoCore

@Suite("Asistencia y peso corporal")
struct AttendanceWeightTests {

    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Madrid")!
        return c
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    @Test("T07/T34: solo serie de trabajo elegible crea asistencia automática")
    func automaticAttendanceNeedsWorkingSet() {
        let warmupOnly = [SetRecord(load: Load(amount: 20, unit: .kilograms, convention: .externalTotal), reps: 10, type: .warmup, performedAt: Date())]
        #expect(AttendanceEngine.qualifiesForAutomaticAttendance(sessionSets: warmupOnly) == false)
        let working = [SetRecord(load: Load(amount: 40, unit: .kilograms, convention: .externalTotal), reps: 8, type: .working, performedAt: Date())]
        #expect(AttendanceEngine.qualifiesForAutomaticAttendance(sessionSets: working) == true)
    }

    @Test("T35: dos sesiones y asistencia manual el mismo día = un día asistido")
    func sameDayConsolidation() {
        let d = day(2026, 3, 10)
        let events: [(date: Date, source: AttendanceSource, partial: Bool)] = [
            (d, .automatic, false),
            (d, .automatic, false),
            (d, .manual, false)
        ]
        let days = AttendanceEngine.consolidate(events: events, calendar: cal)
        #expect(days.count == 1)
        #expect(days[0].sessionCount == 3)
        #expect(days[0].sources == Set([.automatic, .manual]))
    }

    @Test("T36: sesión parcial conserva estado parcial y cuenta como asistida")
    func partialSessionCounts() {
        let d = day(2026, 3, 11)
        let days = AttendanceEngine.consolidate(events: [(d, .automatic, true)], calendar: cal)
        #expect(days[0].isPartial == true)
    }

    @Test("T39: compliance usa denominador del plan; sin plan no inventa porcentaje")
    func adherenceWithoutPlan() {
        let noPlan = AdherenceMetrics(attendedDays: 3, completedSessions: 3, plannedDays: 0)
        #expect(noPlan.compliance == nil)
        let withPlan = AdherenceMetrics(attendedDays: 4, completedSessions: 4, plannedDays: 5)
        #expect(withPlan.compliance == 0.8)
    }

    @Test("T52: registrar hoy un peso antiguo no cambia el peso actual")
    func currentWeightUsesMeasurementDate() {
        let recent = BodyWeightEntry(measurementDate: day(2026, 3, 10), enteredAt: day(2026, 3, 10), amount: 70, unit: .kilograms, isEstimated: false)
        // Ingresado hoy (15) pero medido en el pasado (1).
        let oldButEnteredNow = BodyWeightEntry(measurementDate: day(2026, 3, 1), enteredAt: day(2026, 3, 15), amount: 68, unit: .kilograms, isEstimated: false)
        let current = BodyWeightAnalytics.currentWeight(from: [recent, oldButEnteredNow])
        #expect(current?.measurementDate == day(2026, 3, 10))  // el más reciente por medición
        #expect(current?.amount == 70)
    }

    @Test("T53: tendencia de 7 días solo con ≥3 fechas medidas y excluye estimados")
    func sevenDayTrend() {
        let end = day(2026, 3, 7)
        let measured = [
            BodyWeightEntry(measurementDate: day(2026, 3, 1), enteredAt: end, amount: 70, unit: .kilograms, isEstimated: false),
            BodyWeightEntry(measurementDate: day(2026, 3, 3), enteredAt: end, amount: 71, unit: .kilograms, isEstimated: false),
            BodyWeightEntry(measurementDate: day(2026, 3, 7), enteredAt: end, amount: 69, unit: .kilograms, isEstimated: true) // estimado: se excluye
        ]
        // Solo 2 fechas medidas → sin tendencia.
        #expect(BodyWeightAnalytics.sevenDayTrend(from: measured, endingOn: end, calendar: cal).isEmpty)
        // Añadir una tercera fecha medida.
        let more = measured + [BodyWeightEntry(measurementDate: day(2026, 3, 5), enteredAt: end, amount: 70, unit: .kilograms, isEstimated: false)]
        let trend = BodyWeightAnalytics.sevenDayTrend(from: more, endingOn: end, calendar: cal)
        #expect(trend.count == 3)  // 3 días medidos distintos
    }
}
