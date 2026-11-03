//
//  VaultImageLoader.swift
//  Arco
//
//  Carga perezosa, descifrado y caché acotada de imágenes de la bóveda
//  (spec §16 "Decodificar progresivamente para no cargar toda la galería a
//  memoria", T68).
//
//  CONCURRENCIA (skill swift-concurrency)
//  --------------------------------------
//  - `VaultImageLoader` es un `actor`: serializa el acceso a la caché y evita
//    carreras de datos sin locks ad-hoc. El descifrado y la decodificación
//    ocurren FUERA del main actor; la vista hace hop al main actor solo para
//    mostrar la imagen ya lista.
//  - La caché está ACOTADA (recuento máximo) para no retener años de imágenes
//    en memoria (T68). Al superar el límite se descartan las entradas más
//    antiguas (política aproximada FIFO sobre orden de inserción).
//

import Foundation
import UIKit
import ImageIO

/// Caché de imágenes de la bóveda, segura entre tareas.
///
/// Guarda tanto miniaturas (para la cuadrícula) como imágenes a tamaño de
/// pantalla (para comparación/secuencia), diferenciadas por clave. El tamaño
/// máximo de píxel se pasa en cada petición y se decodifica con downsampling de
/// ImageIO para no inflar memoria (skill de rendimiento de imágenes).
actor VaultImageLoader {

    /// Dependencia de cifrado. `VaultCrypto` es Sendable y nonisolated, así que
    /// puede usarse con seguridad desde el aislamiento del actor.
    private let crypto: VaultCrypto

    /// Caché acotada: clave -> imagen. El orden de inserción se mantiene aparte
    /// para poder expulsar las más antiguas al superar el límite.
    private var cache: [String: UIImage] = [:]
    private var insertionOrder: [String] = []

    /// Número máximo de imágenes retenidas simultáneamente (acotación de
    /// memoria, T68). Valor conservador para galerías de años.
    private let maxEntries: Int

    init(crypto: VaultCrypto = VaultCrypto(), maxEntries: Int = 40) {
        self.crypto = crypto
        self.maxEntries = max(1, maxEntries)
    }

    /// Devuelve una imagen de la bóveda, descifrándola y haciendo downsampling
    /// al tamaño máximo pedido. Usa caché si está disponible.
    ///
    /// - Parameters:
    ///   - fileName: nombre del archivo cifrado en el contenedor privado.
    ///   - maxPixel: lado máximo en píxeles del resultado decodificado.
    /// - Returns: la imagen lista, o nil si no se pudo descifrar/decodificar.
    func image(fileName: String, maxPixel: CGFloat) -> UIImage? {
        let key = "\(fileName)#\(Int(maxPixel))"
        if let cached = cache[key] {
            return cached
        }

        guard let data = try? crypto.readEncryptedFile(named: fileName) else {
            return nil
        }
        guard let image = Self.downsample(data: data, maxPixel: maxPixel) else {
            return nil
        }

        store(image, forKey: key)
        return image
    }

    /// Descarta toda la caché (p. ej. al bloquear la bóveda) para no retener
    /// imágenes descifradas en memoria más de lo necesario.
    func purge() {
        cache.removeAll(keepingCapacity: false)
        insertionOrder.removeAll(keepingCapacity: false)
    }

    /// Expulsa todas las variantes (tamaños) en caché de un archivo concreto, p. ej. al
    /// borrar la foto (T67): no debe quedar ninguna copia descifrada en memoria.
    func evict(fileName: String) {
        let prefix = "\(fileName)#"
        let keys = insertionOrder.filter { $0.hasPrefix(prefix) }
        for key in keys { cache[key] = nil }
        insertionOrder.removeAll { $0.hasPrefix(prefix) }
    }

    // MARK: - Interno

    private func store(_ image: UIImage, forKey key: String) {
        if cache[key] == nil {
            insertionOrder.append(key)
        }
        cache[key] = image

        // Expulsa las entradas más antiguas por encima del límite (T68).
        while insertionOrder.count > maxEntries {
            let oldest = insertionOrder.removeFirst()
            cache[oldest] = nil
        }
    }

    /// Downsampling con ImageIO: decodifica solo al tamaño necesario, sin cargar
    /// el bitmap completo a memoria (skill de optimización de imágenes).
    /// `nonisolated static` para poder llamarse fuera del actor si hiciera falta.
    nonisolated static func downsample(data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return nil
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
            source, 0, downsampleOptions as CFDictionary
        ) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
