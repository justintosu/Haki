//
//  FlashcardMakerView.swift
//  Haki
//
//  "Make flashcards with AI" for a note, in a sheet with its own
//  NavigationStack: choose how many cards, Haki's AI writes them from the
//  note's text, then the person keeps, skips or edits each one before
//  saving them as a deck (which the note editor then opens).
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct FlashcardMakerView: View {
    /// The note's own title ("" when it has none).
    let noteTitle: String
    let noteText: String
    /// The new deck's name (the note's display title).
    let deckName: String
    let noteID: UUID
    /// Called with the saved deck just before the sheet closes.
    let onSaved: (FlashcardDeck) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HakiAIService.self) private var hakiAI

    @State private var count = 12
    @State private var phase: FlashcardMakerPhase = .setup
    @State private var drafts: [FlashcardMakerDraft] = []
    @State private var aiNotes = ""
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @State private var showsDiscardConfirmation = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(phase == .review ? "Review cards" : "AI flashcards")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .confirmationDialog("Discard these cards?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                    Button("Discard cards", role: .destructive) { dismiss() }
                    Button("Keep reviewing", role: .cancel) {}
                } message: {
                    Text("The cards Haki wrote won't be saved.")
                }
        }
        .interactiveDismissDisabled(phase != .setup)
        .onDisappear { task?.cancel() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .setup:
            setupScreen
        case .working:
            workingScreen
        case .review:
            reviewList
        }
    }

    // MARK: Setup

    private var setupScreen: some View {
        ScrollView {
            VStack(spacing: 16) {
                intro
                countCard
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.hakiWarning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .hakiCard()
                }
                Button {
                    generate()
                } label: {
                    Label(errorMessage == nil ? "Make \(count) flashcards" : "Try again", systemImage: "sparkles")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("Haki sends this note's text to Claude to write the cards, and you check them before anything is saved. AI can make mistakes.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
    }

    private var intro: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.largeTitle)
                .foregroundStyle(Color.purple)
                .accessibilityHidden(true)
            Text("Turn “\(deckName)” into flashcards")
                .font(.title3.weight(.bold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Question-and-answer cards about the main ideas in your note, ready to study with spaced repetition.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .hakiCard()
    }

    private var countCard: some View {
        Stepper(value: $count, in: 5...30) {
            HStack {
                Text("Number of cards")
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.headline)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .hakiCard()
    }

    // MARK: Working

    private var workingScreen: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Text("Writing \(count) flashcards…")
                .font(.headline)
            Text("This usually takes a few seconds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Cancel", role: .cancel) {
                cancelGenerating()
            }
            .buttonStyle(.bordered)
            .padding(.top, 8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hakiBackground)
        .accessibilityElement(children: .contain)
    }

    // MARK: Review

    private var keptCount: Int {
        drafts.filter { $0.keep && $0.isComplete }.count
    }

    private var reviewList: some View {
        List {
            Section {
                ForEach($drafts) { $draft in
                    FlashcardMakerDraftRow(draft: $draft)
                }
            } header: {
                Text("\(StudyFormat.cards(drafts.count)) · \(keptCount) kept")
                    .monospacedDigit()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Tap a card's text to edit it. Unticked cards aren't saved.")
                    if !aiNotes.isEmpty {
                        Text(aiNotes)
                    }
                }
            }
            Section {
                Button {
                    startOver()
                } label: {
                    Label("Start over", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { cancel() }
        }
        ToolbarItem(placement: .confirmationAction) {
            if phase == .review {
                Button("Save deck") { save() }
                    .disabled(keptCount == 0)
            }
        }
    }

    // MARK: Actions

    private func generate() {
        let text = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        task?.cancel()
        errorMessage = nil
        let trimmedTitle = noteTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title: String? = trimmedTitle.isEmpty ? nil : trimmedTitle
        let requested = count
        withAnimation(.snappy) { phase = .working }
        UIAccessibility.post(notification: .announcement, argument: "Writing flashcards")
        task = Task {
            do {
                let report = try await hakiAI.makeFlashcards(title: title, text: text, count: requested)
                guard !Task.isCancelled else { return }
                show(report)
            } catch {
                guard !Task.isCancelled else { return }
                if !Backend.isCancellation(error) {
                    errorMessage = error.localizedDescription
                }
                withAnimation(.snappy) { phase = .setup }
            }
        }
    }

    private func show(_ report: FlashcardDraftReport) {
        let made = report.cards.map { FlashcardMakerDraft(front: $0.front, back: $0.back) }
        aiNotes = report.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !made.isEmpty else {
            errorMessage = aiNotes.isEmpty ? "Haki couldn't find enough in this note to make cards. Try adding more detail." : aiNotes
            withAnimation(.snappy) { phase = .setup }
            return
        }
        drafts = made
        withAnimation(.snappy) { phase = .review }
        UIAccessibility.post(notification: .announcement, argument: "\(StudyFormat.cards(made.count)) ready to review")
    }

    private func cancelGenerating() {
        task?.cancel()
        task = nil
        withAnimation(.snappy) { phase = .setup }
    }

    private func startOver() {
        drafts = []
        aiNotes = ""
        withAnimation(.snappy) { phase = .setup }
    }

    private func cancel() {
        if phase == .review && keptCount > 0 {
            showsDiscardConfirmation = true
            return
        }
        task?.cancel()
        dismiss()
    }

    private func save() {
        let cards = drafts
            .filter { $0.keep && $0.isComplete }
            .map { FlashcardDraft(front: $0.front, back: $0.back) }
        guard !cards.isEmpty else { return }
        let deck = StudyStore.createDeck(name: deckName, sourceNoteID: noteID, cards: cards, in: modelContext)
        onSaved(deck)
        dismiss()
    }
}

private enum FlashcardMakerPhase {
    case setup
    case working
    case review
}

/// A card the AI wrote, while the person reviews it.
private struct FlashcardMakerDraft: Identifiable {
    let id = UUID()
    var front: String
    var back: String
    var keep = true

    var isComplete: Bool {
        !front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Keep toggle plus editable front and back.
private struct FlashcardMakerDraftRow: View {
    @Binding var draft: FlashcardMakerDraft
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                draft.keep.toggle()
            } label: {
                Image(systemName: draft.keep ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(draft.keep ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Keep this card")
            .accessibilityValue(draft.keep ? "On" : "Off")

            VStack(alignment: .leading, spacing: 0) {
                TextField("Question", text: $draft.front, axis: .vertical)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
                    // Drawn over the field rather than as its own stack item: an inline
                    // Divider vanished on drafts whose question wraps to two lines.
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(Color(uiColor: .separator))
                            .frame(height: 1 / displayScale)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                TextField("Answer", text: $draft.back, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(draft.keep ? 1 : 0.45)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    FlashcardMakerView(
        noteTitle: PreviewData.sampleNote.title,
        noteText: PreviewData.sampleNote.body,
        deckName: PreviewData.sampleNote.displayTitle,
        noteID: PreviewData.sampleNote.id,
        onSaved: { _ in }
    )
    .previewEnvironment()
}
