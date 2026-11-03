import Testing
import Foundation
@testable import ArcoCore

@Suite("Unidades y conversión de carga")
struct UnitsTests {

    @Test("T23: 100 lb equivale a 45,359237 kg exactos")
    func poundsToKilogramsExact() throws {
        let load = Load(amount: 100, unit: .pounds, convention: .externalTotal)
        let kg = try #require(load.kilograms)
        #expect(kg == Decimal(string: "45.359237")!)
    }

    @Test("T23: conversión ida y vuelta no acumula deriva")
    func roundTripNoDrift() {
        let original = Decimal(string: "100")!
        let kg = UnitConverter.convertMass(original, from: .pounds, to: .kilograms)
        let back = UnitConverter.convertMass(kg, from: .kilograms, to: .pounds)
        #expect(back == original)
    }

    @Test("Carga desconocida se distingue de cero")
    func unknownVsZero() {
        let unknown = Load.unknown(convention: .machineNominal)
        let zero = Load(amount: 0, unit: .kilograms, convention: .bodyweight)
        #expect(unknown.isKnown == false)
        #expect(zero.isKnown == true)
        #expect(unknown.kilograms == nil)
        #expect(zero.kilograms == 0)
    }

    @Test("Cambiar unidad de visualización no altera cantidad registrada")
    func displayConversionPreservesOriginal() {
        let load = Load(amount: Decimal(string: "40")!, unit: .kilograms, convention: .externalTotal)
        // El registro conserva 40 kg; una vista en lb es solo presentación.
        let shownInPounds = UnitConverter.convertMass(load.amount!, from: .kilograms, to: .pounds)
        #expect(load.amount == Decimal(string: "40")!)
        #expect(load.unit == .kilograms)
        // 40 / 0.45359237 ≈ 88.1849...
        #expect(shownInPounds > Decimal(string: "88.18")! && shownInPounds < Decimal(string: "88.19")!)
    }
}
