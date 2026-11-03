//
//  CameraCaptureView.swift
//  Arco
//
//  Captura de fotos de progreso con AVFoundation DENTRO de la app (spec §16
//  "Captura"). No usa PhotoKit ni escribe en Apple Fotos / álbum Ocultos (T48).
//
//  CRITERIOS CUBIERTOS
//  -------------------
//  - T47: si la cámara se deniega o la captura se cancela, el resto de la app y
//    el pesaje siguen utilizables. Se maneja el estado denegado con mensaje y
//    acceso directo a Ajustes; cancelar solo cierra la hoja.
//  - T48: al guardar se cifra el JPEG con VaultCrypto.writeEncryptedFile y se
//    crea un PhotoCheckInModel. Nunca se escribe en la fototeca ni en Ocultos.
//  - Se pide permiso de cámara al ABRIR esta función (no al instalar).
//  - Cuadrícula guía, referencia de pose y temporizador fotográfico OPCIONAL
//    (este temporizador SÍ está permitido; no es el temporizador de descanso).
//  - Confirmar / repetir / cancelar antes de guardar.
//  - Se eliminan metadatos GPS/EXIF innecesarios de la copia gestionada,
//    conservando solo fecha y orientación en el modelo (spec §16).
//
//  CONCURRENCIA (skill swift-concurrency)
//  --------------------------------------
//  - `CameraController` es @Observable @MainActor: su estado dirige la UI.
//  - La AVCaptureSession corre en su PROPIA cola serie (`sessionQueue`), nunca
//    en el main actor: configurarla y arrancarla bloquea, así que se hace fuera
//    del main actor y se vuelve (hop) al main actor solo para publicar estado.
//  - El cifrado/strip de metadatos se hace fuera del main actor y se vuelve al
//    main actor para tocar SwiftData y cerrar la hoja.
//

import SwiftUI
import SwiftData
import ArcoCore
@preconcurrency import AVFoundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Estado de autorización

/// Estado de permiso de cámara mapeado a la UI (spec §16, T47).
enum CameraPermission: Sendable, Equatable {
    case notDetermined
    case authorized
    case denied      // denegado o restringido: se ofrece ir a Ajustes
}

// MARK: - Controller de cámara

/// Orquesta la sesión de captura de AVFoundation.
///
/// @MainActor porque publica estado observado por SwiftUI. La sesión real vive
/// en `sessionQueue` (cola serie dedicada) para no bloquear el main actor; los
/// resultados se reenvían al main actor con `MainActor.run` / `await`.
@MainActor
@Observable
final class CameraController: NSObject {

    // MARK: Estado publicado (UI)

    /// Permiso actual de cámara. Arranca sin determinar y se resuelve al abrir.
    private(set) var permission: CameraPermission = .notDetermined

    /// Indica si la sesión está activa y mostrando vista previa.
    private(set) var isRunning = false

    /// Imagen capturada pendiente de confirmar (nil mientras se previsualiza).
    private(set) var capturedImage: UIImage?

    /// Datos JPEG ya sin metadatos sensibles, listos para cifrar al confirmar.
    private(set) var capturedJPEGData: Data?

    /// Mensaje de error legible para la UI (sin rutas ni datos sensibles, T65).
    private(set) var errorMessage: String?

    /// Cuenta atrás visible del temporizador fotográfico (0 = inactivo).
    private(set) var countdown: Int = 0

    /// Evita guardar dos veces la misma captura por pulsaciones repetidas.
    private(set) var isSaving = false

    // MARK: Infraestructura AVFoundation (no publicada)

    /// La sesión no es observable: no debe disparar invalidaciones de SwiftUI.
    let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()

    /// Cola serie dedicada: toda la configuración/arranque de la sesión ocurre
    /// aquí, nunca en el main actor (evita bloqueos de UI).
    private let sessionQueue = DispatchQueue(label: "com.arco.camera.session")

    private var isConfigured = false
    private var countdownTask: Task<Void, Never>?

    // MARK: - Ciclo de vida

    /// Solicita permiso (si hace falta) y arranca la sesión. Se llama al abrir
    /// la función de captura, no al instalar (spec §16).
    func start() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            permission = .authorized
        case .notDetermined:
            permission = .notDetermined
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            permission = granted ? .authorized : .denied
        case .denied, .restricted:
            permission = .denied
        @unknown default:
            permission = .denied
        }

        guard permission == .authorized else { return }
        await configureAndRunSession()
    }

    /// Detiene la sesión y cancela temporizadores. Idempotente.
    func stop() {
        countdownTask?.cancel()
        countdownTask = nil
        countdown = 0
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
        isRunning = false
    }

    /// Configura entradas/salidas y arranca la sesión fuera del main actor.
    private func configureAndRunSession() async {
        let session = self.session
        let output = self.photoOutput
        let alreadyConfigured = isConfigured

        // El trabajo de configuración corre en la cola de la sesión; devolvemos
        // si tuvo éxito para publicar estado en el main actor.
        let ok: Bool = await withCheckedContinuation { continuation in
            sessionQueue.async {
                if alreadyConfigured {
                    if !session.isRunning { session.startRunning() }
                    continuation.resume(returning: true)
                    return
                }

                session.beginConfiguration()
                session.sessionPreset = .photo

                guard
                    let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
                        ?? AVCaptureDevice.default(for: .video),
                    let input = try? AVCaptureDeviceInput(device: device),
                    session.canAddInput(input)
                else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                session.addInput(input)

                guard session.canAddOutput(output) else {
                    session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                session.addOutput(output)
                session.commitConfiguration()
                session.startRunning()
                continuation.resume(returning: true)
            }
        }

        if ok {
            isConfigured = true
            isRunning = true
        } else {
            errorMessage = "No se pudo iniciar la cámara en este dispositivo."
        }
    }

    // MARK: - Temporizador fotográfico (permitido, spec §16)

    /// Dispara con un temporizador opcional de `seconds` segundos. El descanso
    /// entre series NO lleva temporizador; este es el de la cámara, sí permitido.
    func capture(withTimer seconds: Int) {
        countdownTask?.cancel()
        guard seconds > 0 else {
            capturePhotoNow()
            return
        }
        // La espera NO necesita el main actor; solo la mutación de `countdown`.
        // Mantenemos la cuenta atrás en el main actor por ser estado de UI, pero
        // la pausa usa Task.sleep sin bloquear el hilo.
        countdownTask = Task { [weak self] in
            guard let self else { return }
            var remaining = seconds
            self.countdown = remaining
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                remaining -= 1
                self.countdown = remaining
            }
            self.capturePhotoNow()
        }
    }

    /// Captura inmediata. La entrega del resultado llega por el delegate.
    private func capturePhotoNow() {
        countdown = 0
        let settings = AVCapturePhotoSettings()
        // No pedimos ubicación ni incrustamos metadatos adicionales; los que
        // queden se eliminan al procesar (spec §16 "Eliminar coordenadas GPS").
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Confirmar / repetir

    /// Descarta la captura actual para repetir (spec §16 "repetir").
    func retake() {
        capturedImage = nil
        capturedJPEGData = nil
        errorMessage = nil
    }

    /// Cifra la captura confirmada y crea el `PhotoCheckInModel` asociado.
    ///
    /// El cifrado y el strip de metadatos ocurren fuera del main actor; la
    /// escritura en SwiftData vuelve al main actor (skill de concurrencia, T48).
    /// - Returns: el id del `PhotoCheckInModel` creado, o nil si falla.
    func confirmAndSave(
        pose: Pose,
        date: Date,
        crypto: VaultCrypto,
        context: ModelContext,
        bodyWeightID: UUID?
    ) async -> UUID? {
        guard !isSaving else { return nil }
        guard let jpeg = capturedJPEGData else {
            errorMessage = "No hay ninguna foto para guardar."
            return nil
        }
        isSaving = true
        defer { isSaving = false }

        let fileName = "checkin-\(UUID().uuidString).enc"

        // Cifrado fuera del main actor: VaultCrypto es Sendable y nonisolated.
        let saved: Bool = await Task.detached(priority: .userInitiated) {
            do {
                try crypto.writeEncryptedFile(jpeg, named: fileName)
                return true
            } catch {
                return false
            }
        }.value

        guard saved else {
            errorMessage = "No se pudo guardar la foto cifrada."
            return nil
        }

        // Volvemos al main actor (ya estamos en él) para tocar SwiftData.
        let model = PhotoCheckInModel(
            date: date,
            poseRaw: pose.rawValue,
            encryptedFileName: fileName,
            orientationRaw: 0,     // la copia gestionada se normaliza "arriba"
            mirrored: false,
            bodyWeightID: bodyWeightID
        )
        context.insert(model)
        do {
            try context.save()
        } catch {
            // Sin registro no debe quedar un archivo cifrado huérfano.
            context.delete(model)
            try? crypto.deleteEncryptedFile(named: fileName)
            errorMessage = "No se pudo registrar la foto."
            return nil
        }

        capturedImage = nil
        capturedJPEGData = nil
        return model.id
    }
}

// MARK: - Delegate de captura

/// El delegate de AVFoundation llega en una cola de la sesión. Hacemos hop al
/// main actor para publicar el resultado (skill de concurrencia).
extension CameraController: @preconcurrency AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Procesamos (strip de metadatos) fuera del main actor y publicamos en él.
        let fileData = photo.fileDataRepresentation()
        Task { @concurrent in
            let processed = CameraController.sanitizedJPEG(from: fileData)
            await MainActor.run {
                if let processed {
                    self.capturedJPEGData = processed.data
                    self.capturedImage = processed.image
                } else {
                    self.errorMessage = "No se pudo procesar la foto."
                }
            }
        }
    }

    /// Reencoda el JPEG eliminando metadatos GPS/EXIF innecesarios, conservando
    /// solo orientación normalizada (spec §16). Devuelve datos + imagen para UI.
    /// `nonisolated static` para poder ejecutarse fuera del main actor.
    nonisolated static func sanitizedJPEG(from data: Data?) -> (data: Data, image: UIImage)? {
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        // Escribimos un JPEG nuevo SIN diccionarios GPS/EXIF: solo orientación.
        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }

        // Conservamos únicamente orientación (ya normalizada a .up al re-codificar).
        let properties: [CFString: Any] = [
            kCGImagePropertyOrientation: 1,              // 1 = up
            kCGImageDestinationLossyCompressionQuality: 0.9
        ]
        CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }

        let clean = output as Data
        guard let image = UIImage(data: clean) else { return nil }
        return (clean, image)
    }
}

// MARK: - Vista previa de la cámara (AVCaptureVideoPreviewLayer)

/// Puente mínimo a `AVCaptureVideoPreviewLayer`. No hay API SwiftUI nativa para
/// la vista previa de AVFoundation, por lo que se justifica el puente a UIKit.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    /// UIView cuyo layer backing es un `AVCaptureVideoPreviewLayer`.
    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // Forzado seguro: layerClass garantiza el tipo.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}

// MARK: - Cuadrícula guía

/// Cuadrícula de tercios superpuesta a la vista previa (spec §16 "Cuadrícula").
private struct GridOverlay: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height
                for i in 1..<3 {
                    let x = w * CGFloat(i) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: h))
                    let y = h * CGFloat(i) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Vista de captura

/// Hoja de captura guiada. Pide cámara al abrir (spec §16) y permite confirmar,
/// repetir o cancelar antes de guardar. Al cancelar o denegar, el resto de la
/// app sigue usable (T47): esta hoja solo se cierra.
struct CameraCaptureView: View {
    let pose: Pose
    /// Peso ya existente a vincular (spec §16 "Peso y foto", T49). Opcional (T50).
    var bodyWeightID: UUID?
    /// Foto anterior de la misma pose para la superposición opcional (dentro de la bóveda
    /// desbloqueada: esta vista solo se presenta desde la galería desbloqueada, T62).
    var previousFileName: String?
    /// Se invoca tras guardar correctamente con el id de la foto creada.
    var onSaved: (UUID) -> Void = { _ in }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

    @State private var controller = CameraController()
    @State private var timerSeconds = 0
    @State private var showOverlay = false
    @State private var overlayImage: UIImage?
    /// Caché mínima propia: solo la imagen de superposición.
    @State private var overlayLoader = VaultImageLoader(maxEntries: 1)

    var body: some View {
        NavigationStack {
            content
                .background(Color.black.ignoresSafeArea())
                .navigationTitle(pose.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") {
                            controller.stop()
                            dismiss()   // T47: cancelar solo cierra, nada más.
                        }
                    }
                }
        }
        .task {
            await controller.start()
        }
        .task(id: showOverlay) {
            guard showOverlay, overlayImage == nil, let previousFileName else { return }
            overlayImage = await overlayLoader.image(fileName: previousFileName, maxPixel: 1200 * displayScale)
        }
        .onDisappear { controller.stop() }
        .onChange(of: scenePhase) { _, newPhase in
            // Al salir de la app, detenemos la cámara (privacidad de interfaz).
            if newPhase != .active { controller.stop() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch controller.permission {
        case .notDetermined:
            ProgressView("Solicitando acceso a la cámara…")
                .tint(.white)
                .foregroundStyle(.white)
        case .denied:
            deniedState
        case .authorized:
            if let image = controller.capturedImage {
                reviewState(image: image)
            } else {
                liveState
            }
        }
    }

    // MARK: Estados

    /// Estado denegado: mensaje claro y acceso a Ajustes (T47). El resto de la
    /// app sigue utilizable porque esta vista no bloquea nada más.
    private var deniedState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.white.opacity(0.7))
            Text("Cámara sin acceso")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text("Para tomar fotos de progreso, activa la cámara para Arco en Ajustes. Puedes seguir usando el resto de la app y registrar tu peso sin cámara.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Abre los ajustes del sistema para conceder acceso a la cámara")
        }
        .padding(Spacing.xl)
    }

    /// Vista en vivo con cuadrícula, referencia de pose y temporizador opcional.
    private var liveState: some View {
        VStack(spacing: 0) {
            ZStack {
                CameraPreview(session: controller.session)
                    .ignoresSafeArea(edges: .horizontal)
                if showOverlay, let overlayImage {
                    // Solo guía visual en pantalla; no se incorpora a la foto guardada.
                    Image(uiImage: overlayImage)
                        .resizable()
                        .scaledToFill()
                        .opacity(0.35)
                        .allowsHitTesting(false)
                        .clipped()
                        .accessibilityHidden(true)
                }
                GridOverlay()
                poseReferenceBadge
                if controller.countdown > 0 {
                    Text("\(controller.countdown)")
                        .font(.system(size: 96, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(radius: 8)
                        .accessibilityLabel("Temporizador: \(controller.countdown) segundos")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            captureControls
        }
    }

    /// Insignia de referencia de pose superpuesta (spec §16 "referencia de pose").
    private var poseReferenceBadge: some View {
        VStack {
            HStack(spacing: Spacing.sm) {
                Image(systemName: pose.referenceSymbol)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pose.displayName).font(.subheadline.bold())
                    Text(pose.shortDescription)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(Spacing.sm)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.control))
            .foregroundStyle(.white)
            .padding(Spacing.md)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pose \(pose.displayName). \(pose.shortDescription)")
    }

    /// Controles de disparo y temporizador fotográfico.
    private var captureControls: some View {
        VStack(spacing: Spacing.md) {
            Picker("Temporizador", selection: $timerSeconds) {
                Text("Sin temporizador").tag(0)
                Text("3 s").tag(3)
                Text("5 s").tag(5)
                Text("10 s").tag(10)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Temporizador fotográfico")

            if previousFileName != nil {
                Toggle("Superponer la foto anterior", isOn: $showOverlay)
                    .foregroundStyle(.white)
                    .tint(ArcoColor.brand)
            }

            Button {
                controller.capture(withTimer: timerSeconds)
            } label: {
                Image(systemName: "camera.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.white)
            }
            .disabled(controller.countdown > 0 || !controller.isRunning)
            .accessibilityLabel("Tomar foto")

            if let error = controller.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(Spacing.lg)
        .background(.black)
    }

    /// Revisión antes de guardar: confirmar, repetir o cancelar (spec §16).
    private func reviewState(image: UIImage) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .padding(Spacing.md)
                .accessibilityLabel("Vista previa de la foto capturada")

            if let error = controller.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack(spacing: Spacing.lg) {
                Button(role: .cancel) {
                    controller.retake()
                } label: {
                    Label("Repetir", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        let savedID = await controller.confirmAndSave(
                            pose: pose,
                            date: Date(),
                            crypto: appState.vaultCrypto,
                            context: modelContext,
                            bodyWeightID: bodyWeightID
                        )
                        if let savedID {
                            controller.stop()
                            onSaved(savedID)
                            dismiss()
                        }
                    }
                } label: {
                    Label("Guardar", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isSaving)
            }
            .padding(.bottom, Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}

// MARK: - Preview

#Preview("Captura — pose frontal") {
    // Preview autocontenida: no arranca cámara real en el canvas, muestra el
    // andamiaje de navegación/controles con datos mock.
    let container = try! ModelContainer(
        for: PhotoCheckInModel.self, BodyWeightModel.self, AppSettingsModel.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    CameraCaptureView(pose: .frontRelaxed, bodyWeightID: nil)
        .modelContainer(container)
        .environment(AppState(context: ModelContext(container)))
}
