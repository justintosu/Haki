//
//  ImageUpload.swift
//  Haki
//
//  Prepares photos picked in the app for upload: upright, downscaled JPEGs
//  without the original's metadata (location, camera details).
//

import CoreGraphics
import Foundation
import UIKit

enum ImageUpload {
    /// Downscales to at most `maxDimension` px on the long side and encodes JPEG. nil if the data isn't an image.
    static func jpegData(from imageData: Data, maxDimension: CGFloat, quality: CGFloat) -> Data? {
        // `UIImage(data:)` has scale 1, so `size` is in pixels, already rotated to the photo's orientation.
        guard let image = UIImage(data: imageData) else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }

        let longSide = max(size.width, size.height)
        let factor = maxDimension > 0 && longSide > maxDimension ? maxDimension / longSide : 1
        let target = CGSize(
            width: max(1, (size.width * factor).rounded()),
            height: max(1, (size.height * factor).rounded())
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let rendered = renderer.image { context in
            // JPEG has no transparency: put see-through images on white instead of black.
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: target))
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return rendered.jpegData(compressionQuality: min(max(quality, 0), 1))
    }
}
