import Testing
import Foundation
@testable import ArcoCore

@Suite("IMC adulto NHS/NICE")
struct BMITests {

    @Test("T55: 70 kg y 1,70 m → IMC interno ≈ 24,22; mostrado 24,2")
    func bmiValueAndDisplay() throws {
        let r = try #require(BMICalculator.bmi(massKilograms: 70, heightMeters: Decimal(string: "1.70")!, isEstimated: false))
        // 70 / 2.89 = 24.221453...
        #expect(r.rawValue > Decimal(string: "24.22")! && r.rawValue < Decimal(string: "24.23")!)
        #expect(r.displayValue == Decimal(string: "24.2")!)
        #expect(r.band == .healthy)
    }

    @Test("T56: clasificación por valor sin redondear; 24,96 no pasa a 25")
    func boundaryUsesRawValue() throws {
        // peso/altura² = 24.96 → sigue siendo healthy aunque muestre 25,0.
        let height = Decimal(string: "1")!
        let r = try #require(BMICalculator.bmi(massKilograms: Decimal(string: "24.96")!, heightMeters: height, isEstimated: false))
        #expect(r.band == .healthy)
        #expect(r.displayValue == Decimal(string: "25")!)
        #expect(r.displayCrossesBoundary == true)  // se mostrará precisión adicional
    }

    @Test("T56: exactamente 25,0 es sobrepeso")
    func exactly25IsOverweight() throws {
        let r = try #require(BMICalculator.bmi(massKilograms: 25, heightMeters: 1, isEstimated: false))
        #expect(r.band == .overweight)
    }

    @Test("Peso estimado produce IMC estimado")
    func estimatedPropagates() throws {
        let r = try #require(BMICalculator.bmi(massKilograms: 70, heightMeters: Decimal(string: "1.70")!, isEstimated: true))
        #expect(r.isEstimated == true)
    }

    @Test("Altura no positiva no produce resultado")
    func noResultWithoutHeight() {
        #expect(BMICalculator.bmi(massKilograms: 70, heightMeters: 0, isEstimated: false) == nil)
    }
}

@Suite("Récords, progresión y e1RM")
struct RecordsTests {

    private func workingSet(_ kg: Decimal, reps: Int, conv: LoadConvention = .externalTotal, rir: RIR? = nil, date: Date = Date()) -> SetRecord {
        SetRecord(load: Load(amount: kg, unit: .kilograms, convention: conv), reps: reps, type: .working, state: .completed, rir: rir, performedAt: date)
    }

    @Test("T26: mayor asistencia no genera récord de carga")
    func assistanceNotCountedAsStrength() {
        let sets = [
            workingSet(50, reps: 8, conv: .assistance),
            workingSet(30, reps: 8, conv: .externalTotal)
        ]
        let record = RecordsEngine.maxLoadRecord(from: sets)
        #expect(record?.loadKilograms == 30)  // la de asistencia (50) se excluye
    }

    @Test("T27: 40×8 luego 40×10 identifica progreso de repeticiones")
    func repsProgressSameLoad() {
        let prev = [workingSet(40, reps: 8)]
        let curr = [workingSet(40, reps: 10)]
        let cmp = ProgressionAnalyzer.compare(previous: prev, current: curr)
        #expect(cmp?.repsProgressAtSameLoad == true)
        #expect(cmp?.ambiguousTradeoff == false)
    }

    @Test("T28: más carga con menos reps es tradeoff ambiguo")
    func ambiguousTradeoff() {
        let prev = [workingSet(40, reps: 10)]
        let curr = [workingSet(45, reps: 6)]
        let cmp = ProgressionAnalyzer.compare(previous: prev, current: curr)
        #expect(cmp?.loadIncreased == true)
        #expect(cmp?.repsDecreased == true)
        #expect(cmp?.ambiguousTradeoff == true)
    }

    @Test("T29: borrar serie que daba récord recalcula el récord")
    func deletingSetRecalculatesRecord() {
        var sets = [workingSet(60, reps: 5), workingSet(50, reps: 8)]
        let before = RecordsEngine.maxLoadRecord(from: sets)
        #expect(before?.loadKilograms == 60)
        // "Borrar" la de 60 (marcar eliminada).
        sets[0] = SetRecord(id: sets[0].id, load: sets[0].load, reps: sets[0].reps, type: .working, state: .deleted, performedAt: sets[0].performedAt)
        let after = RecordsEngine.maxLoadRecord(from: sets)
        #expect(after?.loadKilograms == 50)
    }

    @Test("T30: solo una serie alcanza el techo → no sugiere subir")
    func doubleProgressionNeedsAllSets() {
        let config = DoubleProgressionConfig(enabled: true, repRangeLower: 8, repRangeUpper: 12, referenceSets: 3, incrementKilograms: Decimal(string: "2.5")!)
        let sets = [workingSet(40, reps: 12), workingSet(40, reps: 10), workingSet(40, reps: 9)]
        #expect(DoubleProgression.suggestsIncrease(config: config, workingSets: sets) == false)
        // Todas al techo → sí sugiere.
        let allTop = [workingSet(40, reps: 12), workingSet(40, reps: 12), workingSet(40, reps: 12)]
        #expect(DoubleProgression.suggestsIncrease(config: config, workingSets: allTop) == true)
    }

    @Test("e1RM Epley solo con RIR 0-1 y rango 2-10")
    func e1rmFilters() {
        let load = Load(amount: 100, unit: .kilograms, convention: .externalTotal)
        // reps 5, RIR 1 → 100 * (1 + 5/30) = 116.66...
        let v = EstimatedOneRM.epley(load: load, reps: 5, rir: .exact(1))
        #expect(v != nil)
        // RIR desconocido → nil
        #expect(EstimatedOneRM.epley(load: load, reps: 5, rir: .unknown) == nil)
        // reps 15 → nil
        #expect(EstimatedOneRM.epley(load: load, reps: 15, rir: .exact(0)) == nil)
        // asistencia → nil
        let assist = Load(amount: 50, unit: .kilograms, convention: .assistance)
        #expect(EstimatedOneRM.epley(load: assist, reps: 5, rir: .exact(0)) == nil)
    }
}
