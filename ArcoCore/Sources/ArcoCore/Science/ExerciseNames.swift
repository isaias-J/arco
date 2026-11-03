import Foundation

/// Nombres e instrucciones breves del catálogo inicial, en español (spec §6).
/// Instrucciones descriptivas, sin prescripciones agresivas ni mensajes de entrenar con dolor.
public enum ExerciseNames {
    public static func localized(_ id: String) -> String {
        names[id] ?? id
    }
    public static func instructions(_ id: String) -> String {
        info[id] ?? ""
    }

    private static let names: [String: String] = [
        "chest_incline_barbell": "Press inclinado con barra",
        "chest_flat_barbell": "Press plano con barra",
        "chest_pecdeck": "Peck deck de pecho",
        "chest_machine_press": "Press de pecho en máquina",
        "shoulder_lateral_raise": "Elevaciones laterales",
        "shoulder_overhead_press": "Press militar",
        "shoulder_front_raise": "Elevaciones frontales",
        "shoulder_reverse_pecdeck": "Peck deck inverso (hombro posterior)",
        "shoulder_facepull": "Face pull",
        "triceps_seated_dip": "Fondos sentados en máquina",
        "triceps_pushdown": "Extensión de tríceps en polea",
        "triceps_skullcrusher": "Extensión de tríceps acostado",
        "back_pulldown": "Jalón al pecho",
        "back_machine_row": "Remo en máquina",
        "back_straight_arm_pulldown": "Pulldown con brazos extendidos",
        "back_neutral_pulldown": "Jalón al pecho con agarre neutro",
        "curl_preacher": "Curl predicador",
        "curl_hammer": "Curl martillo",
        "curl_reverse": "Curl invertido",
        "curl_bayesian": "Curl bayesian en polea",
        "curl_dumbbell": "Curl con mancuernas",
        "legs_extension": "Extensión de cuádriceps",
        "legs_seated_leg_press": "Prensa de piernas sentada",
        "legs_seated_curl": "Curl femoral sentado",
        "legs_calf_raise": "Elevaciones de pantorrilla",
        "abs_leg_raise": "Elevaciones de piernas",
        "abs_machine_crunch": "Abdominales en máquina"
    ]

    private static let info: [String: String] = [
        "chest_incline_barbell": "Press en banco inclinado con barra. Registra el ángulo si lo conoces.",
        "chest_flat_barbell": "Press en banco plano con barra. Confirma el peso de la barra antes de sumarlo.",
        "chest_pecdeck": "Apertura de pecho en máquina. Distinta del modo posterior de la misma máquina.",
        "chest_machine_press": "Press de pecho en máquina, posición plana o ligeramente declinada.",
        "shoulder_lateral_raise": "Elevación lateral del brazo. Conserva la variante (mancuerna, polea o máquina).",
        "shoulder_overhead_press": "Press por encima de la cabeza. Indica el equipo y la posición.",
        "shoulder_front_raise": "Elevación frontal del brazo.",
        "shoulder_reverse_pecdeck": "Trabajo de hombro posterior en peck deck inverso.",
        "shoulder_facepull": "Tracción hacia la cara con cuerda o polea. El agarre influye en la atribución.",
        "triceps_seated_dip": "Empuje hacia abajo sentado en máquina. No son fondos asistidos de peso corporal.",
        "triceps_pushdown": "Extensión de tríceps en polea. Agarre configurable.",
        "triceps_skullcrusher": "Extensión de tríceps acostado. Equipo y recorrido configurables.",
        "back_pulldown": "Jalón vertical al pecho. Agarre convencional configurable.",
        "back_machine_row": "Remo horizontal en máquina. Guarda el alias de la máquina cuando lo conozcas.",
        "back_straight_arm_pulldown": "Brazos relativamente fijos, movimiento desde arriba hacia la cintura.",
        "back_neutral_pulldown": "Jalón al pecho con agarre neutro.",
        "curl_preacher": "Curl en banco predicador.",
        "curl_hammer": "Curl con agarre neutro. Convención de peso por mancuerna.",
        "curl_reverse": "Curl con agarre pronado. Participa el antebrazo.",
        "curl_bayesian": "Curl en polea desde atrás, uni o bilateral.",
        "curl_dumbbell": "Curl con mancuernas, alterno o simultáneo.",
        "legs_extension": "Extensión de rodilla en máquina.",
        "legs_seated_leg_press": "Prensa sentada con asiento móvil: los pies se apoyan y se desplaza el asiento.",
        "legs_seated_curl": "Flexión de rodilla sentado en máquina.",
        "legs_calf_raise": "Elevación de talones. Indica rodilla extendida o flexionada.",
        "abs_leg_raise": "Elevación de piernas. Indica la forma del movimiento.",
        "abs_machine_crunch": "Flexión de tronco en máquina."
    ]
}

/// Nombres de las plantillas semanales (spec §2).
public enum RoutineNames {
    public static func localized(_ id: String) -> String {
        [
            "mon_push": "Lunes · Empuje",
            "tue_pull": "Martes · Tirón",
            "wed_legs": "Miércoles · Pierna y abdomen",
            "thu_rest": "Jueves · Descanso",
            "fri_upper": "Viernes · Tren superior y antebrazo",
            "sat_legs": "Sábado · Pierna y abdomen",
            "sun_rest": "Domingo · Descanso"
        ][id] ?? id
    }
}
