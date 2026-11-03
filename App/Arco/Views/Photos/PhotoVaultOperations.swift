//
//  PhotoVaultOperations.swift
//  Arco
//
//  Reglas de vínculo foto-peso y de borrado de fotos (spec §16 "Peso y foto",
//  §17 "Local significa local"; T49, T50, T51, T67).
//
//  - Una revisión fotográfica (una o varias poses) comparte UN pesaje: todas sus
//    fotos apuntan al mismo `bodyWeightID` (T49).
//  - Vincular un peso existente no crea una medición nueva (T51).
//  - "Sin peso" es válido (T50).
//  - Borrar una foto elimina el archivo cifrado y sus derivados, el registro y
//    el vínculo desde el peso; el peso se conserva (T67).
//

import Foundation
import SwiftData
import ArcoCore

/// Validación del peso introducido en la revisión fotográfica.
enum PhotoWeightInput {
    enum Problem: Error, Equatable {
        case empty, notANumber, notPositive, implausible
        var message: String {
            switch self {
            case .empty: return "Escribe tu peso."
            case .notANumber: return "El peso debe ser un número, por ejemplo 72,5."
            case .notPositive: return "El peso debe ser mayor que 0."
            case .implausible: return "Ese peso no parece real. Revisa el valor y la unidad."
            }
        }
    }

    /// Límite superior de plausibilidad (en kg) para evitar errores de tecleo.
    static let maximumKilograms: Decimal = 600

    static func parse(_ text: String, unit: MassUnit, locale: Locale = .current) -> Result<Decimal, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let value = DecimalParser(locale: locale).parse(trimmed) else { return .failure(.notANumber) }
        guard value > 0, !value.isNaN else { return .failure(.notPositive) }
        guard value * unit.kilogramsPerUnit <= maximumKilograms else { return .failure(.implausible) }
        return .success(value)
    }
}

@MainActor
enum PhotoVaultOperations {

    // MARK: - Peso de una revisión

    /// Crea una medición nueva (solo cuando el usuario la introduce y confirma).
    @discardableResult
    static func createWeight(amount: Decimal, unit: MassUnit, isEstimated: Bool, now: Date = Date(), context: ModelContext) throws -> BodyWeightModel {
        let model = BodyWeightModel(measurementDate: now, enteredAt: now, amount: amount, unitRaw: unit.rawValue, isEstimated: isEstimated)
        context.insert(model)
        try context.save()
        return model
    }

    /// Aplica el peso elegido (o ninguno) a TODAS las fotos de la revisión.
    ///
    /// - Las fotos quedan con el mismo `bodyWeightID` (un pesaje, no varios).
    /// - Los pesos que apuntaban a una foto de la revisión y ya no son el elegido se desvinculan.
    /// - El peso elegido apunta a una foto de la revisión si aún no apuntaba a ninguna foto
    ///   existente (no se roba el vínculo de otra revisión; la relación vive en la foto).
    static func applyWeight(_ weightID: UUID?, toPhotos photoIDs: [UUID], context: ModelContext) throws {
        let photos = try fetchPhotos(photoIDs, context: context)
        for photo in photos { photo.bodyWeightID = weightID }

        let idSet = Set(photoIDs)
        let weights = try context.fetch(FetchDescriptor<BodyWeightModel>())
        for weight in weights where weight.id != weightID {
            if let linked = weight.photoCheckInID, idSet.contains(linked) {
                weight.photoCheckInID = nil
            }
        }

        if let weightID, let weight = weights.first(where: { $0.id == weightID }), let firstPhoto = photoIDs.first {
            let current = weight.photoCheckInID
            let pointsToExistingPhoto = try current.map { try photoExists($0, context: context) } ?? false
            if !pointsToExistingPhoto { weight.photoCheckInID = firstPhoto }
        }
        try context.save()
    }

    // MARK: - Borrado (T67)

    /// Borra la foto: archivo cifrado + derivados (.thumb/.preview/.tmp), caché en memoria,
    /// registro y vínculo desde el peso. El peso se conserva. Las copias exportadas no se tocan.
    static func deletePhoto(id: UUID, fileName: String, crypto: VaultCrypto, loader: VaultImageLoader?, context: ModelContext) async throws {
        // El borrado de archivos no necesita el main actor.
        try await Task.detached(priority: .userInitiated) {
            do {
                try crypto.deleteEncryptedFile(named: fileName)
            } catch VaultCryptoError.storageUnavailable {
                // Sin carpeta de la bóveda no queda nada que borrar en disco.
            }
        }.value
        await loader?.evict(fileName: fileName)

        let photos = try fetchPhotos([id], context: context)
        for photo in photos { context.delete(photo) }

        let weights = try context.fetch(FetchDescriptor<BodyWeightModel>(predicate: #Predicate { $0.photoCheckInID == id }))
        for weight in weights {
            // Si otra foto de la misma revisión comparte el peso, el vínculo pasa a ella.
            let weightID = weight.id
            let siblings = try context.fetch(FetchDescriptor<PhotoCheckInModel>(predicate: #Predicate { $0.bodyWeightID == weightID }))
            weight.photoCheckInID = siblings.first(where: { $0.id != id })?.id
        }
        try context.save()
    }

    // MARK: - Utilidades

    private static func fetchPhotos(_ ids: [UUID], context: ModelContext) throws -> [PhotoCheckInModel] {
        guard !ids.isEmpty else { return [] }
        let all = try context.fetch(FetchDescriptor<PhotoCheckInModel>())
        let set = Set(ids)
        return all.filter { set.contains($0.id) }
    }

    private static func photoExists(_ id: UUID, context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<PhotoCheckInModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetchCount(descriptor) > 0
    }
}

// MARK: - Texto de un peso

extension BodyWeightModel {
    /// "72,5 kg · medido" con el formato numérico del usuario.
    var photoLabel: String {
        let number = amount.formatted(.number.precision(.fractionLength(0...2)))
        let kind = isEstimated ? "estimado" : "medido"
        return "\(number) \(unitRaw) · \(kind)"
    }
}
