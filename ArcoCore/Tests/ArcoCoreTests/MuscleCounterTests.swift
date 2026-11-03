import Testing
import Foundation
@testable import ArcoCore

@Suite("Conteo muscular (D/I/F/U)")
struct MuscleCounterTests {

    /// Construye una serie atribuida usando una regla ad-hoc.
    private func set(
        _ exerciseID: String,
        side: BodySide = .bilateral,
        _ attrs: [MuscleAttribution]
    ) -> AttributedSet {
        AttributedSet(
            setID: UUID(),
            exerciseID: exerciseID,
            side: side,
            ruleSet: AttributionRuleSet(exerciseID: exerciseID, version: .initial, attributions: attrs)
        )
    }

    private func direct(_ m: Muscle) -> MuscleAttribution {
        MuscleAttribution(muscle: m, role: .direct, support: .biomechanical, rationaleKey: "k")
    }
    private func indirect(_ m: Muscle) -> MuscleAttribution {
        MuscleAttribution(muscle: m, role: .indirect, support: .biomechanical, rationaleKey: "k")
    }
    private func unknown(_ m: Muscle) -> MuscleAttribution {
        MuscleAttribution(muscle: m, role: .unknown, support: .productInference, rationaleKey: "k")
    }

    @Test("T09: 2 directas + 4 indirectas para un músculo → D=2, I=4, F=4")
    func directIndirectFractional() {
        var sets: [AttributedSet] = []
        for _ in 0..<2 { sets.append(set("e", [direct(.pectoral)])) }
        for _ in 0..<4 { sets.append(set("e", [indirect(.pectoral)])) }
        let counts = MuscleCounter.countByMuscle(sets)
        let pec = counts[.pectoral]!
        #expect(pec.direct == 2)
        #expect(pec.indirect == 4)
        #expect(pec.fractional == 4.0)
    }

    @Test("T10: regla con papel directo e indirecto se resuelve a un único papel")
    func roleConflictResolvesSingle() {
        let rs = AttributionRuleSet(
            exerciseID: "e",
            version: .initial,
            attributions: [direct(.pectoral), indirect(.pectoral)]
        )
        #expect(rs.hasRoleConflict == true)
        // Resolución determinista: direct gana.
        #expect(rs.role(for: .pectoral) == .direct)
        let counts = MuscleCounter.countByMuscle([
            AttributedSet(setID: UUID(), exerciseID: "e", side: .bilateral, ruleSet: rs)
        ])
        #expect(counts[.pectoral]?.direct == 1)
        #expect(counts[.pectoral]?.indirect == 0)
    }

    @Test("T11: serie que alcanza dos regiones de hombro no duplica en el grupo")
    func groupUnionNoDoubleCount() {
        // Una serie con delt anterior directo y delt lateral indirecto.
        let s = set("ohp", [direct(.deltoidAnterior), indirect(.deltoidLateral)])
        let groups = MuscleCounter.countByGroup([s])
        let shoulders = groups[.shoulders]!
        // Máximo de hijos = direct; una sola serie → direct=1, no 2.
        #expect(shoulders.direct == 1)
        #expect(shoulders.indirect == 0)
    }

    @Test("T12/T13: pares unilaterales cuentan por lado, no se inflan")
    func unilateralPairing() {
        var sets: [AttributedSet] = []
        for _ in 0..<3 {
            sets.append(set("curl", side: .left, [direct(.elbowFlexors)]))
            sets.append(set("curl", side: .right, [direct(.elbowFlexors)]))
        }
        let left = MuscleCounter.countByMuscle(sets, side: .left)
        let right = MuscleCounter.countByMuscle(sets, side: .right)
        #expect(left[.elbowFlexors]?.direct == 3)   // 3 exposiciones por lado
        #expect(right[.elbowFlexors]?.direct == 3)
        // Solo un lado registrado: el otro queda sin exposiciones.
        let onlyLeft = MuscleCounter.countByMuscle(
            (0..<3).map { _ in set("curl", side: .left, [direct(.elbowFlexors)]) }
        )
        #expect(onlyLeft[.elbowFlexors]?.direct == 3)
        let onlyLeftRight = MuscleCounter.countByMuscle(
            (0..<3).map { _ in set("curl", side: .left, [direct(.elbowFlexors)]) },
            side: .right
        )
        #expect(onlyLeftRight[.elbowFlexors] == nil)
    }

    @Test("T14: pulldown de brazos extendidos no suma bíceps")
    func straightArmNoBiceps() {
        let rs = ExerciseCatalog.ruleSet(for: "back_straight_arm_pulldown")!
        let s = AttributedSet(setID: UUID(), exerciseID: rs.exerciseID, side: .bilateral, ruleSet: rs)
        let counts = MuscleCounter.countByMuscle([s])
        #expect(counts[.lats]?.direct == 1)
        #expect(counts[.elbowFlexors] == nil)  // ni directo ni indirecto ni U
    }

    @Test("T15: prensa sentada no suma isquiotibiales automáticamente")
    func legPressNoHamstrings() {
        let rs = ExerciseCatalog.ruleSet(for: "legs_seated_leg_press")!
        let s = AttributedSet(setID: UUID(), exerciseID: rs.exerciseID, side: .bilateral, ruleSet: rs)
        let counts = MuscleCounter.countByMuscle([s])
        #expect(counts[.quadriceps]?.direct == 1)
        #expect(counts[.hamstrings] == nil)
    }

    @Test("T16: agarre isométrico no genera series directas de antebrazo")
    func noAutomaticForearm() {
        // Curl invertido acredita braquiorradial (región), no flexores/extensores de muñeca.
        let rs = ExerciseCatalog.ruleSet(for: "curl_reverse")!
        let s = AttributedSet(setID: UUID(), exerciseID: rs.exerciseID, side: .bilateral, ruleSet: rs)
        let counts = MuscleCounter.countByMuscle([s])
        #expect(counts[.elbowFlexors]?.direct == 1)
        #expect(counts[.brachioradialis]?.direct == 1)
        #expect(counts[.forearm] == nil)  // forearm genérico no recibe crédito directo
    }

    @Test("T17: variante con atribución desconocida aparece como pendiente, sin crédito inventado")
    func unknownAttributionPending() {
        let s = set("abs_leg_raise", [unknown(.abdomen), direct(.hipFlexors)])
        let counts = MuscleCounter.countByMuscle([s])
        #expect(counts[.abdomen]?.unknown == 1)
        #expect(counts[.abdomen]?.direct == 0)
        #expect(counts[.hipFlexors]?.direct == 1)
    }
}
