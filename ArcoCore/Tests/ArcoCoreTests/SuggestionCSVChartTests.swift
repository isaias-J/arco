import Testing
import Foundation
@testable import ArcoCore

@Suite("Motor de sugerencias")
struct SuggestionTests {

    private func attributed(_ exerciseID: String) -> AttributedSet {
        AttributedSet(setID: UUID(), exerciseID: exerciseID, side: .bilateral, ruleSet: ExerciseCatalog.ruleSet(for: exerciseID)!)
    }

    private var shoulderExercises: [ExerciseDefinition] {
        ["shoulder_lateral_raise", "shoulder_overhead_press", "shoulder_front_raise", "shoulder_reverse_pecdeck"]
            .compactMap { ExerciseCatalog.definition($0) }
    }

    @Test("T19: hombro anterior trabajado, sin lateral/posterior → prioriza esas regiones")
    func lowExposurePrioritised() {
        // Trabajo reciente concentrado en delt anterior (press militar + elevación frontal).
        let recent = [attributed("shoulder_overhead_press"), attributed("shoulder_front_raise")]
        let input = SuggestionEngine.Input(
            plannedGroups: [.shoulders],
            recentSets: recent,
            availableExercises: shoulderExercises
        )
        let result = SuggestionEngine.suggest(input)
        #expect(result.insufficientData == false)
        #expect(result.noSuitableExercise == false)
        // La primera sugerencia debe ser una región con 0 exposición directa (lateral o posterior).
        let first = result.suggestions.first!
        #expect(first.directSetsObserved == 0)
        #expect([Muscle.deltoidLateral, .deltoidPosterior].contains(first.targetMuscle))
        // Y propone ejercicios pertinentes del catálogo.
        #expect(!first.suggestedExerciseIDs.isEmpty)
    }

    @Test("T20: catálogo sin ejercicio apto informa la falta")
    func noSuitableExercise() {
        // Día de hombros pero solo hay un ejercicio de pecho disponible.
        let recent = [attributed("shoulder_overhead_press")]
        let input = SuggestionEngine.Input(
            plannedGroups: [.shoulders],
            recentSets: recent,
            availableExercises: [ExerciseCatalog.definition("chest_flat_barbell")!]
        )
        let result = SuggestionEngine.suggest(input)
        #expect(result.noSuitableExercise == true)
        #expect(result.suggestions.isEmpty)
    }

    @Test("T22: sin historial no diagnostica déficit")
    func insufficientData() {
        let input = SuggestionEngine.Input(plannedGroups: [.shoulders], recentSets: [], availableExercises: shoulderExercises)
        let result = SuggestionEngine.suggest(input)
        #expect(result.insufficientData == true)
        #expect(result.suggestions.isEmpty)
    }

    @Test("Determinismo: misma entrada produce misma salida")
    func deterministic() {
        let recent = [attributed("shoulder_overhead_press"), attributed("shoulder_front_raise")]
        let input = SuggestionEngine.Input(plannedGroups: [.shoulders], recentSets: recent, availableExercises: shoulderExercises)
        let a = SuggestionEngine.suggest(input)
        let b = SuggestionEngine.suggest(input)
        #expect(a.suggestions == b.suggestions)
    }
}

@Suite("Exportación CSV segura")
struct CSVTests {

    @Test("T69: celda que empieza por = se neutraliza")
    func formulaInjectionNeutralised() {
        #expect(CSVExport.escape("=SUM(A1:A2)").hasPrefix("'="))
        #expect(CSVExport.escape("+1").hasPrefix("'+"))
        #expect(CSVExport.escape("@cmd").hasPrefix("'@"))
    }

    @Test("T69: comillas y comas se escapan RFC 4180; tildes se conservan")
    func quotingAndAccents() {
        let field = "Press \"inclinado\", con tilde: á"
        let escaped = CSVExport.escape(field)
        #expect(escaped.hasPrefix("\""))
        #expect(escaped.contains("\"\"inclinado\"\""))
        #expect(escaped.contains("á"))
    }

    @Test("CSV incluye BOM UTF-8")
    func bomPresent() {
        let data = CSVExport.data(rows: [])
        #expect(data.starts(with: [0xEF, 0xBB, 0xBF]))
    }
}

@Suite("Agregación de gráficos")
struct ChartTests {
    private var cal: Calendar { Calendar(identifier: .gregorian) }
    private func day(_ d: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 3, day: d, hour: 12))! }

    @Test("T31: carga anterior cero o ausente no produce porcentaje inválido")
    func safePercent() {
        #expect(ChartAnalytics.percentChange(previous: 0, current: 50) == nil)
        #expect(ChartAnalytics.percentChange(previous: nil, current: 50) == nil)
        #expect(ChartAnalytics.percentChange(previous: 40, current: 50) == 25)
    }

    @Test("T32: fecha sin datos no se dibuja como cero")
    func absentNotZero() {
        let sessions: [(date: Date, sets: [SetRecord])] = [
            (day(1), [SetRecord(load: Load(amount: 40, unit: .kilograms, convention: .externalTotal), reps: 8, performedAt: day(1))]),
            (day(2), [])  // sesión sin series elegibles
        ]
        let points = ChartAnalytics.maxLoadPerSession(sessions)
        #expect(points[0].value == 40)
        #expect(points[1].value == nil)  // ausente, no 0
    }

    @Test("T33: semana en curso se marca parcial")
    func partialWeek() {
        let weekStart = day(2)  // lunes
        let midWeek = day(4)
        let status = ChartAnalytics.weekStatus(weekStart: weekStart, reference: midWeek, calendar: cal)
        #expect(status.isPartial == true)
    }
}
