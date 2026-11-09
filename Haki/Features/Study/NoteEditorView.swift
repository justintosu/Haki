//
//  NoteEditorView.swift
//  Haki
//
//  Writing a note, pushed: a title and the text (Markdown), with a Preview
//  that renders it. Edits go straight into the note and are saved a moment
//  after typing stops (and when leaving or backgrounding); a new note left
//  empty is removed on the way out. The menu pins, shares, deletes, and
//  makes flashcards from the note, with AI or by hand.
//

import Foundation
import SwiftData
import SwiftUI

struct NoteEditorView: View {
    @Bindable var note: Note

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @FocusState private var focusedField: NoteEditorField?
    @State private var isPreviewing = false
    /// Bumped on every edit; the save waits for it to stop changing.
    @State private var editGeneration = 0
    @State private var hasUnsavedEdits = false
    @State private var showsFlashcardMaker = false
    /// A deck the AI sheet saved, opened once the sheet is gone.
    @State private var deckToOpen: FlashcardDeck?
    /// The deck pushed from here (made from this note).
    @State private var openedDeck: FlashcardDeck?
    @State private var showsDeleteConfirmation = false
    /// Set when deleting: the screen shows nothing while it closes, and the
    /// note is deleted once it's gone, so nothing reads a deleted model.
    @State private var isDeleting = false
    @State private var pinFeedback = 0

    var body: some View {
        Group {
            if isDeleting {
                Color.clear
            } else if isNoteGone {
                ContentUnavailableView(
                    "Note deleted",
                    systemImage: "note.text",
                    description: Text("This note is no longer here.")
                )
            } else {
                editorScreen
            }
        }
        .onDisappear { leave() }
    }

    private var isNoteGone: Bool {
        note.isDeleted || note.modelContext == nil
    }

    // MARK: Screen

    // The modifiers are split over two properties so no single expression
    // gets long enough to strain the type checker.

    private var editorScreen: some View {
        editorWithSaving
            .sheet(isPresented: $showsFlashcardMaker, onDismiss: { openSavedDeck() }) {
                FlashcardMakerView(
                    noteTitle: note.title,
                    noteText: note.body,
                    deckName: note.displayTitle,
                    noteID: note.id,
                    onSaved: { deck in deckToOpen = deck }
                )
            }
            .navigationDestination(item: $openedDeck) { deck in
                DeckDetailView(deck: deck)
            }
            .confirmationDialog("Delete this note?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete note", role: .destructive) { deleteNote() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Flashcard decks made from it stay.")
            }
            .sensoryFeedback(.selection, trigger: pinFeedback)
    }

    private var editorWithSaving: some View {
        editorContent
            .navigationTitle(isPreviewing ? "Preview" : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onChange(of: note.title) { _, _ in noteEdited() }
            .onChange(of: note.body) { _, _ in noteEdited() }
            .task(id: editGeneration) { await saveAfterPause() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { saveNow() }
            }
    }

    @ViewBuilder
    private var editorContent: some View {
        if isPreviewing {
            preview
        } else {
            writingArea
        }
    }

    private var writingArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $note.title)
                .font(.title2.weight(.bold))
                .focused($focusedField, equals: .title)
                .submitLabel(.next)
                .onSubmit { focusedField = .body }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 4)
            TextEditor(text: $note.body)
                .font(.body)
                .focused($focusedField, equals: .body)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 15)
                .overlay(alignment: .topLeading) { bodyPlaceholder }
                .accessibilityLabel("Note text")
        }
        .safeAreaInset(edge: .bottom) { statusBar }
    }

    @ViewBuilder
    private var bodyPlaceholder: some View {
        if note.body.isEmpty {
            Text(verbatim: "Start writing… Markdown works: **bold**, *italics*, “- ” for lists, “# ” for headings.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Text(wordCountText)
                .monospacedDigit()
            Text("·")
                .accessibilityHidden(true)
            Text("Edited \(StudyFormat.noteDate(note.updatedAt))")
            Spacer(minLength: 0)
            if note.isPinned {
                Label("Pinned", systemImage: "pin.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }

    private var wordCountText: String {
        let count = note.body.split(whereSeparator: { $0.isWhitespace }).count
        return count == 1 ? "1 word" : "\(count.formatted()) words"
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(StudyFormat.title(for: note))
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Nothing to preview yet.")
                        .foregroundStyle(.secondary)
                } else {
                    NoteMarkdownView(text: note.body)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                togglePreview()
            } label: {
                Label(isPreviewing ? "Edit" : "Preview", systemImage: isPreviewing ? "pencil" : "eye")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            moreMenu
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                togglePin()
            } label: {
                Label(note.isPinned ? "Unpin" : "Pin", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            ShareLink(item: shareText) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            Divider()
            Button {
                openFlashcardMaker()
            } label: {
                Label("Make flashcards with AI", systemImage: "sparkles")
            }
            .disabled(trimmedBody.isEmpty)
            Button {
                makeOwnDeck()
            } label: {
                Label("Make flashcards yourself", systemImage: "rectangle.stack.badge.plus")
            }
            Divider()
            Button(role: .destructive) {
                focusedField = nil
                showsDeleteConfirmation = true
            } label: {
                Label("Delete note", systemImage: "trash")
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    private var trimmedBody: String {
        note.body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shareText: String {
        let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if title.isEmpty { return note.body }
        if trimmedBody.isEmpty { return title }
        return "\(title)\n\n\(note.body)"
    }

    // MARK: Saving

    private func noteEdited() {
        hasUnsavedEdits = true
        editGeneration += 1
    }

    /// Saves about 0.6 s after the last keystroke (a newer edit cancels this).
    private func saveAfterPause() async {
        guard hasUnsavedEdits else { return }
        do {
            try await Task.sleep(for: .milliseconds(600))
        } catch {
            return
        }
        saveNow()
    }

    private func saveNow() {
        guard hasUnsavedEdits, !isNoteGone else { return }
        hasUnsavedEdits = false
        StudyStore.touch(note, in: modelContext)
    }

    /// On the way out: save, delete if asked to, and drop a note left empty
    /// (but not while a deck made from it is pushed on top).
    private func leave() {
        if isDeleting {
            if !isNoteGone {
                StudyStore.deleteNote(note, in: modelContext)
            }
            return
        }
        guard !isNoteGone else { return }
        saveNow()
        if openedDeck == nil && !showsFlashcardMaker {
            StudyStore.deleteIfEmpty(note, in: modelContext)
        }
    }

    // MARK: Actions

    private func togglePreview() {
        focusedField = nil
        saveNow()
        withAnimation(.snappy) {
            isPreviewing.toggle()
        }
    }

    private func togglePin() {
        StudyStore.togglePin(note, in: modelContext)
        pinFeedback += 1
    }

    private func openFlashcardMaker() {
        focusedField = nil
        saveNow()
        showsFlashcardMaker = true
    }

    private func openSavedDeck() {
        guard let deck = deckToOpen else { return }
        deckToOpen = nil
        openedDeck = deck
    }

    private func makeOwnDeck() {
        focusedField = nil
        saveNow()
        let deck = StudyStore.createDeck(name: note.displayTitle, sourceNoteID: note.id, in: modelContext)
        openedDeck = deck
    }

    private func deleteNote() {
        hasUnsavedEdits = false
        isDeleting = true
        dismiss()
    }
}

private enum NoteEditorField: Hashable {
    case title
    case body
}

#Preview {
    NavigationStack {
        NoteEditorView(note: PreviewData.sampleNote)
    }
    .previewEnvironment()
}
