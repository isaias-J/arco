import Foundation

/// Patrón de movimiento (metadato para agrupar y filtrar en sugerencias).
public enum MovementPattern: String, Codable, Sendable {
    case horizontalPush, verticalPush, horizontalPull, verticalPull
    case elbowFlexion, elbowExtension
    case kneeExtension, kneeFlexion, calfRaise
    case lateralRaise, frontRaise, rearDelt
    case trunkFlexion, hipFlexion
    case isolationOther
}

/// Tipo de carga predominante del ejercicio.
public enum LoadType: String, Codable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight, mixed
}

/// Origen del ejercicio en el catálogo.
public enum ExerciseOrigin: String, Codable, Sendable {
    case initial   // del catálogo base
    case custom    // creado por el usuario
}

/// Definición de ejercicio (spec §5, §6). ID estable; renombrar o archivar NO pierde registros.
public struct ExerciseDefinition: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let nameKey: String        // clave/base de nombre mostrado
    public let aliases: [String]
    public let defaultLoadType: LoadType
    public let pattern: MovementPattern
    public let origin: ExerciseOrigin
    public let instructionsKey: String
    public let archived: Bool

    public init(
        id: String,
        nameKey: String,
        aliases: [String] = [],
        defaultLoadType: LoadType,
        pattern: MovementPattern,
        origin: ExerciseOrigin = .initial,
        instructionsKey: String,
        archived: Bool = false
    ) {
        self.id = id
        self.nameKey = nameKey
        self.aliases = aliases
        self.defaultLoadType = defaultLoadType
        self.pattern = pattern
        self.origin = origin
        self.instructionsKey = instructionsKey
        self.archived = archived
    }
}

/// Catálogo inicial de 27 ejercicios y su matriz de atribución conservadora (spec §6, §10.3).
/// La matriz es un modelo inicial, versionado y mostrable con límites; NO coeficientes clínicos.
public enum ExerciseCatalog {

    public static let attributionVersion = AttributionVersion.initial

    // MARK: - Definiciones

    public static let all: [ExerciseDefinition] = [
        .init(id: "chest_incline_barbell", nameKey: "ex.chest_incline_barbell", defaultLoadType: .barbell, pattern: .horizontalPush, instructionsKey: "ex.chest_incline_barbell.info"),
        .init(id: "chest_flat_barbell", nameKey: "ex.chest_flat_barbell", defaultLoadType: .barbell, pattern: .horizontalPush, instructionsKey: "ex.chest_flat_barbell.info"),
        .init(id: "chest_pecdeck", nameKey: "ex.chest_pecdeck", defaultLoadType: .machine, pattern: .isolationOther, instructionsKey: "ex.chest_pecdeck.info"),
        .init(id: "chest_machine_press", nameKey: "ex.chest_machine_press", defaultLoadType: .machine, pattern: .horizontalPush, instructionsKey: "ex.chest_machine_press.info"),
        .init(id: "shoulder_lateral_raise", nameKey: "ex.shoulder_lateral_raise", defaultLoadType: .mixed, pattern: .lateralRaise, instructionsKey: "ex.shoulder_lateral_raise.info"),
        .init(id: "shoulder_overhead_press", nameKey: "ex.shoulder_overhead_press", defaultLoadType: .mixed, pattern: .verticalPush, instructionsKey: "ex.shoulder_overhead_press.info"),
        .init(id: "shoulder_front_raise", nameKey: "ex.shoulder_front_raise", defaultLoadType: .mixed, pattern: .frontRaise, instructionsKey: "ex.shoulder_front_raise.info"),
        .init(id: "shoulder_reverse_pecdeck", nameKey: "ex.shoulder_reverse_pecdeck", defaultLoadType: .machine, pattern: .rearDelt, instructionsKey: "ex.shoulder_reverse_pecdeck.info"),
        .init(id: "shoulder_facepull", nameKey: "ex.shoulder_facepull", defaultLoadType: .cable, pattern: .rearDelt, instructionsKey: "ex.shoulder_facepull.info"),
        .init(id: "triceps_seated_dip", nameKey: "ex.triceps_seated_dip", defaultLoadType: .machine, pattern: .elbowExtension, instructionsKey: "ex.triceps_seated_dip.info"),
        .init(id: "triceps_pushdown", nameKey: "ex.triceps_pushdown", defaultLoadType: .cable, pattern: .elbowExtension, instructionsKey: "ex.triceps_pushdown.info"),
        .init(id: "triceps_skullcrusher", nameKey: "ex.triceps_skullcrusher", defaultLoadType: .mixed, pattern: .elbowExtension, instructionsKey: "ex.triceps_skullcrusher.info"),
        .init(id: "back_pulldown", nameKey: "ex.back_pulldown", defaultLoadType: .cable, pattern: .verticalPull, instructionsKey: "ex.back_pulldown.info"),
        .init(id: "back_machine_row", nameKey: "ex.back_machine_row", defaultLoadType: .machine, pattern: .horizontalPull, instructionsKey: "ex.back_machine_row.info"),
        .init(id: "back_straight_arm_pulldown", nameKey: "ex.back_straight_arm_pulldown", defaultLoadType: .cable, pattern: .verticalPull, instructionsKey: "ex.back_straight_arm_pulldown.info"),
        .init(id: "back_neutral_pulldown", nameKey: "ex.back_neutral_pulldown", defaultLoadType: .cable, pattern: .verticalPull, instructionsKey: "ex.back_neutral_pulldown.info"),
        .init(id: "curl_preacher", nameKey: "ex.curl_preacher", defaultLoadType: .mixed, pattern: .elbowFlexion, instructionsKey: "ex.curl_preacher.info"),
        .init(id: "curl_hammer", nameKey: "ex.curl_hammer", defaultLoadType: .dumbbell, pattern: .elbowFlexion, instructionsKey: "ex.curl_hammer.info"),
        .init(id: "curl_reverse", nameKey: "ex.curl_reverse", defaultLoadType: .mixed, pattern: .elbowFlexion, instructionsKey: "ex.curl_reverse.info"),
        .init(id: "curl_bayesian", nameKey: "ex.curl_bayesian", defaultLoadType: .cable, pattern: .elbowFlexion, instructionsKey: "ex.curl_bayesian.info"),
        .init(id: "curl_dumbbell", nameKey: "ex.curl_dumbbell", defaultLoadType: .dumbbell, pattern: .elbowFlexion, instructionsKey: "ex.curl_dumbbell.info"),
        .init(id: "legs_extension", nameKey: "ex.legs_extension", defaultLoadType: .machine, pattern: .kneeExtension, instructionsKey: "ex.legs_extension.info"),
        .init(id: "legs_seated_leg_press", nameKey: "ex.legs_seated_leg_press", defaultLoadType: .machine, pattern: .kneeExtension, instructionsKey: "ex.legs_seated_leg_press.info"),
        .init(id: "legs_seated_curl", nameKey: "ex.legs_seated_curl", defaultLoadType: .machine, pattern: .kneeFlexion, instructionsKey: "ex.legs_seated_curl.info"),
        .init(id: "legs_calf_raise", nameKey: "ex.legs_calf_raise", defaultLoadType: .machine, pattern: .calfRaise, instructionsKey: "ex.legs_calf_raise.info"),
        .init(id: "abs_leg_raise", nameKey: "ex.abs_leg_raise", defaultLoadType: .bodyweight, pattern: .hipFlexion, instructionsKey: "ex.abs_leg_raise.info"),
        .init(id: "abs_machine_crunch", nameKey: "ex.abs_machine_crunch", defaultLoadType: .machine, pattern: .trunkFlexion, instructionsKey: "ex.abs_machine_crunch.info"),
    ]

    public static func definition(_ id: String) -> ExerciseDefinition? {
        all.first { $0.id == id }
    }

    // MARK: - Matriz de atribución inicial conservadora (§10.3)

    private static func d(_ m: Muscle, _ support: SupportLevel, _ key: String, _ sources: [String] = []) -> MuscleAttribution {
        MuscleAttribution(muscle: m, role: .direct, support: support, rationaleKey: key, sourceIDs: sources)
    }
    private static func i(_ m: Muscle, _ support: SupportLevel, _ key: String, _ sources: [String] = []) -> MuscleAttribution {
        MuscleAttribution(muscle: m, role: .indirect, support: support, rationaleKey: key, sourceIDs: sources)
    }
    private static func u(_ m: Muscle, _ key: String, _ sources: [String] = []) -> MuscleAttribution {
        MuscleAttribution(muscle: m, role: .unknown, support: .productInference, rationaleKey: key, sourceIDs: sources)
    }

    /// Reglas por ejercicio. Los músculos no listados = notCounted (sin crédito automático).
    public static let ruleSets: [String: AttributionRuleSet] = {
        var map: [String: AttributionRuleSet] = [:]
        func set(_ id: String, _ attrs: [MuscleAttribution]) {
            map[id] = AttributionRuleSet(exerciseID: id, version: attributionVersion, attributions: attrs)
        }

        set("chest_incline_barbell", [d(.pectoral, .biomechanical, "attr.chest_press"), i(.triceps, .biomechanical, "attr.triceps_assist"), i(.deltoidAnterior, .biomechanical, "attr.front_delt_assist")])
        set("chest_flat_barbell", [d(.pectoral, .biomechanical, "attr.chest_press"), i(.triceps, .biomechanical, "attr.triceps_assist"), i(.deltoidAnterior, .biomechanical, "attr.front_delt_assist")])
        // Peck deck: pectoral directo; deltoides anterior SIN crédito automático (conservador).
        set("chest_pecdeck", [d(.pectoral, .biomechanical, "attr.chest_fly")])
        set("chest_machine_press", [d(.pectoral, .biomechanical, "attr.chest_press"), i(.triceps, .biomechanical, "attr.triceps_assist"), i(.deltoidAnterior, .biomechanical, "attr.front_delt_assist")])
        // Elevaciones laterales: lateral directo; otras regiones dependen de variante.
        set("shoulder_lateral_raise", [d(.deltoidLateral, .biomechanical, "attr.lateral_raise")])
        set("shoulder_overhead_press", [d(.deltoidAnterior, .biomechanical, "attr.ohp"), i(.triceps, .biomechanical, "attr.triceps_assist"), i(.deltoidLateral, .productInference, "attr.ohp_lateral_provisional")])
        set("shoulder_front_raise", [d(.deltoidAnterior, .biomechanical, "attr.front_raise")])
        set("shoulder_reverse_pecdeck", [d(.deltoidPosterior, .biomechanical, "attr.rear_delt"), u(.scapularRetractors, "attr.scap_depends")])
        set("shoulder_facepull", [d(.deltoidPosterior, .productInference, "attr.facepull_provisional"), u(.scapularRetractors, "attr.scap_depends")])
        // Fondos sentados en máquina: tríceps directo; pecho y delt anterior U (no copiar fondos libres).
        set("triceps_seated_dip", [d(.triceps, .biomechanical, "attr.seated_dip"), u(.pectoral, "attr.seated_dip_depends"), u(.deltoidAnterior, "attr.seated_dip_depends")])
        set("triceps_pushdown", [d(.triceps, .biomechanical, "attr.pushdown")])
        set("triceps_skullcrusher", [d(.triceps, .biomechanical, "attr.skullcrusher")])
        set("back_pulldown", [d(.lats, .biomechanical, "attr.pulldown"), i(.elbowFlexors, .biomechanical, "attr.elbow_flex_assist"), u(.scapularRetractors, "attr.scap_depends")])
        set("back_neutral_pulldown", [d(.lats, .biomechanical, "attr.pulldown"), i(.elbowFlexors, .biomechanical, "attr.elbow_flex_assist"), u(.scapularRetractors, "attr.scap_depends")])
        set("back_machine_row", [d(.lats, .productInference, "attr.row_provisional"), i(.elbowFlexors, .biomechanical, "attr.elbow_flex_assist"), i(.scapularRetractors, .productInference, "attr.row_scap_provisional"), u(.deltoidPosterior, "attr.row_reardelt_depends")])
        // Pulldown de brazos extendidos: dorsales directo; NO media serie de bíceps (T14).
        set("back_straight_arm_pulldown", [d(.lats, .biomechanical, "attr.straight_arm")])
        set("curl_preacher", [d(.elbowFlexors, .biomechanical, "attr.curl")])
        set("curl_hammer", [d(.elbowFlexors, .biomechanical, "attr.hammer")])
        // Curl invertido: flexores del codo + braquiorradial como región; NO muñeca directa (T16).
        set("curl_reverse", [d(.elbowFlexors, .biomechanical, "attr.reverse_curl"), d(.brachioradialis, .biomechanical, "attr.brachioradialis")])
        set("curl_bayesian", [d(.elbowFlexors, .biomechanical, "attr.curl")])
        set("curl_dumbbell", [d(.elbowFlexors, .biomechanical, "attr.curl")])
        set("legs_extension", [d(.quadriceps, .biomechanical, "attr.leg_extension")])
        // Prensa sentada: cuádriceps directo; glúteos U/provisional; NO isquiotibiales auto (T15).
        set("legs_seated_leg_press", [d(.quadriceps, .biomechanical, "attr.leg_press"), u(.glutes, "attr.leg_press_glutes_depends")])
        set("legs_seated_curl", [d(.hamstrings, .biomechanical, "attr.leg_curl")])
        set("legs_calf_raise", [d(.calves, .biomechanical, "attr.calf")])
        // Elevaciones de piernas: abdomen U (solo variante confirmada); flexores de cadera D.
        set("abs_leg_raise", [u(.abdomen, "attr.leg_raise_abs_depends"), d(.hipFlexors, .biomechanical, "attr.hip_flexion")])
        set("abs_machine_crunch", [d(.abdomen, .biomechanical, "attr.crunch")])

        return map
    }()

    public static func ruleSet(for exerciseID: String) -> AttributionRuleSet? {
        ruleSets[exerciseID]
    }
}
