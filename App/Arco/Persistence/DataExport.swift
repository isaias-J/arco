import Foundation
import SwiftData
import ArcoCore

/// Serializa los datos de la app a un JSON versionado para el archivo cifrado (spec §19) y
/// genera el CSV de entrenamiento (T69, usando CSVExport de ArcoCore). No incluye secretos,
/// claves ni PIN. Las fotos NO se incluyen en la exportación de series.
@MainActor
struct DataExport {
    let context: ModelContext

    /// Estructura JSON versionada de la exportación completa (sin binarios de foto).
    struct Payload: Codable {
        var version: Int = 1
        var exportedAt: Date = Date()
        var profiles: [ProfileDTO]
        var settings: [SettingsDTO]
        var sessions: [SessionDTO]
        var bodyWeights: [BodyWeightDTO]
        var heights: [HeightDTO]
        var measurements: [MeasurementDTO]
        var attendance: [AttendanceDTO]
    }

    struct ProfileDTO: Codable { var id: UUID; var displayName: String?; var birthDate: Date?; var experience: String?; var goal: String?; var gender: String? }
    struct SettingsDTO: Codable { var massUnit: String; var lengthUnit: String; var theme: String; var weekStartsMonday: Bool }
    struct SetDTO: Codable { var id: UUID; var loadAmount: Decimal?; var unit: String; var convention: String; var reps: Int?; var type: String; var state: String; var side: String; var rirKind: String; var rirValue: Int?; var performedAt: Date; var attrMajor: Int; var attrMinor: Int }
    struct ExerciseDTO: Codable { var exerciseID: String; var variantKey: String?; var order: Int; var sets: [SetDTO] }
    struct SessionDTO: Codable { var id: UUID; var startedAt: Date; var endedAt: Date?; var state: String; var trainingDate: Date; var timeZone: String; var templateID: String?; var exercises: [ExerciseDTO] }
    struct BodyWeightDTO: Codable { var id: UUID; var measurementDate: Date; var enteredAt: Date; var amount: Decimal; var unit: String; var isEstimated: Bool }
    struct HeightDTO: Codable { var id: UUID; var date: Date; var amount: Decimal; var unit: String }
    struct MeasurementDTO: Codable { var id: UUID; var typeKey: String; var side: String; var protocolNote: String; var amount: Decimal; var unit: String; var date: Date }
    struct AttendanceDTO: Codable { var id: UUID; var trainingDate: Date; var source: String; var sessionID: UUID?; var isPartial: Bool }

    // MARK: - Recolección

    func buildPayload() -> Payload {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSessionModel>())) ?? []
        let weights = (try? context.fetch(FetchDescriptor<BodyWeightModel>())) ?? []
        let heights = (try? context.fetch(FetchDescriptor<HeightModel>())) ?? []
        let measurements = (try? context.fetch(FetchDescriptor<BodyMeasurementModel>())) ?? []
        let attendance = (try? context.fetch(FetchDescriptor<AttendanceEventModel>())) ?? []
        let profiles = (try? context.fetch(FetchDescriptor<UserProfileModel>())) ?? []
        let settings = (try? context.fetch(FetchDescriptor<AppSettingsModel>())) ?? []

        return Payload(
            profiles: profiles.map { ProfileDTO(id: $0.id, displayName: $0.displayName, birthDate: $0.birthDate, experience: $0.experience, goal: $0.goalDescription, gender: $0.gender) },
            settings: settings.map { SettingsDTO(massUnit: $0.massUnitRaw, lengthUnit: $0.lengthUnitRaw, theme: $0.themeRaw, weekStartsMonday: $0.weekStartsMonday) },
            sessions: sessions.map { s in
                SessionDTO(
                    id: s.id, startedAt: s.startedAt, endedAt: s.endedAt, state: s.stateRaw,
                    trainingDate: s.trainingDate, timeZone: s.originTimeZoneID, templateID: s.templateID,
                    exercises: s.exercises.sorted { $0.order < $1.order }.map { e in
                        ExerciseDTO(exerciseID: e.exerciseID, variantKey: e.variantKey, order: e.order, sets: e.sets.map { set in
                            SetDTO(id: set.id, loadAmount: set.loadAmount, unit: set.loadUnitRaw, convention: set.loadConventionRaw, reps: set.reps, type: set.typeRaw, state: set.stateRaw, side: set.sideRaw, rirKind: set.rirKind, rirValue: set.rirValue, performedAt: set.performedAt, attrMajor: set.attributionMajor, attrMinor: set.attributionMinor)
                        })
                    }
                )
            },
            bodyWeights: weights.map { BodyWeightDTO(id: $0.id, measurementDate: $0.measurementDate, enteredAt: $0.enteredAt, amount: $0.amount, unit: $0.unitRaw, isEstimated: $0.isEstimated) },
            heights: heights.map { HeightDTO(id: $0.id, date: $0.date, amount: $0.amount, unit: $0.unitRaw) },
            measurements: measurements.map { MeasurementDTO(id: $0.id, typeKey: $0.typeKey, side: $0.sideRaw, protocolNote: $0.protocolNote, amount: $0.amount, unit: $0.unitRaw, date: $0.date) },
            attendance: attendance.map { AttendanceDTO(id: $0.id, trainingDate: $0.trainingDate, source: $0.sourceRaw, sessionID: $0.sessionID, isPartial: $0.isPartial) }
        )
    }

    /// JSON serializado del payload.
    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(buildPayload())
    }

    /// Conteos informativos para el manifiesto del archivo cifrado.
    func counts() -> [String: Int] {
        let p = buildPayload()
        return [
            "sessions": p.sessions.count,
            "bodyWeights": p.bodyWeights.count,
            "measurements": p.measurements.count,
            "attendance": p.attendance.count
        ]
    }

    // MARK: - CSV de entrenamiento (T69)

    /// Genera el CSV de series usando CSVExport de ArcoCore (escapado seguro de fórmulas, BOM).
    func workoutCSV() -> Data {
        let sessions = (try? context.fetch(FetchDescriptor<WorkoutSessionModel>())) ?? []
        var rows: [CSVExport.Row] = []
        for s in sessions {
            for e in s.exercises.sorted(by: { $0.order < $1.order }) {
                for set in e.sets {
                    let d = set.toDomain()
                    rows.append(CSVExport.Row(
                        setID: set.id.uuidString,
                        sessionID: s.id.uuidString,
                        trainingDate: ISO8601DateFormatter().string(from: s.trainingDate),
                        timeZone: s.originTimeZoneID,
                        exercise: ExerciseNames.localized(e.exerciseID),
                        variant: e.variantKey ?? "",
                        equipment: "",
                        type: set.typeRaw,
                        state: set.stateRaw,
                        load: d.load.amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? "",
                        unit: set.loadUnitRaw,
                        reps: set.reps.map(String.init) ?? "",
                        side: set.sideRaw,
                        rir: rirText(kind: set.rirKind, value: set.rirValue)
                    ))
                }
            }
        }
        return CSVExport.data(rows: rows)
    }

    private func rirText(kind: String, value: Int?) -> String {
        switch kind {
        case "exact": return value.map(String.init) ?? ""
        case "atLeast": return value.map { "\($0)+" } ?? ""
        case "unknown": return "?"
        default: return ""
        }
    }
}
