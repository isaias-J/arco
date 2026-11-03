import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import ArcoCore

/// Exportación y restauración (spec §19). Archivo cifrado con contraseña separada del PIN y
/// CSV de entrenamiento. La restauración valida antes de tocar datos (T70). Export solo por
/// acción expresa; el usuario elige destino.
struct BackupView: View {
    @Environment(AppState.self) private var appState

    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var includePhotos = false
    @State private var exportDocument: EncryptedBackupDocument?
    @State private var showExporter = false
    @State private var csvDocument: CSVDocument?
    @State private var showCSVExporter = false
    @State private var showImporter = false
    @State private var message: String?
    @State private var restorePassword = ""
    @State private var pendingRestoreURL: URL?
    @State private var showRestorePrompt = false

    var body: some View {
        Form {
            exportSection
            csvSection
            restoreSection
            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Copia de seguridad")
        .fileExporter(
            isPresented: $showExporter,
            document: exportDocument,
            contentType: .data,
            defaultFilename: "Arco-respaldo-\(dateStamp).arcobk"
        ) { result in
            handleExportResult(result, label: "Archivo cifrado exportado.")
        }
        .fileExporter(
            isPresented: $showCSVExporter,
            document: csvDocument,
            contentType: .commaSeparatedText,
            defaultFilename: "Arco-entrenamiento-\(dateStamp).csv"
        ) { result in
            handleExportResult(result, label: "CSV exportado.")
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .alert("Restaurar copia", isPresented: $showRestorePrompt) {
            SecureField("Contraseña del archivo", text: $restorePassword)
            Button("Restaurar") { performRestore() }
            Button("Cancelar", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text("Introduce la contraseña con la que se cifró este archivo. Se validará antes de modificar tus datos.")
        }
    }

    // MARK: - Secciones

    private var exportSection: some View {
        Section("Archivo cifrado") {
            SecureField("Contraseña de exportación", text: $password)
            SecureField("Confirmar contraseña", text: $confirmPassword)
            Toggle("Incluir fotos (requiere bóveda desbloqueada)", isOn: $includePhotos)
                .disabled(!appState.vaultLock.isUnlocked)
            Button("Exportar archivo cifrado") { prepareEncryptedExport() }
                .disabled(password.count < 8 || password != confirmPassword)
            Text("La contraseña es distinta de tu PIN y no se guarda. Sin ella, el archivo no se puede abrir.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var csvSection: some View {
        Section("Exportar entrenamiento (CSV)") {
            Button("Exportar CSV de series") {
                csvDocument = CSVDocument(data: DataExport(context: appState.context).workoutCSV())
                showCSVExporter = true
            }
            Text("Incluye tus series con fechas, cargas y repeticiones. No contiene fotos ni datos privados.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var restoreSection: some View {
        Section("Restaurar") {
            Button("Restaurar desde archivo cifrado") { showImporter = true }
            Text("Se te mostrará un resumen y se validará la contraseña e integridad antes de sustituir nada.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: - Export

    private func prepareEncryptedExport() {
        do {
            let export = DataExport(context: appState.context)
            let payload = try export.jsonData()
            let archive = try appState.backup.export(
                payload: payload,
                password: password,
                includesPhotos: includePhotos,
                counts: export.counts()
            )
            exportDocument = EncryptedBackupDocument(data: archive)
            showExporter = true
        } catch {
            message = "No se pudo preparar el archivo cifrado."
        }
    }

    private func handleExportResult(_ result: Result<URL, Error>, label: String) {
        switch result {
        case .success: message = label
        case .failure: message = "La exportación se canceló o falló."
        }
        password = ""; confirmPassword = ""
    }

    // MARK: - Restore

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            pendingRestoreURL = url
            restorePassword = ""
            showRestorePrompt = true
        case .failure:
            message = "No se pudo abrir el archivo."
        }
    }

    private func performRestore() {
        guard let url = pendingRestoreURL else { return }
        defer { pendingRestoreURL = nil }
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let restored = try appState.backup.restore(archive: data, password: restorePassword)
            // Validación superada: aplicar la restauración (transaccional, sin duplicar por ID).
            try DataImport(context: appState.context).apply(payload: restored.payload)
            message = "Restauración completada: \(restored.manifest.counts["sessions"] ?? 0) sesiones."
        } catch let e as BackupError {
            switch e {
            case .invalidPassword: message = "Contraseña incorrecta: no se modificó ningún dato."
            case .corrupted: message = "El archivo está dañado: no se modificó ningún dato."
            case .unsupportedVersion: message = "Versión de archivo no compatible."
            default: message = "No se pudo restaurar."
            }
        } catch {
            message = "No se pudo restaurar el archivo."
        }
    }

    private var dateStamp: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date())
    }
}

/// Documento del archivo cifrado para `fileExporter`.
struct EncryptedBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Documento CSV para `fileExporter`.
struct CSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
