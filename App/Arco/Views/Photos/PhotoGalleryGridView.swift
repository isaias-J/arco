//
//  PhotoGalleryGridView.swift
//  Arco
//
//  Galería de la bóveda DESBLOQUEADA (spec §16 "Galería y comparación").
//
//  CRITERIOS / DECISIONES
//  ----------------------
//  - Lista de check-ins con fecha absoluta, tiempo transcurrido, pose y peso
//    asociado con su tipo (medido/estimado) — spec §16.
//  - Filtro por pose y por periodo (spec §16).
//  - Miniaturas descifradas de forma PEREZOSA con VaultImageLoader; no se cargan
//    todas las imágenes de años a memoria: LazyVGrid + carga bajo demanda +
//    caché acotada (T68).
//  - Descifrado/decodificación fuera del main actor, hop para mostrar
//    (skill swift-concurrency).
//  - Navegación a captura, comparación y secuencia desde aquí.
//

import SwiftUI
import SwiftData
import ArcoCore

// MARK: - Periodo de filtrado

/// Periodos de filtrado de la galería (spec §16 "Filtro por pose y periodo").
enum GalleryPeriod: String, CaseIterable, Identifiable {
    case all, last30, last90, lastYear
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Todo"
        case .last30: return "30 días"
        case .last90: return "90 días"
        case .lastYear: return "1 año"
        }
    }
    /// Fecha de corte inferior; nil = sin límite.
    var cutoff: Date? {
        let cal = Calendar.current
        switch self {
        case .all: return nil
        case .last30: return cal.date(byAdding: .day, value: -30, to: Date())
        case .last90: return cal.date(byAdding: .day, value: -90, to: Date())
        case .lastYear: return cal.date(byAdding: .year, value: -1, to: Date())
        }
    }
}

// MARK: - Galería

struct PhotoGalleryGridView: View {
    /// Orden descendente por fecha para ver primero lo más reciente.
    @Query(sort: \PhotoCheckInModel.date, order: .reverse)
    private var checkIns: [PhotoCheckInModel]

    /// Pesos para resolver el tipo (medido/estimado) y valor del peso asociado.
    @Query private var weights: [BodyWeightModel]

    @Environment(AppState.self) private var appState

    @State private var selectedPose: Pose?       // nil = todas
    @State private var period: GalleryPeriod = .all
    /// Revisión fotográfica en curso (hoja). Lleva el peso inicial si viene de Perfil.
    @State private var revisionRequest: PhotoRevisionRequest?

    /// Cargador compartido con caché acotada (T68). @State para vivir con la vista.
    @State private var loader = VaultImageLoader()

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: Spacing.sm)]

    var body: some View {
        ScrollView {
            filterBar
            if filtered.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.sm) {
                    // Identidad estable por id de modelo, nunca por índice.
                    ForEach(filtered, id: \.id) { checkIn in
                        NavigationLink {
                            PhotoDetailView(checkIn: checkIn, loader: loader, weight: weight(for: checkIn))
                        } label: {
                            PhotoThumbnailCell(
                                checkIn: checkIn,
                                loader: loader,
                                weight: weight(for: checkIn)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.sm)
            }
        }
        .background(ArcoColor.background)
        .navigationTitle("Bóveda")
        .toolbar { toolbarContent }
        .sheet(item: $revisionRequest) { request in
            CapturePosePickerView(initialWeightID: request.initialWeightID)
                .vaultPrivacyScreen()
        }
        .onAppear(perform: consumePendingWeight)
        .onChange(of: appState.pendingPhotoWeightID) { _, _ in consumePendingWeight() }
    }

    /// Perfil guardó un peso y el usuario pulsó "Añadir foto": tras desbloquear se abre la
    /// revisión con ese peso vinculado y la petición se limpia.
    private func consumePendingWeight() {
        guard let weightID = appState.pendingPhotoWeightID else { return }
        appState.pendingPhotoWeightID = nil
        revisionRequest = PhotoRevisionRequest(initialWeightID: weightID)
    }

    // MARK: Subvistas

    private var filterBar: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    PoseFilterChip(title: "Todas", isSelected: selectedPose == nil) {
                        selectedPose = nil
                    }
                    ForEach(Pose.predefined, id: \.id) { pose in
                        PoseFilterChip(title: pose.displayName, isSelected: selectedPose == pose) {
                            selectedPose = pose
                        }
                    }
                }
                .padding(.horizontal, Spacing.sm)
            }
            Picker("Periodo", selection: $period) {
                ForEach(GalleryPeriod.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Spacing.sm)
        }
        .padding(.top, Spacing.sm)
        .accessibilityElement(children: .contain)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Sin fotos en este filtro", systemImage: "photo.on.rectangle")
        } description: {
            Text("Toma una foto de progreso o ajusta el filtro de pose y periodo.")
        } actions: {
            Button("Tomar fotos") { revisionRequest = PhotoRevisionRequest() }
                .buttonStyle(.borderedProminent)
        }
        .padding(.top, Spacing.xxl)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                revisionRequest = PhotoRevisionRequest()
            } label: {
                Label("Tomar fotos", systemImage: "camera")
            }
        }
        ToolbarItemGroup(placement: .secondaryAction) {
            NavigationLink {
                PhotoComparisonView(checkIns: filtered, loader: loader)
            } label: {
                Label("Comparar", systemImage: "rectangle.split.2x1")
            }
            NavigationLink {
                PhotoTimelapseView(checkIns: filtered, loader: loader, weights: weights)
            } label: {
                Label("Secuencia", systemImage: "play.rectangle")
            }
            NavigationLink {
                VaultSettingsView()
            } label: {
                Label("Ajustes de la bóveda", systemImage: "gearshape")
            }
        }
    }

    // MARK: Datos derivados

    /// Check-ins tras aplicar filtros de pose y periodo.
    private var filtered: [PhotoCheckInModel] {
        checkIns.filter { item in
            if let selectedPose, Pose(rawValue: item.poseRaw) != selectedPose {
                return false
            }
            if let cutoff = period.cutoff, item.date < cutoff {
                return false
            }
            return true
        }
    }

    /// Resuelve el peso vinculado a un check-in (si lo hay), para mostrar valor
    /// y tipo (medido/estimado) — spec §16.
    private func weight(for checkIn: PhotoCheckInModel) -> BodyWeightModel? {
        guard let id = checkIn.bodyWeightID else { return nil }
        return weights.first { $0.id == id }
    }
}

// MARK: - Chip de filtro de pose

private struct PoseFilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(isSelected ? .bold : .regular))
                .padding(.vertical, Spacing.xs)
                .padding(.horizontal, Spacing.md)
                .background(
                    isSelected ? ArcoColor.brand : ArcoColor.surface,
                    in: Capsule()
                )
                .foregroundStyle(isSelected ? Color.white : ArcoColor.textPrimary)
        }
        .accessibilityLabel("Filtrar por \(title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Celda de miniatura (carga perezosa)

/// Celda que descifra su miniatura bajo demanda al aparecer, con placeholder.
/// El trabajo pesado corre en el actor `VaultImageLoader` (fuera del main actor)
/// y el resultado se publica aquí (skill de concurrencia).
struct PhotoThumbnailCell: View {
    let checkIn: PhotoCheckInModel
    let loader: VaultImageLoader
    let weight: BodyWeightModel?

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle()
                .fill(ArcoColor.surface)
                .aspectRatio(0.75, contentMode: .fit)
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView()
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.control))

            caption
        }
        .task(id: checkIn.id) {
            // Lado de píxel en función de la escala de pantalla (no estado global).
            let maxPixel = 104 * displayScale
            let loaded = await loader.image(fileName: checkIn.encryptedFileName, maxPixel: maxPixel)
            self.image = loaded
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Pose(rawValue: checkIn.poseRaw).displayName)
                .font(.caption2.bold())
            Text(checkIn.date, format: .dateTime.day().month())
                .font(.caption2)
        }
        .padding(Spacing.xs)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.control))
        .foregroundStyle(.primary)
        .padding(Spacing.xs)
    }

    private var accessibilityText: String {
        var parts = [Pose(rawValue: checkIn.poseRaw).displayName]
        parts.append(checkIn.date.formatted(date: .abbreviated, time: .omitted))
        if let weight {
            let kind = weight.isEstimated ? "estimado" : "medido"
            parts.append("peso \(kind)")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Detalle de un check-in

/// Detalle de un check-in: imagen a tamaño de pantalla, fecha absoluta, tiempo
/// transcurrido, pose y peso asociado con su tipo (spec §16). Permite borrar la foto (T67).
///
/// La vista trabaja con una instantánea de valores (no lee el modelo en `body`) para que
/// borrar el registro no deje la vista leyendo un modelo eliminado.
struct PhotoDetailView: View {
    private let photoID: UUID
    private let fileName: String
    private let pose: Pose
    private let date: Date
    private let weightText: String?
    let loader: VaultImageLoader

    init(checkIn: PhotoCheckInModel, loader: VaultImageLoader, weight: BodyWeightModel?) {
        self.photoID = checkIn.id
        self.fileName = checkIn.encryptedFileName
        self.pose = Pose(rawValue: checkIn.poseRaw)
        self.date = checkIn.date
        self.weightText = weight.map { "\($0.photoLabel) · \($0.measurementDate.formatted(date: .abbreviated, time: .omitted))" }
        self.loader = loader
    }

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                    } else {
                        RoundedRectangle(cornerRadius: Radius.card)
                            .fill(ArcoColor.surface)
                            .aspectRatio(0.75, contentMode: .fit)
                            .overlay { ProgressView() }
                    }
                }
                .accessibilityLabel("Foto de \(pose.displayName)")

                ArcoCard {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        LabeledContent("Pose", value: pose.displayName)
                        LabeledContent("Fecha", value: date.formatted(date: .long, time: .omitted))
                        LabeledContent("Hace", value: date.formatted(.relative(presentation: .named)))
                        LabeledContent("Peso", value: weightText ?? "Sin peso vinculado")
                    }
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Eliminar foto", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(isDeleting)

                if let deleteError {
                    Text(deleteError).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(Spacing.lg)
        }
        .background(ArcoColor.background)
        .navigationTitle(pose.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: photoID) {
            let maxPixel = 1200 * displayScale
            self.image = await loader.image(fileName: fileName, maxPixel: maxPixel)
        }
        .confirmationDialog("¿Eliminar esta foto?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Eliminar foto", role: .destructive) {
                Task { await deletePhoto() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Se borra la imagen cifrada y sus derivados de este dispositivo. El peso vinculado se conserva. Las copias exportadas que ya tengas no se borran.")
        }
    }

    private func deletePhoto() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await PhotoVaultOperations.deletePhoto(
                id: photoID,
                fileName: fileName,
                crypto: appState.vaultCrypto,
                loader: loader,
                context: modelContext
            )
            image = nil
            dismiss()
        } catch {
            deleteError = "No se pudo eliminar la foto. Inténtalo de nuevo."
        }
    }
}

// MARK: - Preview

#Preview("Galería vacía") {
    NavigationStack {
        PhotoGalleryGridView()
    }
    .modelContainer(for: [PhotoCheckInModel.self, BodyWeightModel.self], inMemory: true)
    .environment(AppState(context: ModelContext(try! ModelContainer(
        for: PhotoCheckInModel.self, BodyWeightModel.self, AppSettingsModel.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ))))
}
