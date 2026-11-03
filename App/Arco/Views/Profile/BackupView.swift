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
    @State private var strategy: RestoreStrategy = .mergeKeepDevice

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
            RestorePreviewSheet(preview: p, replaceProfile: $replaceProfile, strategy: $strategy) { confirmed in
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
            Text("Antes de cambiar nada verás qué se añadirá, qué ya está, qué conflictos hay y qué harás con ellos. Una contraseña incorrecta o un archivo dañado no modifican nada. Las fotos de este iPhone nunca se borran al restaurar.")
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
            strategy = .mergeKeepDevice
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
            let withProfile = replaceProfile || strategy == .replace
            let (report, prefs) = try ArchiveImporter(context: appState.context, photos: appState.vaultCrypto)
                .restore(url: url, password: restorePassword, replaceProfileAndSettings: withProfile, strategy: strategy)
            if withProfile { Preferences.restore(prefs) }
            try? appState.vaultCrypto.reapplyProtectionAttributes()
            if let settings = (try? appState.context.fetch(FetchDescriptor<AppSettingsModel>()))?.first {
                appState.settings = settings
            }
            await appState.refreshReminders()
            message = RestoreReportText.outcome(report, strategy: strategy)
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

/// Resumen previo a restaurar (spec §19): qué contiene la copia, qué hará cada opción con los
/// datos actuales (calculado sin modificar nada) y confirmación explícita. Reemplazar exige una
/// segunda confirmación que enumera lo que se eliminará.
struct RestorePreviewSheet: View {
    let preview: RestorePreview
    @Binding var replaceProfile: Bool
    @Binding var strategy: RestoreStrategy
    let onDecision: (Bool) -> Void
    @State private var confirmReplace = false

    private let labels: [(String, String)] = [
        ("sessions", "Sesiones"), ("sets", "Series"), ("bodyWeights", "Pesajes"), ("heights", "Alturas"),
        ("measurements", "Medidas"), ("attendance", "Registros de asistencia"), ("goals", "Metas"),
        ("customExercises", "Ejercicios personalizados"), ("photos", "Fotos")
    ]

    private var plan: RestoreReport { preview.plans[strategy] ?? RestoreReport() }
    private var hasExistingData: Bool {
        let p = preview.plans[.mergeKeepDevice] ?? RestoreReport()
        return !p.skippedExisting.isEmpty || !p.updated.isEmpty || !p.keptDevice.isEmpty || !p.conflicts.isEmpty || !p.onlyOnDevice.filter { $0.key != "exercises" }.isEmpty
    }

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
                    Picker("Cómo restaurar", selection: $strategy) {
                        Text("Combinar (recomendado)").tag(RestoreStrategy.mergeKeepDevice)
                        Text("Combinar; en conflictos, usar la copia").tag(RestoreStrategy.mergePreferArchive)
                        Text("Reemplazar con la copia").tag(RestoreStrategy.replace)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .accessibilityIdentifier("restore.strategy")
                } header: {
                    Text("Cómo restaurar")
                } footer: {
                    Text(RestoreReportText.explanation(strategy))
                }

                Section {
                    ForEach(RestoreReportText.forecastLines(plan, strategy: strategy), id: \.self) { line in
                        Text(line).font(.subheadline)
                    }
                } header: {
                    Text(hasExistingData ? "Qué pasará con los datos de este iPhone" : "Qué se añadirá")
                }
                .accessibilityIdentifier("restore.forecast")

                if !plan.conflicts.isEmpty {
                    Section {
                        ForEach(Array(plan.conflicts.prefix(12).enumerated()), id: \.offset) { _, c in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.summary).font(.footnote)
                                Text(c.resolution == .keptDevice ? "Se conservará lo de este iPhone" : "Se aplicará lo de la copia")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if plan.conflicts.count > 12 {
                            Text("Y \(plan.conflicts.count - 12) conflictos más.").font(.caption).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Conflictos (\(plan.conflicts.count))")
                    } footer: {
                        Text("Un conflicto es un registro que cambió de forma distinta aquí y en la copia sin que los datos permitan saber cuál es posterior. Arco no adivina: aplica la opción que elijas.")
                    }
                }

                Section {
                    Toggle("Sustituir perfil, ajustes, rutina y recordatorios por los del archivo", isOn: strategy == .replace ? .constant(true) : $replaceProfile)
                        .disabled(strategy == .replace)
                } footer: {
                    Text(strategy == .replace ? "Al reemplazar, el perfil, los ajustes, la rutina y los recordatorios también pasan a ser los de la copia." : "Si lo desactivas, se conservan los de este iPhone.")
                }
            }
            .navigationTitle("Restaurar copia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { onDecision(false) } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(strategy == .replace ? "Reemplazar" : "Restaurar") {
                        if strategy == .replace { confirmReplace = true } else { onDecision(true) }
                    }
                    .accessibilityIdentifier("restore.confirm")
                }
            }
            .alert("¿Reemplazar los datos de este iPhone?", isPresented: $confirmReplace) {
                Button("Reemplazar", role: .destructive) { onDecision(true) }
                    .accessibilityIdentifier("restore.replace.confirm")
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text(RestoreReportText.replaceWarning(plan))
            }
        }
    }
}

/// Textos de la restauración en español, a partir del informe real (sin promesas).
enum RestoreReportText {
    static let names: [String: String] = [
        "sessions": "sesiones", "sessionExercises": "ejercicios de sesión", "sets": "series",
        "exercises": "ejercicios del catálogo", "exerciseSettings": "ajustes de carga", "progressionRules": "reglas de progresión",
        "customAttributions": "atribuciones personalizadas", "bodyWeights": "pesajes", "heights": "alturas",
        "measurements": "medidas", "attendance": "registros de asistencia", "resolutions": "descansos o ausencias",
        "reminderOverrides": "cambios de avisos", "goals": "metas", "photos": "fotos", "drafts": "borradores sin realizar"
    ]
    private static let order = ["sessions", "sets", "exercises", "photos", "bodyWeights", "heights", "measurements", "attendance", "resolutions", "goals", "sessionExercises", "exerciseSettings", "progressionRules", "customAttributions", "reminderOverrides", "drafts"]

    static func list(_ dict: [String: Int]) -> String {
        order.compactMap { key in dict[key].flatMap { $0 > 0 ? "\($0) \(names[key] ?? key)" : nil } }.joined(separator: ", ")
    }

    static func explanation(_ s: RestoreStrategy) -> String {
        switch s {
        case .mergeKeepDevice:
            return "Añade lo que falta y adopta los cambios de la copia cuando se puede saber que son posteriores (por ejemplo, una serie confirmada después de su borrador). Si un registro cambió de forma distinta en los dos lados, se queda lo de este iPhone. No borra nada."
        case .mergePreferArchive:
            return "Igual que combinar, pero en los conflictos se aplica lo de la copia. No borra nada de este iPhone."
        case .replace:
            return "Deja entrenamientos, medidas, asistencia, catálogo, perfil y rutina exactamente como en la copia y elimina de este iPhone lo que la copia no tiene. Las fotos de este iPhone nunca se borran. Crea antes una copia de este iPhone si quieres poder volver atrás."
        }
    }

    static func forecastLines(_ r: RestoreReport, strategy: RestoreStrategy) -> [String] {
        var out: [String] = []
        if !r.inserted.isEmpty { out.append("Se añadirán: \(list(r.inserted)).") }
        if !r.updated.isEmpty { out.append("Se actualizarán con la copia: \(list(r.updated)).") }
        if !r.keptDevice.isEmpty { out.append("Se conservará la versión de este iPhone, que es posterior o ya incluye lo de la copia: \(list(r.keptDevice)).") }
        if !r.conflicts.isEmpty {
            out.append("Conflictos: \(r.conflicts.count) (\(strategy == .mergeKeepDevice ? "se conservará lo de este iPhone" : "se aplicará lo de la copia")).")
        }
        if r.skippedDrafts > 0 { out.append("No se añadirán \(r.skippedDrafts) borradores sin realizar de sesiones que aquí ya existen.") }
        if let drafts = r.removed["drafts"], drafts > 0 { out.append("Se descartarán \(drafts) borradores sin realizar de sesiones que la copia ya cerró.") }
        let removed = r.removed.filter { $0.key != "drafts" }
        if !removed.isEmpty { out.append("Se ELIMINARÁN de este iPhone: \(list(removed)).") }
        let onlyHere = r.onlyOnDevice.filter { $0.key != "exercises" }
        if !onlyHere.isEmpty { out.append("Solo están en este iPhone y se conservan: \(list(onlyHere)).") }
        if !r.skippedExisting.isEmpty { out.append("Ya están aquí sin cambios: \(r.total(r.skippedExisting)) registros.") }
        if out.isEmpty { out.append("La copia no aporta cambios.") }
        return out
    }

    static func replaceWarning(_ r: RestoreReport) -> String {
        let removed = r.removed.filter { $0.key != "drafts" }
        let what = removed.isEmpty ? "No se eliminará ningún registro." : "Se eliminarán de este iPhone: \(list(removed))."
        return "\(what) Los registros que también están en la copia quedarán como en la copia. Las fotos de este iPhone se conservan. Esta acción no se puede deshacer salvo con otra copia."
    }

    /// Mensaje final: solo dice "completa" si todo lo de la copia quedó reflejado.
    static func outcome(_ r: RestoreReport, strategy: RestoreStrategy) -> String {
        let leftOut = r.conflictsKeptDevice + r.skippedDrafts
        var parts: [String] = []
        parts.append(leftOut == 0 ? "Restauración terminada." : "Restauración terminada con diferencias.")
        parts.append(r.inserted.isEmpty ? "No había registros nuevos." : "Añadido: \(list(r.inserted)).")
        if !r.updated.isEmpty { parts.append("Actualizado con la copia: \(list(r.updated)).") }
        if !r.keptDevice.isEmpty { parts.append("Conservada la versión posterior de este iPhone: \(list(r.keptDevice)).") }
        if r.conflictsKeptDevice > 0 { parts.append("\(r.conflictsKeptDevice) conflictos: se conservó lo de este iPhone y no se aplicó lo de la copia.") }
        if r.conflictsUsedArchive > 0 { parts.append("\(r.conflictsUsedArchive) conflictos: se aplicó lo de la copia.") }
        if r.skippedDrafts > 0 { parts.append("\(r.skippedDrafts) borradores sin realizar no se añadieron.") }
        let removed = r.removed.filter { $0.key != "drafts" }
        if !removed.isEmpty { parts.append("Eliminado de este iPhone: \(list(removed)).") }
        let onlyHere = r.onlyOnDevice.filter { $0.key != "exercises" }
        if !onlyHere.isEmpty { parts.append("Conservado lo que solo estaba aquí: \(list(onlyHere)).") }
        return parts.joined(separator: " ")
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
