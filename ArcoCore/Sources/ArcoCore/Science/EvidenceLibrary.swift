import Foundation

/// Fuente consultable de la biblioteca de evidencia (spec §9, §24). Cada entrada indica qué
/// respalda y qué NO, para no convertir una referencia relacionada en una regla universal.
public struct EvidenceSource: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case training, bmi, apple

        public var displayName: String {
            switch self {
            case .training: return "Evidencia de entrenamiento"
            case .bmi: return "IMC y contexto corporal"
            case .apple: return "Documentación de Apple"
            }
        }
    }

    public let id: String
    /// Autoría o institución tal como figura en el §24 (nil en documentación técnica).
    public let authors: String?
    public let title: String
    /// Año de publicación (nil en referencias sin fecha de publicación única).
    public let year: Int?
    public let kind: Kind
    /// Enlace principal.
    public let url: String
    /// Enlaces adicionales (texto completo, comunicación oficial, permisos…).
    public let additionalURLs: [String]
    /// Qué respalda y qué no respalda, resumido.
    public let scope: String
    /// Fecha de revisión de la entrada (AAAA-MM-DD).
    public let reviewed: String

    public init(id: String, authors: String?, title: String, year: Int?, kind: Kind, url: String, additionalURLs: [String] = [], scope: String, reviewed: String = EvidenceLibrary.reviewDate) {
        self.id = id; self.authors = authors; self.title = title; self.year = year; self.kind = kind
        self.url = url; self.additionalURLs = additionalURLs; self.scope = scope; self.reviewed = reviewed
    }
}

/// Biblioteca de fuentes del §24 del encargo (E01–E13, B01–B03, A01–A13).
public enum EvidenceLibrary {
    public static let reviewDate = "2026-11-02"

    public static func sources(of kind: EvidenceSource.Kind) -> [EvidenceSource] {
        all.filter { $0.kind == kind }
    }

    public static func source(_ id: String) -> EvidenceSource? {
        all.first { $0.id == id }
    }

    public static let all: [EvidenceSource] = training + bmi + apple

    static let training: [EvidenceSource] = [
        EvidenceSource(
            id: "E01", authors: "ACSM", title: "Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults: An Overview of Reviews",
            year: 2026, kind: .training, url: "https://pubmed.ncbi.nlm.nih.gov/41843416/",
            additionalURLs: ["https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823/", "https://acsm.org/resistance-training-guidelines-update-2026/"],
            scope: "Síntesis para adultos sanos que orienta volumen, esfuerzo e individualización. No fija una dosis óptima universal ni una fórmula de recuperación."
        ),
        EvidenceSource(
            id: "E02", authors: "Pelland y colaboradores", title: "The Resistance Training Dose Response: Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on Muscle Hypertrophy and Strength Gains",
            year: 2026, kind: .training, url: "https://pubmed.ncbi.nlm.nih.gov/41343037/",
            additionalURLs: ["https://doi.org/10.1007/s40279-025-02344-w"],
            scope: "Justifica separar series directas e indirectas y estudiar un conteo fraccional como modelo agregado. No valida media serie para cada sinergista ni para cada variante."
        ),
        EvidenceSource(
            id: "E03", authors: "Robinson y colaboradores", title: "Exploring the Dose–Response Relationship Between Estimated Resistance Training Proximity to Failure, Strength Gain, and Muscle Hypertrophy",
            year: 2024, kind: .training, url: "https://link.springer.com/article/10.1007/s40279-024-02069-2",
            scope: "Relación exploratoria con el RIR, útil como contexto. Tiene incertidumbre y no obliga a llegar al fallo."
        ),
        EvidenceSource(
            id: "E04", authors: "Refalo y colaboradores", title: "Influence of Resistance Training Proximity-to-Failure on Skeletal Muscle Hypertrophy",
            year: 2023, kind: .training, url: "https://pubmed.ncbi.nlm.nih.gov/36334240/",
            scope: "Distingue el fallo momentáneo de otras definiciones. No demuestra que entrenar al fallo sea superior en general."
        ),
        EvidenceSource(
            id: "E05", authors: "Vigotsky y colaboradores", title: "Methods matter: the relationship between strength and hypertrophy depends on methods of measurement and analysis",
            year: 2018, kind: .training, url: "https://pubmed.ncbi.nlm.nih.gov/29967737/",
            scope: "Respalda separar el rendimiento (fuerza registrada) de la medición de hipertrofia. No permite deducir crecimiento muscular de los kilos."
        ),
        EvidenceSource(
            id: "E06", authors: "Schoenfeld y colaboradores", title: "Calculating Set-Volume for the Limb Muscles with the Performance of Multi-Joint Exercises",
            year: 2019, kind: .training, url: "https://pubmed.ncbi.nlm.nih.gov/31336594/",
            additionalURLs: ["https://pmc.ncbi.nlm.nih.gov/articles/PMC6681288/"],
            scope: "Analiza los límites del conteo entre ejercicios multiarticulares y monoarticulares. Es una perspectiva, no una tabla universal de coeficientes."
        ),
        EvidenceSource(
            id: "E07", authors: "Vigotsky y colaboradores", title: "Interpreting Signal Amplitudes in Surface Electromyography Studies in Sport and Rehabilitation Sciences",
            year: 2018, kind: .training, url: "https://pmc.ncbi.nlm.nih.gov/articles/PMC5758546/",
            scope: "Advierte contra inferir crecimiento muscular a partir de amplitudes de EMG. No aporta coeficientes de atribución."
        ),
        EvidenceSource(
            id: "E08", authors: "Kassiano y colaboradores", title: "Does Varying Resistance Exercises Promote Superior Muscle Hypertrophy and Strength Gains? A Systematic Review",
            year: 2022, kind: .training, url: "https://pubmed.ncbi.nlm.nih.gov/35438660/",
            additionalURLs: ["https://doi.org/10.1519/JSC.0000000000004258"],
            scope: "Sustenta una variación organizada de ejercicios y los límites de rotarlos en exceso. No prescribe un algoritmo individual."
        ),
        EvidenceSource(
            id: "E09", authors: "Kinoshita y colaboradores", title: "Hypertrophic Effects of Single- versus Multi-Joint Exercise: A Direct Comparison between Knee Extension and Leg Press",
            year: 2026, kind: .training, url: "https://pubmed.ncbi.nlm.nih.gov/41630124/",
            additionalURLs: ["https://doi.org/10.1249/MSS.0000000000003957"],
            scope: "Muestra diferencias entre músculos y regiones. No permite transferir un protocolo de prensa a cualquier máquina o ejecución."
        ),
        EvidenceSource(
            id: "E10", authors: "Maeo y colaboradores", title: "Triceps brachii hypertrophy is substantially greater after elbow extension training performed in the overhead versus neutral arm position",
            year: 2023, kind: .training, url: "https://pubmed.ncbi.nlm.nih.gov/35819335/",
            scope: "Ejemplo de especificidad regional. No prueba equivalencia con todo skull crusher ni justifica multiplicar su conteo."
        ),
        EvidenceSource(
            id: "E11", authors: "Kinoshita y colaboradores", title: "Triceps surae muscle hypertrophy is greater after standing versus seated calf-raise training",
            year: 2023, kind: .training, url: "https://pubmed.ncbi.nlm.nih.gov/38156065/",
            scope: "Diferencias según la posición de la rodilla y el músculo. Contexto para variantes, no coeficientes generales."
        ),
        EvidenceSource(
            id: "E12", authors: "IUSCA", title: "Resistance Training Recommendations to Maximize Muscle Hypertrophy in an Athletic Population",
            year: 2021, kind: .training, url: "https://journal.iusca.org/index.php/Journal/article/view/81",
            additionalURLs: ["https://doi.org/10.47206/ijsc.v1i1.81"],
            scope: "Consenso complementario de programación para población atlética. No sustituye a la evidencia en adultos sanos en general."
        ),
        EvidenceSource(
            id: "E13", authors: "Royal College of Physicians, NRAP", title: "Preguntas frecuentes del NRAP (fórmula de Epley)",
            year: 2025, kind: .training, url: "https://www.rcp.ac.uk/media/j1llw4ul/pr_faqs_v51_aug_2025.pdf",
            scope: "Verifica la fórmula de Epley como estimación a partir de una carga y repeticiones al fallo. No valida su exactitud para todo ejercicio, población o serie con RIR."
        )
    ]

    static let bmi: [EvidenceSource] = [
        EvidenceSource(
            id: "B01", authors: "NHS", title: "Calculadora de IMC para adultos",
            year: nil, kind: .bmi, url: "https://www.nhs.uk/health-assessment-tools/calculate-your-body-mass-index/calculate-bmi-for-adults",
            scope: "Calculadora adulta desde los 18 años, fórmula y límites del IMC cuando hay mucha masa muscular. No es un diagnóstico."
        ),
        EvidenceSource(
            id: "B02", authors: "NICE", title: "NG246: Identifying and assessing overweight, obesity and central adiposity",
            year: nil, kind: .bmi, url: "https://www.nice.org.uk/guidance/ng246/chapter/Identifying-and-assessing-overweight-obesity-and-central-adiposity",
            scope: "Referencias de IMC y límites de la evaluación. La app no implementa una valoración clínica completa ni ajustes étnicos."
        ),
        EvidenceSource(
            id: "B03", authors: "CDC", title: "Adult BMI Calculator",
            year: nil, kind: .bmi, url: "https://www.cdc.gov/bmi/adult-calculator/",
            scope: "Su marco adulto empieza a los 20 años. Se cita para explicar por qué Arco usa el marco NHS 18+ y no etiqueta su interpretación como CDC."
        )
    ]

    static let apple: [EvidenceSource] = [
        EvidenceSource(id: "A01", authors: nil, title: "Programar y cancelar notificaciones locales", year: nil, kind: .apple,
                       url: "https://developer.apple.com/documentation/UserNotifications/scheduling-a-notification-locally-from-your-app",
                       scope: "Avisos locales programados en el dispositivo, sin servidor. No garantiza ejecución de código en segundo plano."),
        EvidenceSource(id: "A02", authors: nil, title: "Notificaciones, Focus y entrega", year: nil, kind: .apple,
                       url: "https://developer.apple.com/design/human-interface-guidelines/managing-notifications",
                       scope: "Focus, resúmenes y permisos pueden cambiar cómo se presentan los avisos. Arco no pide alertas críticas."),
        EvidenceSource(id: "A03", authors: nil, title: "Datos de captura y guardado en fototeca como operación explícita", year: nil, kind: .apple,
                       url: "https://developer.apple.com/documentation/avfoundation/saving-captured-photos",
                       additionalURLs: ["https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media"],
                       scope: "Guardar en Fotos es una acción explícita y la cámara requiere permiso. Arco guarda las fotos solo en su bóveda."),
        EvidenceSource(id: "A04", authors: nil, title: "LocalAuthentication", year: nil, kind: .apple,
                       url: "https://developer.apple.com/documentation/localauthentication",
                       scope: "Face ID y código del dispositivo para proteger la bóveda."),
        EvidenceSource(id: "A05", authors: nil, title: "Protección de Keychain", year: nil, kind: .apple,
                       url: "https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web",
                       scope: "Cómo protege el llavero las claves y el PIN locales."),
        EvidenceSource(id: "A06", authors: nil, title: "Protección de archivos", year: nil, kind: .apple,
                       url: "https://developer.apple.com/documentation/foundation/fileprotectiontype",
                       scope: "Clases de protección de datos de los archivos guardados en el dispositivo."),
        EvidenceSource(id: "A07", authors: nil, title: "Privacidad y captura de interfaz al pasar a segundo plano", year: nil, kind: .apple,
                       url: "https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background",
                       scope: "Ocultar contenido privado antes de que el sistema capture la pantalla en segundo plano."),
        EvidenceSource(id: "A08", authors: nil, title: "Datos y exclusión de copias automáticas", year: nil, kind: .apple,
                       url: "https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup",
                       scope: "Qué datos entran en las copias de iCloud y cómo excluirlos."),
        EvidenceSource(id: "A09", authors: nil, title: "Materiales y Liquid Glass", year: nil, kind: .apple,
                       url: "https://developer.apple.com/design/human-interface-guidelines/materials",
                       scope: "Uso de materiales y transparencias en la interfaz."),
        EvidenceSource(id: "A10", authors: nil, title: "Controles táctiles y legibilidad", year: nil, kind: .apple,
                       url: "https://developer.apple.com/design/tips/",
                       scope: "Tamaños mínimos de controles táctiles y legibilidad del texto."),
        EvidenceSource(id: "A11", authors: nil, title: "Gráficos accesibles", year: nil, kind: .apple,
                       url: "https://developer.apple.com/design/human-interface-guidelines/charts",
                       scope: "Gráficos claros y accesibles, sin depender solo del color."),
        EvidenceSource(id: "A12", authors: nil, title: "Instalación personal y límites de firma", year: nil, kind: .apple,
                       url: "https://developer.apple.com/help/account/basics/about-your-developer-account",
                       scope: "Límites de instalación y firma con una cuenta de desarrollador personal."),
        EvidenceSource(id: "A13", authors: nil, title: "Qué significa el álbum Ocultos de Apple Fotos", year: nil, kind: .apple,
                       url: "https://support.apple.com/en-au/104987",
                       scope: "Explica qué hace el álbum Ocultos de Fotos. Arco no lo usa: guarda las fotos en su propia bóveda local, fuera de Fotos.")
    ]
}
