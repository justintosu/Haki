//
//  StudyHomeView.swift
//  Haki
//
//  Notes & Flashcards, pushed from the You tab. Notes: search, pinned first
//  then most recently edited, swipe to pin or delete, "New note" opens the
//  editor. Flashcards: how many cards are due today, each deck with what's
//  due and a Study button (a full-screen session), and "New deck". The
//  chosen side is remembered.
//

import Foundation
import SwiftData
import SwiftUI

struct StudyHomeView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("study.homeTab") private var tab: StudyHomeTab = .notes

    @Query(sort: [SortDescriptor(\Note.updatedAt, order: .reverse)])
    private var notes: [Note]

    @Query(sort: [SortDescriptor(\FlashcardDeck.name)])
    private var decks: [FlashcardDeck]

    @State private var searchText = ""
    @State private var openedNote: Note?
    @State private var openedDeck: FlashcardDeck?
    @State private var session: StudySessionRequest?
    @State private var showsNewDeck = false
    @State private var newDeckName = ""
    @State private var pinFeedback = 0

    init() {}

    var body: some View {
        list
            .navigationTitle("Notes & Flashcards")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: searchPrompt)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    addButton
                }
            }
            .navigationDestination(item: $openedNote) { note in
                NoteEditorView(note: note)
            }
            .navigationDestination(item: $openedDeck) { deck in
                DeckDetailView(deck: deck)
            }
            .fullScreenCover(item: $session) { request in
                StudySessionView(deck: request.deck, cramsAllCards: request.cramsAllCards)
            }
            .alert("New deck", isPresented: $showsNewDeck) {
                TextField("Deck name", text: $newDeckName)
                Button("Create") { createDeck() }
                Button("Cancel", role: .cancel) { newDeckName = "" }
            } message: {
                Text("Name it after a subject. You can add cards next.")
            }
            .sensoryFeedback(.selection, trigger: pinFeedback)
    }

    private var list: some View {
        List {
            Section {
                Picker("Show", selection: $tab) {
                    ForEach(StudyHomeTab.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            switch tab {
            case .notes:
                notesContent
            case .flashcards:
                decksContent
            }
        }
        .listStyle(.insetGrouped)
    }

    @ViewBuilder
    private var addButton: some View {
        switch tab {
        case .notes:
            Button {
                newNote()
            } label: {
                Label("New note", systemImage: "square.and.pencil")
            }
        case .flashcards:
            Button {
                showsNewDeck = true
            } label: {
                Label("New deck", systemImage: "plus")
            }
        }
    }

    private var searchPrompt: String {
        tab == .notes ? "Search notes" : "Search decks"
    }

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Notes

    private var visibleNotes: [Note] {
        let text = query
        guard !text.isEmpty else { return notes }
        return notes.filter { note in
            note.title.localizedCaseInsensitiveContains(text) || note.body.localizedCaseInsensitiveContains(text)
        }
    }

    @ViewBuilder
    private var notesContent: some View {
        let visible = visibleNotes
        let pinned = visible.filter { $0.isPinned }
        let others = visible.filter { !$0.isPinned }
        if notes.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No notes yet", systemImage: "note.text")
                } description: {
                    Text("Write down what you're learning. Markdown works, and Haki can turn a note into flashcards.")
                } actions: {
                    Button("New note") { newNote() }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else if visible.isEmpty {
            Section {
                ContentUnavailableView.search(text: query)
            }
        } else if pinned.isEmpty {
            Section {
                ForEach(others) { note in
                    noteRow(note)
                }
            }
        } else {
            Section("Pinned") {
                ForEach(pinned) { note in
                    noteRow(note)
                }
            }
            if !others.isEmpty {
                Section("Notes") {
                    ForEach(others) { note in
                        noteRow(note)
                    }
                }
            }
        }
    }

    private func noteRow(_ note: Note) -> some View {
        NavigationLink {
            NoteEditorView(note: note)
        } label: {
            NoteListRow(note: note)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                StudyStore.deleteNote(note, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                togglePin(note)
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash.fill" : "pin.fill")
            }
            .tint(.orange)
        }
        .contextMenu {
            Button {
                togglePin(note)
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                StudyStore.deleteNote(note, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Flashcards

    private var visibleDecks: [FlashcardDeck] {
        let text = query
        guard !text.isEmpty else { return decks }
        return decks.filter { deck in
            deck.name.localizedCaseInsensitiveContains(text) || deck.details.localizedCaseInsensitiveContains(text)
        }
    }

    @ViewBuilder
    private var decksContent: some View {
        let visible = visibleDecks
        if decks.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No decks yet", systemImage: "rectangle.on.rectangle.angled")
                } description: {
                    Text("Make a deck and add cards, or open a note and choose “Make flashcards with AI”.")
                } actions: {
                    Button("New deck") { showsNewDeck = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        } else {
            Section {
                StudyDueSummary(totals: StudyDueTotals(decks: decks))
                    .padding(.vertical, 4)
            }
            if visible.isEmpty {
                Section {
                    ContentUnavailableView.search(text: query)
                }
            }
            ForEach(visible) { deck in
                deckSection(deck)
            }
            Section {
                Button {
                    showsNewDeck = true
                } label: {
                    Label("New deck", systemImage: "plus")
                }
            } footer: {
                Text("Tip: open a note and choose “Make flashcards with AI” to turn it into a deck.")
            }
        }
    }

    private func deckSection(_ deck: FlashcardDeck) -> some View {
        let counts = StudyDeckCounts(deck: deck)
        return Section {
            NavigationLink {
                DeckDetailView(deck: deck)
            } label: {
                DeckListRow(deck: deck, counts: counts)
            }
            .contextMenu {
                Button {
                    session = StudySessionRequest(deck: deck)
                } label: {
                    Label("Study", systemImage: "play")
                }
                .disabled(counts.total == 0)
                Button {
                    session = StudySessionRequest(deck: deck, cramsAllCards: true)
                } label: {
                    Label("Cram all cards", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(counts.total == 0)
            }
            Button {
                session = StudySessionRequest(deck: deck)
            } label: {
                Label(studyTitle(counts), systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .disabled(counts.total == 0)
            .accessibilityHint("Studies \(deck.name)")
        }
    }

    private func studyTitle(_ counts: StudyDeckCounts) -> String {
        if counts.total == 0 { return "Add cards to study" }
        if counts.toStudy == 0 { return "Practice anyway" }
        return "Study \(StudyFormat.cards(counts.toStudy))"
    }

    // MARK: Actions

    private func newNote() {
        searchText = ""
        let note = StudyStore.createNote(in: modelContext)
        openedNote = note
    }

    private func createDeck() {
        let name = newDeckName
        newDeckName = ""
        let deck = StudyStore.createDeck(name: name, in: modelContext)
        openedDeck = deck
    }

    private func togglePin(_ note: Note) {
        withAnimation(.snappy) {
            StudyStore.togglePin(note, in: modelContext)
        }
        pinFeedback += 1
    }
}

/// The two sides of the screen (remembered).
nonisolated enum StudyHomeTab: String, CaseIterable, Identifiable {
    case notes
    case flashcards

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notes: "Notes"
        case .flashcards: "Flashcards"
        }
    }
}

#Preview {
    NavigationStack {
        StudyHomeView()
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        StudyHomeView()
    }
    .previewEnvironment(empty: true)
}
