//
//  StudyStore.swift
//  Haki
//
//  Every write to notes and flashcards goes through these helpers (see
//  LedgerStore). Screens read with @Query.
//

import Foundation
import SwiftData

enum StudyStore {
    // MARK: Notes

    @discardableResult
    static func createNote(title: String = "", body: String = "", in context: ModelContext) -> Note {
        let note = Note(title: title, body: body)
        context.insert(note)
        LedgerStore.save(context)
        return note
    }

    /// Saves edits made directly on a note and stamps the edit time.
    static func touch(_ note: Note, now: Date = .now, in context: ModelContext) {
        note.updatedAt = now
        LedgerStore.save(context)
    }

    static func togglePin(_ note: Note, in context: ModelContext) {
        note.isPinned.toggle()
        LedgerStore.save(context)
    }

    static func deleteNote(_ note: Note, in context: ModelContext) {
        context.delete(note)
        LedgerStore.save(context)
    }

    /// Deletes a note left completely empty (e.g. "New note" then back).
    static func deleteIfEmpty(_ note: Note, in context: ModelContext) {
        let empty = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty { deleteNote(note, in: context) }
    }

    // MARK: Decks and cards

    @discardableResult
    static func createDeck(name: String, details: String = "", sourceNoteID: UUID? = nil, cards: [FlashcardDraft] = [], in context: ModelContext) -> FlashcardDeck {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let deck = FlashcardDeck(name: trimmed.isEmpty ? "New deck" : trimmed, details: details, sourceNoteID: sourceNoteID)
        context.insert(deck)
        insertCards(cards, into: deck, in: context)
        LedgerStore.save(context)
        return deck
    }

    /// Adds cards at the end of `deck` and saves.
    static func addCards(_ drafts: [FlashcardDraft], to deck: FlashcardDeck, in context: ModelContext) {
        insertCards(drafts, into: deck, in: context)
        LedgerStore.save(context)
    }

    @discardableResult
    static func addCard(front: String, back: String, to deck: FlashcardDeck, in context: ModelContext) -> Flashcard? {
        let inserted = insertCards([FlashcardDraft(front: front, back: back)], into: deck, in: context)
        LedgerStore.save(context)
        return inserted.first
    }

    @discardableResult
    private static func insertCards(_ drafts: [FlashcardDraft], into deck: FlashcardDeck, in context: ModelContext) -> [Flashcard] {
        var next = (deck.cards.map(\.order).max() ?? -1) + 1
        var inserted: [Flashcard] = []
        let now = Date.now
        for draft in drafts {
            let front = draft.front.trimmingCharacters(in: .whitespacesAndNewlines)
            let back = draft.back.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !front.isEmpty, !back.isEmpty else { continue }
            let card = Flashcard(front: front, back: back, order: next)
            card.createdAt = now
            next += 1
            context.insert(card)
            card.deck = deck
            inserted.append(card)
        }
        return inserted
    }

    /// Saves edits made directly on a card or deck.
    static func save(in context: ModelContext) {
        LedgerStore.save(context)
    }

    static func deleteCard(_ card: Flashcard, in context: ModelContext) {
        context.delete(card)
        LedgerStore.save(context)
    }

    static func deleteDeck(_ deck: FlashcardDeck, in context: ModelContext) {
        context.delete(deck)
        LedgerStore.save(context)
    }

    /// Records an answer: reschedules the card and stamps the deck.
    static func review(_ card: Flashcard, grade: ReviewGrade, now: Date = .now, in context: ModelContext) {
        if card.firstReviewedAt == nil { card.firstReviewedAt = now }
        card.schedule = SpacedRepetition.review(card.schedule, grade: grade, now: now)
        card.deck?.lastStudiedAt = now
        LedgerStore.save(context)
    }

    /// Forgets every card's progress in `deck`.
    static func resetProgress(_ deck: FlashcardDeck, in context: ModelContext) {
        for card in deck.cards {
            card.schedule = .new
            card.firstReviewedAt = nil
        }
        LedgerStore.save(context)
    }

    /// New cards in `deck` first studied on `now`'s calendar day.
    static func newCardsStudiedToday(_ deck: FlashcardDeck, now: Date = .now, calendar: Calendar = .current) -> Int {
        deck.cards.filter { card in
            guard let first = card.firstReviewedAt else { return false }
            return calendar.isDate(first, inSameDayAs: now)
        }.count
    }

    /// What to study in `deck` now: due cards, then new cards up to today's
    /// remaining new-card allowance (or every card, with `includeAll`, for
    /// cramming).
    static func studyQueue(for deck: FlashcardDeck, now: Date = .now, includeAll: Bool = false, calendar: Calendar = .current) -> [Flashcard] {
        let cards = deck.orderedCards
        if includeAll { return cards }
        let remainingNew = max(0, deck.newCardsPerDay - newCardsStudiedToday(deck, now: now, calendar: calendar))
        let ids = SpacedRepetition.studyQueue(cards.map { (id: $0.id, schedule: $0.schedule) }, now: now, newLimit: remainingNew)
        let byID = Dictionary(cards.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byID[$0] }
    }

    static func eraseAll(in context: ModelContext) {
        for deck in (try? context.fetch(FetchDescriptor<FlashcardDeck>())) ?? [] { context.delete(deck) }
        for note in (try? context.fetch(FetchDescriptor<Note>())) ?? [] { context.delete(note) }
        LedgerStore.save(context)
    }
}
