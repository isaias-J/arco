import Foundation

/// Motor de sugerencias de énfasis muscular (spec §11). Local, determinista y explicable.
/// NO usa modelo de lenguaje ni red. Es ayuda organizativa basada en el registro; no demuestra
/// optimización de crecimiento. Las sugerencias NUNCA editan la sesión del usuario (§11.4).
public enum SuggestionEngine {

    /// Entrada del motor (spec §11.2).
    public struct Input: Sendable {
        /// Grupos previstos para el día.
        public let plannedGroups: [MuscleGroup]
        /// Series atribuidas en la ventana consultada (p. ej. últimos 14 días).
        public let recentSets: [AttributedSet]
        /// Ejercicios del catálogo disponibles para el día (ya filtrados por grupo/exclusiones).
        public let availableExercises: [ExerciseDefinition]
        /// Ejercicios que el usuario fijó como referencia (se mantienen).
        public let pinnedExerciseIDs: Set<String>
        /// Exclusiones explícitas.
        public let excludedExerciseIDs: Set<String>
        /// Atribuciones personalizadas por el usuario (prevalecen sobre el catálogo).
        public var customRuleSets: [String: AttributionRuleSet] = [:]

        public init(
            plannedGroups: [MuscleGroup],
            recentSets: [AttributedSet],
            availableExercises: [ExerciseDefinition],
            pinnedExerciseIDs: Set<String> = [],
            excludedExerciseIDs: Set<String> = []
        ) {
            self.plannedGroups = plannedGroups
            self.recentSets = recentSets
            self.availableExercises = availableExercises
            self.pinnedExerciseIDs = pinnedExerciseIDs
            self.excludedExerciseIDs = excludedExerciseIDs
        }
    }

    /// Datos de una región del mismo grupo, mostrados como "por qué".
    public struct Evidence: Sendable, Equatable {
        public let muscle: Muscle
        public let directSets: Int
        public let lastDirect: Date?
    }

    /// Una sugerencia explicable (spec §11.3 regla 12).
    public struct Suggestion: Sendable, Equatable {
        /// Región priorizada por menor exposición directa.
        public let targetMuscle: Muscle
        /// Ejercicios del catálogo pertinentes para esa región.
        public let suggestedExerciseIDs: [String]
        /// Datos que originaron el mensaje: exposiciones directas registradas de la región.
        public let directSetsObserved: Int
        /// Clave de explicación mostrada ("por qué").
        public let explanationKey: String
        /// Series directas y última fecha de cada región del grupo en la ventana consultada.
        public let evidence: [Evidence]
    }

    public struct Result: Sendable, Equatable {
        public let suggestions: [Suggestion]
        /// Si no hay ejercicio apto en el catálogo para una carencia, se informa (T20).
        public let noSuitableExercise: Bool
        /// Si faltan datos, no se anuncia déficit (T22): se devuelve vacío sin diagnóstico.
        public let insufficientData: Bool
    }

    /// Máximo de sugerencias prioritarias mostradas (spec §11.3 regla 12).
    public static let maxSuggestions = 2

    /// Genera sugerencias. Determinista: empates se rompen por orden estable de `Muscle`.
    public static func suggest(_ input: Input) -> Result {
        // Regla 3 / T22: si no hay datos recientes, no diagnosticar; selección inicial editable.
        if input.recentSets.isEmpty {
            return Result(suggestions: [], noSuitableExercise: false, insufficientData: true)
        }

        // Músculos candidatos: los de los grupos previstos del día.
        let candidateMuscles = Muscle.allCases.filter { input.plannedGroups.contains($0.group) }
        guard !candidateMuscles.isEmpty else {
            return Result(suggestions: [], noSuitableExercise: false, insufficientData: false)
        }

        // Exposición directa registrada por músculo en la ventana.
        let counts = MuscleCounter.countByMuscle(input.recentSets)
        let lastDirect = lastDirectDates(input.recentSets)

        // Catálogo disponible, aplicando exclusiones (regla 1).
        let available = input.availableExercises.filter {
            !input.excludedExerciseIDs.contains($0.id) && !$0.archived
        }

        // Para cada músculo candidato, calcular exposición directa y ejercicios que lo cubren.
        func exercisesTargeting(_ muscle: Muscle) -> [String] {
            available.compactMap { ex -> String? in
                guard let rs = input.customRuleSets[ex.id] ?? ExerciseCatalog.ruleSet(for: ex.id) else { return nil }
                return rs.role(for: muscle) == .direct ? ex.id : nil
            }
        }

        // Regla 3/4: solo se prioriza una región si OTRA región del mismo grupo recibió más
        // trabajo directo en la ventana (concentración observada). Si el grupo no tiene datos,
        // no se sugiere nada: no se anuncia un déficit sin evidencia (T22).
        let concentrated = candidateMuscles.filter { m in
            let mine = counts[m]?.direct ?? 0
            return candidateMuscles.contains { $0 != m && $0.group == m.group && (counts[$0]?.direct ?? 0) > mine }
        }
        if concentrated.isEmpty {
            return Result(suggestions: [], noSuitableExercise: false, insufficientData: false)
        }

        // Ordenar músculos por MENOR exposición directa (regla 4), desempate por orden estable.
        let ranked = concentrated
            .map { (muscle: $0, direct: counts[$0]?.direct ?? 0, covers: exercisesTargeting($0)) }
            // Solo priorizar regiones que tienen al menos un ejercicio disponible que las cubra.
            .filter { !$0.covers.isEmpty }
            .sorted {
                if $0.direct != $1.direct { return $0.direct < $1.direct }
                return muscleOrder($0.muscle) < muscleOrder($1.muscle)
            }

        // Si ningún ejercicio disponible cubre ninguna carencia relevante → informar (T20).
        if ranked.isEmpty {
            return Result(suggestions: [], noSuitableExercise: true, insufficientData: false)
        }

        // Evitar redundancia (regla 7): no proponer dos músculos de la misma región con los
        // mismos ejercicios. Tomar hasta `maxSuggestions`, saltando duplicados de cobertura.
        var suggestions: [Suggestion] = []
        var usedExercises: Set<String> = []
        for entry in ranked {
            let fresh = entry.covers.filter { !usedExercises.contains($0) }
            guard !fresh.isEmpty else { continue }
            let evidence = Muscle.allCases
                .filter { $0.group == entry.muscle.group }
                .map { Evidence(muscle: $0, directSets: counts[$0]?.direct ?? 0, lastDirect: lastDirect[$0]) }
            suggestions.append(Suggestion(
                targetMuscle: entry.muscle,
                suggestedExerciseIDs: fresh,
                directSetsObserved: entry.direct,
                explanationKey: "suggestion.lowExposure",
                evidence: evidence
            ))
            usedExercises.formUnion(fresh)
            if suggestions.count >= maxSuggestions { break }
        }

        return Result(suggestions: suggestions, noSuitableExercise: false, insufficientData: false)
    }

    /// Fecha de la última serie directa por músculo (si las series traen fecha).
    static func lastDirectDates(_ sets: [AttributedSet]) -> [Muscle: Date] {
        var result: [Muscle: Date] = [:]
        for set in sets {
            guard let date = set.performedAt else { continue }
            for m in set.ruleSet.directMuscles where (result[m] ?? .distantPast) < date {
                result[m] = date
            }
        }
        return result
    }

    /// Texto explicativo en español con los datos que originan la sugerencia (spec §11.4).
    /// Describe la distribución registrada; no afirma desbalance ni crecimiento.
    public static func explanation(
        for suggestion: Suggestion,
        windowDays: Int,
        muscleName: (Muscle) -> String,
        exerciseName: (String) -> String,
        dateText: (Date) -> String
    ) -> String {
        let worked = suggestion.evidence.filter { $0.directSets > suggestion.directSetsObserved }
        let workedText = worked.map { e -> String in
            var s = "\(muscleName(e.muscle)): \(e.directSets) \(e.directSets == 1 ? "serie directa" : "series directas")"
            if let d = e.lastDirect { s += ", la última el \(dateText(d))" }
            return s
        }.joined(separator: "; ")
        let target = muscleName(suggestion.targetMuscle)
        let targetText = suggestion.directSetsObserved == 0
            ? "\(target) no tiene series directas registradas en los últimos \(windowDays) días"
            : "\(target) tiene \(suggestion.directSetsObserved) en ese periodo"
        let options = suggestion.suggestedExerciseIDs.map(exerciseName).joined(separator: " o ")
        return "Tu trabajo reciente se ha concentrado en otras regiones del grupo (\(workedText)). \(targetText). Hoy puedes priorizar \(options) de tu catálogo."
    }

    private static func muscleOrder(_ m: Muscle) -> Int {
        Muscle.allCases.firstIndex(of: m) ?? Int.max
    }
}
