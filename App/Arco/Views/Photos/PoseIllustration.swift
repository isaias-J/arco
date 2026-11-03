import SwiftUI

/// Ilustración original y minimalista de cada pose (spec §16: ilustración neutra y no
/// sexualizada). Se dibuja con trazos vectoriales en código: no usa fotografías ni recursos de
/// terceros. Sirve como referencia para repetir el mismo encuadre; no analiza el cuerpo.
///
/// Coordenadas normalizadas en una caja de 100 × 200 (ancho × alto).
struct PoseIllustration: View {
    let pose: Pose
    var color: Color = .primary
    /// Grosor relativo de los trazos (1 = normal).
    var weight: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let figure = PoseFigure.figure(for: pose)
            let scale = min(size.width / 100, size.height / 200)
            let origin = CGPoint(x: (size.width - 100 * scale) / 2, y: (size.height - 200 * scale) / 2)
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: origin.x + x * scale, y: origin.y + y * scale) }

            for limb in figure.limbs {
                var path = Path()
                path.move(to: p(limb.points[0].x, limb.points[0].y))
                for pt in limb.points.dropFirst() { path.addLine(to: p(pt.x, pt.y)) }
                context.stroke(path, with: .color(color.opacity(limb.faint ? 0.45 : 1)),
                               style: StrokeStyle(lineWidth: limb.width * scale * weight, lineCap: .round, lineJoin: .round))
            }
            let head = CGRect(x: origin.x + (figure.head.x - 11) * scale, y: origin.y + (figure.head.y - 11) * scale, width: 22 * scale, height: 22 * scale)
            context.fill(Path(ellipseIn: head), with: .color(color))
            for mark in figure.marks {
                var path = Path()
                path.move(to: p(mark.points[0].x, mark.points[0].y))
                for pt in mark.points.dropFirst() { path.addLine(to: p(pt.x, pt.y)) }
                context.stroke(path, with: .color(Color(.systemBackground).opacity(0.9)),
                               style: StrokeStyle(lineWidth: mark.width * scale * weight, lineCap: .round, lineJoin: .round))
            }
            if let arrow = figure.facing {
                // Flecha pequeña bajo los pies: hacia dónde mira la persona.
                var path = Path()
                let y: CGFloat = 196
                let x0: CGFloat = 50 - 14 * arrow, x1: CGFloat = 50 + 14 * arrow
                path.move(to: p(x0, y)); path.addLine(to: p(x1, y))
                path.move(to: p(x1 - 6 * arrow, y - 5)); path.addLine(to: p(x1, y)); path.addLine(to: p(x1 - 6 * arrow, y + 5))
                context.stroke(path, with: .color(color.opacity(0.6)), style: StrokeStyle(lineWidth: 2.5 * scale, lineCap: .round, lineJoin: .round))
            }
        }
        .aspectRatio(0.5, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// Geometría de cada pose. Los trazos gruesos forman un cuerpo esquemático; `marks` son detalles
/// claros sobre el cuerpo (p. ej. la línea de la columna en la espalda).
struct PoseFigure {
    struct Limb { let points: [CGPoint]; let width: CGFloat; var faint = false }
    let head: CGPoint
    let limbs: [Limb]
    var marks: [Limb] = []
    /// Dirección de la mirada en vistas de perfil (+1 derecha, −1 izquierda); nil de frente/espalda.
    var facing: CGFloat? = nil

    private static func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    private static func line(_ w: CGFloat, _ pts: (CGFloat, CGFloat)..., faint: Bool = false) -> Limb {
        Limb(points: pts.map { pt($0.0, $0.1) }, width: w, faint: faint)
    }

    /// Cuerpo de frente o de espaldas: tronco, piernas y brazos relajados a los lados.
    private static func frontal(back: Bool) -> PoseFigure {
        PoseFigure(
            head: pt(50, 22),
            limbs: [
                line(6, (50, 33), (50, 40)),                       // cuello
                line(22, (50, 50), (50, 102)),                     // tronco
                line(9, (38, 50), (62, 50)),                       // hombros
                line(7, (36, 52), (31, 80), (29, 108)),            // brazo izquierdo
                line(7, (64, 52), (69, 80), (71, 108)),            // brazo derecho
                line(9, (44, 108), (41, 148), (40, 186)),          // pierna izquierda
                line(9, (56, 108), (59, 148), (60, 186))           // pierna derecha
            ],
            marks: back
                ? [line(1.6, (50, 54), (50, 98)), line(1.4, (42, 60), (45, 68)), line(1.4, (58, 60), (55, 68))]
                : [line(1.4, (45, 96), (55, 96))]
        )
    }

    /// Perfil mirando a la derecha: un brazo junto al cuerpo y piernas casi alineadas.
    private static func profile(bicepsFlexed: Bool) -> PoseFigure {
        var limbs: [Limb] = [
            line(6, (50, 33), (51, 40)),                           // cuello
            line(15, (50, 50), (49, 102)),                         // tronco de perfil (más estrecho)
            line(9, (48, 108), (46, 148), (46, 186), faint: true), // pierna de fondo
            line(9, (51, 108), (52, 148), (53, 186)),              // pierna de frente
            line(3, (53, 186), (61, 187))                          // pie que indica la dirección
        ]
        if bicepsFlexed {
            limbs.append(line(7, (52, 52), (70, 56), (72, 36)))    // brazo flexionado al frente
        } else {
            limbs.append(line(7, (51, 52), (53, 80), (53, 106)))   // brazo junto al cuerpo
        }
        return PoseFigure(head: pt(51, 22), limbs: limbs, marks: [line(1.6, (57, 21), (60, 23))], facing: 1)
    }

    /// Doble bíceps de frente: brazos a la altura de los hombros y antebrazos hacia arriba.
    private static func doubleBiceps() -> PoseFigure {
        PoseFigure(
            head: pt(50, 22),
            limbs: [
                line(6, (50, 33), (50, 40)),
                line(22, (50, 50), (50, 102)),
                line(9, (38, 50), (62, 50)),
                line(7, (36, 51), (18, 50), (16, 30)),             // brazo izquierdo flexionado
                line(7, (64, 51), (82, 50), (84, 30)),             // brazo derecho flexionado
                line(9, (44, 108), (40, 148), (38, 186)),
                line(9, (56, 108), (60, 148), (62, 186))
            ],
            marks: [line(1.4, (45, 96), (55, 96))]
        )
    }

    static func figure(for pose: Pose) -> PoseFigure {
        switch pose {
        case .frontRelaxed: return frontal(back: false)
        case .back: return frontal(back: true)
        case .side: return profile(bicepsFlexed: false)
        case .sideBiceps: return profile(bicepsFlexed: true)
        case .frontDoubleBiceps: return doubleBiceps()
        case .custom: return frontal(back: false)
        }
    }
}

/// Explicación paso a paso para repetir la pose (texto que acompaña a la ilustración).
extension Pose {
    var steps: [String] {
        switch self {
        case .frontRelaxed:
            return ["De frente a la cámara, pies a la anchura de la cadera.", "Brazos relajados a los lados, sin apretar.", "Mirada al frente; la cabeza dentro del tercio superior."]
        case .side:
            return ["Gira 90° hasta quedar de perfil.", "Brazo del lado de la cámara junto al cuerpo.", "Mira al frente, no a la cámara."]
        case .back:
            return ["De espaldas a la cámara, pies a la anchura de la cadera.", "Brazos relajados a los lados.", "Mismo punto del suelo que en la foto de frente."]
        case .frontDoubleBiceps:
            return ["De frente, brazos a la altura de los hombros.", "Flexiona los codos y lleva los puños hacia arriba.", "Mantén los pies como en la pose frontal."]
        case .sideBiceps:
            return ["De perfil, como en la pose lateral.", "Flexiona el brazo del lado de la cámara al frente.", "El otro brazo queda detrás, sin tapar el cuerpo."]
        case .custom:
            return ["Repite siempre el mismo encuadre, distancia y luz."]
        }
    }

    /// Las personalizadas no tienen ilustración específica.
    var hasIllustration: Bool {
        if case .custom = self { return false }
        return true
    }
}

#Preview {
    HStack {
        ForEach(Pose.predefined) { pose in
            VStack {
                PoseIllustration(pose: pose, color: .blue).frame(height: 140)
                Text(pose.displayName).font(.caption2)
            }
        }
    }
    .padding()
}

/// Guía con la ilustración grande y los pasos de cada pose predefinida.
struct PoseGuideView: View {
    var body: some View {
        List {
            Section {
                Text("Repite la misma pose, distancia, altura de la cámara y luz en cada revisión: así la comparación es honesta. Las ilustraciones son esquemáticas y solo orientan el encuadre.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Pose.predefined) { pose in
                Section(pose.isBase ? "\(pose.displayName) · base" : "\(pose.displayName) · opcional") {
                    HStack(alignment: .top, spacing: Spacing.lg) {
                        PoseIllustration(pose: pose, color: ArcoColor.brand)
                            .frame(width: 70, height: 140)
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            ForEach(pose.steps, id: \.self) { Text("• \($0)").font(.footnote) }
                        }
                    }
                    .padding(.vertical, Spacing.xs)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(pose.displayName). \(pose.steps.joined(separator: " "))")
                }
            }
        }
        .navigationTitle("Guía de poses")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("poseGuide")
    }
}
