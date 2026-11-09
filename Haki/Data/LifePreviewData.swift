//
//  LifePreviewData.swift
//  Haki
//
//  Sample wardrobe, notes, flashcards and an assistant chat for previews
//  (added to `PreviewData.container`) and UI tests, plus accessors for
//  model-taking previews.
//

import Foundation
import SwiftData

extension PreviewData {
    static var sampleClothingItem: ClothingItem {
        if let item = try? context.fetch(FetchDescriptor<ClothingItem>(sortBy: [SortDescriptor(\.createdAt)])).first { return item }
        return WardrobeStore.addItem(name: "White tee", category: .top, colors: [.white], in: context)
    }

    static var sampleOutfit: Outfit {
        if let outfit = try? context.fetch(FetchDescriptor<Outfit>()).first { return outfit }
        return WardrobeStore.createOutfit(name: "Weekend", items: [sampleClothingItem], in: context)
    }

    static var sampleNote: Note {
        if let note = try? context.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])).first { return note }
        return StudyStore.createNote(title: "Cell biology", body: "Mitochondria make ATP.", in: context)
    }

    static var sampleDeck: FlashcardDeck {
        if let deck = try? context.fetch(FetchDescriptor<FlashcardDeck>()).first { return deck }
        return StudyStore.createDeck(name: "Biology", cards: HakiAIPreviewSamples.flashcards.cards, in: context)
    }

    static var sampleThread: AssistantThread {
        if let thread = try? context.fetch(FetchDescriptor<AssistantThread>()).first { return thread }
        return AssistantStore.createThread(title: "Spending this month", in: context)
    }

    /// A small wardrobe (no photos; screens show category icons), two
    /// outfits, notes, two decks with some study history, and one chat.
    static func loadLifeSamples(into context: ModelContext, now: Date = .now) {
        let day = 86_400.0
        let pieces: [(String, ClothingCategory, [ClothingColor], [ClothingSeason], [ClothingStyle], Int, Int, Int, Double?, Int?)] = [
            ("White tee", .top, [.white], [.spring, .summer], [.casual], 1, 1, 14, 2, 1_800),
            ("Navy crew-neck sweater", .top, [.navy], [.fall, .winter], [.casual, .smartCasual], 2, 4, 6, 9, 6_500),
            ("Light blue oxford shirt", .top, [.lightBlue], [.spring, .fall], [.smartCasual, .business], 3, 2, 3, 30, 5_000),
            ("Slim dark jeans", .bottom, [.denim], [.spring, .fall, .winter], [.casual, .smartCasual], 2, 3, 20, 1, 9_000),
            ("Tan chinos", .bottom, [.tan], [.spring, .summer, .fall], [.smartCasual, .business], 3, 2, 5, 12, 6_000),
            ("Black joggers", .bottom, [.black], [.fall, .winter], [.athletic, .lounge], 1, 3, 9, 4, nil),
            ("White leather sneakers", .shoes, [.white], [.spring, .summer, .fall], [.casual, .smartCasual], 2, 2, 25, 1, 11_000),
            ("Brown suede boots", .shoes, [.brown], [.fall, .winter], [.smartCasual], 3, 4, 4, 20, 18_000),
            ("Olive field jacket", .outerwear, [.olive], [.fall, .spring], [.casual, .outdoor], 2, 3, 2, 95, 14_000),
            ("Black leather belt", .accessory, [.black], [], [.smartCasual, .business], 3, 1, 7, 12, 4_000),
        ]
        var items: [ClothingItem] = []
        for (index, piece) in pieces.enumerated() {
            let item = ClothingItem(name: piece.0, category: piece.1)
            item.colors = piece.2
            item.seasons = piece.3
            item.styles = piece.4
            item.formality = piece.5
            item.warmth = piece.6
            item.timesWorn = piece.7
            item.lastWornAt = piece.8.map { now.addingTimeInterval(-$0 * day) }
            item.priceCents = piece.9
            item.createdAt = now.addingTimeInterval(-Double(200 - index) * day)
            context.insert(item)
            items.append(item)
        }
        let weekend = WardrobeStore.createOutfit(name: "Easy weekend", occasion: "Weekend errands", items: [items[0], items[3], items[6]], in: context)
        weekend.timesWorn = 4
        weekend.lastWornAt = now.addingTimeInterval(-3 * day)
        _ = WardrobeStore.createOutfit(name: "Dinner out", occasion: "Dinner", items: [items[2], items[4], items[7], items[9]], in: context)

        let notes: [(String, String, Bool, Double)] = [
            ("Cell biology", """
            **Mitochondria** make ATP, the cell's energy.
            - Photosynthesis happens in the chloroplasts.
            - DNA carries genetic information.
            - Osmosis: water moves across a membrane toward the higher solute concentration.
            """, true, 1),
            ("Spanish verbs", "ser: to be (permanent)\nestar: to be (temporary)\ntener: to have\nir: to go", false, 3),
            ("Trip ideas", "Lisbon in spring. Book flights by February.", false, 10),
        ]
        var noteRecords: [Note] = []
        for note in notes {
            let record = Note(title: note.0, body: note.1)
            record.isPinned = note.2
            record.createdAt = now.addingTimeInterval(-note.3 * day - 3_600)
            record.updatedAt = now.addingTimeInterval(-note.3 * day)
            context.insert(record)
            noteRecords.append(record)
        }

        let biology = StudyStore.createDeck(name: "Cell biology", sourceNoteID: noteRecords.first?.id, cards: HakiAIPreviewSamples.flashcards.cards, in: context)
        // Some history: two cards learned (one due now), the rest new.
        for (index, card) in biology.orderedCards.prefix(2).enumerated() {
            card.firstReviewedAt = now.addingTimeInterval(-4 * day)
            card.schedule = CardSchedule(repetitions: 2, intervalDays: 3, ease: 2.5, dueAt: now.addingTimeInterval(index == 0 ? -3_600 : 2 * day), lapses: 0, lastReviewedAt: now.addingTimeInterval(-3 * day))
        }
        _ = StudyStore.createDeck(name: "Spanish verbs", cards: [
            FlashcardDraft(front: "ser", back: "to be (permanent)"),
            FlashcardDraft(front: "estar", back: "to be (temporary)"),
            FlashcardDraft(front: "tener", back: "to have"),
            FlashcardDraft(front: "ir", back: "to go"),
        ], in: context)

        let thread = AssistantStore.createThread(title: "Spending this month", in: context)
        AssistantStore.append(.user("How much have I spent on restaurants this month?"), to: thread, now: now.addingTimeInterval(-7_200), in: context)
        AssistantStore.append(
            AssistantMessage(role: .assistant, content: [.object(["type": .string("text"), "text": .string("You've spent **$212.40** on restaurants so far this month, about $40 less than this point last month.")])]),
            toolsUsed: [.spending], to: thread, now: now.addingTimeInterval(-7_190), in: context
        )
        LedgerStore.save(context)
    }
}
