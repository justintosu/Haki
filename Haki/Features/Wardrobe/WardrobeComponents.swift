//
//  WardrobeComponents.swift
//  Haki
//
//  Small pieces shared by the wardrobe screens: wording for wears, formality
//  and warmth; the "studio" and board colors; a decoded-image cache; a
//  clothing item's tile and card; an outfit's preview, card and row; filter
//  chips and stat tiles.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Wording

enum WardrobeFormat {
    /// "Not worn yet", "Worn once", "Worn 14 times".
    static func timesWorn(_ count: Int) -> String {
        if count <= 0 { return "Not worn yet" }
        if count == 1 { return "Worn once" }
        return "Worn \(count) times"
    }

    /// "1 wear", "14 wears".
    static func wears(_ count: Int) -> String {
        count == 1 ? "1 wear" : "\(max(count, 0)) wears"
    }

    /// "Never", "Today", "Yesterday", "5 days ago", "Mar 3", "Mar 3, 2025".
    static func lastWorn(_ date: Date?, now: Date = .now, calendar: Calendar = .current) -> String {
        guard let date else { return "Never" }
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days > 1 && days < 30 { return "\(days) days ago" }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func formality(_ level: Int) -> String {
        switch level {
        case ...1: return "Very casual"
        case 2: return "Casual"
        case 3: return "Smart"
        case 4: return "Dressy"
        default: return "Formal"
        }
    }

    static func warmth(_ level: Int) -> String {
        switch level {
        case ...1: return "Very light"
        case 2: return "Light"
        case 3: return "Medium"
        case 4: return "Warm"
        default: return "Very warm"
        }
    }

    static func colors(_ colors: [ClothingColor]) -> String {
        colors.isEmpty ? "Not set" : colors.map(\.title).joined(separator: ", ")
    }

    static func seasons(_ seasons: [ClothingSeason]) -> String {
        seasons.isEmpty ? "Any season" : seasons.map(\.title).joined(separator: ", ")
    }

    static func styles(_ styles: [ClothingStyle]) -> String {
        styles.isEmpty ? "Not set" : styles.map(\.title).joined(separator: ", ")
    }

    /// "3 pieces".
    static func pieces(_ count: Int) -> String {
        count == 1 ? "1 piece" : "\(count) pieces"
    }

    static func isToday(_ date: Date?) -> Bool {
        guard let date else { return false }
        return Calendar.current.isDateInToday(date)
    }
}

// MARK: - Colors

enum WardrobePalette {
    /// The soft backdrop behind clothing photos and icons, like a product shot.
    static let studio = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.20, green: 0.20, blue: 0.215, alpha: 1)
            : UIColor(red: 0.945, green: 0.933, blue: 0.914, alpha: 1)
    })

    /// The outfit board: light in both modes, like a pinboard.
    static let board = Color(red: 0.965, green: 0.955, blue: 0.94)
    static let boardEdge = Color(red: 0.87, green: 0.85, blue: 0.82)
    /// Icons drawn on the light board.
    static let boardIcon = Color(red: 0.42, green: 0.42, blue: 0.45)

    /// The color an item's icon is drawn in: its first color that shows on a
    /// light backdrop, otherwise `fallback`.
    static func iconTint(for colors: [ClothingColor], fallback: Color) -> Color {
        guard let color = colors.first(where: { !paleColors.contains($0) }) else { return fallback }
        return Color(hex: color.hex)
    }

    /// Colors too pale to read on a light backdrop (they get a dark checkmark).
    static let paleColors: Set<ClothingColor> = [.white, .cream, .beige, .silver, .yellow, .lightBlue, .pink, .tan, .gold]
}

// MARK: - Image cache

/// Decoded, downscaled images for clothing items and outfit previews, so
/// grids and the board don't decode photos on every redraw.
@MainActor
enum WardrobeImageCache {
    private static let small: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 400
        return cache
    }()

    private static let large: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 24
        return cache
    }()

    /// `data` decoded at most `maxPixelSize` px. Keyed by `id`, the size and
    /// the data's length, so a replaced photo is decoded afresh.
    static func image(from data: Data?, id: UUID, maxPixelSize: Int) -> UIImage? {
        guard let data, !data.isEmpty else { return nil }
        let cache = maxPixelSize <= 400 ? small : large
        let key = "\(id.uuidString)-\(maxPixelSize)-\(data.count)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let cgImage = WardrobePhotoProcessor.downscaledImage(from: data, maxDimension: maxPixelSize) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key)
        return image
    }

    /// For grids: the thumbnail, or the photo downscaled.
    static func thumbnail(for item: ClothingItem) -> UIImage? {
        image(from: item.thumbnailData, id: item.id, maxPixelSize: 300)
            ?? image(from: item.imageData, id: item.id, maxPixelSize: 300)
    }

    /// For the outfit board: the photo at a size that stays sharp on it.
    static func boardImage(for item: ClothingItem) -> UIImage? {
        image(from: item.imageData, id: item.id, maxPixelSize: 700)
            ?? image(from: item.thumbnailData, id: item.id, maxPixelSize: 300)
    }

    /// For the detail screen and the editor: the full photo.
    static func fullImage(for item: ClothingItem) -> UIImage? {
        image(from: item.imageData, id: item.id, maxPixelSize: WardrobePhotoProcessor.imageMaxDimension)
            ?? image(from: item.thumbnailData, id: item.id, maxPixelSize: 300)
    }
}

// MARK: - Item views

/// The category's symbol, tinted with the item's color.
struct WardrobeCategoryIcon: View {
    let category: ClothingCategory
    let colors: [ClothingColor]
    let fallback: Color

    init(category: ClothingCategory, colors: [ClothingColor], fallback: Color = .secondary) {
        self.category = category
        self.colors = colors
        self.fallback = fallback
    }

    var body: some View {
        Image(systemName: category.systemImage)
            .resizable()
            .scaledToFit()
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(WardrobePalette.iconTint(for: colors, fallback: fallback))
            .accessibilityHidden(true)
    }
}

/// A square-ish picture of a piece on the studio backdrop: the cut-out with
/// room around it, the photo filling the tile, or the category icon.
struct WardrobeItemTile: View {
    let item: ClothingItem
    let cornerRadius: CGFloat
    let prefersFullImage: Bool

    init(item: ClothingItem, cornerRadius: CGFloat = 14, prefersFullImage: Bool = false) {
        self.item = item
        self.cornerRadius = cornerRadius
        self.prefersFullImage = prefersFullImage
    }

    var body: some View {
        WardrobePalette.studio
            .overlay { artwork }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = loadedImage {
            if item.isCutout {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(0.9)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        } else {
            WardrobeCategoryIcon(category: item.category, colors: item.colors)
                .scaleEffect(0.42)
        }
    }

    private var loadedImage: UIImage? {
        prefersFullImage ? WardrobeImageCache.fullImage(for: item) : WardrobeImageCache.thumbnail(for: item)
    }
}

/// A piece in a grid: tile, name and how often it's been worn.
struct WardrobeItemCard: View {
    let item: ClothingItem

    init(item: ClothingItem) {
        self.item = item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WardrobeItemTile(item: item)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if item.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.pink)
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitle: String {
        "\(item.category.singularTitle) · \(WardrobeFormat.wears(item.timesWorn))"
    }

    private var accessibilityText: String {
        var parts = [item.name, item.category.singularTitle, WardrobeFormat.timesWorn(item.timesWorn)]
        if item.isFavorite { parts.append("Favorite") }
        return parts.joined(separator: ", ")
    }
}

/// A piece as drawn on the outfit board (and its snapshot): the cut-out with
/// a soft shadow, the photo as a print with a white border, or an icon card.
struct OutfitPieceArtwork: View {
    let item: ClothingItem

    init(item: ClothingItem) {
        self.item = item
    }

    var body: some View {
        if let image = WardrobeImageCache.boardImage(for: item) {
            if item.isCutout {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 4)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(5)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .shadow(color: Color.black.opacity(0.14), radius: 5, x: 0, y: 3)
            }
        } else {
            Color.white
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    WardrobeCategoryIcon(category: item.category, colors: item.colors, fallback: WardrobePalette.boardIcon)
                        .padding(18)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 5, x: 0, y: 3)
        }
    }
}

// MARK: - Outfit views

/// An outfit's picture: the board snapshot, or a collage of its pieces.
struct WardrobeOutfitPreview: View {
    let outfit: Outfit
    let cornerRadius: CGFloat

    init(outfit: Outfit, cornerRadius: CGFloat = 14) {
        self.outfit = outfit
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        WardrobePalette.board
            .overlay { content }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let snapshot = WardrobeImageCache.image(from: outfit.previewData, id: outfit.id, maxPixelSize: 600) {
            Image(uiImage: snapshot)
                .resizable()
                .scaledToFill()
        } else {
            WardrobeOutfitCollage(items: Array(outfit.items.prefix(4)))
        }
    }
}

/// Up to four pieces in a 2 × 2 grid.
private struct WardrobeOutfitCollage: View {
    let items: [ClothingItem]

    var body: some View {
        if items.isEmpty {
            Image(systemName: "hanger")
                .font(.title2)
                .foregroundStyle(WardrobePalette.boardIcon)
        } else {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    cell(0)
                    cell(1)
                }
                if items.count > 2 {
                    HStack(spacing: 6) {
                        cell(2)
                        cell(3)
                    }
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        if index < items.count {
            OutfitPieceArtwork(item: items[index])
                .padding(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// An outfit in a grid: preview, name, occasion and wears.
struct WardrobeOutfitCard: View {
    let outfit: Outfit

    init(outfit: Outfit) {
        self.outfit = outfit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WardrobeOutfitPreview(outfit: outfit)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if outfit.isAISuggested {
                        Image(systemName: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .padding(6)
                            .background(.regularMaterial, in: Circle())
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(outfit.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitle: String {
        let occasion = outfit.occasion.trimmingCharacters(in: .whitespacesAndNewlines)
        let wears = WardrobeFormat.wears(outfit.timesWorn)
        return occasion.isEmpty ? wears : "\(occasion) · \(wears)"
    }

    private var accessibilityText: String {
        var parts = [outfit.name]
        let occasion = outfit.occasion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !occasion.isEmpty { parts.append(occasion) }
        parts.append(WardrobeFormat.pieces(outfit.items.count))
        parts.append(WardrobeFormat.timesWorn(outfit.timesWorn))
        if outfit.isAISuggested { parts.append("Suggested by Haki") }
        return parts.joined(separator: ", ")
    }
}

/// An outfit in a list: small preview, name, pieces and wears.
struct WardrobeOutfitRow: View {
    let outfit: Outfit
    @ScaledMetric(relativeTo: .body) private var previewWidth: CGFloat = 42

    init(outfit: Outfit) {
        self.outfit = outfit
    }

    var body: some View {
        HStack(spacing: 12) {
            WardrobeOutfitPreview(outfit: outfit, cornerRadius: 8)
                .frame(width: previewWidth, height: previewWidth * 4 / 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(outfit.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text("\(WardrobeFormat.pieces(outfit.items.count)) · \(WardrobeFormat.timesWorn(outfit.timesWorn))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Controls

/// A capsule toggle for filters and tags. Selected chips are filled and show
/// a checkmark, so the state never relies on color alone.
struct WardrobeChip: View {
    let title: String
    let systemImage: String?
    let isSelected: Bool
    let fillsWidth: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isSelected: Bool, fillsWidth: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.fillsWidth = fillsWidth
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// A small stat with an icon: "Pieces 10".
struct WardrobeStatTile: View {
    let title: String
    let value: String
    let detail: String?
    let systemImage: String
    let tint: Color

    init(title: String, value: String, detail: String? = nil, systemImage: String, tint: Color) {
        self.title = title
        self.value = value
        self.detail = detail
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .foregroundStyle(.secondary)
            }
            .font(.caption.weight(.semibold))
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.leading)
                .contentTransition(.numericText())
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Cards") {
    ScrollView {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                WardrobeItemCard(item: PreviewData.sampleClothingItem)
                WardrobeOutfitCard(outfit: PreviewData.sampleOutfit)
            }
            WardrobeOutfitRow(outfit: PreviewData.sampleOutfit)
                .hakiCard()
            HStack {
                WardrobeChip("All", isSelected: true) {}
                WardrobeChip("Tops", systemImage: "tshirt", isSelected: false) {}
            }
            WardrobeStatTile(title: "Pieces", value: "10", systemImage: "tshirt", tint: .teal)
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
