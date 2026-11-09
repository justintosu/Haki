//
//  LifeModels.swift
//  Haki
//
//  SwiftData models for the wardrobe, notes and flashcards, and saved
//  assistant conversations. Same conventions as Models.swift: enums and
//  lists stored as raw strings with typed accessors, a default for every
//  stored property, no unique attributes, and relationships set only through
//  the `WardrobeStore` / `StudyStore` / `AssistantStore` helpers.
//
//  Everything here stays on the device.
//

import Foundation
import SwiftData

/// Comma-separated raw values <-> arrays of enums (keeps predicates simple).
nonisolated enum RawList {
    static func encode<T: RawRepresentable>(_ values: [T]) -> String where T.RawValue == String {
        values.map(\.rawValue).joined(separator: ",")
    }

    static func decode<T: RawRepresentable>(_ text: String) -> [T] where T.RawValue == String {
        text.split(separator: ",").compactMap { T(rawValue: String($0)) }
    }
}

// MARK: - Wardrobe

@Model
final class ClothingItem {
    var id: UUID = UUID()
    var name: String = ""
    var categoryRaw: String = ClothingCategory.other.rawValue
    /// Comma-separated `ClothingColor` raw values.
    var colorsRaw: String = ""
    var pattern: String = ""
    /// Comma-separated `ClothingSeason` raw values; empty = any season.
    var seasonsRaw: String = ""
    /// Comma-separated `ClothingStyle` raw values.
    var stylesRaw: String = ""
    /// 1 (very casual) ... 5 (black tie).
    var formality: Int = 2
    /// 1 (very light) ... 5 (very warm).
    var warmth: Int = 3
    var brand: String = ""
    var notes: String = ""
    /// What it cost, in cents (optional), for cost per wear.
    var priceCents: Int?
    var isFavorite: Bool = false
    var timesWorn: Int = 0
    var lastWornAt: Date?
    /// The photo with its background removed when that worked (PNG with
    /// transparency), otherwise the original photo (JPEG). About 1200 px.
    @Attribute(.externalStorage) var imageData: Data?
    /// A small square thumbnail (JPEG or PNG, about 300 px) for grids.
    @Attribute(.externalStorage) var thumbnailData: Data?
    /// Whether `imageData` is a cut-out (transparent background).
    var isCutout: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \OutfitPiece.item)
    var pieces: [OutfitPiece] = []

    init(name: String, category: ClothingCategory) {
        self.name = name
        self.categoryRaw = category.rawValue
    }

    var category: ClothingCategory {
        get { ClothingCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var colors: [ClothingColor] {
        get { RawList.decode(colorsRaw) }
        set { colorsRaw = RawList.encode(newValue) }
    }

    var seasons: [ClothingSeason] {
        get { RawList.decode(seasonsRaw) }
        set { seasonsRaw = RawList.encode(newValue) }
    }

    var styles: [ClothingStyle] {
        get { RawList.decode(stylesRaw) }
        set { stylesRaw = RawList.encode(newValue) }
    }

    /// The fields the AI sees when suggesting outfits (no photo).
    var summary: WardrobePieceSummary {
        WardrobePieceSummary(
            id: id.uuidString, name: name, category: categoryRaw,
            colors: colors.map(\.rawValue), seasons: seasons.map(\.rawValue), styles: styles.map(\.rawValue),
            formality: formality, warmth: warmth, timesWorn: timesWorn
        )
    }

    var wearInfo: WardrobeWearInfo {
        WardrobeWearInfo(id: id.uuidString, timesWorn: timesWorn, lastWornAt: lastWornAt, priceCents: priceCents, addedAt: createdAt)
    }
}

@Model
final class Outfit {
    var id: UUID = UUID()
    var name: String = ""
    var occasion: String = ""
    var notes: String = ""
    var isFavorite: Bool = false
    var timesWorn: Int = 0
    var lastWornAt: Date?
    /// A rendered picture of the board, for lists.
    @Attribute(.externalStorage) var previewData: Data?
    /// Made by the AI's outfit ideas (the person may have edited it since).
    var isAISuggested: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \OutfitPiece.outfit)
    var pieces: [OutfitPiece] = []

    init(name: String, occasion: String = "") {
        self.name = name
        self.occasion = occasion
    }

    /// Pieces back to front (drawing order on the board).
    var orderedPieces: [OutfitPiece] {
        pieces.sorted { $0.zIndex < $1.zIndex }
    }

    /// The clothing in this outfit that still exists.
    var items: [ClothingItem] {
        orderedPieces.compactMap(\.item)
    }
}

/// One clothing item placed on an outfit board.
@Model
final class OutfitPiece {
    var id: UUID = UUID()
    /// Center of the piece, as a fraction of the board's width and height (0...1).
    var centerX: Double = 0.5
    var centerY: Double = 0.5
    /// Width as a fraction of the board's width.
    var widthFraction: Double = 0.45
    var rotationDegrees: Double = 0
    /// Higher draws on top.
    var zIndex: Int = 0
    var outfit: Outfit?
    var item: ClothingItem?

    init(centerX: Double, centerY: Double, widthFraction: Double, zIndex: Int) {
        self.centerX = centerX
        self.centerY = centerY
        self.widthFraction = widthFraction
        self.zIndex = zIndex
    }
}

// MARK: - Notes and flashcards

@Model
final class Note {
    var id: UUID = UUID()
    var title: String = ""
    /// Plain text; Markdown (bold, italics, lists, links) is rendered.
    var body: String = ""
    var isPinned: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(title: String, body: String = "") {
        self.title = title
        self.body = body
    }

    /// The title, or the first line of the body, or "New note".
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let firstLine = body.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return firstLine.isEmpty ? "New note" : String(firstLine.prefix(80))
    }
}

@Model
final class FlashcardDeck {
    var id: UUID = UUID()
    var name: String = ""
    var details: String = ""
    /// The note it was made from, if any (kept even if the note is deleted).
    var sourceNoteID: UUID?
    /// New cards introduced per day.
    var newCardsPerDay: Int = 20
    var createdAt: Date = Date()
    var lastStudiedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Flashcard.deck)
    var cards: [Flashcard] = []

    init(name: String, details: String = "", sourceNoteID: UUID? = nil) {
        self.name = name
        self.details = details
        self.sourceNoteID = sourceNoteID
    }

    /// Cards in the order they were added.
    var orderedCards: [Flashcard] {
        cards.sorted { $0.createdAt == $1.createdAt ? $0.order < $1.order : $0.createdAt < $1.createdAt }
    }

    func dueCount(now: Date = .now) -> Int {
        cards.filter { !$0.schedule.isNew && SpacedRepetition.isDue($0.schedule, now: now) }.count
    }

    var newCount: Int { cards.filter { $0.schedule.isNew }.count }
}

@Model
final class Flashcard {
    var id: UUID = UUID()
    var front: String = ""
    var back: String = ""
    var order: Int = 0
    var createdAt: Date = Date()
    // Schedule (see `CardSchedule`).
    var repetitions: Int = 0
    var intervalDays: Double = 0
    var ease: Double = 2.5
    var dueAt: Date?
    var lapses: Int = 0
    var lastReviewedAt: Date?
    /// When it was first studied (for the "new cards per day" limit).
    var firstReviewedAt: Date?
    var deck: FlashcardDeck?

    init(front: String, back: String, order: Int) {
        self.front = front
        self.back = back
        self.order = order
    }

    var schedule: CardSchedule {
        get {
            CardSchedule(repetitions: repetitions, intervalDays: intervalDays, ease: ease, dueAt: dueAt, lapses: lapses, lastReviewedAt: lastReviewedAt)
        }
        set {
            repetitions = newValue.repetitions
            intervalDays = newValue.intervalDays
            ease = newValue.ease
            dueAt = newValue.dueAt
            lapses = newValue.lapses
            lastReviewedAt = newValue.lastReviewedAt
        }
    }
}

// MARK: - Assistant

@Model
final class AssistantThread {
    var id: UUID = UUID()
    var title: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \AssistantMessageRecord.thread)
    var messages: [AssistantMessageRecord] = []

    init(title: String) {
        self.title = title
    }

    var orderedMessages: [AssistantMessageRecord] {
        messages.sorted { $0.order < $1.order }
    }

    /// The conversation as sent to the server (records that fail to decode are skipped).
    var conversation: [AssistantMessage] {
        orderedMessages.compactMap(\.message)
    }
}

/// One message of a conversation, stored verbatim as JSON.
@Model
final class AssistantMessageRecord {
    var id: UUID = UUID()
    var order: Int = 0
    var roleRaw: String = AssistantRole.user.rawValue
    /// JSON of `AssistantMessage` (content blocks kept exactly as received).
    var json: Data = Data()
    /// Text to show (empty for tool-result messages).
    var displayText: String = ""
    /// Comma-separated `AssistantTool` raw values used to answer (assistant messages).
    var toolsUsedRaw: String = ""
    var createdAt: Date = Date()
    var thread: AssistantThread?

    init(order: Int, message: AssistantMessage) {
        self.order = order
        self.roleRaw = message.role.rawValue
        self.json = (try? JSONEncoder().encode(message)) ?? Data()
        self.displayText = message.isToolResults ? "" : message.text
    }

    var message: AssistantMessage? {
        try? JSONDecoder().decode(AssistantMessage.self, from: json)
    }

    var role: AssistantRole { AssistantRole(rawValue: roleRaw) ?? .user }

    var toolsUsed: [AssistantTool] {
        get { RawList.decode(toolsUsedRaw) }
        set { toolsUsedRaw = RawList.encode(newValue) }
    }

    /// A message the person sees in the chat: their typed messages and the
    /// assistant's replies with text (not tool calls or tool results).
    var isVisible: Bool {
        !displayText.isEmpty
    }
}
