//
//  PhotoTimelapseView.swift
//  Arco
//
//  Secuencia tipo timelapse de la bóveda (spec §16 "Secuencia tipo timelapse
//  ordenada por fecha").
//
//  CRITERIOS / DECISIONES
//  ----------------------
//  - Ordenada por fecha; por defecto solo poses compatibles (una misma pose),
//    para no mezclar encuadres distintos (spec §16).
//  - Reproducir / pausar / cambiar velocidad / arrastrar el progreso.
//  - Fecha y peso superpuestos OPCIONALES durante la reproducción (spec §16).
//  - Con una sola foto: se muestra y se explica que la secuencia requiere más
//    registros (spec §16).
//  - Memoria controlada (T68): se precarga solo un pequeño prefetch alrededor
//    del fotograma actual a través de la caché acotada del VaultImageLoader; NO
//    se cargan todas las imágenes a la vez.
//  - NO genera un vídeo persistente (spec §16): la "reproducción" es un avance
//    de índice en memoria con un temporizador, sin exportar archivo alguno.
//
//  CONCURRENCIA (skill swift-concurrency)
//  --------------------------------------
//  - El avance de fotogramas usa un Task con Task.sleep: la espera no bloquea el
//    hilo y la mutación del índice (estado de UI) ocurre en el main actor.
//  - El descifrado/decodificación lo hace el actor VaultImageLoader fuera del
//    main actor; la vista hace hop para mostrar.
//

import SwiftUI
import SwiftData
import ArcoCore

struct PhotoTimelapseView: View {
    let checkIns: [PhotoCheckInModel]
    let loader: VaultImageLoader
    let weights: [BodyWeightModel]

    /// Pose seleccionada para la secuencia (compatibilidad por defecto). nil se
    /// resuelve a la pose con más registros al aparecer.
    @State private var pose: Pose?
    @State private var index: Int = 0
    @State private var isPlaying = false
    @State private var speed: Double = 1.0          // fotogramas por segundo base
    @State private var showOverlay = true           // fecha/peso superpuestos
    @State private var playbackTask: Task<Void, Never>?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(spacing: Spacing.md) {
            if sequence.isEmpty {
                emptyState
            } else if sequence.count == 1 {
                singlePhotoState
            } else {
                playerArea
                controls
            }
        }
        .padding(.top, Spacing.md)
        .background(ArcoColor.background)
        .navigationTitle("Secuencia")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: resolveDefaultPose)
        .onDisappear { stop() }
    }

    // MARK: Estados

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Sin fotos para la secuencia", systemImage: "play.rectangle")
        } description: {
            Text("Toma fotos de una misma pose en distintas fechas para ver tu evolución en secuencia.")
        }
    }

    /// Con una sola foto: mostrarla y explicar que falta más (spec §16).
    private var singlePhotoState: some View {
        VStack(spacing: Spacing.lg) {
            poseSelector
            VaultAsyncImage(fileName: sequence.first?.encryptedFileName, loader: loader, maxPixel: 1200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .padding(.horizontal, Spacing.lg)
            Text("Solo hay una foto de esta pose. La secuencia necesita más registros en distintas fechas para reproducir tu evolución.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Spacer()
        }
    }

    private var playerArea: some View {
        ZStack(alignment: .bottomLeading) {
            VaultAsyncImage(fileName: currentCheckIn?.encryptedFileName, loader: loader, maxPixel: 1200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))

            if showOverlay, let item = currentCheckIn {
                overlayBadge(for: item)
            }
        }
        .padding(.horizontal, Spacing.lg)
        .task(id: index) { prefetchNeighbors() }
    }

    private func overlayBadge(for item: PhotoCheckInModel) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.date.formatted(date: .abbreviated, time: .omitted))
                .font(.caption.bold())
            if let w = weight(for: item) {
                Text(verbatim: w.photoLabel)
                    .font(.caption2)
            }
        }
        .padding(Spacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.control))
        .foregroundStyle(.primary)
        .padding(Spacing.lg + Spacing.sm)
        .accessibilityElement(children: .combine)
    }

    private var controls: some View {
        VStack(spacing: Spacing.md) {
            poseSelector

            // Barra de progreso arrastrable.
            Slider(
                value: Binding(
                    get: { Double(index) },
                    set: { newValue in
                        index = min(max(0, Int(newValue.rounded())), sequence.count - 1)
                    }
                ),
                in: 0...Double(max(sequence.count - 1, 1)),
                step: 1
            )
            .accessibilityLabel("Progreso de la secuencia")
            .accessibilityValue("Foto \(index + 1) de \(sequence.count)")

            HStack(spacing: Spacing.xl) {
                Button {
                    isPlaying ? stop() : play()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 44))
                }
                .accessibilityLabel(isPlaying ? "Pausar" : "Reproducir")

                Picker("Velocidad", selection: $speed) {
                    Text("0,5×").tag(0.5)
                    Text("1×").tag(1.0)
                    Text("2×").tag(2.0)
                    Text("4×").tag(4.0)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .accessibilityLabel("Velocidad de reproducción")
                .onChange(of: speed) { _, _ in
                    if isPlaying { play() }  // reinicia el temporizador al nuevo ritmo
                }

                Toggle(isOn: $showOverlay) {
                    Image(systemName: "textformat")
                }
                .toggleStyle(.button)
                .accessibilityLabel("Mostrar fecha y peso")
            }
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.bottom, Spacing.lg)
    }

    private var poseSelector: some View {
        Picker("Pose", selection: $pose) {
            ForEach(availablePoses, id: \.id) { p in
                Text(p.displayName).tag(Optional(p))
            }
        }
        .pickerStyle(.menu)
        .onChange(of: pose) { _, _ in
            stop()
            index = 0
        }
        .accessibilityLabel("Pose de la secuencia")
    }

    // MARK: Reproducción (sin vídeo persistente)

    private func play() {
        playbackTask?.cancel()
        isPlaying = true
        let count = sequence.count
        guard count > 1 else { isPlaying = false; return }
        let interval = 1.0 / max(speed, 0.25)
        // La espera no necesita el main actor; la mutación de índice sí (estado UI).
        playbackTask = Task { [interval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                if index >= count - 1 {
                    // Llegó al final: detiene (no genera bucle ni exporta nada).
                    isPlaying = false
                    return
                }
                index += 1
            }
        }
    }

    private func stop() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }

    // MARK: Prefetch acotado (memoria controlada, T68)

    /// Precarga solo el fotograma siguiente y el anterior. La caché acotada del
    /// loader expulsa lo viejo, evitando retener toda la secuencia en memoria.
    private func prefetchNeighbors() {
        let neighbors = [index - 1, index + 1].filter { $0 >= 0 && $0 < sequence.count }
        let maxPixel = 1200 * displayScale
        for n in neighbors {
            let name = sequence[n].encryptedFileName
            Task { _ = await loader.image(fileName: name, maxPixel: maxPixel) }
        }
    }

    // MARK: Datos derivados

    /// Poses presentes en los check-ins, ordenadas por frecuencia desc.
    private var availablePoses: [Pose] {
        let grouped = Dictionary(grouping: checkIns) { Pose(rawValue: $0.poseRaw) }
        return grouped.keys.sorted { (grouped[$0]?.count ?? 0) > (grouped[$1]?.count ?? 0) }
    }

    /// Secuencia de la pose seleccionada, ordenada por fecha ascendente.
    private var sequence: [PhotoCheckInModel] {
        guard let pose else { return [] }
        return checkIns
            .filter { Pose(rawValue: $0.poseRaw) == pose }
            .sorted { $0.date < $1.date }
    }

    private var currentCheckIn: PhotoCheckInModel? {
        guard sequence.indices.contains(index) else { return sequence.last }
        return sequence[index]
    }

    private func resolveDefaultPose() {
        if pose == nil { pose = availablePoses.first }
    }

    private func weight(for item: PhotoCheckInModel) -> BodyWeightModel? {
        guard let id = item.bodyWeightID else { return nil }
        return weights.first { $0.id == id }
    }
}

// MARK: - Preview

#Preview("Secuencia — sin datos") {
    NavigationStack {
        PhotoTimelapseView(checkIns: [], loader: VaultImageLoader(), weights: [])
    }
}
