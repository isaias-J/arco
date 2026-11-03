import Foundation
import SwiftData

/// Modo de registro de lados para un ejercicio (spec §7, unilateralidad).
public enum SideMode: String, Sendable, CaseIterable {
    case bilateral
    case perSide
}

/// Resumen al finalizar una sesión (spec §8 "Finalización").
public struct SessionSummary: Sendable, Equatable {
    public let workingSets: Int
    public let warmupSets: Int
    public let exerciseIDs: [String]
    public let isPartial: Bool
    /// Ejercicios en los que se superó la mayor carga registrada antes de esta sesión.
    public let newLoadRecords: [String]
}

/// Repositorio de entrenamiento sobre SwiftData. Cada confirmación se persiste de inmediato
/// (spec §8). Los borradores de serie se guardan como filas `pending` con un ID estable creado
/// una sola vez: reintentar confirmar la misma fila nunca duplica (T02, T04) y los borradores
/// sobreviven al cierre de la app (T03).
@MainActor
public struct WorkoutRepository {
    public let context: ModelContext
    /// Operación de guardado inyectable: permite simular un fallo de escritura en pruebas (T04).
    private let saver: (ModelContext) throws -> Void
    private let now: () -> Date
    private let calendar: Calendar

    public init(
        context: ModelContext,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        saver: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.context = context
        self.calendar = calendar
        self.now = now
        self.saver = saver
    }

    // MARK: - Sesión activa (T03)

    /// Sesión activa más reciente, si existe (para reanudar tras cierre).
    public func activeSession() -> WorkoutSessionModel? {
        let predicate = #Predicate<WorkoutSessionModel> { $0.stateRaw == "active" }
        var descriptor = FetchDescriptor<WorkoutSessionModel>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Crea una sesión. No inicia otra si ya hay una activa (spec §8). Los ejercicios indicados
    /// se añaden con borradores precargados desde la sesión comparable anterior.
    @discardableResult
    public func startSession(
        trainingDate: Date,
        timeZone: TimeZone,
        templateID: String?,
        exerciseIDs: [String] = []
    ) -> WorkoutSessionModel {
        if let active = activeSession() { return active }
        let session = WorkoutSessionModel(
            startedAt: now(),
            trainingDate: calendar.startOfDay(for: trainingDate),
            originTimeZoneID: timeZone.identifier,
            templateID: templateID
        )
        context.insert(session)
        for id in exerciseIDs {
            _ = insertExercise(into: session, exerciseID: id, variantKey: defaultVariant(for: id))
        }
        try? saver(context)
        return session
    }

    /// Añade un ejercicio con borradores precargados.
    @discardableResult
    public func addExercise(to session: WorkoutSessionModel, exerciseID: String, variantKey: String?) -> SessionExerciseModel {
        let se = insertExercise(into: session, exerciseID: exerciseID, variantKey: variantKey)
        try? saver(context)
        return se
    }

    private func insertExercise(into session: WorkoutSessionModel, exerciseID: String, variantKey: String?) -> SessionExerciseModel {
        let order = (session.exercises.map(\.order).max() ?? -1) + 1
        let se = SessionExerciseModel(exerciseID: exerciseID, variantKey: variantKey, order: order)
        context.insert(se)
        se.session = session
        session.exercises.append(se)
        prefillDrafts(se, excluding: session)
        return se
    }

    /// Quita un ejercicio de la sesión. Si tiene series confirmadas no se borra: se conservan
    /// (spec §8: una sesión con trabajo real no pierde ese trabajo) y se devuelve `false`.
    @discardableResult
    public func removeExercise(_ se: SessionExerciseModel) -> Bool {
        guard !se.sets.contains(where: { $0.stateRaw == SetState.completed.rawValue }) else { return false }
        let session = se.session
        context.delete(se)
        try? saver(context)
        if let session { reconcileAutomaticAttendance(for: session) }
        return true
    }

    /// Sustituye un ejercicio de la sesión por otro (spec §3.3). Solo si aún no tiene series
    /// realizadas: el trabajo hecho nunca se reasigna a otro ejercicio. Devuelve `false` si no
    /// se pudo (en ese caso, añade el nuevo como ejercicio aparte).
    @discardableResult
    public func substitute(_ se: SessionExerciseModel, with exerciseID: String) -> Bool {
        guard !se.sets.contains(where: { $0.stateRaw == SetState.completed.rawValue }) else { return false }
        for d in se.sets { context.delete(d) }
        se.sets.removeAll()
        se.exerciseID = exerciseID
        se.variantKey = defaultVariant(for: exerciseID)
        if let session = se.session { prefillDrafts(se, excluding: session) }
        try? saver(context)
        return true
    }

    /// Mueve un ejercicio una posición arriba (-1) o abajo (+1).
    public func move(_ se: SessionExerciseModel, by offset: Int) {
        guard let session = se.session else { return }
        var ordered = session.exercises.sorted { $0.order < $1.order }
        guard let i = ordered.firstIndex(where: { $0.id == se.id }) else { return }
        let j = min(max(0, i + offset), ordered.count - 1)
        guard i != j else { return }
        ordered.swapAt(i, j)
        for (index, item) in ordered.enumerated() { item.order = index }
        try? saver(context)
    }

    /// Reordena ejercicios de la sesión.
    public func reorder(_ session: WorkoutSessionModel, orderedIDs: [UUID]) {
        for (index, id) in orderedIDs.enumerated() {
            session.exercises.first { $0.id == id }?.order = index
        }
        try? saver(context)
    }

    /// Cambia la variante del ejercicio en esta sesión (agarre, máquina…). El historial
    /// comparable se separa por variante (T25).
    public func setVariant(_ se: SessionExerciseModel, to variant: String?) {
        let trimmed = variant?.trimmingCharacters(in: .whitespacesAndNewlines)
        se.variantKey = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try? saver(context)
    }

    // MARK: - Preferencias por ejercicio (spec §7)

    public func settings(for exerciseID: String) -> ExerciseSettingsModel? {
        let predicate = #Predicate<ExerciseSettingsModel> { $0.exerciseID == exerciseID }
        return (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first
    }

    @discardableResult
    public func settingsOrCreate(for exerciseID: String) -> ExerciseSettingsModel {
        if let s = settings(for: exerciseID) { return s }
        let s = ExerciseSettingsModel(exerciseID: exerciseID)
        context.insert(s)
        return s
    }

    /// Convención de carga vigente: la elegida o la predeterminada por el equipo.
    public func convention(for exerciseID: String) -> LoadConvention {
        if let raw = settings(for: exerciseID)?.conventionRaw, let c = LoadConvention(rawValue: raw) { return c }
        let loadType = ExerciseCatalog.definition(exerciseID)?.defaultLoadType
            ?? exerciseModel(exerciseID).flatMap { LoadType(rawValue: $0.loadTypeRaw) }
            ?? .mixed
        return LoadConvention.defaultFor(loadType)
    }

    public func sideMode(for exerciseID: String) -> SideMode {
        SideMode(rawValue: settings(for: exerciseID)?.sideModeRaw ?? "") ?? .bilateral
    }

    public func setConvention(_ convention: LoadConvention, for exerciseID: String) {
        settingsOrCreate(for: exerciseID).conventionRaw = convention.rawValue
        try? saver(context)
    }

    /// Cambia el modo de lados. Los borradores pendientes se regeneran; las series
    /// confirmadas conservan el lado con el que se registraron.
    public func setSideMode(_ mode: SideMode, for se: SessionExerciseModel) {
        settingsOrCreate(for: se.exerciseID).sideModeRaw = mode.rawValue
        for draft in se.sets where draft.stateRaw == SetState.pending.rawValue {
            context.delete(draft)
        }
        se.sets.removeAll { $0.stateRaw == SetState.pending.rawValue }
        appendEmptyDrafts(se)
        try? saver(context)
    }

    private func defaultVariant(for exerciseID: String) -> String? {
        settings(for: exerciseID)?.defaultVariant
    }

    private func exerciseModel(_ id: String) -> ExerciseModel? {
        let predicate = #Predicate<ExerciseModel> { $0.id == id }
        return (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first
    }

    // MARK: - Sesión comparable anterior (spec §8)

    /// Series confirmadas de la última sesión comparable: mismo ejercicio, misma variante y
    /// misma convención de carga (T25), anterior a `session`.
    public func previousComparable(
        exerciseID: String,
        variantKey: String?,
        excluding session: WorkoutSessionModel?
    ) -> (date: Date, sets: [SetRecordModel])? {
        let convention = convention(for: exerciseID).rawValue
        let predicate = #Predicate<SessionExerciseModel> { $0.exerciseID == exerciseID }
        let candidates = (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? []
        let excludedID = session?.id
        let sorted = candidates
            .filter { $0.session != nil && $0.session?.id != excludedID && $0.variantKey == variantKey }
            .sorted { ($0.session?.startedAt ?? .distantPast) > ($1.session?.startedAt ?? .distantPast) }
        for se in sorted {
            let done = se.sets
                .filter { $0.stateRaw == SetState.completed.rawValue && $0.loadConventionRaw == convention }
                .sorted { $0.performedAt < $1.performedAt }
            if !done.isEmpty, let date = se.session?.trainingDate {
                return (date, done)
            }
        }
        return nil
    }

    /// Precarga borradores copiando carga, repeticiones, tipo y lado de la sesión comparable
    /// anterior (sin RIR: el esfuerzo no se copia). Sin historial: una fila vacía (o un par
    /// izquierda/derecha). Los borradores NO son series realizadas (T01).
    private func prefillDrafts(_ se: SessionExerciseModel, excluding session: WorkoutSessionModel) {
        guard se.sets.isEmpty else { return }
        let convention = convention(for: se.exerciseID)
        if let previous = previousComparable(exerciseID: se.exerciseID, variantKey: se.variantKey, excluding: session) {
            let base = now()
            for (index, old) in previous.sets.enumerated() {
                insertDraft(
                    into: se,
                    load: Load(amount: old.loadAmount, unit: MassUnit(rawValue: old.loadUnitRaw) ?? .kilograms, convention: convention),
                    reps: old.reps,
                    type: SetType(rawValue: old.typeRaw) ?? .working,
                    side: BodySide(rawValue: old.sideRaw) ?? .bilateral,
                    at: base.addingTimeInterval(Double(index) / 1000)
                )
            }
        } else {
            appendEmptyDrafts(se)
        }
    }

    private func appendEmptyDrafts(_ se: SessionExerciseModel) {
        let convention = convention(for: se.exerciseID)
        let unit = MassUnit(rawValue: settings(for: se.exerciseID)?.unitRaw ?? "") ?? .kilograms
        let load = Load(amount: nil, unit: unit, convention: convention)
        let base = now()
        switch sideMode(for: se.exerciseID) {
        case .bilateral:
            insertDraft(into: se, load: load, reps: nil, type: .working, side: .bilateral, at: base)
        case .perSide:
            insertDraft(into: se, load: load, reps: nil, type: .working, side: .left, at: base)
            insertDraft(into: se, load: load, reps: nil, type: .working, side: .right, at: base.addingTimeInterval(0.001))
        }
    }

    @discardableResult
    private func insertDraft(into se: SessionExerciseModel, load: Load, reps: Int?, type: SetType, side: BodySide, at date: Date) -> SetRecordModel {
        let model = SetRecordModel(
            id: UUID(),
            loadAmount: load.amount,
            loadUnitRaw: load.unit.rawValue,
            loadConventionRaw: load.convention.rawValue,
            reps: reps,
            typeRaw: type.rawValue,
            stateRaw: SetState.pending.rawValue,
            sideRaw: side.rawValue,
            performedAt: date,
            attributionMajor: ExerciseCatalog.attributionVersion.major,
            attributionMinor: ExerciseCatalog.attributionVersion.minor
        )
        context.insert(model)
        model.sessionExercise = se
        se.sets.append(model)
        return model
    }

    // MARK: - Borradores (spec §8)

    /// Añade una fila (o un par por lados) duplicando los valores de la última fila.
    @discardableResult
    public func addDraft(to se: SessionExerciseModel) -> [SetRecordModel] {
        let ordered = orderedSets(se).filter { $0.stateRaw != SetState.deleted.rawValue }
        let mode = sideMode(for: se.exerciseID)
        let convention = convention(for: se.exerciseID)
        let template = ordered.last
        let load = Load(
            amount: template?.loadAmount,
            unit: MassUnit(rawValue: template?.loadUnitRaw ?? "") ?? .kilograms,
            convention: convention
        )
        let type = SetType(rawValue: template?.typeRaw ?? "") ?? .working
        let reps = template?.reps
        let base = max(now(), (ordered.last?.performedAt ?? .distantPast).addingTimeInterval(0.001))
        var created: [SetRecordModel] = []
        switch mode {
        case .bilateral:
            created.append(insertDraft(into: se, load: load, reps: reps, type: type, side: .bilateral, at: base))
        case .perSide:
            created.append(insertDraft(into: se, load: load, reps: reps, type: type, side: .left, at: base))
            created.append(insertDraft(into: se, load: load, reps: reps, type: type, side: .right, at: base.addingTimeInterval(0.001)))
        }
        try? saver(context)
        return created
    }

    /// Guarda los valores editados de un borrador (sin confirmarlo).
    public func updateDraft(_ model: SetRecordModel, amount: Decimal?, unit: MassUnit, reps: Int?, type: SetType, side: BodySide, rir: RIR?) {
        model.loadAmount = amount
        model.loadUnitRaw = unit.rawValue
        model.reps = reps
        model.typeRaw = type.rawValue
        model.sideRaw = side.rawValue
        let (kind, value) = Self.encodeRIR(rir)
        model.rirKind = kind
        model.rirValue = value
        try? saver(context)
    }

    /// Confirma un borrador con un toque. Idempotente: confirmar dos veces la misma fila no
    /// crea otra (T02). Si el guardado falla, la fila vuelve a borrador con sus valores y se
    /// lanza el error para que la interfaz indique el fallo real (T04).
    public func confirm(_ model: SetRecordModel) throws {
        guard model.stateRaw != SetState.completed.rawValue else { return }
        let domain = model.toDomain()
        let check = SetRecord(id: domain.id, load: domain.load, reps: domain.reps, type: domain.type, state: .completed, side: domain.side, rir: domain.rir, performedAt: now())
        let errors = check.validationErrors()
        guard errors.isEmpty else { throw RepositoryError.invalidSet(errors) }

        let previousDate = model.performedAt
        model.stateRaw = SetState.completed.rawValue
        model.performedAt = now()
        do {
            try saver(context)
        } catch {
            model.stateRaw = SetState.pending.rawValue
            model.performedAt = previousDate
            throw RepositoryError.saveFailed
        }
        if let session = model.sessionExercise?.session {
            createAutomaticAttendanceIfNeeded(for: session)
        }
    }

    /// Deshace una confirmación recién hecha: la serie vuelve a ser borrador con sus valores.
    public func unconfirm(_ model: SetRecordModel) {
        guard model.stateRaw == SetState.completed.rawValue else { return }
        model.stateRaw = SetState.pending.rawValue
        try? saver(context)
        if let session = model.sessionExercise?.session {
            reconcileAutomaticAttendance(for: session)
        }
    }

    /// Edita una serie ya confirmada (corrección). Conserva su hora real.
    public func edit(_ model: SetRecordModel, amount: Decimal?, unit: MassUnit, convention: LoadConvention, reps: Int?, type: SetType, side: BodySide, rir: RIR?) throws {
        let candidate = SetRecord(
            id: model.id,
            load: Load(amount: amount, unit: unit, convention: convention),
            reps: reps, type: type, state: .completed, side: side, rir: rir,
            performedAt: model.performedAt
        )
        let errors = candidate.validationErrors()
        guard errors.isEmpty else { throw RepositoryError.invalidSet(errors) }
        model.loadAmount = amount
        model.loadUnitRaw = unit.rawValue
        model.loadConventionRaw = convention.rawValue
        model.reps = reps
        model.typeRaw = type.rawValue
        model.sideRaw = side.rawValue
        let (kind, value) = Self.encodeRIR(rir)
        model.rirKind = kind
        model.rirValue = value
        do { try saver(context) } catch { context.rollback(); throw RepositoryError.saveFailed }
        if let session = model.sessionExercise?.session {
            createAutomaticAttendanceIfNeeded(for: session)
            reconcileAutomaticAttendance(for: session)
        }
    }

    /// Elimina una serie (borrado lógico, deshacible). Los gráficos y récords se recalculan
    /// desde los registros (T05, T29). Devuelve el estado anterior para `undoDelete`.
    @discardableResult
    public func delete(_ model: SetRecordModel) -> SetState {
        let previous = SetState(rawValue: model.stateRaw) ?? .completed
        if previous == .pending {
            // Un borrador nunca fue una serie: se elimina sin dejar rastro.
            model.sessionExercise?.sets.removeAll { $0.id == model.id }
            context.delete(model)
        } else {
            model.stateRaw = SetState.deleted.rawValue
        }
        try? saver(context)
        if let session = model.sessionExercise?.session {
            reconcileAutomaticAttendance(for: session)
        }
        return previous
    }

    /// Deshace un borrado lógico.
    public func undoDelete(_ model: SetRecordModel, previous: SetState) {
        guard model.stateRaw == SetState.deleted.rawValue else { return }
        model.stateRaw = previous.rawValue
        try? saver(context)
        if let session = model.sessionExercise?.session {
            createAutomaticAttendanceIfNeeded(for: session)
        }
    }

    /// Omite un borrador (no realizado): no cuenta en ningún cálculo.
    public func skip(_ model: SetRecordModel) {
        guard model.stateRaw == SetState.pending.rawValue else { return }
        model.stateRaw = SetState.skipped.rawValue
        try? saver(context)
    }

    // MARK: - Finalizar (spec §8)

    /// Finaliza la sesión. Los borradores sin confirmar se descartan (no se inventan series).
    /// Si quedaron borradores pendientes, la sesión se marca parcial (T36).
    @discardableResult
    public func finish(_ session: WorkoutSessionModel) -> SessionSummary {
        let historyBefore = loadRecordsBefore(session)
        var hadPending = false
        for se in session.exercises {
            for draft in se.sets where draft.stateRaw == SetState.pending.rawValue {
                hadPending = true
                context.delete(draft)
            }
            se.sets.removeAll { $0.stateRaw == SetState.pending.rawValue }
        }
        let completed = session.exercises.flatMap(\.sets).filter { $0.stateRaw == SetState.completed.rawValue }
        let working = completed.filter { $0.typeRaw == SetType.working.rawValue }
        session.stateRaw = hadPending ? "partial" : "finished"
        session.endedAt = now()

        // Actualizar la marca de parcialidad de la asistencia automática de esta sesión.
        let sid = session.id
        let predicate = #Predicate<AttendanceEventModel> { $0.sessionID == sid }
        for event in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            event.isPartial = hadPending
        }
        try? saver(context)

        var records: [String] = []
        for se in session.exercises.sorted(by: { $0.order < $1.order }) {
            let sets = se.sets.map { $0.toDomain() }
            guard let best = RecordsEngine.maxLoadRecord(from: sets)?.loadKilograms else { continue }
            let key = Self.comparableKey(se.exerciseID, se.variantKey, convention(for: se.exerciseID))
            if let before = historyBefore[key], best > before { records.append(se.exerciseID) }
        }
        return SessionSummary(
            workingSets: working.count,
            warmupSets: completed.count - working.count,
            exerciseIDs: session.exercises.sorted { $0.order < $1.order }
                .filter { $0.sets.contains { $0.stateRaw == SetState.completed.rawValue } }
                .map(\.exerciseID),
            isPartial: hadPending,
            newLoadRecords: records
        )
    }

    /// Mayor carga previa por ejercicio/variante/convención, para detectar récords reales.
    private func loadRecordsBefore(_ session: WorkoutSessionModel) -> [String: Decimal] {
        var result: [String: Decimal] = [:]
        let all = (try? context.fetch(FetchDescriptor<SessionExerciseModel>())) ?? []
        for se in all where se.session != nil && se.session?.id != session.id {
            let sets = se.sets.map { $0.toDomain() }
            guard let best = RecordsEngine.maxLoadRecord(from: sets)?.loadKilograms else { continue }
            for convention in Set(sets.map(\.load.convention)) {
                let key = Self.comparableKey(se.exerciseID, se.variantKey, convention)
                result[key] = max(result[key] ?? 0, best)
            }
        }
        return result
    }

    static func comparableKey(_ exerciseID: String, _ variant: String?, _ convention: LoadConvention) -> String {
        "\(exerciseID)|\(variant ?? "")|\(convention.rawValue)"
    }

    /// Guarda la selección de ejercicios de la sesión como favorita del día (spec §8).
    public func saveSelectionAsFavorite(_ session: WorkoutSessionModel) {
        guard let templateID = session.templateID else { return }
        let predicate = #Predicate<RoutineTemplateModel> { $0.id == templateID }
        guard let template = (try? context.fetch(FetchDescriptor(predicate: predicate)))?.first else { return }
        template.preferredExerciseIDsJoined = session.exercises
            .sorted { $0.order < $1.order }
            .map(\.exerciseID)
            .joined(separator: ",")
        try? saver(context)
    }

    // MARK: - API compatible: confirmar serie directa por ID (T02)

    /// Confirma (crea o actualiza) una serie identificada por `setID`. Reconfirmar el mismo ID
    /// NO duplica (T02).
    public func confirmSet(
        in sessionExercise: SessionExerciseModel,
        setID: UUID,
        load: Load,
        reps: Int?,
        type: SetType,
        side: BodySide,
        rir: RIR?
    ) throws {
        let domain = SetRecord(id: setID, load: load, reps: reps, type: type, state: .completed, side: side, rir: rir, performedAt: now())
        let errors = domain.validationErrors()
        guard errors.isEmpty else { throw RepositoryError.invalidSet(errors) }

        let model: SetRecordModel
        if let existing = sessionExercise.sets.first(where: { $0.id == setID }) {
            model = existing
        } else {
            model = insertDraft(into: sessionExercise, load: load, reps: reps, type: type, side: side, at: now())
            // Mantener el ID pedido por el llamador.
            model.id = setID
        }
        model.loadAmount = load.amount
        model.loadUnitRaw = load.unit.rawValue
        model.loadConventionRaw = load.convention.rawValue
        model.reps = reps
        model.typeRaw = type.rawValue
        model.sideRaw = side.rawValue
        let (kind, value) = Self.encodeRIR(rir)
        model.rirKind = kind
        model.rirValue = value
        model.stateRaw = SetState.completed.rawValue
        model.performedAt = now()
        do { try saver(context) } catch { context.rollback(); throw RepositoryError.saveFailed }
        if let session = sessionExercise.session {
            createAutomaticAttendanceIfNeeded(for: session)
        }
    }

    /// Compatibilidad: borrado lógico por ID.
    public func deleteSet(_ setID: UUID, in sessionExercise: SessionExerciseModel) {
        if let model = sessionExercise.sets.first(where: { $0.id == setID }) {
            delete(model)
        }
    }

    // MARK: - Asistencia automática (T34, T37)

    /// Deja la asistencia automática de la sesión coherente con sus series actuales: la crea si
    /// hay una serie de trabajo elegible y la retira si ya no la hay (usado al restaurar).
    public func syncAutomaticAttendance(for session: WorkoutSessionModel) {
        createAutomaticAttendanceIfNeeded(for: session)
        reconcileAutomaticAttendance(for: session)
        let sid = session.id
        let predicate = #Predicate<AttendanceEventModel> { $0.sessionID == sid && $0.sourceRaw == "automatic" }
        for event in (try? context.fetch(FetchDescriptor(predicate: predicate))) ?? [] {
            event.isPartial = session.stateRaw == "partial"
        }
    }

    private func createAutomaticAttendanceIfNeeded(for session: WorkoutSessionModel) {
        let sets = allDomainSets(in: session)
        guard AttendanceEngine.qualifiesForAutomaticAttendance(sessionSets: sets) else { return }
        let sid = session.id
        let predicate = #Predicate<AttendanceEventModel> { $0.sessionID == sid && $0.sourceRaw == "automatic" }
        let existing = (try? context.fetch(FetchDescriptor<AttendanceEventModel>(predicate: predicate)))?.first
        if existing == nil {
            let event = AttendanceEventModel(
                trainingDate: calendar.startOfDay(for: session.trainingDate),
                sourceRaw: AttendanceSource.automatic.rawValue,
                sessionID: session.id,
                isPartial: session.stateRaw == "partial"
            )
            context.insert(event)
            try? saver(context)
        }
    }

    /// Si la sesión ya no tiene series elegibles, se retira SOLO su evidencia automática; la
    /// confirmación manual independiente no se toca (T37).
    private func reconcileAutomaticAttendance(for session: WorkoutSessionModel) {
        let sets = allDomainSets(in: session)
        guard !AttendanceEngine.qualifiesForAutomaticAttendance(sessionSets: sets) else { return }
        let sid = session.id
        let predicate = #Predicate<AttendanceEventModel> { $0.sessionID == sid && $0.sourceRaw == "automatic" }
        for event in (try? context.fetch(FetchDescriptor<AttendanceEventModel>(predicate: predicate))) ?? [] {
            context.delete(event)
        }
        try? saver(context)
    }

    // MARK: - Lectura

    public func allDomainSets(in session: WorkoutSessionModel) -> [SetRecord] {
        session.exercises.flatMap { $0.sets.map { $0.toDomain() } }
    }

    /// Series de un ejercicio en orden de trabajo: primero las realizadas (por hora real de
    /// confirmación) y después los borradores pendientes en su orden de creación.
    public func orderedSets(_ se: SessionExerciseModel) -> [SetRecordModel] {
        Self.workOrder(se.sets)
    }

    public static func workOrder(_ sets: [SetRecordModel]) -> [SetRecordModel] {
        let pending = SetState.pending.rawValue
        return sets.sorted { a, b in
            let ap = a.stateRaw == pending, bp = b.stateRaw == pending
            if ap != bp { return !ap }
            return a.performedAt < b.performedAt
        }
    }

    static func encodeRIR(_ rir: RIR?) -> (String, Int?) {
        switch rir {
        case .exact(let v): return ("exact", v)
        case .atLeast(let v): return ("atLeast", v)
        case .unknown: return ("unknown", nil)
        case nil: return ("none", nil)
        }
    }
}

public enum RepositoryError: Error, Equatable {
    case invalidSet([SetValidationError])
    case saveFailed
}
