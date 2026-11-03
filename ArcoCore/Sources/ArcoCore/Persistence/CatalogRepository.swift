import Foundation
import SwiftData

/// Atribución efectiva de un ejercicio: la personalizada por el usuario si existe (marcada como
/// tal, spec §10.4), si no la del catálogo. Ejercicios personalizados sin regla: ninguna (sus
/// series no suman a ningún músculo; no se inventa crédito — T17).
public enum AttributionResolver {
    @MainActor
    public static func customRuleSets(_ context: ModelContext) -> [String: AttributionRuleSet] {
        let all = (try? context.fetch(FetchDescriptor<CustomAttributionModel>())) ?? []
        var grouped: [String: [MuscleAttribution]] = [:]
        for a in all {
            guard let muscle = Muscle(rawValue: a.muscleRaw), let role = AttributionRole(rawValue: a.roleRaw) else { continue }
            grouped[a.exerciseID, default: []].append(MuscleAttribution(muscle: muscle, role: role, support: .productInference, rationaleKey: "attr.userCustomized"))
        }
        var result: [String: AttributionRuleSet] = [:]
        for (id, attrs) in grouped {
            result[id] = AttributionRuleSet(exerciseID: id, version: ExerciseCatalog.attributionVersion, attributions: attrs, userCustomized: true)
        }
        return result
    }

    public static func ruleSet(for exerciseID: String, custom: [String: AttributionRuleSet]) -> AttributionRuleSet? {
        custom[exerciseID] ?? ExerciseCatalog.ruleSet(for: exerciseID)
    }

    /// Series elegibles atribuidas, con emparejamiento de lados y fecha (para conteos y sugerencias).
    @MainActor
    public static func attributedSets(_ sessions: [WorkoutSessionModel], custom: [String: AttributionRuleSet]) -> [AttributedSet] {
        sessions.flatMap { session in
            session.exercises.flatMap { se -> [AttributedSet] in
                guard let rules = ruleSet(for: se.exerciseID, custom: custom) else { return [] }
                return se.sets.compactMap { model in
                    let d = model.toDomain()
                    guard d.isEligibleForWorkCount else { return nil }
                    return AttributedSet(setID: d.id, exerciseID: se.exerciseID, side: d.side, ruleSet: rules, pairingKey: se.id.uuidString, performedAt: d.performedAt)
                }
            }
        }
    }
}

/// Gestión del catálogo y de la rutina (spec §3.2, §3.3, §6). Ningún cambio borra historial:
/// los registros apuntan al identificador estable del ejercicio.
@MainActor
public struct CatalogRepository {
    public let context: ModelContext
    public init(context: ModelContext) { self.context = context }

    public enum CatalogError: Error, Equatable {
        case emptyName
        case duplicateName
    }

    private func exercise(_ id: String) -> ExerciseModel? {
        let p = #Predicate<ExerciseModel> { $0.id == id }
        return (try? context.fetch(FetchDescriptor(predicate: p)))?.first
    }

    /// Renombra sin dividir la historia (mismo ID). Rechaza nombres vacíos o duplicados.
    public func rename(_ id: String, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw CatalogError.emptyName }
        let all = (try? context.fetch(FetchDescriptor<ExerciseModel>())) ?? []
        if all.contains(where: { $0.id != id && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            throw CatalogError.duplicateName
        }
        exercise(id)?.name = trimmed
        try context.save()
    }

    /// Archiva o recupera. Archivar oculta el ejercicio en las selecciones; no borra registros.
    public func setArchived(_ id: String, _ archived: Bool) throws {
        exercise(id)?.archived = archived
        try context.save()
    }

    /// Alias: lista sin vacíos ni duplicados, conservando tildes.
    public func setAliases(_ id: String, _ aliases: [String]) throws {
        var seen = Set<String>()
        let cleaned = aliases
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        exercise(id)?.aliasesJoined = cleaned.joined(separator: "\n")
        try context.save()
    }

    /// Sustituye la atribución personalizada de un ejercicio. Lista vacía = volver a la del
    /// catálogo (o a ninguna si es personalizado).
    public func setCustomAttribution(_ id: String, _ roles: [Muscle: AttributionRole]) throws {
        let p = #Predicate<CustomAttributionModel> { $0.exerciseID == id }
        for old in (try? context.fetch(FetchDescriptor(predicate: p))) ?? [] { context.delete(old) }
        for (muscle, role) in roles where role != .notCounted {
            context.insert(CustomAttributionModel(exerciseID: id, muscleRaw: muscle.rawValue, roleRaw: role.rawValue))
        }
        try context.save()
    }

    // MARK: - Rutina con historial (spec §14, T39)

    public func planHistory() -> PlanHistory {
        let versions = ((try? context.fetch(FetchDescriptor<PlanVersionModel>())) ?? []).compactMap { v -> PlanHistory.Version? in
            guard let plan = PlanHistory.decode(v.daysJSON) else { return nil }
            return .init(validFrom: v.validFrom, plan: plan)
        }
        return PlanHistory(versions: versions)
    }

    /// Crea la versión inicial del plan a partir de las plantillas si aún no hay historial.
    /// Vigente desde siempre: el plan sembrado es el que regía hasta el primer cambio.
    public func ensureInitialPlanVersion() {
        let count = (try? context.fetchCount(FetchDescriptor<PlanVersionModel>())) ?? 0
        guard count == 0 else { return }
        let templates = (try? context.fetch(FetchDescriptor<RoutineTemplateModel>())) ?? []
        guard !templates.isEmpty else { return }
        context.insert(PlanVersionModel(validFrom: .distantPast, daysJSON: PlanHistory.encode(WeeklyPlan(templates: templates))))
        try? context.save()
    }

    /// Cambia la rutina a partir de `effectiveDay` (normalmente hoy). Las fechas anteriores
    /// siguen evaluándose con la versión previa.
    public func updatePlan(_ plan: WeeklyPlan, effective day: Date, calendar: Calendar) throws {
        ensureInitialPlanVersion()
        let start = calendar.startOfDay(for: day)
        let templates = (try? context.fetch(FetchDescriptor<RoutineTemplateModel>())) ?? []
        for d in plan.days {
            let groups = d.groups.map(\.rawValue).joined(separator: ",")
            if let t = templates.first(where: { $0.weekday == d.weekday.rawValue }) {
                t.isRestDay = d.isRest
                t.groupsJoined = groups
                t.name = d.isRest ? "\(d.weekday.displayName) · Descanso" : "\(d.weekday.displayName) · \(d.groups.map(\.displayName).joined(separator: ", "))"
            } else {
                context.insert(RoutineTemplateModel(id: "day_\(d.weekday.rawValue)", name: d.weekday.displayName, weekday: d.weekday.rawValue, groupsJoined: groups, isRestDay: d.isRest))
            }
        }
        // Un cambio el mismo día sustituye la versión de ese día en lugar de apilar otra.
        let p = #Predicate<PlanVersionModel> { $0.validFrom == start }
        for same in (try? context.fetch(FetchDescriptor(predicate: p))) ?? [] { context.delete(same) }
        context.insert(PlanVersionModel(validFrom: start, daysJSON: PlanHistory.encode(plan)))
        try context.save()
    }

    // MARK: - Preferencias de carga por ejercicio (spec §7)

    public func setIncrement(_ id: String, amount: Decimal?, unit: MassUnit, barWeight: Decimal?) throws {
        let repo = WorkoutRepository(context: context)
        let s = repo.settingsOrCreate(for: id)
        s.incrementAmount = amount.flatMap { $0 > 0 ? $0 : nil }
        s.barWeight = barWeight.flatMap { $0 > 0 ? $0 : nil }
        s.unitRaw = unit.rawValue
        try context.save()
    }

    // MARK: - Doble progresión (spec §13)

    public func progressionRule(_ id: String) -> DoubleProgressionModel? {
        let p = #Predicate<DoubleProgressionModel> { $0.exerciseID == id }
        return (try? context.fetch(FetchDescriptor(predicate: p)))?.first
    }

    public func setProgressionRule(_ id: String, enabled: Bool, lower: Int, upper: Int, referenceSets: Int, increment: Decimal, unit: MassUnit, minimumRIR: Int?) throws {
        guard lower > 0, upper >= lower, referenceSets > 0, increment > 0 else { throw CatalogError.emptyName }
        let rule = progressionRule(id) ?? {
            let m = DoubleProgressionModel(exerciseID: id, repLower: lower, repUpper: upper, referenceSets: referenceSets, increment: increment, unitRaw: unit.rawValue)
            context.insert(m)
            return m
        }()
        rule.enabled = enabled
        rule.repLower = lower
        rule.repUpper = upper
        rule.referenceSets = referenceSets
        rule.increment = increment
        rule.unitRaw = unit.rawValue
        rule.minimumRIR = minimumRIR
        try context.save()
    }

    /// Evalúa la regla con la última sesión comparable (misma variante y convención).
    public func evaluateProgression(_ id: String, variantKey: String?, excluding session: WorkoutSessionModel?) -> DoubleProgression.Evaluation {
        guard let rule = progressionRule(id) else { return .disabled }
        let config = DoubleProgressionConfig(
            enabled: rule.enabled, repRangeLower: rule.repLower, repRangeUpper: rule.repUpper,
            referenceSets: rule.referenceSets,
            incrementKilograms: rule.increment * (MassUnit(rawValue: rule.unitRaw) ?? .kilograms).kilogramsPerUnit
        )
        guard let previous = WorkoutRepository(context: context).previousComparable(exerciseID: id, variantKey: variantKey, excluding: session) else {
            return config.enabled ? .notEnoughSets(have: 0, need: rule.referenceSets) : .disabled
        }
        let sets = previous.sets.map { $0.toDomain() }.filter { $0.type == .working }
        return DoubleProgression.evaluate(config: config, minimumRIR: rule.minimumRIR, workingSets: sets)
    }
}
