//
//  WardrobeStore.swift
//  Haki
//
//  Every write to the wardrobe goes through these helpers (see LedgerStore):
//  they insert models before relating them and save. Screens read with @Query.
//

import Foundation
import SwiftData

enum WardrobeStore {
    // MARK: Clothing

    /// Adds a piece of clothing and saves. `imageData` is the (ideally
    /// background-free) photo; `thumbnailData` a small square version.
    @discardableResult
    static func addItem(
        name: String,
        category: ClothingCategory,
        colors: [ClothingColor] = [],
        pattern: String = "",
        seasons: [ClothingSeason] = [],
        styles: [ClothingStyle] = [],
        formality: Int = 2,
        warmth: Int = 3,
        brand: String = "",
        priceCents: Int? = nil,
        imageData: Data? = nil,
        thumbnailData: Data? = nil,
        isCutout: Bool = false,
        in context: ModelContext
    ) -> ClothingItem {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = ClothingItem(name: trimmed.isEmpty ? category.singularTitle : trimmed, category: category)
        item.colors = colors
        item.pattern = pattern
        item.seasons = seasons
        item.styles = styles
        item.formality = min(5, max(1, formality))
        item.warmth = min(5, max(1, warmth))
        item.brand = brand
        item.priceCents = priceCents.flatMap { $0 > 0 ? $0 : nil }
        item.imageData = imageData
        item.thumbnailData = thumbnailData
        item.isCutout = isCutout
        context.insert(item)
        LedgerStore.save(context)
        return item
    }

    /// Fills in an item from AI tags (keeps what the person already chose
    /// for fields the tags leave empty).
    static func apply(_ tags: ClothingTags, to item: ClothingItem, in context: ModelContext) {
        if !tags.name.isEmpty { item.name = tags.name }
        if tags.category != .other { item.category = tags.category }
        if !tags.colors.isEmpty { item.colors = tags.colors }
        if !tags.pattern.isEmpty { item.pattern = tags.pattern }
        if !tags.seasons.isEmpty { item.seasons = tags.seasons }
        if !tags.styles.isEmpty { item.styles = tags.styles }
        item.formality = tags.formality
        item.warmth = tags.warmth
        LedgerStore.save(context)
    }

    /// Saves edits made directly on an item.
    static func save(in context: ModelContext) {
        LedgerStore.save(context)
    }

    /// Deletes the item; outfits that used it lose that piece.
    static func deleteItem(_ item: ClothingItem, in context: ModelContext) {
        context.delete(item)
        LedgerStore.save(context)
    }

    /// Counts a wear of `item` today.
    static func markWorn(_ item: ClothingItem, on date: Date = .now, in context: ModelContext) {
        item.timesWorn += 1
        item.lastWornAt = date
        LedgerStore.save(context)
    }

    // MARK: Outfits

    /// Creates an outfit from `items`, laid out on the board by type
    /// (outerwear and tops high, bottoms middle, shoes low, extras at the sides).
    @discardableResult
    static func createOutfit(name: String, occasion: String = "", items: [ClothingItem], isAISuggested: Bool = false, in context: ModelContext) -> Outfit {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let outfit = Outfit(name: trimmed.isEmpty ? "New outfit" : trimmed, occasion: occasion)
        outfit.isAISuggested = isAISuggested
        context.insert(outfit)
        for (index, layout) in defaultLayout(for: items.map(\.category)).enumerated() where index < items.count {
            let piece = OutfitPiece(centerX: layout.x, centerY: layout.y, widthFraction: layout.width, zIndex: index)
            context.insert(piece)
            piece.outfit = outfit
            piece.item = items[index]
        }
        LedgerStore.save(context)
        return outfit
    }

    /// Adds `item` to the board, in its usual spot, on top.
    @discardableResult
    static func addPiece(_ item: ClothingItem, to outfit: Outfit, in context: ModelContext) -> OutfitPiece {
        let existing = outfit.items.map(\.category)
        let spot = defaultLayout(for: existing + [item.category]).last ?? (x: 0.5, y: 0.5, width: 0.45)
        let piece = OutfitPiece(centerX: spot.x, centerY: spot.y, widthFraction: spot.width, zIndex: (outfit.pieces.map(\.zIndex).max() ?? -1) + 1)
        context.insert(piece)
        piece.outfit = outfit
        piece.item = item
        LedgerStore.save(context)
        return piece
    }

    static func removePiece(_ piece: OutfitPiece, in context: ModelContext) {
        context.delete(piece)
        LedgerStore.save(context)
    }

    /// Moves a piece to the top of the board.
    static func bringToFront(_ piece: OutfitPiece, in context: ModelContext) {
        let top = (piece.outfit?.pieces.map(\.zIndex).max() ?? 0) + 1
        piece.zIndex = top
        LedgerStore.save(context)
    }

    /// Counts a wear of the outfit and of every piece in it.
    static func markWorn(_ outfit: Outfit, on date: Date = .now, in context: ModelContext) {
        outfit.timesWorn += 1
        outfit.lastWornAt = date
        for item in outfit.items {
            item.timesWorn += 1
            item.lastWornAt = date
        }
        LedgerStore.save(context)
    }

    static func deleteOutfit(_ outfit: Outfit, in context: ModelContext) {
        context.delete(outfit)
        LedgerStore.save(context)
    }

    /// Saves an AI outfit idea as an outfit (ids not found are skipped).
    @discardableResult
    static func saveIdea(_ idea: OutfitIdea, occasion: String, from items: [ClothingItem], in context: ModelContext) -> Outfit? {
        let byID = Dictionary(items.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let chosen = idea.itemIDs.compactMap { byID[$0] }
        guard chosen.count >= 2 else { return nil }
        let outfit = createOutfit(name: idea.name, occasion: occasion, items: chosen, isAISuggested: true, in: context)
        outfit.notes = idea.reason
        LedgerStore.save(context)
        return outfit
    }

    /// Where pieces go on a fresh board, in the order of `categories`.
    static func defaultLayout(for categories: [ClothingCategory]) -> [(x: Double, y: Double, width: Double)] {
        var extrasPlaced = 0
        var topsPlaced = 0
        return categories.map { category -> (x: Double, y: Double, width: Double) in
            switch category.slot {
            case .outer:
                return (0.32, 0.28, 0.5)
            case .top:
                defer { topsPlaced += 1 }
                return (topsPlaced == 0 ? 0.5 : 0.62, 0.26, 0.48)
            case .onePiece:
                return (0.5, 0.4, 0.52)
            case .bottom:
                return (0.5, 0.58, 0.44)
            case .shoes:
                // A square card's bottom (y · 4/3 · W + width/2 + 6 pt padding)
                // has to stay inside the 3:4 board.
                return (0.5, 0.85, 0.32)
            case .extra:
                defer { extrasPlaced += 1 }
                let spots: [(Double, Double)] = [(0.84, 0.18), (0.16, 0.62), (0.84, 0.62), (0.16, 0.18)]
                let spot = spots[extrasPlaced % spots.count]
                return (spot.0, spot.1, 0.24)
            }
        }
    }

    static func eraseAll(in context: ModelContext) {
        for outfit in (try? context.fetch(FetchDescriptor<Outfit>())) ?? [] { context.delete(outfit) }
        for item in (try? context.fetch(FetchDescriptor<ClothingItem>())) ?? [] { context.delete(item) }
        LedgerStore.save(context)
    }
}
