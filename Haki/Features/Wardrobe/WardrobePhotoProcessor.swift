//
//  WardrobePhotoProcessor.swift
//  Haki
//
//  Prepares a clothing photo on the device: an upright copy of at most
//  1200 px, the piece cut out of its background with Vision (when Vision
//  finds it), small square thumbnails for grids and a 1024 px JPEG for AI
//  tagging. Nothing here touches the main actor: `prepare(_:)` runs the work
//  in a detached task, the same way `ImageUpload.makeJPEG` does.
//

import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

/// A photo ready to save as a clothing item. The originals carry none of the
/// photo's metadata (location, camera details).
nonisolated struct WardrobePreparedPhoto: Sendable {
    /// The photo as taken, upright, at most 1200 px (JPEG).
    let originalJPEG: Data
    /// A 300 px square crop of the photo (JPEG).
    let originalThumbnailJPEG: Data
    /// The piece without its background, cropped to it (PNG with transparency).
    /// Nil when Vision found nothing or isn't available (e.g. the Simulator).
    let cutoutPNG: Data?
    /// The cut-out centered on a transparent 300 px square (PNG).
    let cutoutThumbnailPNG: Data?
    /// What the AI reads to tag the piece: the photo at most 1024 px (JPEG).
    let taggingJPEG: Data

    var hasCutout: Bool {
        cutoutPNG != nil && cutoutThumbnailPNG != nil
    }
}

nonisolated enum WardrobePhotoProcessor {
    static let imageMaxDimension = 1200
    static let thumbnailSide = 300
    static let taggingMaxDimension = 1024

    /// `process(_:)` off the main actor, so big photos never freeze the UI.
    static func prepare(_ imageData: Data) async -> WardrobePreparedPhoto? {
        await Task.detached(priority: .userInitiated) {
            WardrobePhotoProcessor.process(imageData)
        }.value
    }

    /// Downscales, cuts the piece out and makes the thumbnails. Nil when the
    /// data isn't an image. Falls back to the photo alone when the cut-out fails.
    static func process(_ imageData: Data) -> WardrobePreparedPhoto? {
        guard let base = downscaledImage(from: imageData, maxDimension: imageMaxDimension),
              let originalJPEG = jpegData(from: base, quality: 0.85),
              let originalThumbnail = squareThumbnail(of: base, side: thumbnailSide, fills: true),
              let originalThumbnailJPEG = jpegData(from: originalThumbnail, quality: 0.78)
        else { return nil }

        let taggingJPEG = ImageUpload.jpegData(
            from: originalJPEG,
            maxDimension: CGFloat(taggingMaxDimension),
            quality: 0.75
        ) ?? originalJPEG

        var cutoutPNG: Data?
        var cutoutThumbnailPNG: Data?
        if let maskedImage = makeCutout(of: base),
           let maskedPNG = pngData(from: maskedImage),
           let maskedThumbnail = squareThumbnail(of: maskedImage, side: thumbnailSide, fills: false),
           let maskedThumbnailPNG = pngData(from: maskedThumbnail) {
            cutoutPNG = maskedPNG
            cutoutThumbnailPNG = maskedThumbnailPNG
        }

        return WardrobePreparedPhoto(
            originalJPEG: originalJPEG,
            originalThumbnailJPEG: originalThumbnailJPEG,
            cutoutPNG: cutoutPNG,
            cutoutThumbnailPNG: cutoutThumbnailPNG,
            taggingJPEG: taggingJPEG
        )
    }

    // MARK: Decoding

    /// An upright copy of at most `maxDimension` px on the long side, decoded
    /// without loading the full-size photo. Keeps transparency (PNG).
    static func downscaledImage(from imageData: Data, maxDimension: Int) -> CGImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(imageData as CFData, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxDimension),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width > 0, image.height > 0
        else { return nil }
        return image
    }

    // MARK: Background removal

    /// The foreground (the piece of clothing) without its background, cropped
    /// to it. Nil when Vision finds nothing, fails, or isn't supported here.
    static func makeCutout(of image: CGImage) -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else { return nil }
            let instances = observation.allInstances
            guard !instances.isEmpty else { return nil }
            let buffer = try observation.generateMaskedImage(
                ofInstances: instances,
                from: handler,
                croppedToInstancesExtent: true
            )
            let masked = CIImage(cvPixelBuffer: buffer)
            let extent = masked.extent
            // A speck isn't a piece of clothing.
            guard extent.width >= 24, extent.height >= 24 else { return nil }
            let context = CIContext()
            return context.createCGImage(masked, from: extent)
        } catch {
            return nil
        }
    }

    // MARK: Thumbnails

    /// A `side` px square: the image cropped to fill it (`fills`), or fitted
    /// inside it on a transparent background with a little room around it.
    static func squareThumbnail(of image: CGImage, side: Int, fills: Bool) -> CGImage? {
        let width = Double(image.width)
        let height = Double(image.height)
        guard width > 0, height > 0, side > 0 else { return nil }
        let canvas = Double(side)
        let scale = fills
            ? max(canvas / width, canvas / height)
            : min(canvas / width, canvas / height) * 0.9
        let drawWidth = width * scale
        let drawHeight = height * scale
        let rect = CGRect(
            x: (canvas - drawWidth) / 2,
            y: (canvas - drawHeight) / 2,
            width: drawWidth,
            height: drawHeight
        )
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: rect)
        return context.makeImage()
    }

    // MARK: Encoding

    static func jpegData(from image: CGImage, quality: Double) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(max(quality, 0), 1),
            // JPEG has no transparency: see-through parts become white, not black.
            kCGImageDestinationBackgroundColor: CGColor(gray: 1, alpha: 1),
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    static func pngData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
