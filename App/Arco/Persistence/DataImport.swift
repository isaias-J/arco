import Foundation
import SwiftData
import ArcoCore

/// Aplica un payload restaurado al almacén SwiftData (spec §19). No duplica por ID (T72):
/// si una entidad con el mismo ID ya existe, se omite. Importa de forma que un fallo no borra
/// los datos actuales (T70, T73): primero decodifica todo; solo entonces inserta.
@MainActor
struct DataImport {
    let context: ModelContext

    func apply(payload data: Data) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(DataExport.Payload.self, from: data)

        // IDs existentes para no duplicar (T72).
        let existingSessionIDs = Set(((try? context.fetch(FetchDescriptor<WorkoutSessionModel>())) ?? []).map(\.id))
        let existingWeightIDs = Set(((try? context.fetch(FetchDescriptor<BodyWeightModel>())) ?? []).map(\.id))
        let existingMeasurementIDs = Set(((try? context.fetch(FetchDescriptor<BodyMeasurementModel>())) ?? []).map(\.id))
        let existingAttendanceIDs = Set(((try? context.fetch(FetchDescriptor<AttendanceEventModel>())) ?? []).map(\.id))
        let existingHeightIDs = Set(((try? context.fetch(FetchDescriptor<HeightModel>())) ?? []).map(\.id))

        for s in payload.sessions where !existingSessionIDs.contains(s.id) {
            let session = WorkoutSessionModel(
                id: s.id, startedAt: s.startedAt, endedAt: s.endedAt, stateRaw: s.state,
                trainingDate: s.trainingDate, originTimeZoneID: s.timeZone, templateID: s.templateID
            )
            context.insert(session)
            for e in s.exercises.sorted(by: { $0.order < $1.order }) {
                let se = SessionExerciseModel(exerciseID: e.exerciseID, variantKey: e.variantKey, order: e.order)
                se.session = session
                session.exercises.append(se)
                context.insert(se)
                for set in e.sets {
                    let model = SetRecordModel(
                        id: set.id, loadAmount: set.loadAmount, loadUnitRaw: set.unit,
                        loadConventionRaw: set.convention, reps: set.reps, typeRaw: set.type,
                        stateRaw: set.state, sideRaw: set.side, rirKind: set.rirKind, rirValue: set.rirValue,
                        performedAt: set.performedAt, attributionMajor: set.attrMajor, attributionMinor: set.attrMinor
                    )
                    model.sessionExercise = se
                    se.sets.append(model)
                    context.insert(model)
                }
            }
        }

        for w in payload.bodyWeights where !existingWeightIDs.contains(w.id) {
            context.insert(BodyWeightModel(id: w.id, measurementDate: w.measurementDate, enteredAt: w.enteredAt, amount: w.amount, unitRaw: w.unit, isEstimated: w.isEstimated))
        }
        for h in payload.heights where !existingHeightIDs.contains(h.id) {
            context.insert(HeightModel(id: h.id, date: h.date, amount: h.amount, unitRaw: h.unit))
        }
        for m in payload.measurements where !existingMeasurementIDs.contains(m.id) {
            context.insert(BodyMeasurementModel(id: m.id, typeKey: m.typeKey, sideRaw: m.side, protocolNote: m.protocolNote, amount: m.amount, unitRaw: m.unit, date: m.date))
        }
        for a in payload.attendance where !existingAttendanceIDs.contains(a.id) {
            context.insert(AttendanceEventModel(id: a.id, trainingDate: a.trainingDate, sourceRaw: a.source, sessionID: a.sessionID, isPartial: a.isPartial))
        }

        try context.save()
    }
}
