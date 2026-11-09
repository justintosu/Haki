//
//  StudySummaryCard.swift
//  Haki
//
//  The You tab's notes and flashcards card: cards due today across decks
//  (the top links to Notes & Flashcards), "Study now" for the deck with the
//  most due (a full-screen session), and the two most recent notes.
//

import Foundation
import SwiftData
import SwiftUI

struct StudySummaryCard: View {
    @Query(sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var notes: [Note]

    @Query(sort: [SortDescriptor(\FlashcardDeck.name)])
    private var decks: [FlashcardDeck]

    @State private var session: StudySessionRequest?

    init() {}

    var body: some View {
        let totals = StudyDueTotals(decks: decks)
        let recentNotes = Array(notes.prefix(2))

        VStack(alignment: .leading, spacing: 16) {
            NavigationLink {
                StudyHomeView()
            } label: {
                StudySummaryCardTop(totals: totals, isEmpty: decks.isEmpty && notes.isEmpty)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your notes and flashcard decks")

            if let deck = totals.busiestDeck {
                studyNowButton(deck, count: totals.busiestCount)
            }

            if !recentNotes.isEmpty {
                StudyRecentNotesList(notes: recentNotes)
            }
        }
        .hakiCard()
        .fullScreenCover(item: $session) { request in
            StudySessionView(deck: request.deck, cramsAllCards: request.cramsAllCards)
        }
    }

    private func studyNowButton(_ deck: FlashcardDeck, count: Int) -> some View {
        Button {
            session = StudySessionRequest(deck: deck)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .accessibilityHidden(true)
                // One Text, so the spaces either side of the "·" match.
                Text("\(Text("Study now").fontWeight(.semibold)) · \(deck.name)")
                    .lineLimit(1)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityLabel("Study now: \(deck.name)")
        .accessibilityValue("\(StudyFormat.cards(count)) to study")
    }
}

/// The linked part of the card: header, and what's due or what this is for.
private struct StudySummaryCardTop: View {
    let totals: StudyDueTotals
    let isEmpty: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if isEmpty {
                Text("Write notes, turn them into flashcards with AI, and Haki tells you what to review each day.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if totals.deckCount > 0 {
                StudyDueSummary(totals: totals)
            } else {
                Text("Make a deck from one of your notes to start studying.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label("Notes & Flashcards", systemImage: "book.closed.fill")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }
}

/// "Recent notes" with up to two notes, each opening the editor.
private struct StudyRecentNotesList: View {
    let notes: [Note]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent notes")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
            ForEach(notes) { note in
                if note.id != notes.first?.id {
                    Divider()
                        .padding(.leading, 44)
                }
                NavigationLink {
                    NoteEditorView(note: note)
                } label: {
                    row(note)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ note: Note) -> some View {
        HStack(spacing: 12) {
            StudyIconTile(systemImage: note.isPinned ? "pin.fill" : "note.text", tint: .orange, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(StudyFormat.title(for: note))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(StudyFormat.noteDate(note.updatedAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens this note")
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            StudySummaryCard()
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        ScrollView {
            StudySummaryCard()
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment(empty: true)
}
