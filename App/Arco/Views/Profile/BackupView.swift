import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ArcoCore

/// Copia de seguridad y restauración (spec §19).
/// - Archivo cifrado con contraseña propia (≥ 8 caracteres, distinta del PIN; no se guarda).
/// - Las fotos solo se incluyen si el usuario lo elige Y la bóveda está desbloqueada; el texto
///   indica exactamente qué contiene el archivo.
/// - Restaurar valida contraseña e integridad de TODO el archivo, muestra un resumen y pide
///   confirmación antes de modificar datos; las fotos se vuelven a cifrar con la clave local.
struct BackupView: View {
    @Environment(AppState.self) private var appState
    @Query private var photos: [PhotoCheckInModel]
    @Query private var sessions: [WorkoutSessionModel]

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var includePhotos = false
    @State private var exportDocument: FileURLDocument?
    @State private var showExporter = false
    @State private var csvDocument: FileURLDocument?
    @State private var showCSVExporter = false
    @State private var working = false
    @State private var message: String?

    @State private var showImporter = false
    @State private var restoreURL: URL?
    @State private var restorePassword = ""
    @State private var showPasswordPrompt = false
    @State private var preview: RestorePreview?
    @State private var replaceProfile = true

    private var vaultUnlocked: Bool { appState.vaultLock.isUnlocked }
    private var passwordProblem: String? {
        if password.count < PortableArchive.minimumPasswordLength { return "Usa al menos \(PortableArchive.minimumPasswordLength) caracteres." }
        if password != confirmPassword { return "Las contraseñas no coinciden." }
        if password.count == 4 && password.allSatisfy(\.isNumber) { return "No uses tu PIN como contraseña." }
        return nil
    }

    var body: some View {
        Form {
            exportSection
            csvSection
            restoreSection
            if working {
                Section { HStack { ProgressView(); Text("Procesando…") } }
            }
            if let message {
                Section { Text(message).font(.footnote).accessibilityIdentifier("backup.message") }
            }
        }
        .navigationTitle("Copia de seguridad")
        .disabled(working)
        .fileExporter(isPresented: $showExporter, document: exportDocument, contentType: .data, defaultFilename: "Arco-\(Self.stamp).arcobk") { result in
            finishExport(result, label: includePhotos ? "Copia cifrada exportada con \(photos.count) fotos." : "Copia cifrada exportada (sin fotos).")
        }
        .fileExporter(isPresented: $showCSVExporter, document: csvDocument, contentType: .commaSeparatedText, defaultFilename: "Arco-series-\(Self.stamp).csv") { result in
            finishExport(result, label: "CSV de series exportado.")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data, .item], allowsMultipleSelection: false) { result in
            importSelected(result)
        }
        .alert("Contraseña del archivo", isPresented: $showPasswordPrompt) {
            SecureField("Contraseña", text: $restorePassword)
            Button("Revisar archivo") { Task { await validateArchive() } }
            Button("Cancelar", role: .cancel) { cleanupRestore() }
        } message: {
            Text("Se comprobará todo el archivo antes de cambiar nada.")
        }
        .sheet(item: $preview) { p in
            RestorePreviewSheet(preview: p, replaceProfile: $replaceProfile) { confirmed in
                preview = nil
                if confirmed { Task { await performRestore() } } else { cleanupRestore() }
            }
        }
        .onDisappear { password = ""; confirmPassword = ""; restorePassword = "" }
    }

    // MARK: - Exportar

    private var exportSection: some View {
        Section {
            SecureField("Contraseña de la copia", text: $password)
                .textContentType(.newPassword)
                .accessibilityIdentifier("backup.password")
            SecureField("Repetir contraseña", text: $confirmPassword)
                .textContentType(.newPassword)
                .accessibilityIdentifier("backup.confirm")
            if !password.isEmpty, let p = passwordProblem {
                Text(p).font(.caption).foregroundStyle(.red)
            }
            Toggle("Incluir fotos (\(photos.count))", isOn: $includePhotos)
                .disabled(!vaultUnlocked || photos.isEmpty)
                .accessibilityIdentifier("backup.includePhotos")
            if !vaultUnlocked && !photos.isEmpty {
                Text("Para incluir fotos, desbloquea primero la bóveda en la pestaña Fotos. Sin desbloquear, la copia NO contiene fotos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Crear copia cifrada") { Task { await exportArchive() } }
                .disabled(passwordProblem != nil)
                .accessibilityIdentifier("backup.export")
        } header: {
            Text("Copia cifrada")
        } footer: {
            Text("Contiene: \(sessions.count) sesiones con sus series, ejercicios personalizados, rutina, perfil, ajustes, pesos, alturas, medidas, asistencia, descansos, recordatorios y metas. Fotos: \(includePhotos && vaultUnlocked ? "sí, \(photos.count)" : "no"). La contraseña es distinta de tu PIN y no se guarda: sin ella el archivo no se puede abrir. Si eliges un servicio en la nube como destino, esa copia sale de este dispositivo.")
        }
    }

    private var csvSection: some View {
        Section {
            Button("Exportar series (CSV)") {
                do {
                    let url = try Self.temporaryURL("csv")
                    try WorkoutCSV.build(context: appState.context).write(to: url, options: [.atomic, .completeFileProtection])
                    csvDocument = FileURLDocument(url: url)
                    showCSVExporter = true
                } catch {
                    message = "No se pudo preparar el CSV."
                }
            }
        } footer: {
            Text("Solo series de entrenamiento (fechas, ejercicio, variante, carga, repeticiones, lado y RIR). Sin fotos ni datos corporales. No está cifrado.")
        }
    }

    private var restoreSection: some View {
        Section {
            Button("Restaurar desde una copia") { showImporter = true }
                .accessibilityIdentifier("backup.restore")
        } footer: {
            Text("Se combinan los datos del archivo con los actuales sin duplicar registros. Una contraseña incorrecta o un archivo dañado no modifican nada.")
        }
    }

    private func exportArchive() async {
        guard passwordProblem == nil else { return }
        working = true
        defer { working = false }
        let withPhotos = includePhotos && vaultUnlocked && !photos.isEmpty
        do {
            let url = try Self.temporaryURL("arcobk")
            await Task.yield()
            try ArchiveExporter(context: appState.context, photos: withPhotos ? appState.vaultCrypto : nil, preferences: Preferences.all)
                .write(to: url, password: password, includePhotos: withPhotos)
            includePhotos = withPhotos
            exportDocument = FileURLDocument(url: url)
            showExporter = true
        } catch BackupError.weakPassword {
            message = "La contraseña es demasiado corta."
        } catch {
            message = "No se pudo crear la copia. No se ha guardado ningún archivo."
        }
    }

    private func finishExport(_ result: Result<URL, Error>, label: String) {
        switch result {
        case .success: message = label
        case .failure: message = "Exportación cancelada."
        }
        for doc in [exportDocument, csvDocument].compactMap({ $0 }) { try? FileManager.default.removeItem(at: doc.url) }
        exportDocument = nil
        csvDocument = nil
        password = ""
        confirmPassword = ""
    }

    // MARK: - Restaurar

    private func importSelected(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let source = urls.first else { message = "No se pudo abrir el archivo."; return }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        do {
            let local = try Self.temporaryURL("arcobk")
            try FileManager.default.copyItem(at: source, to: local)
            guard PortableArchiveReader.isPortableArchive(local) else {
                try? FileManager.default.removeItem(at: local)
                message = "Este archivo no es una copia de Arco compatible."
                return
            }
            restoreURL = local
            restorePassword = ""
            showPasswordPrompt = true
        } catch {
            message = "No se pudo leer el archivo."
        }
    }

    private func validateArchive() async {
        guard let url = restoreURL else { return }
        working = true
        defer { working = false }
        await Task.yield()
        do {
            preview = try ArchiveImporter(context: appState.context, photos: appState.vaultCrypto).preview(url: url, password: restorePassword)
        } catch {
            message = Self.describe(error)
            cleanupRestore()
        }
    }

    private func performRestore() async {
        guard let url = restoreURL else { return }
        working = true
        defer { working = false; cleanupRestore() }
        await Task.yield()
        do {
            let (report, prefs) = try ArchiveImporter(context: appState.context, photos: appState.vaultCrypto)
                .restore(url: url, password: restorePassword, replaceProfileAndSettings: replaceProfile)
            if replaceProfile { Preferences.restore(prefs) }
            try? appState.vaultCrypto.reapplyProtectionAttributes()
            if let settings = (try? appState.context.fetch(FetchDescriptor<AppSettingsModel>()))?.first {
                appState.settings = settings
            }
            await appState.refreshReminders()
            let inserted = report.inserted
            message = "Restauración completada: \(inserted["sessions"] ?? 0) sesiones, \(inserted["photos"] ?? 0) fotos y \(inserted["bodyWeights"] ?? 0) pesajes añadidos. Ya existentes y conservados: \(report.skippedExisting.values.reduce(0, +))."
        } catch {
            message = Self.describe(error)
        }
    }

    private func cleanupRestore() {
        if let url = restoreURL { try? FileManager.default.removeItem(at: url) }
        restoreURL = nil
        restorePassword = ""
    }

    // MARK: - Utilidades

    static func describe(_ error: Error) -> String {
        switch error {
        case BackupError.invalidPassword: return "Contraseña incorrecta. No se modificó ningún dato."
        case BackupError.corrupted: return "El archivo está dañado o incompleto. No se modificó ningún dato."
        case BackupError.unsupportedVersion: return "Versión de copia no compatible. No se modificó ningún dato."
        case ArchiveError.invalidContent: return "El contenido del archivo no es coherente. No se modificó ningún dato."
        default: return "No se pudo restaurar. No se modificó ningún dato."
        }
    }

    static func temporaryURL(_ ext: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("arco-export", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        return dir.appendingPathComponent("\(UUID().uuidString).\(ext)")
    }

    static var stamp: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
}

extension RestorePreview: @retroactive Identifiable {
    public var id: Date { exportedAt }
}

/// Resumen previo a restaurar (spec §19): qué contiene y qué hará.
struct RestorePreviewSheet: View {
    let preview: RestorePreview
    @Binding var replaceProfile: Bool
    let onDecision: (Bool) -> Void

    private let labels: [(String, String)] = [
        ("sessions", "Sesiones"), ("sets", "Series"), ("bodyWeights", "Pesajes"), ("heights", "Alturas"),
        ("measurements", "Medidas"), ("attendance", "Registros de asistencia"), ("goals", "Metas"),
        ("customExercises", "Ejercicios personalizados"), ("photos", "Fotos")
    ]

    var body: some View {
        NavigationStack {
            List {
                Section("Copia del \(preview.exportedAt.formatted(date: .long, time: .shortened))") {
                    ForEach(labels, id: \.0) { key, label in
                        LabeledContent(label, value: "\(preview.counts[key] ?? 0)")
                    }
                    if !preview.includesPhotos {
                        Label("Esta copia no incluye fotos.", systemImage: "photo.badge.exclamationmark")
                    }
                }
                Section {
                    Toggle("Sustituir perfil, ajustes, rutina y recordatorios por los del archivo", isOn: $replaceProfile)
                } footer: {
                    Text("Los entrenamientos, pesos, medidas, fotos y asistencia se añaden sin duplicar lo que ya existe. No se borra nada de lo actual.")
                }
            }
            .navigationTitle("Restaurar copia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { onDecision(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restaurar") { onDecision(true) }.accessibilityIdentifier("restore.confirm")
                }
            }
        }
    }
}

/// Documento que apunta a un archivo ya escrito (no lo carga entero en memoria).
struct FileURLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    let url: URL
    init(url: URL) { self.url = url }
    init(configuration: ReadConfiguration) throws { throw CocoaError(.featureUnsupported) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: url, options: [])
    }
}
