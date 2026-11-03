import Foundation
import SwiftData

// MARK: - Estrategia, conflictos e informe

/// Cómo se aplica una copia sobre un iPhone que ya tiene datos (spec §19).
///
/// - `mergeKeepDevice` (recomendada): añade lo que falta y adopta los cambios de la copia que
///   se pueden ordenar con seguridad; ante un conflicto real conserva lo de este iPhone.
/// - `mergePreferArchive`: igual, pero ante un conflicto real aplica lo de la copia.
/// - `replace`: deja entrenamientos, medidas, asistencia, catálogo y ajustes exactamente como en
///   la copia y elimina de este iPhone los registros que la copia no tiene. Las fotos de este
///   iPhone nunca se borran al restaurar.
public enum RestoreStrategy: String, Sendable, CaseIterable, Codable, Hashable {
    case mergeKeepDevice
    case mergePreferArchive
    case replace
}

/// Un registro que existe en los dos lados con contenido distinto y sin información suficiente
/// para saber cuál es posterior.
public struct RestoreConflict: Sendable, Equatable {
    public enum Resolution: String, Sendable, Equatable {
        case keptDevice      // se conservó lo de este iPhone
        case usedArchive     // se aplicó lo de la copia
    }
    public let category: String
    public let summary: String
    public let resolution: Resolution
}

/// Resultado (o previsión) de una restauración. Las claves son categorías: "sessions",
/// "sessionExercises", "sets", "exercises", "exerciseSettings", "progressionRules",
/// "customAttributions", "bodyWeights", "heights", "measurements", "attendance",
/// "resolutions", "reminderOverrides", "goals", "photos", "drafts".
public struct RestoreReport: Sendable, Equatable {
    /// Registros nuevos añadidos desde la copia.
    public var inserted: [String: Int] = [:]
    /// Registros ya presentes e idénticos: no cambian.
    public var skippedExisting: [String: Int] = [:]
    /// Registros existentes actualizados con la copia sin perder nada de este iPhone (p. ej.
    /// una serie que en la copia se confirmó después del borrador local, o un ejercicio
    /// preinstalado que aquí seguía con sus valores iniciales).
    public var updated: [String: Int] = [:]
    /// Versiones de este iPhone conservadas porque son demostrablemente posteriores o porque la
    /// copia no aporta cambios (no son conflictos).
    public var keptDevice: [String: Int] = [:]
    /// Registros que solo existen en este iPhone; al combinar se conservan.
    public var onlyOnDevice: [String: Int] = [:]
    /// Registros eliminados de este iPhone (solo en reemplazo; nunca fotos).
    public var removed: [String: Int] = [:]
    public var conflicts: [RestoreConflict] = []
    /// Borradores (series sin realizar) de la copia que no se añadieron a sesiones existentes.
    public var skippedDrafts: Int = 0

    public init() {}

    /// Conflictos en los que se conservó lo de este iPhone: lo de la copia no se aplicó.
    public var conflictsKeptDevice: Int { conflicts.filter { $0.resolution == .keptDevice }.count }
    public var conflictsUsedArchive: Int { conflicts.filter { $0.resolution == .usedArchive }.count }

    public func total(_ dict: [String: Int], excluding: Set<String> = []) -> Int {
        dict.filter { !excluding.contains($0.key) }.values.reduce(0, +)
    }
}

// MARK: - Comparación de instantes

/// Compara fechas según la precisión con que la copia las guardó. Las copias anteriores usaban
/// segundos enteros; las actuales, milisegundos.
struct ArchiveClock {
    let fine: Bool

    func same(_ a: Date, _ b: Date) -> Bool {
        fine ? abs(a.timeIntervalSince(b)) < 0.001
             : floor(a.timeIntervalSince1970) == floor(b.timeIntervalSince1970)
    }

    func same(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return same(x, y)
        default: return false
        }
    }

    /// `a` es estrictamente posterior a `b` con la precisión disponible.
    func later(_ a: Date, than b: Date) -> Bool {
        fine ? a.timeIntervalSince(b) >= 0.001
             : floor(a.timeIntervalSince1970) > floor(b.timeIntervalSince1970)
    }
}

// MARK: - Motor de combinación

/// Aplica (o solo prevé, con `write == false`) el contenido de una copia sobre el contexto.
/// No guarda: el importador guarda una única vez al final o deshace todo si algo falla.
///
/// Política (documentada en SEGUIMIENTO/02-DECISIONES.md):
/// - Nada se borra al combinar. Lo que solo está en este iPhone se conserva.
/// - Lo que solo está en la copia se añade, salvo borradores para sesiones que ya existen aquí.
/// - Si un registro existe en ambos lados con contenido distinto, solo se decide sin preguntar
///   cuando los datos guardados permiten ordenar las versiones (transiciones que la app solo
///   hace en un sentido, o valores iniciales de fábrica frente a valores del usuario). En
///   cualquier otro caso es un conflicto y se resuelve según la estrategia elegida.
@MainActor
final class ArchiveMerger {
    let context: ModelContext
    let payload: ArchivePayload
    let strategy: RestoreStrategy
    let write: Bool
    let clock: ArchiveClock
    private(set) var report = RestoreReport()
    private var touchedSessions: [UUID: WorkoutSessionModel] = [:]
    private var exerciseNames: [String: String] = [:]

    init(context: ModelContext, payload: ArchivePayload, strategy: RestoreStrategy, write: Bool) {
        self.context = context
        self.payload = payload
        self.strategy = strategy
        self.write = write
        self.clock = ArchiveClock(fine: payload.datePrecision == ArchivePayload.millisecondPrecision)
        for e in payload.exercises { exerciseNames[e.id] = e.name }
        for e in fetchAll(ExerciseModel.self) { exerciseNames[e.id] = e.name }
    }

    // MARK: Utilidades

    enum Outcome: Equatable {
        case same
        case takeArchive
        case keepDevice
        case conflict
    }

    private func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }

    private func bump(_ dict: inout [String: Int], _ key: String, _ n: Int = 1) {
        guard n > 0 else { return }
        dict[key, default: 0] += n
    }

    /// Registra el resultado y devuelve si hay que aplicar lo de la copia.
    @discardableResult
    private func settle(_ outcome: Outcome, _ category: String, _ describe: @autoclosure () -> String) -> Bool {
        switch outcome {
        case .same:
            bump(&report.skippedExisting, category)
            return false
        case .takeArchive:
            bump(&report.updated, category)
            return true
        case .keepDevice:
            if strategy == .replace { bump(&report.updated, category); return true }
            bump(&report.keptDevice, category)
            return false
        case .conflict:
            let useArchive = strategy != .mergeKeepDevice
            report.conflicts.append(RestoreConflict(category: category, summary: describe(), resolution: useArchive ? .usedArchive : .keptDevice))
            return useArchive
        }
    }

    private func name(_ exerciseID: String) -> String {
        exerciseNames[exerciseID] ?? ExerciseNames.localized(exerciseID)
    }

    private func day(_ d: Date) -> String {
        d.formatted(.dateTime.day().month(.abbreviated).year())
    }

    // MARK: Entrada

    /// Combina todo salvo las fotos (las gestiona el importador con `photo(_:insert:)`) y el
    /// perfil/rutina, que se reemplazan aparte por decisión explícita.
    func mergeAll() throws {
        mergeExercises()
        mergeExerciseSettings()
        mergeProgressionRules()
        mergeCustomAttributions()
        mergeSessions()
        mergeBodyWeights()
        mergeSimple(category: "heights", device: fetchAll(HeightModel.self), key: \.id, archive: payload.heights, archiveKey: \.id,
                    equal: { d, a in d.amount == a.amount && d.unitRaw == a.unit && self.clock.same(d.date, a.date) },
                    describe: { a in "Altura del \(self.day(a.date))" },
                    insert: { a in self.context.insert(HeightModel(id: a.id, date: a.date, amount: a.amount, unitRaw: a.unit)) },
                    update: { d, a in d.amount = a.amount; d.unitRaw = a.unit; d.date = a.date })
        mergeSimple(category: "measurements", device: fetchAll(BodyMeasurementModel.self), key: \.id, archive: payload.measurements, archiveKey: \.id,
                    equal: { d, a in d.typeKey == a.typeKey && d.sideRaw == a.side && d.protocolNote == a.protocolNote && d.amount == a.amount && d.unitRaw == a.unit && self.clock.same(d.date, a.date) },
                    describe: { a in "Medida del \(self.day(a.date))" },
                    insert: { a in self.context.insert(BodyMeasurementModel(id: a.id, typeKey: a.typeKey, sideRaw: a.side, protocolNote: a.protocolNote, amount: a.amount, unitRaw: a.unit, date: a.date)) },
                    update: { d, a in d.typeKey = a.typeKey; d.sideRaw = a.side; d.protocolNote = a.protocolNote; d.amount = a.amount; d.unitRaw = a.unit; d.date = a.date })
        mergeSimple(category: "goals", device: fetchAll(WeeklyGoalModel.self), key: \.id, archive: payload.goals, archiveKey: \.id,
                    equal: { d, a in d.muscleRaw == a.muscle && d.methodRaw == a.method && d.target == a.target && self.clock.same(d.validFrom, a.validFrom) && self.clock.same(d.validTo, a.validTo) && d.sourceRaw == a.source },
                    describe: { a in "Meta de \(a.muscle)" },
                    insert: { a in self.context.insert(WeeklyGoalModel(id: a.id, muscleRaw: a.muscle, methodRaw: a.method, target: a.target, validFrom: a.validFrom, validTo: a.validTo, sourceRaw: a.source)) },
                    update: { d, a in d.muscleRaw = a.muscle; d.methodRaw = a.method; d.target = a.target; d.validFrom = a.validFrom; d.validTo = a.validTo; d.sourceRaw = a.source })
        mergeSimple(category: "resolutions", device: fetchAll(AttendanceResolutionModel.self), key: \.dayKey, archive: payload.resolutions, archiveKey: \.dayKey,
                    equal: { d, a in d.kindRaw == a.kind },
                    describe: { a in "Resolución del día \(a.dayKey) (\(a.kind == "rest" ? "descanso" : "ausencia") en la copia)" },
                    insert: { a in self.context.insert(AttendanceResolutionModel(id: a.id, dayKey: a.dayKey, kindRaw: a.kind, createdAt: a.createdAt)) },
                    update: { d, a in d.kindRaw = a.kind; d.createdAt = a.createdAt })
        mergeSimple(category: "reminderOverrides", device: fetchAll(ReminderOverrideModel.self), key: \.id, archive: payload.reminderOverrides, archiveKey: \.id,
                    equal: { d, a in d.categoryRaw == a.category && d.dayKey == a.dayKey && d.hour == a.hour && d.minute == a.minute && d.enabled == a.enabled },
                    describe: { a in "Cambio de aviso del \(a.dayKey)" },
                    insert: { a in self.context.insert(ReminderOverrideModel(id: a.id, categoryRaw: a.category, dayKey: a.dayKey, hour: a.hour, minute: a.minute, enabled: a.enabled)) },
                    update: { d, a in d.categoryRaw = a.category; d.dayKey = a.dayKey; d.hour = a.hour; d.minute = a.minute; d.enabled = a.enabled })
        mergeAttendance()
        if write { syncDerivedData() }
    }

    // MARK: Registros simples por clave

    private func mergeSimple<M: PersistentModel, A, K: Hashable>(
        category: String,
        device: [M], key: (M) -> K,
        archive: [A], archiveKey: (A) -> K,
        equal: (M, A) -> Bool,
        outcome: ((M, A) -> Outcome)? = nil,
        describe: (A) -> String,
        insert: (A) -> Void,
        update: (M, A) -> Void
    ) {
        var byKey: [K: M] = [:]
        for d in device { byKey[key(d)] = d }
        let archiveKeys = Set(archive.map(archiveKey))
        for a in archive {
            if let d = byKey[archiveKey(a)] {
                let o: Outcome = equal(d, a) ? .same : (outcome?(d, a) ?? .conflict)
                if settle(o, category, describe(a)), write { update(d, a) }
            } else {
                bump(&report.inserted, category)
                if write { insert(a) }
            }
        }
        let deviceOnly = device.filter { !archiveKeys.contains(key($0)) }
        if strategy == .replace {
            bump(&report.removed, category, deviceOnly.count)
            if write { deviceOnly.forEach { context.delete($0) } }
        } else {
            bump(&report.onlyOnDevice, category, deviceOnly.count)
        }
    }

    // MARK: Catálogo

    /// Valores con los que se siembra un ejercicio preinstalado. nil para personalizados.
    private func factoryDefaults(_ id: String) -> ArchivePayload.Exercise? {
        guard let def = ExerciseCatalog.definition(id) else { return nil }
        return .init(id: id, name: ExerciseNames.localized(id), aliases: def.aliases.joined(separator: "\n"),
                     loadType: def.defaultLoadType.rawValue, pattern: def.pattern.rawValue,
                     origin: def.origin.rawValue, instructions: ExerciseNames.instructions(id), archived: false)
    }

    private func mergeExercises() {
        let device = fetchAll(ExerciseModel.self)
        var byID: [String: ExerciseModel] = [:]
        for d in device { byID[d.id] = d }
        let archiveIDs = Set(payload.exercises.map(\.id))

        for a in payload.exercises {
            guard let d = byID[a.id] else {
                bump(&report.inserted, "exercises")
                if write {
                    context.insert(ExerciseModel(id: a.id, name: a.name, aliasesJoined: a.aliases, loadTypeRaw: a.loadType, patternRaw: a.pattern, originRaw: a.origin, instructions: a.instructions, archived: a.archived))
                }
                continue
            }
            let defaults = factoryDefaults(a.id)
            // Campo a campo: si este iPhone conserva el valor de fábrica, se adopta el de la copia
            // (no se pierde nada local); si la copia trae el de fábrica, se conserva lo local; si
            // ambos lo cambiaron de forma distinta, es un conflicto.
            struct Field { let label: String; let device: String; let archive: String; let factory: String?; let apply: (ExerciseModel) -> Void }
            let fields: [Field] = [
                Field(label: "nombre", device: d.name, archive: a.name, factory: defaults?.name, apply: { $0.name = a.name }),
                Field(label: "alias", device: d.aliasesJoined, archive: a.aliases, factory: defaults?.aliases, apply: { $0.aliasesJoined = a.aliases }),
                Field(label: "equipo", device: d.loadTypeRaw, archive: a.loadType, factory: defaults?.loadType, apply: { $0.loadTypeRaw = a.loadType }),
                Field(label: "patrón", device: d.patternRaw, archive: a.pattern, factory: defaults?.pattern, apply: { $0.patternRaw = a.pattern }),
                Field(label: "instrucciones", device: d.instructions, archive: a.instructions, factory: defaults?.instructions, apply: { $0.instructions = a.instructions }),
                Field(label: "archivado", device: String(d.archived), archive: String(a.archived), factory: defaults.map { String($0.archived) }, apply: { $0.archived = a.archived })
            ]
            let differing = fields.filter { $0.device != $0.archive }
            if differing.isEmpty { bump(&report.skippedExisting, "exercises"); continue }

            var safe: [Field] = []
            var conflicting: [Field] = []
            var keptLocal = false
            for f in differing {
                if let factory = f.factory, f.device == factory { safe.append(f) }
                else if let factory = f.factory, f.archive == factory { keptLocal = true }
                else { conflicting.append(f) }
            }
            // Un nombre de la copia que ya usa otro ejercicio de este iPhone no se aplica nunca:
            // Arco no fusiona historiales (spec §6).
            let nameClash = device.contains { $0.id != a.id && $0.name.compare(a.name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
            if nameClash {
                safe.removeAll { $0.label == "nombre" }
                conflicting.removeAll { $0.label == "nombre" }
            }

            var apply = safe
            if !conflicting.isEmpty {
                let detail = conflicting.map { "\($0.label): «\(Self.short($0.device))» aquí, «\(Self.short($0.archive))» en la copia" }.joined(separator: "; ")
                if settle(.conflict, "exercises", "Ejercicio \(d.name) — \(detail)") { apply += conflicting }
            } else if !safe.isEmpty {
                bump(&report.updated, "exercises")
            } else if keptLocal || nameClash {
                settle(.keepDevice, "exercises", "")
            }
            // Reemplazar deja el ejercicio exactamente como en la copia (salvo un nombre ocupado).
            if strategy == .replace {
                apply = differing.filter { !(nameClash && $0.label == "nombre") }
            }
            if nameClash && d.name != a.name {
                report.conflicts.append(RestoreConflict(category: "exercises", summary: "Ejercicio \(d.name): la copia lo llama «\(a.name)», nombre que aquí ya usa otro ejercicio; se conserva el nombre actual.", resolution: .keptDevice))
            }
            if write { apply.forEach { $0.apply(d) } }
        }
        let deviceOnly = device.filter { !archiveIDs.contains($0.id) }.count
        // Los ejercicios nunca se borran al restaurar: pueden tener historial asociado.
        bump(&report.onlyOnDevice, "exercises", deviceOnly)
    }

    private static func short(_ s: String) -> String {
        let one = s.replacingOccurrences(of: "\n", with: ", ")
        return one.count > 40 ? String(one.prefix(40)) + "…" : one
    }

    private func mergeExerciseSettings() {
        let device = fetchAll(ExerciseSettingsModel.self)
        var byID: [String: ExerciseSettingsModel] = [:]
        for d in device { byID[d.exerciseID] = d }
        let archiveIDs = Set(payload.exerciseSettings.map(\.exerciseID))
        for a in payload.exerciseSettings {
            guard let d = byID[a.exerciseID] else {
                bump(&report.inserted, "exerciseSettings")
                if write { context.insert(ExerciseSettingsModel(exerciseID: a.exerciseID, conventionRaw: a.convention, sideModeRaw: a.sideMode, incrementAmount: a.increment, barWeight: a.barWeight, unitRaw: a.unit, defaultVariant: a.defaultVariant)) }
                continue
            }
            let same = d.conventionRaw == a.convention && d.sideModeRaw == a.sideMode && d.incrementAmount == a.increment
                && d.barWeight == a.barWeight && d.unitRaw == a.unit && d.defaultVariant == a.defaultVariant
            if same { bump(&report.skippedExisting, "exerciseSettings"); continue }
            // Un valor vacío aquí (desconocido) se completa con el de la copia sin perder nada.
            // `sideMode` no tiene "vacío": si difiere, es un conflicto.
            func onlyFills<T: Equatable>(_ dv: T?, _ av: T?) -> Bool { dv == av || dv == nil }
            let fillsOnly = onlyFills(d.conventionRaw, a.convention) && onlyFills(d.incrementAmount, a.increment)
                && onlyFills(d.barWeight, a.barWeight) && onlyFills(d.unitRaw, a.unit) && onlyFills(d.defaultVariant, a.defaultVariant)
                && d.sideModeRaw == a.sideMode
            let outcome: Outcome = fillsOnly ? .takeArchive : .conflict
            if settle(outcome, "exerciseSettings", "Carga y lados de \(name(a.exerciseID))"), write {
                d.conventionRaw = a.convention; d.sideModeRaw = a.sideMode; d.incrementAmount = a.increment
                d.barWeight = a.barWeight; d.unitRaw = a.unit; d.defaultVariant = a.defaultVariant
            }
        }
        removeOrKeepDeviceOnly(device.filter { !archiveIDs.contains($0.exerciseID) }, "exerciseSettings")
    }

    private func mergeProgressionRules() {
        let rules = payload.progressionRules ?? []
        mergeSimple(category: "progressionRules", device: fetchAll(DoubleProgressionModel.self), key: \.exerciseID, archive: rules, archiveKey: \.exerciseID,
                    equal: { d, a in d.enabled == a.enabled && d.repLower == a.lower && d.repUpper == a.upper && d.referenceSets == a.referenceSets && d.increment == a.increment && d.unitRaw == a.unit && d.minimumRIR == a.minimumRIR },
                    describe: { a in "Regla de doble progresión de \(self.name(a.exerciseID))" },
                    insert: { a in self.context.insert(DoubleProgressionModel(exerciseID: a.exerciseID, enabled: a.enabled, repLower: a.lower, repUpper: a.upper, referenceSets: a.referenceSets, increment: a.increment, unitRaw: a.unit, minimumRIR: a.minimumRIR)) },
                    update: { d, a in d.enabled = a.enabled; d.repLower = a.lower; d.repUpper = a.upper; d.referenceSets = a.referenceSets; d.increment = a.increment; d.unitRaw = a.unit; d.minimumRIR = a.minimumRIR })
    }

    /// Las atribuciones personalizadas se comparan por ejercicio (conjunto de músculo y papel).
    private func mergeCustomAttributions() {
        let incoming = Dictionary(grouping: payload.customAttributions ?? [], by: \.exerciseID)
        let device = Dictionary(grouping: fetchAll(CustomAttributionModel.self), by: \.exerciseID)
        for (exerciseID, rows) in incoming {
            let a = Set(rows.map { "\($0.muscle)=\($0.role)" })
            guard let current = device[exerciseID] else {
                bump(&report.inserted, "customAttributions")
                if write { rows.forEach { context.insert(CustomAttributionModel(exerciseID: $0.exerciseID, muscleRaw: $0.muscle, roleRaw: $0.role)) } }
                continue
            }
            let d = Set(current.map { "\($0.muscleRaw)=\($0.roleRaw)" })
            let outcome: Outcome = a == d ? .same : .conflict
            if settle(outcome, "customAttributions", "Atribución muscular de \(name(exerciseID))"), write {
                current.forEach { context.delete($0) }
                rows.forEach { context.insert(CustomAttributionModel(exerciseID: $0.exerciseID, muscleRaw: $0.muscle, roleRaw: $0.role)) }
            }
        }
        let deviceOnly = device.filter { incoming[$0.key] == nil }
        if strategy == .replace {
            bump(&report.removed, "customAttributions", deviceOnly.count)
            if write { deviceOnly.values.flatMap { $0 }.forEach { context.delete($0) } }
        } else {
            bump(&report.onlyOnDevice, "customAttributions", deviceOnly.count)
        }
    }

    private func removeOrKeepDeviceOnly<M: PersistentModel>(_ items: [M], _ category: String) {
        if strategy == .replace {
            bump(&report.removed, category, items.count)
            if write { items.forEach { context.delete($0) } }
        } else {
            bump(&report.onlyOnDevice, category, items.count)
        }
    }

    // MARK: Sesiones, ejercicios de sesión y series

    private static func isTerminal(_ state: String) -> Bool { state != "active" }

    private func mergeSessions() {
        let device = fetchAll(WorkoutSessionModel.self)
        var byID: [UUID: WorkoutSessionModel] = [:]
        for d in device { byID[d.id] = d }
        var deviceSets: [UUID: SetRecordModel] = [:]
        for s in fetchAll(SetRecordModel.self) { deviceSets[s.id] = s }
        let archiveIDs = Set(payload.sessions.map(\.id))

        for a in payload.sessions {
            if let d = byID[a.id] {
                mergeSession(d, a, deviceSets: deviceSets)
            } else {
                insertSession(a)
            }
        }
        let deviceOnly = device.filter { !archiveIDs.contains($0.id) }
        if strategy == .replace {
            bump(&report.removed, "sessions", deviceOnly.count)
            bump(&report.removed, "sets", deviceOnly.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } })
            if write { deviceOnly.forEach { context.delete($0) } }   // cascada: ejercicios y series
        } else {
            bump(&report.onlyOnDevice, "sessions", deviceOnly.count)
        }
    }

    private func insertSession(_ a: ArchivePayload.Session) {
        bump(&report.inserted, "sessions")
        bump(&report.inserted, "sets", a.exercises.reduce(0) { $0 + $1.sets.count })
        guard write else { return }
        let session = WorkoutSessionModel(id: a.id, startedAt: a.startedAt, endedAt: a.endedAt, stateRaw: a.state, trainingDate: a.trainingDate, originTimeZoneID: a.timeZone, templateID: a.templateID)
        context.insert(session)
        for e in a.exercises { insertSessionExercise(e, into: session, sets: e.sets) }
        touchedSessions[session.id] = session
    }

    @discardableResult
    private func insertSessionExercise(_ e: ArchivePayload.SessionExercise, into session: WorkoutSessionModel, sets: [ArchivePayload.SetRow]) -> SessionExerciseModel? {
        guard write else { return nil }
        let se = SessionExerciseModel(id: e.id, exerciseID: e.exerciseID, variantKey: e.variantKey, order: e.order)
        context.insert(se)
        se.session = session
        session.exercises.append(se)
        for r in sets { insertSet(r, into: se) }
        return se
    }

    private func insertSet(_ r: ArchivePayload.SetRow, into se: SessionExerciseModel) {
        let m = SetRecordModel(id: r.id, loadAmount: r.loadAmount, loadUnitRaw: r.unit, loadConventionRaw: r.convention, reps: r.reps, typeRaw: r.type, stateRaw: r.state, sideRaw: r.side, rirKind: r.rirKind, rirValue: r.rirValue, performedAt: r.performedAt, attributionMajor: r.attrMajor, attributionMinor: r.attrMinor)
        context.insert(m)
        m.sessionExercise = se
        se.sets.append(m)
    }

    private func sessionOutcome(_ d: WorkoutSessionModel, _ a: ArchivePayload.Session) -> Outcome {
        let core = clock.same(d.startedAt, a.startedAt) && clock.same(d.trainingDate, a.trainingDate)
            && d.originTimeZoneID == a.timeZone && d.templateID == a.templateID
        let status = d.stateRaw == a.state && clock.same(d.endedAt, a.endedAt)
        if core && status { return .same }
        if core {
            // Finalizar es definitivo en Arco: una sesión cerrada no se reabre.
            if d.stateRaw == "active" && Self.isTerminal(a.state) { return .takeArchive }
            if Self.isTerminal(d.stateRaw) && a.state == "active" { return .keepDevice }
        }
        return .conflict
    }

    private func mergeSession(_ d: WorkoutSessionModel, _ a: ArchivePayload.Session, deviceSets: [UUID: SetRecordModel]) {
        let wasActive = d.stateRaw == "active"
        let outcome = sessionOutcome(d, a)
        let applyMeta = settle(outcome, "sessions", "Sesión del \(day(a.trainingDate)): fecha, estado u hora de cierre distintos")
        if applyMeta && write {
            d.startedAt = a.startedAt; d.endedAt = a.endedAt; d.stateRaw = a.state
            d.trainingDate = a.trainingDate; d.originTimeZoneID = a.timeZone; d.templateID = a.templateID
            touchedSessions[d.id] = d
        }
        let archiveSetIDs = Set(a.exercises.flatMap { $0.sets.map(\.id) })
        // Si la copia cerró la sesión, los borradores locales que la copia no tiene se descartan,
        // igual que al finalizar en Arco (un borrador nunca fue una serie realizada).
        if applyMeta && wasActive && Self.isTerminal(a.state) {
            let drafts = d.exercises.flatMap(\.sets).filter { $0.stateRaw == SetState.pending.rawValue && !archiveSetIDs.contains($0.id) }
            bump(&report.removed, "drafts", drafts.count)
            if write {
                for draft in drafts {
                    draft.sessionExercise?.sets.removeAll { $0.id == draft.id }
                    context.delete(draft)
                }
            }
        }
        let sessionIsTerminal = Self.isTerminal(applyMeta ? a.state : d.stateRaw)

        var deviceSE: [UUID: SessionExerciseModel] = [:]
        for se in d.exercises { deviceSE[se.id] = se }
        let archiveSEIDs = Set(a.exercises.map(\.id))

        for e in a.exercises {
            if let dse = deviceSE[e.id] {
                mergeSessionExercise(dse, e, session: d, sessionIsTerminal: sessionIsTerminal, deviceSets: deviceSets)
            } else {
                // Ejercicio que solo tiene la copia. En una sesión que ya existe aquí no se añaden
                // borradores (pueden haberse descartado aquí a propósito), solo series reales.
                let rows = strategy == .replace ? e.sets : e.sets.filter { $0.state != SetState.pending.rawValue }
                report.skippedDrafts += e.sets.count - rows.count
                // Sin series reales que aportar, solo se añade un ejercicio vacío a una sesión
                // abierta (es parte del plan de la sesión); nunca a una ya cerrada.
                if rows.isEmpty && strategy != .replace && !(e.sets.isEmpty && !sessionIsTerminal) { continue }
                bump(&report.inserted, "sessionExercises")
                bump(&report.inserted, "sets", rows.count)
                insertSessionExercise(e, into: d, sets: rows)
                touchedSessions[d.id] = d
            }
        }
        let deviceOnlySE = d.exercises.filter { !archiveSEIDs.contains($0.id) }
        if strategy == .replace {
            bump(&report.removed, "sessionExercises", deviceOnlySE.count)
            bump(&report.removed, "sets", deviceOnlySE.reduce(0) { $0 + $1.sets.count })
            if write {
                for se in deviceOnlySE {
                    d.exercises.removeAll { $0.id == se.id }
                    context.delete(se)
                }
                touchedSessions[d.id] = d
            }
        } else {
            bump(&report.onlyOnDevice, "sessionExercises", deviceOnlySE.count)
        }
    }

    private func mergeSessionExercise(_ dse: SessionExerciseModel, _ e: ArchivePayload.SessionExercise, session: WorkoutSessionModel, sessionIsTerminal: Bool, deviceSets: [UUID: SetRecordModel]) {
        if dse.exerciseID != e.exerciseID {
            // Sustitución distinta en cada lado. Las series hechas nunca se reasignan a otro
            // ejercicio: solo se aplica la copia si este iPhone no tiene series realizadas ahí.
            let localWork = dse.sets.contains { $0.stateRaw != SetState.pending.rawValue }
            let canApply = strategy == .replace || !localWork
            let archiveWork = e.sets.filter { $0.state != SetState.pending.rawValue }.count
            let summary = "Sesión del \(day(session.trainingDate)): aquí \(name(dse.exerciseID)), en la copia \(name(e.exerciseID))"
                + (archiveWork > 0 ? " con \(archiveWork) series realizadas" : "")
            if strategy == .mergeKeepDevice || !canApply {
                report.conflicts.append(RestoreConflict(category: "sessionExercises", summary: summary + (canApply ? "" : "; no se combinan porque aquí ya hay series realizadas"), resolution: .keptDevice))
                return
            }
            report.conflicts.append(RestoreConflict(category: "sessionExercises", summary: summary, resolution: .usedArchive))
            if write {
                for draft in dse.sets where draft.stateRaw == SetState.pending.rawValue && !e.sets.contains(where: { $0.id == draft.id }) {
                    dse.sets.removeAll { $0.id == draft.id }
                    context.delete(draft)
                }
                dse.exerciseID = e.exerciseID; dse.variantKey = e.variantKey; dse.order = e.order
                touchedSessions[session.id] = session
            }
        } else {
            let same = dse.variantKey == e.variantKey && dse.order == e.order
            let outcome: Outcome = same ? .same : .conflict
            if settle(outcome, "sessionExercises", "Sesión del \(day(session.trainingDate)): orden o variante de \(name(e.exerciseID))"), write {
                dse.variantKey = e.variantKey; dse.order = e.order
            }
        }

        let archiveSetIDs = Set(e.sets.map(\.id))
        for r in e.sets {
            if let ds = deviceSets[r.id] {
                let outcome = setOutcome(ds, r)
                if settle(outcome, "sets", setConflictSummary(ds, r, session: session, exerciseID: e.exerciseID)), write {
                    ds.loadAmount = r.loadAmount; ds.loadUnitRaw = r.unit; ds.loadConventionRaw = r.convention
                    ds.reps = r.reps; ds.typeRaw = r.type; ds.stateRaw = r.state; ds.sideRaw = r.side
                    ds.rirKind = r.rirKind; ds.rirValue = r.rirValue; ds.performedAt = r.performedAt
                    ds.attributionMajor = r.attrMajor; ds.attributionMinor = r.attrMinor
                    touchedSessions[session.id] = session
                }
            } else if r.state == SetState.pending.rawValue && strategy != .replace {
                report.skippedDrafts += 1
            } else {
                bump(&report.inserted, "sets")
                if write { insertSet(r, into: dse); touchedSessions[session.id] = session }
            }
        }
        let deviceOnly = dse.sets.filter { !archiveSetIDs.contains($0.id) }
        if strategy == .replace {
            bump(&report.removed, "sets", deviceOnly.count)
            if write {
                for s in deviceOnly { dse.sets.removeAll { $0.id == s.id }; context.delete(s) }
                touchedSessions[session.id] = session
            }
        } else {
            bump(&report.onlyOnDevice, "sets", deviceOnly.count)
        }
    }

    /// Decide entre dos versiones de una misma serie.
    ///
    /// Datos que lo permiten: confirmar estampa la hora real (`performedAt`) y omitir solo
    /// ocurre desde un borrador. Por eso una versión realizada cuya hora es posterior a la del
    /// borrador del otro lado es la más reciente. Si las horas coinciden (p. ej. se deshizo una
    /// confirmación) o ambas están realizadas con valores distintos (una edición), no hay forma
    /// de saber cuál es posterior: es un conflicto.
    func setOutcome(_ d: SetRecordModel, _ a: ArchivePayload.SetRow) -> Outcome {
        let equal = d.loadAmount == a.loadAmount && d.loadUnitRaw == a.unit && d.loadConventionRaw == a.convention
            && d.reps == a.reps && d.typeRaw == a.type && d.stateRaw == a.state && d.sideRaw == a.side
            && d.rirKind == a.rirKind && d.rirValue == a.rirValue && clock.same(d.performedAt, a.performedAt)
            && d.attributionMajor == a.attrMajor && d.attributionMinor == a.attrMinor
        if equal { return .same }
        let pending = SetState.pending.rawValue, skipped = SetState.skipped.rawValue
        let dPending = d.stateRaw == pending, aPending = a.state == pending
        if dPending && !aPending {
            if a.state == skipped || clock.later(a.performedAt, than: d.performedAt) { return .takeArchive }
        }
        if aPending && !dPending {
            if d.stateRaw == skipped || clock.later(d.performedAt, than: a.performedAt) { return .keepDevice }
        }
        if dPending && aPending { return .keepDevice }   // dos borradores: ninguno es una serie hecha
        return .conflict
    }

    private func setConflictSummary(_ d: SetRecordModel, _ a: ArchivePayload.SetRow, session: WorkoutSessionModel, exerciseID: String) -> String {
        func text(_ amount: Decimal?, _ unit: String, _ reps: Int?, _ state: String) -> String {
            let load = amount.map { "\(NSDecimalNumber(decimal: $0).stringValue) \(unit)" } ?? "carga desconocida"
            let r = reps.map { "\($0) rep." } ?? "— rep."
            return "\(load) × \(r) (\(Self.stateLabel(state)))"
        }
        return "Serie de \(name(exerciseID)) del \(day(session.trainingDate)): aquí \(text(d.loadAmount, d.loadUnitRaw, d.reps, d.stateRaw)); en la copia \(text(a.loadAmount, a.unit, a.reps, a.state))"
    }

    static func stateLabel(_ raw: String) -> String {
        switch SetState(rawValue: raw) {
        case .pending: return "borrador"
        case .completed: return "realizada"
        case .skipped: return "omitida"
        case .deleted: return "eliminada"
        case nil: return raw
        }
    }

    // MARK: Peso corporal

    private func mergeBodyWeights() {
        mergeSimple(category: "bodyWeights", device: fetchAll(BodyWeightModel.self), key: \.id, archive: payload.bodyWeights, archiveKey: \.id,
                    equal: { d, a in self.weightCore(d, a) && d.photoCheckInID == a.photoCheckInID },
                    outcome: { d, a in
                        // Vincular una foto a un pesaje es un añadido: si aquí no tiene foto y el
                        // resto coincide, se adopta el vínculo de la copia.
                        (self.weightCore(d, a) && d.photoCheckInID == nil && a.photoCheckInID != nil) ? .takeArchive : .conflict
                    },
                    describe: { a in "Pesaje del \(self.day(a.measurementDate))" },
                    insert: { a in self.context.insert(BodyWeightModel(id: a.id, measurementDate: a.measurementDate, enteredAt: a.enteredAt, amount: a.amount, unitRaw: a.unit, isEstimated: a.isEstimated, photoCheckInID: a.photoCheckInID)) },
                    update: { d, a in d.measurementDate = a.measurementDate; d.enteredAt = a.enteredAt; d.amount = a.amount; d.unitRaw = a.unit; d.isEstimated = a.isEstimated; d.photoCheckInID = a.photoCheckInID })
    }

    private func weightCore(_ d: BodyWeightModel, _ a: ArchivePayload.BodyWeight) -> Bool {
        d.amount == a.amount && d.unitRaw == a.unit && d.isEstimated == a.isEstimated
            && clock.same(d.measurementDate, a.measurementDate) && clock.same(d.enteredAt, a.enteredAt)
    }

    // MARK: Fotos (metadatos; la imagen la escribe el importador)

    /// Decide qué hacer con una foto de la copia. `insert` escribe la imagen recifrada y crea el
    /// registro; solo se llama si la foto no existe aquí. Las fotos de este iPhone nunca se
    /// borran ni se sustituyen al restaurar.
    func photo(_ p: ArchivePayload.Photo, existing: PhotoCheckInModel?, insert: () throws -> Void) rethrows {
        guard let d = existing else {
            bump(&report.inserted, "photos")
            if write { try insert() }
            return
        }
        let core = clock.same(d.date, p.date) && d.poseRaw == p.pose && d.orientationRaw == p.orientation && d.mirrored == p.mirrored
        if core && d.bodyWeightID == p.bodyWeightID { bump(&report.skippedExisting, "photos"); return }
        let outcome: Outcome = (core && d.bodyWeightID == nil && p.bodyWeightID != nil) ? .takeArchive : .conflict
        if settle(outcome, "photos", "Datos de una foto del \(day(p.date)) (la imagen no se sustituye)"), write {
            d.date = p.date; d.poseRaw = p.pose; d.orientationRaw = p.orientation; d.mirrored = p.mirrored; d.bodyWeightID = p.bodyWeightID
        }
    }

    /// Fotos de este iPhone que la copia no tiene: siempre se conservan.
    func countDeviceOnlyPhotos(_ deviceIDs: Set<UUID>) {
        let archiveIDs = Set(payload.photos.map(\.id))
        bump(&report.onlyOnDevice, "photos", deviceIDs.subtracting(archiveIDs).count)
    }

    // MARK: Asistencia

    private func mergeAttendance() {
        let device = fetchAll(AttendanceEventModel.self)
        var byID: [UUID: AttendanceEventModel] = [:]
        for d in device { byID[d.id] = d }
        let automaticSessions = Set(device.filter { $0.sourceRaw == AttendanceSource.automatic.rawValue }.compactMap(\.sessionID))
        let archiveIDs = Set(payload.attendance.map(\.id))
        for a in payload.attendance {
            if let d = byID[a.id] {
                let same = clock.same(d.trainingDate, a.trainingDate) && d.sourceRaw == a.source && d.sessionID == a.sessionID && d.isPartial == a.isPartial
                // La asistencia automática se deriva de las series: se recalcula al final.
                let outcome: Outcome = same ? .same : (a.source == AttendanceSource.automatic.rawValue ? .keepDevice : .conflict)
                if settle(outcome, "attendance", "Asistencia del \(day(a.trainingDate))"), write {
                    d.trainingDate = a.trainingDate; d.sourceRaw = a.source; d.sessionID = a.sessionID; d.isPartial = a.isPartial
                }
            } else if a.source == AttendanceSource.automatic.rawValue, let sid = a.sessionID, automaticSessions.contains(sid) {
                // La misma sesión ya tiene aquí su asistencia automática: no se duplica el día.
                bump(&report.skippedExisting, "attendance")
            } else {
                bump(&report.inserted, "attendance")
                if write { context.insert(AttendanceEventModel(id: a.id, trainingDate: a.trainingDate, sourceRaw: a.source, sessionID: a.sessionID, isPartial: a.isPartial)) }
            }
        }
        removeOrKeepDeviceOnly(device.filter { !archiveIDs.contains($0.id) }, "attendance")
    }

    /// Datos derivados de las series combinadas: asistencia automática de cada sesión tocada y
    /// vínculos foto-pesaje que hayan quedado sin destino. Récords, gráficas, conteos y
    /// sugerencias se recalculan siempre desde los registros, no se guardan.
    private func syncDerivedData() {
        let repository = WorkoutRepository(context: context, saver: { _ in })
        for session in touchedSessions.values where !session.isDeleted {
            repository.syncAutomaticAttendance(for: session)
        }
        let weights = fetchAll(BodyWeightModel.self)
        let photos = fetchAll(PhotoCheckInModel.self)
        let weightIDs = Set(weights.map(\.id)), photoIDs = Set(photos.map(\.id))
        for p in photos where p.bodyWeightID.map({ !weightIDs.contains($0) }) ?? false { p.bodyWeightID = nil }
        for w in weights where w.photoCheckInID.map({ !photoIDs.contains($0) }) ?? false { w.photoCheckInID = nil }
    }
}
