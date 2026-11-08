//
//  ImageUpload.swift
//  Haki
//
//  Prepares photos picked in the app for upload: upright, downscaled JPEGs
//  without the original's metadata (location, camera details).
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated enum ImageUpload {
    /// Downscales to at most `maxDimension` px on the long side and encodes JPEG. nil if the data isn't an image.
    ///
    /// Decodes only a downscaled copy (ImageIO thumbnailing), never the whole
    /// photo. On the main actor, prefer `makeJPEG(from:maxDimension:quality:)`.
    static func jpegData(from imageData: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        var thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Rotated to the photo's orientation, so no orientation tag is needed.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if maxDimension > 0 {
            thumbnailOptions[kCGImageSourceThumbnailMaxPixelSize] = max(1, Int(maxDimension.rounded()))
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary),
              image.width > 0, image.height > 0
        else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        // Only the pixels: none of the original's metadata is copied.
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1),
            // JPEG has no transparency: put see-through images on white instead of black.
            kCGImageDestinationBackgroundColor: CGColor(gray: 1, alpha: 1),
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// `jpegData(from:maxDimension:quality:)` off the main thread, so large
    /// photos (48 MP, panoramas) don't freeze the UI while they're prepared.
    static func makeJPEG(from imageData: Data, maxDimension: CGFloat, quality: CGFloat) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            ImageUpload.jpegData(from: imageData, maxDimension: maxDimension, quality: quality)
        }.value
    }
}
