import Foundation
import Testing
@testable import ArcoCore

@Suite("Comprobaciones independientes de revisión")
struct ReviewRegressionTests {
    @Test("Tres pares unilaterales deben sumar tres series al grupo")
    func pairedSetsDoNotDoubleCount() {
        let rules = ExerciseCatalog.ruleSet(for: "curl_dumbbell")!
        var sets: [AttributedSet] = []
        for _ in 0..<3 {
            sets.append(AttributedSet(setID: UUID(), exerciseID: rules.exerciseID, side: .left, ruleSet: rules))
            sets.append(AttributedSet(setID: UUID(), exerciseID: rules.exerciseID, side: .right, ruleSet: rules))
        }
        #expect(MuscleCounter.countByGroup(sets)[.biceps]?.direct == 3)
    }

    @Test("La gráfica de carga no debe mostrar asistencia como peso levantado")
    func assistanceIsNotLiftedLoad() {
        let now = Date()
        let set = SetRecord(load: Load(amount: 40, unit: .kilograms, convention: .assistance), reps: 8, performedAt: now)
        let point = ChartAnalytics.maxLoadPerSession([(date: now, sets: [set])]).first
        #expect(point?.value == nil)
    }

    @Test("Peso actual debe ignorar mediciones no válidas")
    func invalidWeightIsNotCurrent() {
        let now = Date()
        let valid = BodyWeightEntry(measurementDate: now.addingTimeInterval(-3600), enteredAt: now, amount: 70, unit: .kilograms, isEstimated: false)
        let invalid = BodyWeightEntry(measurementDate: now, enteredAt: now, amount: -1, unit: .kilograms, isEstimated: false)
        #expect(BodyWeightAnalytics.currentWeight(from: [valid, invalid])?.amount == 70)
    }
}
