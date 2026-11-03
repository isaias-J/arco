import Foundation
import SwiftData

/// Almacén de imágenes de la bóveda. La app lo implementa con `VaultCrypto` (cifrado con la
/// clave local del dispositivo); las pruebas usan una implementación con su propia clave.
public protocol PhotoFileStore: Sendable {
    /// Devuelve la imagen descifrada.
    func readPhoto(named name: String) throws -> Data
    /// Cifra con la clave local y guarda.
    func writePhoto(_ data: Data, named name: String) throws
    /// Elimina la imagen y sus derivados.
    func deletePhoto(named name: String) throws
    func photoExists(named name: String) -> Bool
}

/// Contenido completo del archivo (spec §19). Sin PIN, claves ni contraseñas.
public struct ArchivePayload: Codable, Sendable {
    public var formatVersion: Int = 2
    public var exportedAt: Date
    public var includesPhotos: Bool
    public var attributionVersion: String
    public var profiles: [Profile]
    public var settings: [Settings]
    public var preferences: [String: String]
    public var exercises: [Exercise]
    public var templates: [Template]
    public var exerciseSettings: [ExerciseSetting]
    public var sessions: [Session]
    public var bodyWeights: [BodyWeight]
    public var heights: [Height]
    public var measurements: [Measurement]
    public var attendance: [Attendance]
    public var resolutions: [Resolution]
    public var reminderRules: [ReminderRuleDTO]
    public var reminderOverrides: [ReminderOverrideDTO]
    public var goals: [Goal]
    public var photos: [Photo]
    /// Añadidos con el esquema v3; opcionales para leer copias anteriores.
    public var progressionRules: [ProgressionRule]? = nil
    public var planVersions: [PlanVersion]? = nil
    public var customAttributions: [CustomAttribution]? = nil
    /// Precisión de las fechas. nil en copias anteriores (segundos enteros); "ms" en las actuales.
    /// Permite comparar con seguridad qué versión de una serie es posterior al combinar.
    public var datePrecision: String? = nil

    public static let millisecondPrecision = "ms"

    /// Codificador de fechas con milisegundos (ISO 8601).
    static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, enc in
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var c = enc.singleValueContainer()
            try c.encode(f.string(from: date))
        }
        return encoder
    }

    /// Decodificador que acepta fechas con y sin milisegundos (copias anteriores).
    static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let text = try dec.singleValueContainer().decode(String.self)
            let fine = ISO8601DateFormatter()
            fine.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = fine.date(from: text) { return d }
            let coarse = ISO8601DateFormatter()
            coarse.formatOptions = [.withInternetDateTime]
            if let d = coarse.date(from: text) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: dec.codingPath, debugDescription: "fecha no válida"))
        }
        return decoder
    }

    public struct ProgressionRule: Codable, Sendable { public var exerciseID: String; public var enabled: Bool; public var lower: Int; public var upper: Int; public var referenceSets: Int; public var increment: Decimal; public var unit: String; public var minimumRIR: Int? }
    public struct PlanVersion: Codable, Sendable { public var id: UUID; public var validFrom: Date; public var daysJSON: String }
    public struct CustomAttribution: Codable, Sendable { public var exerciseID: String; public var muscle: String; public var role: String }

    public struct Profile: Codable, Sendable { public var id: UUID; public var displayName: String?; public var birthDate: Date?; public var experience: String?; public var goal: String?; public var gender: String? }
    public struct Settings: Codable, Sendable { public var languageCode: String; public var massUnit: String; public var lengthUnit: String; public var theme: String; public var weekStartsMonday: Bool; public var hapticsEnabled: Bool; public var onboardingCompleted: Bool }
    public struct Exercise: Codable, Sendable { public var id: String; public var name: String; public var aliases: String; public var loadType: String; public var pattern: String; public var origin: String; public var instructions: String; public var archived: Bool }
    public struct Template: Codable, Sendable { public var id: String; public var name: String; public var weekday: Int; public var groups: String; public var preferred: String; public var isRest: Bool }
    public struct ExerciseSetting: Codable, Sendable { public var exerciseID: String; public var convention: String?; public var sideMode: String; public var increment: Decimal?; public var barWeight: Decimal?; public var unit: String?; public var defaultVariant: String? }
    public struct SetRow: Codable, Sendable { public var id: UUID; public var loadAmount: Decimal?; public var unit: String; public var convention: String; public var reps: Int?; public var type: String; public var state: String; public var side: String; public var rirKind: String; public var rirValue: Int?; public var performedAt: Date; public var attrMajor: Int; public var attrMinor: Int }
    public struct SessionExercise: Codable, Sendable { public var id: UUID; public var exerciseID: String; public var variantKey: String?; public var order: Int; public var sets: [SetRow] }
    public struct Session: Codable, Sendable { public var id: UUID; public var startedAt: Date; public var endedAt: Date?; public var state: String; public var trainingDate: Date; public var timeZone: String; public var templateID: String?; public var exercises: [SessionExercise] }
    public struct BodyWeight: Codable, Sendable { public var id: UUID; public var measurementDate: Date; public var enteredAt: Date; public var amount: Decimal; public var unit: String; public var isEstimated: Bool; public var photoCheckInID: UUID? }
    public struct Height: Codable, Sendable { public var id: UUID; public var date: Date; public var amount: Decimal; public var unit: String }
    public struct Measurement: Codable, Sendable { public var id: UUID; public var typeKey: String; public var side: String; public var protocolNote: String; public var amount: Decimal; public var unit: String; public var date: Date }
    public struct Attendance: Codable, Sendable { public var id: UUID; public var trainingDate: Date; public var source: String; public var sessionID: UUID?; public var isPartial: Bool }
    public struct Resolution: Codable, Sendable { public var id: UUID; public var dayKey: String; public var kind: String; public var createdAt: Date }
    public struct ReminderRuleDTO: Codable, Sendable { public var id: UUID; public var category: String; public var weekday: Int?; public var hour: Int; public var minute: Int; public var enabled: Bool; public var timeZoneID: String }
    public struct ReminderOverrideDTO: Codable, Sendable { public var id: UUID; public var category: String; public var dayKey: String; public var hour: Int; public var minute: Int; public var enabled: Bool }
    public struct Goal: Codable, Sendable { public var id: UUID; public var muscle: String; public var method: String; public var target: Decimal; public var validFrom: Date; public var validTo: Date?; public var source: String }
    /// Metadatos de foto; la imagen viaja en el fragmento `chunkIndex` del archivo.
    public struct Photo: Codable, Sendable { public var id: UUID; public var date: Date; public var pose: String; public var orientation: Int; public var mirrored: Bool; public var bodyWeightID: UUID?; public var chunkIndex: Int }

    public var counts: [String: Int] {
        [
            "sessions": sessions.count,
            "sets": sessions.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } },
            "bodyWeights": bodyWeights.count,
            "heights": heights.count,
            "measurements": measurements.count,
            "attendance": attendance.count,
            "photos": photos.count,
            "goals": goals.count,
            "customExercises": exercises.filter { $0.origin == ExerciseOrigin.custom.rawValue }.count
        ]
    }
}

/// Resumen previo a restaurar (spec §19: mostrar resumen y elección explícita).
public struct RestorePreview: Sendable, Equatable {
    public let exportedAt: Date
    public let includesPhotos: Bool
    public let counts: [String: Int]
    /// Qué haría cada estrategia sobre los datos actuales, sin modificar nada.
    public let plans: [RestoreStrategy: RestoreReport]
}

/// Resultado de una restauración: ver `RestoreReport` en ArchiveMerge.swift.

public enum ArchiveError: Error, Equatable {
    case photosRequireUnlockedVault
    case invalidContent(String)
}

/// Exportación del archivo completo (spec §19).
@MainActor
public struct ArchiveExporter {
    public let context: ModelContext
    public let photos: PhotoFileStore?
    public let preferences: [String: String]

    public init(context: ModelContext, photos: PhotoFileStore?, preferences: [String: String] = [:]) {
        self.context = context
        self.photos = photos
        self.preferences = preferences
    }

    private func all<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    /// Construye el contenido. Con `includePhotos`, las fotos se numeran como fragmentos 1…n.
    public func payload(includePhotos: Bool, now: Date = Date()) -> ArchivePayload {
        let photoModels = includePhotos ? all(PhotoCheckInModel.self).sorted { $0.date < $1.date } : []
        let photoIDs = Set(photoModels.map(\.id))
        return ArchivePayload(
            exportedAt: now,
            includesPhotos: includePhotos,
            attributionVersion: ExerciseCatalog.attributionVersion.description,
            profiles: all(UserProfileModel.self).map { .init(id: $0.id, displayName: $0.displayName, birthDate: $0.birthDate, experience: $0.experience, goal: $0.goalDescription, gender: $0.gender) },
            settings: all(AppSettingsModel.self).map { .init(languageCode: $0.languageCode, massUnit: $0.massUnitRaw, lengthUnit: $0.lengthUnitRaw, theme: $0.themeRaw, weekStartsMonday: $0.weekStartsMonday, hapticsEnabled: $0.hapticsEnabled, onboardingCompleted: $0.onboardingCompleted) },
            preferences: preferences,
            exercises: all(ExerciseModel.self).map { .init(id: $0.id, name: $0.name, aliases: $0.aliasesJoined, loadType: $0.loadTypeRaw, pattern: $0.patternRaw, origin: $0.originRaw, instructions: $0.instructions, archived: $0.archived) },
            templates: all(RoutineTemplateModel.self).map { .init(id: $0.id, name: $0.name, weekday: $0.weekday, groups: $0.groupsJoined, preferred: $0.preferredExerciseIDsJoined, isRest: $0.isRestDay) },
            exerciseSettings: all(ExerciseSettingsModel.self).map { .init(exerciseID: $0.exerciseID, convention: $0.conventionRaw, sideMode: $0.sideModeRaw, increment: $0.incrementAmount, barWeight: $0.barWeight, unit: $0.unitRaw, defaultVariant: $0.defaultVariant) },
            sessions: all(WorkoutSessionModel.self).map { s in
                .init(id: s.id, startedAt: s.startedAt, endedAt: s.endedAt, state: s.stateRaw, trainingDate: s.trainingDate, timeZone: s.originTimeZoneID, templateID: s.templateID,
                      exercises: s.exercises.sorted { $0.order < $1.order }.map { e in
                          .init(id: e.id, exerciseID: e.exerciseID, variantKey: e.variantKey, order: e.order, sets: e.sets.map { r in
                              .init(id: r.id, loadAmount: r.loadAmount, unit: r.loadUnitRaw, convention: r.loadConventionRaw, reps: r.reps, type: r.typeRaw, state: r.stateRaw, side: r.sideRaw, rirKind: r.rirKind, rirValue: r.rirValue, performedAt: r.performedAt, attrMajor: r.attributionMajor, attrMinor: r.attributionMinor)
                          })
                      })
            },
            bodyWeights: all(BodyWeightModel.self).map {
                .init(id: $0.id, measurementDate: $0.measurementDate, enteredAt: $0.enteredAt, amount: $0.amount, unit: $0.unitRaw, isEstimated: $0.isEstimated,
                      photoCheckInID: $0.photoCheckInID.flatMap { photoIDs.contains($0) ? $0 : nil })
            },
            heights: all(HeightModel.self).map { .init(id: $0.id, date: $0.date, amount: $0.amount, unit: $0.unitRaw) },
            measurements: all(BodyMeasurementModel.self).map { .init(id: $0.id, typeKey: $0.typeKey, side: $0.sideRaw, protocolNote: $0.protocolNote, amount: $0.amount, unit: $0.unitRaw, date: $0.date) },
            attendance: all(AttendanceEventModel.self).map { .init(id: $0.id, trainingDate: $0.trainingDate, source: $0.sourceRaw, sessionID: $0.sessionID, isPartial: $0.isPartial) },
            resolutions: all(AttendanceResolutionModel.self).map { .init(id: $0.id, dayKey: $0.dayKey, kind: $0.kindRaw, createdAt: $0.createdAt) },
            reminderRules: all(ReminderRuleModel.self).map { .init(id: $0.id, category: $0.categoryRaw, weekday: $0.weekday, hour: $0.hour, minute: $0.minute, enabled: $0.enabled, timeZoneID: $0.timeZoneID) },
            reminderOverrides: all(ReminderOverrideModel.self).map { .init(id: $0.id, category: $0.categoryRaw, dayKey: $0.dayKey, hour: $0.hour, minute: $0.minute, enabled: $0.enabled) },
            goals: all(WeeklyGoalModel.self).map { .init(id: $0.id, muscle: $0.muscleRaw, method: $0.methodRaw, target: $0.target, validFrom: $0.validFrom, validTo: $0.validTo, source: $0.sourceRaw) },
            photos: photoModels.enumerated().map { i, p in
                .init(id: p.id, date: p.date, pose: p.poseRaw, orientation: p.orientationRaw, mirrored: p.mirrored, bodyWeightID: p.bodyWeightID, chunkIndex: i + 1)
            },
            progressionRules: all(DoubleProgressionModel.self).map { .init(exerciseID: $0.exerciseID, enabled: $0.enabled, lower: $0.repLower, upper: $0.repUpper, referenceSets: $0.referenceSets, increment: $0.increment, unit: $0.unitRaw, minimumRIR: $0.minimumRIR) },
            planVersions: all(PlanVersionModel.self).map { .init(id: $0.id, validFrom: $0.validFrom, daysJSON: $0.daysJSON) },
            customAttributions: all(CustomAttributionModel.self).map { .init(exerciseID: $0.exerciseID, muscle: $0.muscleRaw, role: $0.roleRaw) },
            datePrecision: ArchivePayload.millisecondPrecision
        )
    }

    /// Escribe el archivo cifrado en `url`. Con fotos, lee cada imagen de la bóveda (ya
    /// desbloqueada) y la cifra con la clave del archivo, de una en una. Si algo falla, borra el
    /// archivo parcial. Devuelve el contenido exportado (para el resumen).
    @discardableResult
    public func write(to url: URL, password: String, includePhotos: Bool) throws -> ArchivePayload {
        if includePhotos && photos == nil { throw ArchiveError.photosRequireUnlockedVault }
        let content = payload(includePhotos: includePhotos)
        let photoModels = includePhotos ? all(PhotoCheckInModel.self) : []
        let fileByID = Dictionary(uniqueKeysWithValues: photoModels.map { ($0.id, $0.encryptedFileName) })
        let manifest = ArchiveManifest(version: PortableArchive.formatVersion, createdAt: content.exportedAt, includesPhotos: includePhotos, counts: content.counts)
        let writer = try PortableArchiveWriter(url: url, password: password, manifest: manifest, chunkCount: 1 + content.photos.count)
        do {
            let encoder = ArchivePayload.makeEncoder()
            try writer.append(try encoder.encode(content))
            for photo in content.photos {
                guard let name = fileByID[photo.id], let store = photos else { throw ArchiveError.invalidContent("foto sin archivo") }
                try autoreleasepool { try writer.append(try store.readPhoto(named: name)) }
            }
            try writer.finish()
            return content
        } catch {
            writer.abort()
            throw error
        }
    }
}

#if !canImport(ObjectiveC)
@inline(__always) func autoreleasepool<T>(invoking body: () throws -> T) rethrows -> T { try body() }
#endif

/// Restauración del archivo (spec §19). Primero valida TODO (contraseña, integridad de cada
/// fragmento, versión, referencias); solo después modifica datos, en una única transacción:
/// si algo falla se deshacen los cambios y se borran las fotos ya escritas.
@MainActor
public struct ArchiveImporter {
    public let context: ModelContext
    public let photos: PhotoFileStore?
    /// Guardado inyectable para probar fallos a mitad de restauración.
    private let saver: (ModelContext) throws -> Void

    public init(context: ModelContext, photos: PhotoFileStore?, saver: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.context = context
        self.photos = photos
        self.saver = saver
    }

    /// Valida el archivo completo sin modificar nada y devuelve el resumen, con la previsión de
    /// lo que haría cada estrategia sobre los datos actuales.
    public func preview(url: URL, password: String) throws -> RestorePreview {
        let (payload, _) = try readAndValidate(url: url, password: password, keepPhotos: false)
        var plans: [RestoreStrategy: RestoreReport] = [:]
        for strategy in RestoreStrategy.allCases {
            plans[strategy] = try plan(payload, strategy: strategy)
        }
        return RestorePreview(exportedAt: payload.exportedAt, includesPhotos: payload.includesPhotos, counts: payload.counts, plans: plans)
    }

    /// Previsión sin escribir nada (mismas reglas que `restore`).
    private func plan(_ payload: ArchivePayload, strategy: RestoreStrategy) throws -> RestoreReport {
        let merger = ArchiveMerger(context: context, payload: payload, strategy: strategy, write: false)
        let existing = Dictionary(uniqueKeysWithValues: fetchAll(PhotoCheckInModel.self).map { ($0.id, $0) })
        for photo in payload.photos { merger.photo(photo, existing: existing[photo.id]) {} }
        merger.countDeviceOnlyPhotos(Set(existing.keys))
        try merger.mergeAll()
        return merger.report
    }

    /// Restaura según `strategy` (por defecto, combinar conservando este iPhone ante conflictos;
    /// ver `RestoreStrategy` y `ArchiveMerger`). Con `replaceProfileAndSettings` (siempre en
    /// reemplazo), el perfil, los ajustes, la rutina y los recordatorios del archivo sustituyen a
    /// los actuales. Las fotos se vuelven a cifrar con la clave local de ESTE dispositivo (T71).
    @discardableResult
    public func restore(url: URL, password: String, replaceProfileAndSettings: Bool, strategy: RestoreStrategy = .mergeKeepDevice) throws -> (RestoreReport, preferences: [String: String]) {
        let (payload, _) = try readAndValidate(url: url, password: password, keepPhotos: false)
        var writtenFiles: [String] = []
        do {
            let merger = ArchiveMerger(context: context, payload: payload, strategy: strategy, write: true)
            if replaceProfileAndSettings || strategy == .replace {
                applyProfileSettingsAndRoutine(payload)
            }
            // Segunda pasada: las imágenes se leen de nuevo, una a una, para no retenerlas todas.
            let reader = try PortableArchiveReader(url: url, password: password)
            _ = try reader.next()
            let existing = Dictionary(uniqueKeysWithValues: fetchAll(PhotoCheckInModel.self).map { ($0.id, $0) })
            for photo in payload.photos.sorted(by: { $0.chunkIndex < $1.chunkIndex }) {
                let data = try reader.next()
                try merger.photo(photo, existing: existing[photo.id]) {
                    guard let store = photos else { throw ArchiveError.photosRequireUnlockedVault }
                    let name = "restored-\(photo.id.uuidString).enc"
                    try store.writePhoto(data, named: name)
                    writtenFiles.append(name)
                    context.insert(PhotoCheckInModel(id: photo.id, date: photo.date, poseRaw: photo.pose, encryptedFileName: name, orientationRaw: photo.orientation, mirrored: photo.mirrored, bodyWeightID: photo.bodyWeightID))
                }
            }
            try reader.assertAtEnd()
            merger.countDeviceOnlyPhotos(Set(existing.keys))
            try merger.mergeAll()
            try saver(context)
            return (merger.report, payload.preferences)
        } catch {
            context.rollback()
            for name in writtenFiles { try? photos?.deletePhoto(named: name) }
            throw error
        }
    }

    // MARK: - Validación

    private func readAndValidate(url: URL, password: String, keepPhotos: Bool) throws -> (ArchivePayload, [Data]) {
        let reader = try PortableArchiveReader(url: url, password: password)
        let first = try reader.next()
        guard let payload = try? ArchivePayload.makeDecoder().decode(ArchivePayload.self, from: first) else { throw BackupError.corrupted }
        guard payload.formatVersion == 2 else {
            throw BackupError.unsupportedVersion(found: payload.formatVersion, supported: 2)
        }
        try validateReferences(payload, chunkCount: reader.chunkCount)
        if payload.includesPhotos && !payload.photos.isEmpty && photos == nil {
            throw ArchiveError.photosRequireUnlockedVault
        }
        var kept: [Data] = []
        for _ in payload.photos {
            let data = try reader.next()   // autentica cada fragmento
            if keepPhotos { kept.append(data) }
        }
        try reader.assertAtEnd()
        return (payload, kept)
    }

    private func validateReferences(_ p: ArchivePayload, chunkCount: Int) throws {
        func unique<T: Hashable>(_ values: [T], _ what: String) throws {
            guard Set(values).count == values.count else { throw ArchiveError.invalidContent("\(what) duplicados") }
        }
        try unique(p.sessions.map(\.id), "sesiones")
        try unique(p.sessions.flatMap { $0.exercises.map(\.id) }, "ejercicios de sesión")
        try unique(p.sessions.flatMap { $0.exercises.flatMap { $0.sets.map(\.id) } }, "series")
        try unique(p.bodyWeights.map(\.id), "pesajes")
        try unique(p.photos.map(\.id), "fotos")
        try unique(p.exercises.map(\.id), "ejercicios")
        try unique(p.exerciseSettings.map(\.exerciseID), "ajustes de ejercicio")
        try unique(p.resolutions.map(\.dayKey), "resoluciones")
        try unique((p.progressionRules ?? []).map(\.exerciseID), "reglas de progresión")
        let indices = p.photos.map(\.chunkIndex).sorted()
        guard indices == Array(1..<(p.photos.count + 1)), chunkCount == p.photos.count + 1 else {
            throw ArchiveError.invalidContent("fragmentos de foto inconsistentes")
        }
        let weightIDs = Set(p.bodyWeights.map(\.id))
        for photo in p.photos {
            if let w = photo.bodyWeightID, !weightIDs.contains(w) { throw ArchiveError.invalidContent("foto con pesaje inexistente") }
        }
        for set in p.sessions.flatMap({ $0.exercises.flatMap(\.sets) }) {
            guard SetState(rawValue: set.state) != nil, SetType(rawValue: set.type) != nil, LoadConvention(rawValue: set.convention) != nil else {
                throw ArchiveError.invalidContent("serie con valores desconocidos")
            }
        }
        for w in p.bodyWeights where w.amount <= 0 { throw ArchiveError.invalidContent("pesaje no válido") }
    }

    // MARK: - Aplicación (dentro de la transacción)

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    /// Perfil, ajustes, rutina (plantillas y versiones del plan) y recordatorios: se sustituyen
    /// por los del archivo solo con la opción explícita o en reemplazo.
    private func applyProfileSettingsAndRoutine(_ p: ArchivePayload) {
        for old in fetchAll(UserProfileModel.self) { context.delete(old) }
        for prof in p.profiles {
            context.insert(UserProfileModel(id: prof.id, displayName: prof.displayName, birthDate: prof.birthDate, experience: prof.experience, goalDescription: prof.goal, gender: prof.gender))
        }
        if let s = p.settings.first {
            let target = fetchAll(AppSettingsModel.self).first ?? {
                let m = AppSettingsModel(); context.insert(m); return m
            }()
            target.languageCode = s.languageCode
            target.massUnitRaw = s.massUnit
            target.lengthUnitRaw = s.lengthUnit
            target.themeRaw = s.theme
            target.weekStartsMonday = s.weekStartsMonday
            target.hapticsEnabled = s.hapticsEnabled
            target.onboardingCompleted = true
        }
        let templates = Dictionary(uniqueKeysWithValues: fetchAll(RoutineTemplateModel.self).map { ($0.id, $0) })
        for t in p.templates {
            if let existing = templates[t.id] {
                existing.name = t.name; existing.weekday = t.weekday; existing.groupsJoined = t.groups
                existing.preferredExerciseIDsJoined = t.preferred; existing.isRestDay = t.isRest
            } else {
                context.insert(RoutineTemplateModel(id: t.id, name: t.name, weekday: t.weekday, groupsJoined: t.groups, preferredExerciseIDsJoined: t.preferred, isRestDay: t.isRest))
            }
        }
        for old in fetchAll(ReminderRuleModel.self) { context.delete(old) }
        for r in p.reminderRules {
            context.insert(ReminderRuleModel(id: r.id, categoryRaw: r.category, weekday: r.weekday, hour: r.hour, minute: r.minute, enabled: r.enabled, timeZoneID: r.timeZoneID))
        }
        if let versions = p.planVersions, !versions.isEmpty {
            for old in fetchAll(PlanVersionModel.self) { context.delete(old) }
            for v in versions { context.insert(PlanVersionModel(id: v.id, validFrom: v.validFrom, daysJSON: v.daysJSON)) }
        }
    }
}

/// CSV de entrenamiento (spec §19, T69): solo series, sin fotos ni datos corporales.
@MainActor
public enum WorkoutCSV {
    public static func build(context: ModelContext, exerciseName: (String) -> String = ExerciseNames.localized) -> Data {
        let sessions = ((try? context.fetch(FetchDescriptor<WorkoutSessionModel>())) ?? []).sorted { $0.startedAt < $1.startedAt }
        let names = Dictionary(uniqueKeysWithValues: ((try? context.fetch(FetchDescriptor<ExerciseModel>())) ?? []).map { ($0.id, $0.name) })
        let day = DateFormatter()
        day.calendar = Calendar(identifier: .gregorian)
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        var rows: [CSVExport.Row] = []
        for s in sessions {
            day.timeZone = TimeZone(identifier: s.originTimeZoneID) ?? .current
            for e in s.exercises.sorted(by: { $0.order < $1.order }) {
                for set in WorkoutRepository.workOrder(e.sets) where set.stateRaw != SetState.pending.rawValue {
                    let d = set.toDomain()
                    rows.append(CSVExport.Row(
                        setID: set.id.uuidString,
                        sessionID: s.id.uuidString,
                        trainingDate: day.string(from: s.trainingDate),
                        timeZone: s.originTimeZoneID,
                        exercise: names[e.exerciseID] ?? exerciseName(e.exerciseID),
                        variant: e.variantKey ?? "",
                        equipment: d.load.convention.rawValue,
                        type: set.typeRaw,
                        state: set.stateRaw,
                        load: d.load.amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
                        unit: set.loadUnitRaw,
                        reps: set.reps.map(String.init) ?? "",
                        side: set.sideRaw,
                        rir: {
                            switch d.rir {
                            case .exact(let v): return "\(v)"
                            case .atLeast(let v): return "\(v)+"
                            case .unknown: return "?"
                            case nil: return ""
                            }
                        }()
                    ))
                }
            }
        }
        return CSVExport.data(rows: rows)
    }
}
