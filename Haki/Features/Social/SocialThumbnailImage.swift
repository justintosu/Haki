//
//  SocialThumbnailImage.swift
//  Haki
//
//  Small previews of post photos (profile grid tiles, activity rows). The
//  photo is downscaled to about the size it's shown at and kept in memory,
//  so tiles don't each hold a full-size bitmap, and scrolling back doesn't
//  download and decode the photo again.
//

import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// Where a thumbnail is: loading, shown, or failed to load.
enum SocialThumbnailPhase {
    case loading
    case success(Image)
    case failure
}

/// Like `AsyncImage`, for photos shown small: `side` is the length in points
/// of the thumbnail's shorter side (it's drawn to fill a frame about that size).
struct SocialThumbnailImage<Content: View>: View {
    let url: URL
    let side: CGFloat
    private let content: (SocialThumbnailPhase) -> Content

    @State private var image: UIImage?
    @State private var failed = false

    init(url: URL, side: CGFloat, @ViewBuilder content: @escaping (SocialThumbnailPhase) -> Content) {
        self.url = url
        self.side = side
        self.content = content
        // Straight from memory when it's been shown before, without a loading flash.
        _image = State(initialValue: SocialThumbnailCache.image(for: SocialThumbnailCache.key(url: url, side: side)))
    }

    var body: some View {
        content(phase)
            .task(id: url) {
                await load()
            }
    }

    private var phase: SocialThumbnailPhase {
        if let image {
            return .success(Image(uiImage: image))
        }
        return failed ? .failure : .loading
    }

    private func load() async {
        let key = SocialThumbnailCache.key(url: url, side: side)
        if let cached = SocialThumbnailCache.image(for: key) {
            image = cached
            failed = false
            return
        }
        image = nil
        failed = false
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let full = UIImage(data: data) else {
                failed = true
                return
            }
            let size = Self.thumbnailSize(for: full.size, side: side)
            let thumbnail = await full.byPreparingThumbnail(ofSize: size) ?? full
            SocialThumbnailCache.insert(thumbnail, for: key)
            image = thumbnail
        } catch {
            if !Backend.isCancellation(error) {
                failed = true
            }
        }
    }

    /// `pixelSize` (scale 1, as `UIImage(data:)` makes it) scaled so its
    /// shorter side covers `side` points on a 3x screen, keeping its shape.
    /// Never larger than the original.
    private static func thumbnailSize(for pixelSize: CGSize, side: CGFloat) -> CGSize {
        let shorter = min(pixelSize.width, pixelSize.height)
        guard shorter > 0 else { return pixelSize }
        let factor = min(1, side * 3 / shorter)
        return CGSize(
            width: max(1, (pixelSize.width * factor).rounded()),
            height: max(1, (pixelSize.height * factor).rounded())
        )
    }
}

/// Thumbnails made this session, keyed by URL and size.
private enum SocialThumbnailCache {
    private static let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 300
        // About 60 MB of decoded pixels.
        cache.totalCostLimit = 60 * 1024 * 1024
        return cache
    }()

    static func key(url: URL, side: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(side.rounded()))" as NSString
    }

    static func image(for key: NSString) -> UIImage? {
        images.object(forKey: key)
    }

    static func insert(_ image: UIImage, for key: NSString) {
        let pixels = image.size.width * image.scale * image.size.height * image.scale
        images.setObject(image, forKey: key, cost: Int(pixels) * 4)
    }
}

#Preview {
    VStack(spacing: 16) {
        if let url = URL(string: "https://example.com/missing.jpg") {
            SocialThumbnailImage(url: url, side: 120) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                case .loading:
                    ProgressView()
                }
            }
            .frame(width: 120, height: 120)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
    .padding()
    .previewEnvironment()
}
