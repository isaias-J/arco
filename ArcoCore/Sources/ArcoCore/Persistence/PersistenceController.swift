import Foundation
import SwiftData

/// Configura el contenedor SwiftData y siembra el catálogo/plantillas iniciales.
public enum PersistenceController {

    /// Esquema vigente (v2).
    public static let schema = Schema(versionedSchema: ArcoSchemaV3.self)

    /// Ubicación de la base. Es la misma ruta que SwiftData usa por defecto
    /// (`Application Support/default.store`), fijada explícitamente para poder aplicarle la
    /// exclusión de copias automáticas sin mover datos ya existentes.
    public static var defaultStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    /// Contenedor de la app.
    /// - Parameters:
    ///   - inMemory: almacenamiento solo en memoria (vista previa y pruebas).
    ///   - url: ruta alternativa (pruebas aisladas). Por defecto, `defaultStoreURL`.
    /// - Important: `cloudKitDatabase: .none` es obligatorio: local significa local (spec §17).
    ///   Sin ese valor SwiftData intenta el modo automático y falla fuera de una app firmada.
    @MainActor
    public static func makeContainer(inMemory: Bool = false, url: URL? = nil) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let storeURL = url ?? defaultStoreURL
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            config = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        }
        let container = try ModelContainer(
            for: schema,
            migrationPlan: ArcoMigrationPlan.self,
            configurations: [config]
        )
        if !inMemory {
            // La base y sus archivos auxiliares (-wal, -shm) se excluyen de la copia automática
            // del dispositivo (spec §17). Se reaplica en cada arranque porque SQLite puede
            // recrear los auxiliares.
            try? BackupExclusion.apply(toStoreAt: url ?? defaultStoreURL)
        }
        seedIfNeeded(container.mainContext)
        return container
    }

    /// Siembra catálogo, ajustes y plantillas la primera vez. Idempotente: no duplica ni
    /// reemplaza datos del usuario (ejercicios renombrados o archivados se conservan).
    @MainActor
    public static func seedIfNeeded(_ context: ModelContext) {
        seedCatalog(context)
        seedSettings(context)
        seedTemplates(context)
        try? context.save()
    }

    private static func seedCatalog(_ context: ModelContext) {
        let existingIDs = Set(((try? context.fetch(FetchDescriptor<ExerciseModel>())) ?? []).map(\.id))
        for def in ExerciseCatalog.all where !existingIDs.contains(def.id) {
            context.insert(ExerciseModel(
                id: def.id,
                name: ExerciseNames.localized(def.id),
                aliasesJoined: def.aliases.joined(separator: "\n"),
                loadTypeRaw: def.defaultLoadType.rawValue,
                patternRaw: def.pattern.rawValue,
                originRaw: def.origin.rawValue,
                instructions: ExerciseNames.instructions(def.id)
            ))
        }
    }

    private static func seedSettings(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<AppSettingsModel>()))?.count ?? 0
        guard existing == 0 else { return }
        context.insert(AppSettingsModel())
    }

    /// Plantilla semanal confirmada por el propietario (spec §2), a partir de
    /// `WeeklyPlan.ownerDefault`. `weekday` usa la convención de `Calendar` (1 = domingo).
    private static func seedTemplates(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<RoutineTemplateModel>()))?.count ?? 0
        guard existing == 0 else { return }
        let ids: [Weekday: String] = [
            .monday: "mon_push", .tuesday: "tue_pull", .wednesday: "wed_legs", .thursday: "thu_rest",
            .friday: "fri_upper", .saturday: "sat_legs", .sunday: "sun_rest"
        ]
        for day in WeeklyPlan.ownerDefault.days {
            let id = ids[day.weekday] ?? "day_\(day.weekday.rawValue)"
            context.insert(RoutineTemplateModel(
                id: id,
                name: RoutineNames.localized(id),
                weekday: day.weekday.rawValue,
                groupsJoined: day.groups.map(\.rawValue).joined(separator: ","),
                isRestDay: day.isRest
            ))
        }
    }

    /// Plan semanal vigente construido a partir de las plantillas guardadas.
    @MainActor
    public static func weeklyPlan(_ context: ModelContext) -> WeeklyPlan {
        let templates = (try? context.fetch(FetchDescriptor<RoutineTemplateModel>())) ?? []
        return WeeklyPlan(templates: templates)
    }
}

public extension WeeklyPlan {
    /// Construye el plan desde las plantillas persistidas (misma convención de weekday).
    init(templates: [RoutineTemplateModel]) {
        self.init(days: templates.compactMap { t in
            guard let wd = Weekday(rawValue: t.weekday) else { return nil }
            let groups = t.groupsJoined.split(separator: ",").compactMap { MuscleGroup(rawValue: String($0)) }
            return Day(weekday: wd, isRest: t.isRestDay, groups: groups)
        })
    }
}

/// Exclusión de la copia de seguridad automática del dispositivo (spec §17, [A08]).
public enum BackupExclusion {
    /// Marca la base y sus auxiliares como excluidos. Los auxiliares que aún no existan se
    /// cubren reaplicando en cada arranque.
    public static func apply(toStoreAt storeURL: URL) throws {
        let fm = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let url = URL(fileURLWithPath: storeURL.path + suffix)
            if fm.fileExists(atPath: url.path) {
                try exclude(url)
            }
        }
    }

    public static func exclude(_ url: URL) throws {
        var mutable = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutable.setResourceValues(values)
    }

    public static func isExcluded(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup) ?? false
    }
}
