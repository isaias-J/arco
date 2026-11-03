import Foundation
import SwiftData

/// Esquema v1: el publicado en la primera entrega (13 modelos). No se debe modificar: si un
/// modelo existente cambia en el futuro, su forma anterior se congela aquí como tipo anidado.
public enum ArcoSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [
            UserProfileModel.self, AppSettingsModel.self, ExerciseModel.self,
            WorkoutSessionModel.self, SessionExerciseModel.self, SetRecordModel.self,
            BodyWeightModel.self, HeightModel.self, BodyMeasurementModel.self,
            PhotoCheckInModel.self, AttendanceEventModel.self, ReminderRuleModel.self,
            RoutineTemplateModel.self
        ]
    }
}

/// Esquema v2: añade preferencias por ejercicio, resoluciones de asistencia, excepciones de
/// avisos y objetivos semanales. Cambio aditivo: migración ligera sin pérdida de datos.
public enum ArcoSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] {
        ArcoSchemaV1.models + [
            ExerciseSettingsModel.self, AttendanceResolutionModel.self,
            ReminderOverrideModel.self, WeeklyGoalModel.self
        ]
    }
}

/// Plan de migración explícito (spec §4: migraciones explícitas; nunca recrear la base).
public enum ArcoMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [ArcoSchemaV1.self, ArcoSchemaV2.self] }
    public static var stages: [MigrationStage] {
        [.lightweight(fromVersion: ArcoSchemaV1.self, toVersion: ArcoSchemaV2.self)]
    }
}
