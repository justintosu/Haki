//
//  DeckCardEditorView.swift
//  Haki
//
//  Add or edit one flashcard (front and back), in a sheet with its own
//  NavigationStack. Adding offers "Save and add another" for typing in a
//  run of cards. Editing keeps the card's study progress.
//

import Foundation
import SwiftData
import SwiftUI

struct DeckCardEditorView: View {
    let deck: FlashcardDeck
    /// The card being edited; nil adds a new one.
    let card: Flashcard?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var front: String
    @State private var back: String
    @State private var addedCount = 0
    @FocusState private var focusedField: DeckCardField?

    /// `initialFront` and `initialBack` are the card's text when editing, read
    /// by the presenter, so this sheet never reads a card that was just deleted.
    init(deck: FlashcardDeck, card: Flashcard?, initialFront: String = "", initialBack: String = "") {
        self.deck = deck
        self.card = card
        _front = State(initialValue: initialFront)
        _back = State(initialValue: initialBack)
    }

    private var isNew: Bool { card == nil }

    private var trimmedFront: String { front.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedBack: String { back.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedFront.isEmpty && !trimmedBack.isEmpty }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle(isNew ? "New card" : "Edit card")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .onAppear {
                    if isNew { focusedField = .front }
                }
                .sensoryFeedback(.success, trigger: addedCount)
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Question, word or term", text: $front, axis: .vertical)
                    .lineLimit(2...6)
                    .focused($focusedField, equals: .front)
            } header: {
                Text("Front")
            }
            Section {
                TextField("Answer", text: $back, axis: .vertical)
                    .lineLimit(2...8)
                    .focused($focusedField, equals: .back)
            } header: {
                Text("Back")
            } footer: {
                Text("For typed answers, separate answers that also count with “/” (for example, “car / automobile”).")
            }
            if isNew {
                Section {
                    Button {
                        saveAndAddAnother()
                    } label: {
                        Label("Save and add another", systemImage: "plus.square.on.square")
                    }
                    .disabled(!canSave)
                } footer: {
                    if addedCount > 0 {
                        Text(addedCount == 1 ? "1 card added." : "\(addedCount) cards added.")
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(addedCount > 0 ? "Done" : "Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(isNew ? "Add" : "Save") { save() }
                .disabled(!canSave)
        }
    }

    private func save() {
        guard canSave else { return }
        if let card {
            if !card.isDeleted && card.modelContext != nil {
                card.front = trimmedFront
                card.back = trimmedBack
                StudyStore.save(in: modelContext)
            }
        } else if !deck.isDeleted && deck.modelContext != nil {
            StudyStore.addCard(front: trimmedFront, back: trimmedBack, to: deck, in: modelContext)
        }
        dismiss()
    }

    private func saveAndAddAnother() {
        guard canSave, isNew, !deck.isDeleted, deck.modelContext != nil else { return }
        StudyStore.addCard(front: trimmedFront, back: trimmedBack, to: deck, in: modelContext)
        front = ""
        back = ""
        addedCount += 1
        focusedField = .front
    }
}

private enum DeckCardField: Hashable {
    case front
    case back
}

#Preview("New") {
    DeckCardEditorView(deck: PreviewData.sampleDeck, card: nil)
        .previewEnvironment()
}

#Preview("Edit") {
    let card = PreviewData.sampleDeck.orderedCards.first
    return DeckCardEditorView(
        deck: PreviewData.sampleDeck,
        card: card,
        initialFront: card?.front ?? "",
        initialBack: card?.back ?? ""
    )
    .previewEnvironment()
}
