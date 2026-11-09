//
//  DeckDetailView.swift
//  Haki
//
//  One flashcard deck, pushed: what's due, when it was last studied,
//  "Study now" (or cram every card) in a full-screen session, the note it
//  came from, every card with when it's next due (tap to edit, swipe to
//  delete), and the deck's settings: new cards per day, rename, reset
//  progress, delete.
//

import Foundation
import SwiftData
import SwiftUI

struct DeckDetailView: View {
    @Bindable var deck: FlashcardDeck

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var cardSheet: DeckCardSheet?
    @State private var session: StudySessionRequest?
    @State private var showsRename = false
    @State private var renameText = ""
    @State private var showsResetConfirmation = false
    @State private var showsDeleteConfirmation = false
    /// Set when deleting: the screen shows nothing while it closes, and the
    /// deck is deleted once it's gone, so nothing reads a deleted model.
    @State private var isDeleting = false
    @State private var resetFeedback = 0

    var body: some View {
        Group {
            if isDeleting {
                Color.hakiBackground
                    .ignoresSafeArea()
            } else if isDeckGone {
                ContentUnavailableView(
                    "Deck deleted",
                    systemImage: "rectangle.stack",
                    description: Text("This deck is no longer here.")
                )
            } else {
                deckScreen
            }
        }
        .onDisappear {
            if isDeleting && !isDeckGone {
                StudyStore.deleteDeck(deck, in: modelContext)
            }
        }
    }

    private var isDeckGone: Bool {
        deck.isDeleted || deck.modelContext == nil
    }

    // MARK: Screen

    // The modifiers are split over two properties so no single expression
    // gets long enough to strain the type checker.

    private var deckScreen: some View {
        deckListWithSheets
            .alert("Rename deck", isPresented: $showsRename) {
                TextField("Deck name", text: $renameText)
                Button("Save") { rename() }
                Button("Cancel", role: .cancel) {}
            }
            .confirmationDialog("Reset progress?", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
                Button("Reset progress", role: .destructive) { resetProgress() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every card goes back to new, as if you'd never studied it. The cards themselves stay.")
            }
            .confirmationDialog("Delete this deck?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete deck", role: .destructive) { deleteDeck() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
            .sensoryFeedback(.success, trigger: resetFeedback)
    }

    private var deckListWithSheets: some View {
        deckList
            .navigationTitle(deck.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        cardSheet = DeckCardSheet(card: nil, front: "", back: "")
                    } label: {
                        Label("Add card", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $cardSheet) { sheet in
                DeckCardEditorView(deck: deck, card: sheet.card, initialFront: sheet.front, initialBack: sheet.back)
            }
            .fullScreenCover(item: $session) { request in
                StudySessionView(deck: request.deck, cramsAllCards: request.cramsAllCards)
            }
            .onChange(of: deck.newCardsPerDay) { _, _ in
                StudyStore.save(in: modelContext)
            }
    }

    private var deckList: some View {
        let counts = StudyDeckCounts(deck: deck)
        let cards = StudyCards.live(in: deck)
        return List {
            Section {
                DeckHeaderCard(
                    deck: deck,
                    counts: counts,
                    onStudy: { session = StudySessionRequest(deck: deck) },
                    onCram: { session = StudySessionRequest(deck: deck, cramsAllCards: true) }
                )
                .listRowInsets(EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16))
                if let noteID = deck.sourceNoteID {
                    DeckSourceNoteRow(noteID: noteID)
                }
            }
            cardsSection(cards)
            settingsSection(counts: counts)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: Cards

    private func cardsSection(_ cards: [Flashcard]) -> some View {
        Section {
            if cards.isEmpty {
                Text("No cards yet. Add a question and its answer, then study.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cards) { card in
                    cardRow(card)
                }
            }
            Button {
                cardSheet = DeckCardSheet(card: nil, front: "", back: "")
            } label: {
                Label("Add card", systemImage: "plus")
            }
        } header: {
            Text(StudyFormat.cards(cards.count))
        }
    }

    private func cardRow(_ card: Flashcard) -> some View {
        Button {
            cardSheet = DeckCardSheet(card: card, front: card.front, back: card.back)
        } label: {
            DeckCardRow(card: card)
        }
        .foregroundStyle(.primary)
        .accessibilityHint("Edit this card")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                StudyStore.deleteCard(card, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Settings

    private func settingsSection(counts: StudyDeckCounts) -> some View {
        Section {
            Stepper(value: $deck.newCardsPerDay, in: 0...100, step: 5) {
                HStack {
                    Text("New cards per day")
                    Spacer(minLength: 8)
                    Text("\(deck.newCardsPerDay)")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                renameText = deck.name
                showsRename = true
            } label: {
                Label("Rename deck", systemImage: "pencil")
            }
            Button {
                showsResetConfirmation = true
            } label: {
                Label("Reset progress", systemImage: "arrow.counterclockwise")
            }
            .disabled(counts.learned == 0)
            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("Delete deck", systemImage: "trash")
                    .foregroundStyle(Color.hakiNegative)
            }
        } header: {
            Text("Deck")
        } footer: {
            Text("New cards are introduced at most this many a day, so reviews don't pile up.")
        }
    }

    private var deleteMessage: String {
        let count = deck.cards.count
        if count == 0 { return "“\(deck.name)” will be deleted." }
        return "“\(deck.name)” and its \(StudyFormat.cards(count)) will be deleted. This can't be undone."
    }

    // MARK: Actions

    private func rename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isDeckGone else { return }
        deck.name = trimmed
        StudyStore.save(in: modelContext)
    }

    private func resetProgress() {
        guard !isDeckGone else { return }
        StudyStore.resetProgress(deck, in: modelContext)
        resetFeedback += 1
    }

    private func deleteDeck() {
        isDeleting = true
        dismiss()
    }
}

/// The add/edit card sheet. The card's text is read when the sheet is
/// requested, so the sheet never reads a card deleted in the meantime.
private struct DeckCardSheet: Identifiable {
    let id = UUID()
    let card: Flashcard?
    let front: String
    let back: String
}

// MARK: - Header

/// Counts, last studied, and the study buttons.
private struct DeckHeaderCard: View {
    let deck: FlashcardDeck
    let counts: StudyDeckCounts
    let onStudy: () -> Void
    let onCram: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            titleBlock
            stats
            Label(StudyFormat.lastStudied(deck.lastStudiedAt), systemImage: "clock")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            buttons
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(deck.name)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if !deck.details.isEmpty {
                Text(deck.details)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var stats: some View {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .leading), count: columnCount)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            StudyStatTile(title: "Due", value: "\(counts.due)")
            StudyStatTile(title: "New", value: "\(counts.fresh)")
            StudyStatTile(title: "Learned", value: "\(counts.learned)")
            StudyStatTile(title: "Cards", value: "\(counts.total)")
        }
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                onStudy()
            } label: {
                Label(studyTitle, systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(counts.total == 0)
            .accessibilityHint(counts.toStudy > 0 ? "" : "Nothing is due, so this goes through every card")

            Button {
                onCram()
            } label: {
                Label("Cram all cards", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(counts.total == 0)
            .accessibilityHint("Go through every card in the deck, due or not")
        }
    }

    private var studyTitle: String {
        if counts.toStudy > 0 {
            return "Study now · \(StudyFormat.cards(counts.toStudy))"
        }
        return counts.total == 0 ? "Study now" : "Practice anyway"
    }
}

// MARK: - Rows

/// A card: front, back, and when it's next due.
private struct DeckCardRow: View {
    let card: Flashcard

    var body: some View {
        let schedule = card.schedule
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(card.front)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Text(card.back)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            Spacer(minLength: 8)
            dueTag(schedule)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(card.front). Answer: \(card.back)")
        .accessibilityValue(StudyFormat.spokenDueText(schedule))
    }

    private func dueTag(_ schedule: CardSchedule) -> some View {
        let isDue = SpacedRepetition.isDue(schedule, now: .now)
        let tint: Color = schedule.isNew ? Color.indigo : (isDue ? Color.hakiWarning : Color.secondary)
        return Text(StudyFormat.dueText(schedule))
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

/// "Made from: Cell biology", linking to the note (nothing if it was deleted).
private struct DeckSourceNoteRow: View {
    @Query private var notes: [Note]

    init(noteID: UUID) {
        let id = noteID
        _notes = Query(filter: #Predicate<Note> { $0.id == id })
    }

    var body: some View {
        if let note = notes.first {
            NavigationLink {
                NoteEditorView(note: note)
            } label: {
                HStack(spacing: 12) {
                    StudyIconTile(systemImage: "note.text", tint: .orange, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Made from")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(note.displayTitle)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DeckDetailView(deck: PreviewData.sampleDeck)
    }
    .previewEnvironment()
}
