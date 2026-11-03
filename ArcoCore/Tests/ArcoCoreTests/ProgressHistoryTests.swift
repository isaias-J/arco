import Testing
import Foundation
@testable import ArcoCore

/// Curvas históricas: series por músculo (semana/mes/año) y evolución de repeticiones.
@Suite("Historial de series por músculo y de repeticiones")
struct ProgressHistoryTests {
    let cal = testCalendar()

    private func attr(_ m: Muscle, _ role: AttributionRole) -> MuscleAttribution {
        MuscleAttribution(muscle: m, role: role, support: .biomechanical, rationaleKey: "k")
    }

    private func aset(_ ex: String, _ attrs: [MuscleAttribution], at d: Date, side: BodySide = .bilateral, pairing: String? = nil) -> AttributedSet {
        AttributedSet(setID: UUID(), exerciseID: ex, side: side,
                      ruleSet: AttributionRuleSet(exerciseID: ex, version: .initial, attributions: attrs),
                      pairingKey: pairing, performedAt: d)
    }

    // MARK: Series por músculo

    @Test("Semanas: D, I y F con datos conocidos; el grupo usa la unión, no la suma de subregiones")
    func weeklyKnownData() {
        // Lunes 26 oct y lunes 2 nov 2026 (semanas desde lunes).
        let press = [attr(.deltoidAnterior, .direct), attr(.deltoidLateral, .indirect), attr(.triceps, .indirect)]
        let sets = [
            aset("press", press, at: date(2026, 10, 26, 18)),
            aset("press", press, at: date(2026, 10, 26, 18, 5)),
            aset("lateral", [attr(.deltoidLateral, .direct)], at: date(2026, 11, 2, 18))
        ]
        let now = date(2026, 11, 4, 12)
        let work = sets.compactMap(\.performedAt)
        let shoulders = MuscleHistory.buckets(sets, target: .group(.shoulders), scale: .week, workDates: work, now: now, calendar: cal)
        #expect(shoulders.count == 2)                                  // no empieza antes del primer registro
        #expect(shoulders[0].direct == 2 && shoulders[0].indirect == 0)   // unión: el press cuenta 1 vez para hombros
        #expect(shoulders[1].direct == 1)
        #expect(!shoulders[0].isPartial && shoulders[1].isPartial)        // semana en curso
        let lateral = MuscleHistory.buckets(sets, target: .muscle(.deltoidLateral), scale: .week, workDates: work, now: now, calendar: cal)
        #expect(lateral[0].direct == 0 && lateral[0].indirect == 2 && lateral[0].fractional == 1)
        #expect(lateral[0].value(.fractional) == 1 && lateral[0].value(.directAndIndirect) == 2)
    }

    @Test("Sin registros en un periodo es nil, no cero; entrenar otros músculos sí es cero")
    func missingVersusZero() {
        let sets = [
            aset("curl", [attr(.elbowFlexors, .direct)], at: date(2026, 10, 12, 18)),
            aset("squat", [attr(.quadriceps, .direct)], at: date(2026, 10, 26, 18))
        ]
        let work = sets.compactMap(\.performedAt)
        let b = MuscleHistory.buckets(sets, target: .muscle(.elbowFlexors), scale: .week, workDates: work,
                                      manualAttendanceDays: [date(2026, 10, 20)], now: date(2026, 11, 1, 20), calendar: cal)
        #expect(b.map(\.start) == [date(2026, 10, 12, 0), date(2026, 10, 19, 0), date(2026, 10, 26, 0)])
        #expect(b[0].value(.direct) == 1)
        #expect(b[1].value(.direct) == nil && b[1].attendanceWithoutSets == 1)   // "Sí fui" sin series
        #expect(b[2].value(.direct) == 0)                                    // entrenó pierna: cero real de bíceps
    }

    @Test("Pares unilaterales cuentan una exposición por par")
    func unilateralPairs() {
        let curl = [attr(.elbowFlexors, .direct)]
        var sets: [AttributedSet] = []
        for i in 0..<3 {
            sets.append(aset("curl", curl, at: date(2026, 11, 2, 18, i), side: .left, pairing: "se1"))
            sets.append(aset("curl", curl, at: date(2026, 11, 2, 18, i), side: .right, pairing: "se1"))
        }
        let b = MuscleHistory.buckets(sets, target: .group(.biceps), scale: .month, workDates: sets.compactMap(\.performedAt), now: date(2026, 11, 20), calendar: cal)
        #expect(b.count == 1 && b[0].direct == 3)
    }

    @Test("Meses y años: límites de calendario, periodo actual parcial y primer periodo parcial")
    func monthsAndYears() {
        let sets = [
            aset("row", [attr(.lats, .direct)], at: date(2025, 12, 31, 20)),
            aset("row", [attr(.lats, .direct)], at: date(2026, 1, 1, 9)),
            aset("row", [attr(.lats, .direct)], at: date(2026, 2, 28, 9))
        ]
        let work = sets.compactMap(\.performedAt)
        let months = MuscleHistory.buckets(sets, target: .muscle(.lats), scale: .month, workDates: work, now: date(2026, 3, 10), calendar: cal)
        #expect(months.map(\.direct) == [1, 1, 1, 0])           // dic, ene, feb, mar
        #expect(months.first?.isPartial == true)                  // empezó a registrar el 31 dic
        #expect(months.last?.isPartial == true && months.last?.hasWorkRecords == false)
        #expect(months[2].isPartial == false)
        let years = MuscleHistory.buckets(sets, target: .muscle(.lats), scale: .year, workDates: work, now: date(2026, 3, 10), calendar: cal)
        #expect(years.map(\.direct) == [1, 2] && years[1].isPartial)
    }

    @Test("Sin ningún registro no hay curva")
    func emptyHistory() {
        #expect(MuscleHistory.buckets([], target: .group(.chest), scale: .week, workDates: [], now: Date(), calendar: cal).isEmpty)
    }

    // MARK: Repeticiones

    private func s(_ kg: Decimal?, _ reps: Int?, unit: MassUnit = .kilograms, side: BodySide = .bilateral, type: SetType = .working, at d: Date) -> SetRecord {
        SetRecord(load: Load(amount: kg, unit: unit, convention: .externalTotal), reps: reps, type: type, side: side, performedAt: d)
    }

    @Test("Con la misma carga: mejor serie de cada sesión; sesiones sin esa carga no son cero")
    func repsAtLoad() {
        let a = RepsSession(id: UUID(), date: date(2026, 10, 1), sets: [s(40, 10, at: date(2026, 10, 1)), s(40, 8, at: date(2026, 10, 1)), s(20, 15, type: .warmup, at: date(2026, 10, 1))])
        let b = RepsSession(id: UUID(), date: date(2026, 10, 8), sets: [s(45, 6, at: date(2026, 10, 8))])
        let c = RepsSession(id: UUID(), date: date(2026, 10, 15), sets: [s(40, 12, at: date(2026, 10, 15)), s(nil, 20, at: date(2026, 10, 15))])
        let sessions = [c, a, b]
        #expect(RepsHistory.defaultComparison(sessions) == .atLoad(40))
        let points = RepsHistory.points(sessions, comparison: .atLoad(40))
        #expect(points.map(\.reps) == [10, 12])                    // calentamiento y otras cargas fuera
        #expect(points.allSatisfy { $0.loadKilograms == 40 })
        let heavy = RepsHistory.points(sessions, comparison: .heaviestSet)
        #expect(heavy.map(\.reps) == [10, 6, 12] && heavy.map(\.loadKilograms) == [40, 45, 40])
    }

    @Test("Unidades: la misma carga en libras se compara con su equivalente; lados separados")
    func repsUnitsAndSides() {
        let d1 = date(2026, 10, 1), d2 = date(2026, 10, 8)
        let a = RepsSession(id: UUID(), date: d1, sets: [s(45, 8, unit: .pounds, side: .left, at: d1), s(45, 7, unit: .pounds, side: .right, at: d1)])
        let b = RepsSession(id: UUID(), date: d2, sets: [s(45, 9, unit: .pounds, side: .left, at: d2), s(45, 9, unit: .pounds, side: .right, at: d2)])
        let loads = RepsHistory.loads([a, b])
        #expect(loads.count == 1 && loads[0].sessions == 2)
        let points = RepsHistory.points([a, b], comparison: .atLoad(loads[0].kilograms))
        #expect(points.filter { $0.side == .left }.map(\.reps) == [8, 9])
        #expect(points.filter { $0.side == .right }.map(\.reps) == [7, 9])
        #expect(!points.contains { $0.side == .bilateral })
    }

    @Test("Sin carga registrada: mejor serie por sesión; sin series no hay puntos")
    func repsWithoutLoad() {
        let d = date(2026, 10, 1)
        let a = RepsSession(id: UUID(), date: d, sets: [s(nil, 15, at: d), s(nil, 18, at: d)])
        #expect(RepsHistory.defaultComparison([a]) == .withoutLoad)
        #expect(RepsHistory.points([a], comparison: .withoutLoad).map(\.reps) == [18])
        #expect(RepsHistory.points([], comparison: .heaviestSet).isEmpty)
    }
}
