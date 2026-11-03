import Foundation
import SwiftData

// MARK: - Modelos SwiftData
//
// Estos @Model son la persistencia real de la app. Los value types de ArcoCore (SetRecord,
// Load, etc.) son el dominio puro y verificable; aquí se mapean a entidades persistentes.
// Datos derivados (conteos, récords) NO se persisten como única verdad: se recalculan.
//
// Viven en ArcoCore (no en el target de app) para poder probar la capa de persistencia y el
// repositorio con `swift test` sin lanzar la app en el simulador.

@Model
public final class UserProfileModel {
    public var id: UUID
    public var displayName: String?
    public var birthDate: Date?
    public var experience: String?       // autodeclarada
    public var goalDescription: String?
    public var gender: String?           // opcional; nunca requerido

    public init(id: UUID = UUID(), displayName: String? = nil, birthDate: Date? = nil, experience: String? = nil, goalDescription: String? = nil, gender: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.birthDate = birthDate
        self.experience = experience
        self.goalDescription = goalDescription
        self.gender = gender
    }
}

@Model
public final class AppSettingsModel {
    public var id: UUID
    public var languageCode: String
    public var massUnitRaw: String
    public var lengthUnitRaw: String
    public var themeRaw: String          // system | light | dark
    public var weekStartsMonday: Bool
    public var hapticsEnabled: Bool
    public var onboardingCompleted: Bool

    public init(id: UUID = UUID(), languageCode: String = "es", massUnitRaw: String = MassUnit.kilograms.rawValue, lengthUnitRaw: String = LengthUnit.centimeters.rawValue, themeRaw: String = "system", weekStartsMonday: Bool = true, hapticsEnabled: Bool = true, onboardingCompleted: Bool = false) {
        self.id = id
        self.languageCode = languageCode
        self.massUnitRaw = massUnitRaw
        self.lengthUnitRaw = lengthUnitRaw
        self.themeRaw = themeRaw
        self.weekStartsMonday = weekStartsMonday
        self.hapticsEnabled = hapticsEnabled
        self.onboardingCompleted = onboardingCompleted
    }

    public var massUnit: MassUnit { MassUnit(rawValue: massUnitRaw) ?? .kilograms }
    public var lengthUnit: LengthUnit { LengthUnit(rawValue: lengthUnitRaw) ?? .centimeters }
}

@Model
public final class ExerciseModel {
    // ID estable del catálogo. La unicidad se garantiza por la lógica de seed (que no inserta
    // si ya existe), en lugar de `@Attribute(.unique)`, que puede fallar con almacenamiento en
    // memoria en algunas versiones de SwiftData.
    public var id: String
    public var name: String
    public var aliasesJoined: String     // alias separados por "\n"
    public var loadTypeRaw: String
    public var patternRaw: String
    public var originRaw: String
    public var instructions: String
    public var archived: Bool

    public init(id: String, name: String, aliasesJoined: String = "", loadTypeRaw: String, patternRaw: String, originRaw: String, instructions: String, archived: Bool = false) {
        self.id = id
        self.name = name
        self.aliasesJoined = aliasesJoined
        self.loadTypeRaw = loadTypeRaw
        self.patternRaw = patternRaw
        self.originRaw = originRaw
        self.instructions = instructions
        self.archived = archived
    }
}

@Model
public final class WorkoutSessionModel {
    public var id: UUID
    public var startedAt: Date
    public var endedAt: Date?
    public var stateRaw: String          // active | finished | abandoned
    public var trainingDate: Date        // fecha civil asignada
    public var originTimeZoneID: String
    public var templateID: String?
    @Relationship(deleteRule: .cascade, inverse: \SessionExerciseModel.session)
    public var exercises: [SessionExerciseModel]

    public init(id: UUID = UUID(), startedAt: Date, endedAt: Date? = nil, stateRaw: String = "active", trainingDate: Date, originTimeZoneID: String, templateID: String? = nil, exercises: [SessionExerciseModel] = []) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.stateRaw = stateRaw
        self.trainingDate = trainingDate
        self.originTimeZoneID = originTimeZoneID
        self.templateID = templateID
        self.exercises = exercises
    }
}

@Model
public final class SessionExerciseModel {
    public var id: UUID
    public var exerciseID: String
    public var variantKey: String?
    public var order: Int
    public var session: WorkoutSessionModel?
    @Relationship(deleteRule: .cascade, inverse: \SetRecordModel.sessionExercise)
    public var sets: [SetRecordModel]

    public init(id: UUID = UUID(), exerciseID: String, variantKey: String? = nil, order: Int, sets: [SetRecordModel] = []) {
        self.id = id
        self.exerciseID = exerciseID
        self.variantKey = variantKey
        self.order = order
        self.sets = sets
    }
}

@Model
public final class SetRecordModel {
    public var id: UUID
    public var loadAmount: Decimal?      // nil = desconocido (NO 0)
    public var loadUnitRaw: String
    public var loadConventionRaw: String
    public var reps: Int?
    public var typeRaw: String
    public var stateRaw: String
    public var sideRaw: String
    public var rirKind: String           // exact | atLeast | unknown | none
    public var rirValue: Int?
    public var performedAt: Date
    public var attributionMajor: Int
    public var attributionMinor: Int
    public var sessionExercise: SessionExerciseModel?

    public init(id: UUID = UUID(), loadAmount: Decimal?, loadUnitRaw: String, loadConventionRaw: String, reps: Int?, typeRaw: String, stateRaw: String, sideRaw: String, rirKind: String = "none", rirValue: Int? = nil, performedAt: Date, attributionMajor: Int = 1, attributionMinor: Int = 0) {
        self.id = id
        self.loadAmount = loadAmount
        self.loadUnitRaw = loadUnitRaw
        self.loadConventionRaw = loadConventionRaw
        self.reps = reps
        self.typeRaw = typeRaw
        self.stateRaw = stateRaw
        self.sideRaw = sideRaw
        self.rirKind = rirKind
        self.rirValue = rirValue
        self.performedAt = performedAt
        self.attributionMajor = attributionMajor
        self.attributionMinor = attributionMinor
    }

    /// Mapea a value type de dominio para aplicar reglas puras de ArcoCore.
    public func toDomain() -> SetRecord {
        let unit = MassUnit(rawValue: loadUnitRaw) ?? .kilograms
        let conv = LoadConvention(rawValue: loadConventionRaw) ?? .externalTotal
        let rir: RIR?
        switch rirKind {
        case "exact": rir = .exact(rirValue ?? 0)
        case "atLeast": rir = .atLeast(rirValue ?? 0)
        case "unknown": rir = .unknown
        default: rir = nil
        }
        return SetRecord(
            id: id,
            load: Load(amount: loadAmount, unit: unit, convention: conv),
            reps: reps,
            type: SetType(rawValue: typeRaw) ?? .working,
            state: SetState(rawValue: stateRaw) ?? .completed,
            side: BodySide(rawValue: sideRaw) ?? .bilateral,
            rir: rir,
            performedAt: performedAt,
            attributionVersion: AttributionVersion(attributionMajor, attributionMinor)
        )
    }
}

@Model
public final class BodyWeightModel {
    public var id: UUID
    public var measurementDate: Date
    public var enteredAt: Date
    public var amount: Decimal
    public var unitRaw: String
    public var isEstimated: Bool
    public var photoCheckInID: UUID?

    public init(id: UUID = UUID(), measurementDate: Date, enteredAt: Date, amount: Decimal, unitRaw: String, isEstimated: Bool, photoCheckInID: UUID? = nil) {
        self.id = id
        self.measurementDate = measurementDate
        self.enteredAt = enteredAt
        self.amount = amount
        self.unitRaw = unitRaw
        self.isEstimated = isEstimated
        self.photoCheckInID = photoCheckInID
    }

    public func toDomain() -> BodyWeightEntry {
        BodyWeightEntry(id: id, measurementDate: measurementDate, enteredAt: enteredAt, amount: amount, unit: MassUnit(rawValue: unitRaw) ?? .kilograms, isEstimated: isEstimated)
    }
}

@Model
public final class HeightModel {
    public var id: UUID
    public var date: Date
    public var amount: Decimal
    public var unitRaw: String
    public init(id: UUID = UUID(), date: Date, amount: Decimal, unitRaw: String) {
        self.id = id; self.date = date; self.amount = amount; self.unitRaw = unitRaw
    }
}

@Model
public final class BodyMeasurementModel {
    public var id: UUID
    public var typeKey: String
    public var sideRaw: String
    public var protocolNote: String
    public var amount: Decimal
    public var unitRaw: String
    public var date: Date
    public init(id: UUID = UUID(), typeKey: String, sideRaw: String, protocolNote: String, amount: Decimal, unitRaw: String, date: Date) {
        self.id = id; self.typeKey = typeKey; self.sideRaw = sideRaw; self.protocolNote = protocolNote
        self.amount = amount; self.unitRaw = unitRaw; self.date = date
    }
}

@Model
public final class PhotoCheckInModel {
    public var id: UUID
    public var date: Date
    public var poseRaw: String
    public var encryptedFileName: String   // nombre del fichero cifrado en el contenedor privado
    public var orientationRaw: Int
    public var mirrored: Bool
    public var bodyWeightID: UUID?
    public init(id: UUID = UUID(), date: Date, poseRaw: String, encryptedFileName: String, orientationRaw: Int = 0, mirrored: Bool = false, bodyWeightID: UUID? = nil) {
        self.id = id; self.date = date; self.poseRaw = poseRaw; self.encryptedFileName = encryptedFileName
        self.orientationRaw = orientationRaw; self.mirrored = mirrored; self.bodyWeightID = bodyWeightID
    }
}

@Model
public final class AttendanceEventModel {
    public var id: UUID
    public var trainingDate: Date
    public var sourceRaw: String
    public var sessionID: UUID?
    public var isPartial: Bool
    public init(id: UUID = UUID(), trainingDate: Date, sourceRaw: String, sessionID: UUID? = nil, isPartial: Bool = false) {
        self.id = id; self.trainingDate = trainingDate; self.sourceRaw = sourceRaw
        self.sessionID = sessionID; self.isPartial = isPartial
    }
}

@Model
public final class ReminderRuleModel {
    public var id: UUID
    public var categoryRaw: String
    public var weekday: Int?          // convención Calendar 1=domingo … 7=sábado; nil = todos
    public var hour: Int
    public var minute: Int
    public var enabled: Bool
    public var timeZoneID: String
    public init(id: UUID = UUID(), categoryRaw: String, weekday: Int? = nil, hour: Int, minute: Int, enabled: Bool, timeZoneID: String) {
        self.id = id; self.categoryRaw = categoryRaw; self.weekday = weekday
        self.hour = hour; self.minute = minute; self.enabled = enabled; self.timeZoneID = timeZoneID
    }
}

@Model
public final class RoutineTemplateModel {
    public var id: String
    public var name: String
    public var weekday: Int           // convención Calendar: 1=domingo, 2=lunes … 7=sábado (ver Weekday)
    public var groupsJoined: String   // MuscleGroup rawValues separados por ","
    public var preferredExerciseIDsJoined: String
    public var isRestDay: Bool
    public init(id: String, name: String, weekday: Int, groupsJoined: String, preferredExerciseIDsJoined: String = "", isRestDay: Bool = false) {
        self.id = id; self.name = name; self.weekday = weekday; self.groupsJoined = groupsJoined
        self.preferredExerciseIDsJoined = preferredExerciseIDsJoined; self.isRestDay = isRestDay
    }
}

// MARK: - Modelos añadidos en el esquema v2 (aditivos: migración ligera desde v1)

/// Preferencias de registro por ejercicio (spec §5 EquipmentProfile, §7): convención de carga,
/// modo de lados, incremento disponible y peso de barra conocido. Valores desconocidos = nil.
@Model
public final class ExerciseSettingsModel {
    public var exerciseID: String
    public var conventionRaw: String?
    /// "bilateral" o "perSide".
    public var sideModeRaw: String
    public var incrementAmount: Decimal?
    public var barWeight: Decimal?
    public var unitRaw: String?
    /// Variante por defecto (agarre, máquina…). Cambiarla separa el historial comparable.
    public var defaultVariant: String?

    public init(exerciseID: String, conventionRaw: String? = nil, sideModeRaw: String = "bilateral", incrementAmount: Decimal? = nil, barWeight: Decimal? = nil, unitRaw: String? = nil, defaultVariant: String? = nil) {
        self.exerciseID = exerciseID
        self.conventionRaw = conventionRaw
        self.sideModeRaw = sideModeRaw
        self.incrementAmount = incrementAmount
        self.barWeight = barWeight
        self.unitRaw = unitRaw
        self.defaultVariant = defaultVariant
    }
}

/// Resolución de un día sin asistencia (spec §5 AttendanceResolution, §14): descanso puntual
/// confirmado o ausencia confirmada. `dayKey` es la fecha civil "yyyy-MM-dd".
@Model
public final class AttendanceResolutionModel {
    public var id: UUID
    public var dayKey: String
    /// "rest" o "absence".
    public var kindRaw: String
    public var createdAt: Date

    public init(id: UUID = UUID(), dayKey: String, kindRaw: String, createdAt: Date = Date()) {
        self.id = id
        self.dayKey = dayKey
        self.kindRaw = kindRaw
        self.createdAt = createdAt
    }
}

/// Excepción puntual de un aviso para una fecha (spec §15): "cambio solo hoy" del recordatorio
/// de entrenamiento o aplazamiento ("Voy más tarde") de la revisión de asistencia.
@Model
public final class ReminderOverrideModel {
    public var id: UUID
    public var categoryRaw: String
    public var dayKey: String
    public var hour: Int
    public var minute: Int
    public var enabled: Bool

    public init(id: UUID = UUID(), categoryRaw: String, dayKey: String, hour: Int, minute: Int, enabled: Bool) {
        self.id = id
        self.categoryRaw = categoryRaw
        self.dayKey = dayKey
        self.hour = hour
        self.minute = minute
        self.enabled = enabled
    }
}

/// Objetivo semanal de series elegido por el usuario (spec §5 WeeklyGoal, §10.5). Se guarda
/// con su método de conteo y vigencia; nunca se compara con otro método.
@Model
public final class WeeklyGoalModel {
    public var id: UUID
    public var muscleRaw: String
    /// "direct" o "fractional".
    public var methodRaw: String
    public var target: Decimal
    public var validFrom: Date
    public var validTo: Date?
    /// "owner" o "professional".
    public var sourceRaw: String

    public init(id: UUID = UUID(), muscleRaw: String, methodRaw: String, target: Decimal, validFrom: Date, validTo: Date? = nil, sourceRaw: String = "owner") {
        self.id = id
        self.muscleRaw = muscleRaw
        self.methodRaw = methodRaw
        self.target = target
        self.validFrom = validFrom
        self.validTo = validTo
        self.sourceRaw = sourceRaw
    }
}

// MARK: - Modelos añadidos en el esquema v3 (aditivos: migración ligera desde v2)

/// Regla de doble progresión elegida por el usuario para un ejercicio (spec §13). Desactivable.
@Model
public final class DoubleProgressionModel {
    public var exerciseID: String
    public var enabled: Bool
    public var repLower: Int
    public var repUpper: Int
    public var referenceSets: Int
    /// Incremento en la unidad `unitRaw`.
    public var increment: Decimal
    public var unitRaw: String
    /// RIR mínimo exigido en las series de referencia (nil = sin criterio de esfuerzo).
    public var minimumRIR: Int?

    public init(exerciseID: String, enabled: Bool = true, repLower: Int, repUpper: Int, referenceSets: Int, increment: Decimal, unitRaw: String, minimumRIR: Int? = nil) {
        self.exerciseID = exerciseID
        self.enabled = enabled
        self.repLower = repLower
        self.repUpper = repUpper
        self.referenceSets = referenceSets
        self.increment = increment
        self.unitRaw = unitRaw
        self.minimumRIR = minimumRIR
    }
}

/// Versión del plan semanal vigente desde una fecha (spec §14: "cambiar hoy los días de rutina
/// no altera el denominador de meses anteriores"). `daysJSON` codifica [WeeklyPlan.Day].
@Model
public final class PlanVersionModel {
    public var id: UUID
    public var validFrom: Date
    public var daysJSON: String

    public init(id: UUID = UUID(), validFrom: Date, daysJSON: String) {
        self.id = id
        self.validFrom = validFrom
        self.daysJSON = daysJSON
    }
}

/// Atribución muscular corregida por el usuario para un ejercicio (spec §10.4). Se muestra como
/// personalización, nunca como regla científica revisada.
@Model
public final class CustomAttributionModel {
    public var exerciseID: String
    public var muscleRaw: String
    /// "direct", "indirect" o "unknown".
    public var roleRaw: String

    public init(exerciseID: String, muscleRaw: String, roleRaw: String) {
        self.exerciseID = exerciseID
        self.muscleRaw = muscleRaw
        self.roleRaw = roleRaw
    }
}
