//
//  PhotoComparisonView.swift
//  Arco
//
//  Comparación de dos imágenes de la bóveda (spec §16 "Comparación lado a lado
//  o deslizador entre dos imágenes").
//
//  DECISIONES
//  ----------
//  - Dos modos: lado a lado y deslizador (slider con revelado).
//  - No modifica proporciones para "alinear" cuerpos (spec §16): las imágenes se
//    muestran con scaledToFit, sin estirar ni deformar.
//  - Descifrado fuera del main actor vía VaultImageLoader; hop para mostrar
//    (skill swift-concurrency).
//

import SwiftUI
import SwiftData
import ArcoCore

struct PhotoComparisonView: View {
    let checkIns: [PhotoCheckInModel]
    let loader: VaultImageLoader

    @State private var leftID: UUID?
    @State private var rightID: UUID?
    @State private var mode: ComparisonMode = .sideBySide

    enum ComparisonMode: String, CaseIterable, Identifiable {
        case sideBySide, slider
        var id: String { rawValue }
        var label: String {
            switch self {
            case .sideBySide: return "Lado a lado"
            case .slider: return "Deslizador"
            }
        }
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            if checkIns.count < 2 {
                ContentUnavailableView {
                    Label("Necesitas dos fotos", systemImage: "rectangle.split.2x1")
                } description: {
                    Text("La comparación requiere al menos dos registros. Toma más fotos para comparar tu evolución.")
                }
            } else {
                pickers
                Picker("Modo", selection: $mode) {
                    ForEach(ComparisonMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.lg)

                comparisonArea
            }
        }
        .padding(.top, Spacing.md)
        .background(ArcoColor.background)
        .navigationTitle("Comparar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: selectDefaults)
    }

    // MARK: Subvistas

    private var pickers: some View {
        HStack(spacing: Spacing.md) {
            checkInPicker("Antes", selection: $leftID)
            checkInPicker("Después", selection: $rightID)
        }
        .padding(.horizontal, Spacing.lg)
    }

    private func checkInPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            ForEach(checkIns, id: \.id) { item in
                Text("\(Pose(rawValue: item.poseRaw).displayName) · \(item.date.formatted(date: .abbreviated, time: .omitted))")
                    .tag(Optional(item.id))
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel("\(title): elegir foto")
    }

    @ViewBuilder
    private var comparisonArea: some View {
        switch mode {
        case .sideBySide:
            HStack(spacing: Spacing.sm) {
                comparisonImage(for: leftID, label: "Antes")
                comparisonImage(for: rightID, label: "Después")
            }
            .padding(Spacing.lg)
        case .slider:
            if let leftID, let rightID {
                SliderCompareView(
                    topFileName: fileName(for: rightID),
                    bottomFileName: fileName(for: leftID),
                    loader: loader
                )
                .padding(Spacing.lg)
            } else {
                Spacer()
            }
        }
    }

    private func comparisonImage(for id: UUID?, label: String) -> some View {
        VStack(spacing: Spacing.xs) {
            VaultAsyncImage(fileName: fileName(for: id), loader: loader, maxPixel: 900)
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            if let item = checkIn(for: id) {
                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("\(label): \(checkIn(for: id).map { $0.date.formatted(date: .abbreviated, time: .omitted) } ?? "sin selección")")
    }

    // MARK: Datos

    private func selectDefaults() {
        guard checkIns.count >= 2 else { return }
        if leftID == nil { leftID = checkIns.last?.id }     // más antigua
        if rightID == nil { rightID = checkIns.first?.id }  // más reciente
    }

    private func checkIn(for id: UUID?) -> PhotoCheckInModel? {
        guard let id else { return nil }
        return checkIns.first { $0.id == id }
    }

    private func fileName(for id: UUID?) -> String? {
        checkIn(for: id)?.encryptedFileName
    }
}

// MARK: - Vista de deslizador

/// Revela la imagen superior sobre la inferior según la posición del deslizador.
/// No deforma ninguna imagen: ambas usan el mismo encuadre con scaledToFit.
private struct SliderCompareView: View {
    let topFileName: String?
    let bottomFileName: String?
    let loader: VaultImageLoader

    @State private var reveal: CGFloat = 0.5

    var body: some View {
        VStack(spacing: Spacing.md) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    VaultAsyncImage(fileName: bottomFileName, loader: loader, maxPixel: 1200)
                    VaultAsyncImage(fileName: topFileName, loader: loader, maxPixel: 1200)
                        .frame(width: geo.size.width * reveal, alignment: .leading)
                        .clipped()
                    // Línea separadora del revelado.
                    Rectangle()
                        .fill(Color.white)
                        .frame(width: 2)
                        .offset(x: geo.size.width * reveal - 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))
            }
            .aspectRatio(0.75, contentMode: .fit)

            Slider(value: $reveal, in: 0...1) {
                Text("Revelado")
            }
            .accessibilityLabel("Deslizador de comparación")
            .accessibilityValue("\(Int(reveal * 100)) por ciento")
        }
    }
}

// MARK: - Imagen asíncrona descifrada reutilizable

/// Carga y muestra una imagen de la bóveda de forma perezosa, sin deformar.
/// Reutilizable por comparación y secuencia.
struct VaultAsyncImage: View {
    let fileName: String?
    let loader: VaultImageLoader
    let maxPixel: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()            // nunca deforma (spec §16)
            } else {
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(ArcoColor.surface)
                    .aspectRatio(0.75, contentMode: .fit)
                    .overlay {
                        if fileName == nil {
                            Image(systemName: "photo").foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                        }
                    }
            }
        }
        .task(id: fileName) {
            guard let fileName else {
                image = nil
                return
            }
            image = await loader.image(fileName: fileName, maxPixel: maxPixel * displayScale)
        }
    }
}

// MARK: - Preview

#Preview("Comparación — sin datos") {
    NavigationStack {
        PhotoComparisonView(checkIns: [], loader: VaultImageLoader())
    }
}
