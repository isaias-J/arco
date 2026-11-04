import SwiftUI

/// Tokens de diseño (spec §20). Identidad de azules, curvas y profundidad sutil.
/// Colores semánticos adaptativos claro/oscuro. Respeta Aumentar contraste y Reducir
/// transparencia mediante materiales nativos y variantes legibles.
enum ArcoColor {
    // Fondos y superficies
    static let background = Color("ArcoBackground", bundle: .main)
    static let surface = Color("ArcoSurface", bundle: .main)

    // Texto
    static let textPrimary = Color("ArcoTextPrimary", bundle: .main)
    static let textSecondary = Color("ArcoTextSecondary", bundle: .main)

    // Acentos
    static let brand = Color("ArcoBrand", bundle: .main)        // azul #4B8DFF
    static let chart = Color("ArcoChart", bundle: .main)        // cian #59D5FF
    static let chartSecondary = Color("ArcoChartSecondary", bundle: .main) // violeta #9F8AFF

    /// Variante de marca legible como texto sobre superficie clara (azul más oscuro).
    static let brandText = Color("ArcoBrandText", bundle: .main)
}

/// Escala de espaciado base 4/8 (spec §20).
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// Radios coherentes (bordes suaves, curvas — spec §20).
enum Radius {
    static let card: CGFloat = 20
    static let control: CGFloat = 12
    static let pill: CGFloat = 999
}

/// Tema de la app.
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Tarjeta con profundidad sutil. No aplica vidrio a todas las tarjetas por igual (spec §20):
/// usa superficie legible. La transparencia se reserva para navegación/controles.
struct ArcoCard<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.xl)
            .background {
                let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
                shape.fill(ArcoColor.surface)
                    .overlay {
                        if !reduceTransparency {
                            shape.fill(LinearGradient(
                                colors: [ArcoColor.brand.opacity(scheme == .dark ? 0.13 : 0.05), .clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        }
                    }
                    .overlay {
                        shape.strokeBorder(
                            LinearGradient(colors: [
                                ArcoColor.brand.opacity(scheme == .dark ? 0.30 : 0.16),
                                ArcoColor.brand.opacity(0.03)
                            ], startPoint: .topLeading, endPoint: .bottomTrailing),
                            lineWidth: 1
                        )
                    }
                    .shadow(color: .black.opacity(scheme == .dark ? 0.18 : 0.035), radius: 18, y: 8)
            }
    }
}

/// Un fondo discreto y adaptable, sin imágenes ni datos decorativos que parezcan métricas.
struct ArcoBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ArcoColor.background
            if !reduceTransparency {
                RadialGradient(
                    colors: [ArcoColor.brand.opacity(scheme == .dark ? 0.20 : 0.09), .clear],
                    center: .topTrailing, startRadius: 0, endRadius: 420
                )
                RadialGradient(
                    colors: [ArcoColor.chartSecondary.opacity(scheme == .dark ? 0.07 : 0.04), .clear],
                    center: .bottomLeading, startRadius: 0, endRadius: 360
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Etiqueta editorial para identificar secciones sin añadir ruido visual.
struct ArcoEyebrow: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(1.5)
            .foregroundStyle(ArcoColor.brandText)
    }
}
