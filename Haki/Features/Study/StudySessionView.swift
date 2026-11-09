//
//  StudySessionView.swift
//  Haki
//
//  A study session for one deck, full screen in its own NavigationStack.
//  The queue (due reviews, then today's new cards) is worked out once when
//  it opens; when nothing is due it goes through every card instead and says
//  so. Pick how to answer (flip, type it, multiple choice; remembered), then
//  each answer reschedules the card. Cards answered "Again" come back once
//  at the end. A summary closes the session.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct StudySessionView: View {
    let deck: FlashcardDeck
    /// Go through every card in the deck (shuffled), due or not.
    let cramsAllCards: Bool

    init(deck: FlashcardDeck, cramsAllCards: Bool = false) {
        self.deck = deck
        self.cramsAllCards = cramsAllCards
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("study.sessionMode") private var savedMode: StudyQuizMode = .flip

    @State private var stage: StudySessionStage = .setup
    @State private var mode: StudyQuizMode = .flip
    @State private var plannedQueue: [Flashcard] = []
    @State private var isCramming = false
    @State private var fellBackToCramming = false
    @State private var choiceAnswers: [String] = []
    @State private var progress = StudySessionProgress()
    @State private var hasPrepared = false
    @State private var showsEndConfirmation = false
    @State private var finishFeedback = 0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(isDeckGone ? "Study" : deck.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            close()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close")
                    }
                }
                .confirmationDialog("End this session?", isPresented: $showsEndConfirmation, titleVisibility: .visible) {
                    Button("End session", role: .destructive) { dismiss() }
                    Button("Keep studying", role: .cancel) {}
                } message: {
                    Text("Cards you've already answered keep their new schedule.")
                }
        }
        .onAppear { prepareIfNeeded() }
        .sensoryFeedback(.success, trigger: finishFeedback)
    }

    // MARK: Content

    private var isDeckGone: Bool {
        deck.isDeleted || deck.modelContext == nil
    }

    @ViewBuilder
    private var content: some View {
        if isDeckGone {
            ContentUnavailableView(
                "Deck deleted",
                systemImage: "rectangle.stack",
                description: Text("This deck is no longer here.")
            )
        } else {
            switch stage {
            case .setup:
                setupScreen
            case .studying:
                studyingScreen
            case .finished:
                summaryScreen
            }
        }
    }

    @ViewBuilder
    private var setupScreen: some View {
        if !hasPrepared {
            Color.hakiBackground
                .ignoresSafeArea()
        } else if plannedQueue.isEmpty {
            ContentUnavailableView {
                Label("No cards to study", systemImage: "rectangle.stack")
            } description: {
                Text("Add some cards to this deck first.")
            } actions: {
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hakiBackground)
        } else {
            StudySessionSetupView(
                queueCount: plannedQueue.count,
                reviewCount: plannedQueue.filter { !$0.schedule.isNew }.count,
                newCount: plannedQueue.filter { $0.schedule.isNew }.count,
                isCramming: isCramming,
                fellBackToCramming: fellBackToCramming,
                modes: availableModes,
                mode: $mode,
                onStart: { start() }
            )
        }
    }

    private var studyingScreen: some View {
        VStack(spacing: 0) {
            StudySessionProgressHeader(
                position: progress.position,
                total: progress.queue.count,
                isRepeat: progress.isRepeat
            )
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 4)
            ScrollView {
                currentCard
                    .padding(.horizontal)
                    .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color.hakiBackground)
    }

    @ViewBuilder
    private var currentCard: some View {
        if let card = progress.current {
            cardView(for: card)
                .id(progress.position)
                .transition(cardTransition)
        }
    }

    @ViewBuilder
    private func cardView(for card: Flashcard) -> some View {
        switch mode {
        case .flip:
            StudyFlipCard(card: card, onGrade: { grade in answer(card, grade: grade) })
        case .typing:
            StudyTypeCard(card: card, onGrade: { grade in answer(card, grade: grade) })
        case .choice:
            StudyChoiceCard(card: card, otherAnswers: choiceAnswers, onGrade: { grade in answer(card, grade: grade) })
        }
    }

    private var cardTransition: AnyTransition {
        if reduceMotion { return AnyTransition.opacity }
        return AnyTransition.asymmetric(
            insertion: AnyTransition.move(edge: .trailing).combined(with: .opacity),
            removal: AnyTransition.move(edge: .leading).combined(with: .opacity)
        )
    }

    private var summaryScreen: some View {
        StudySessionSummaryView(
            studied: progress.studiedCount,
            accuracy: progress.accuracy,
            forgotten: progress.forgottenFirstTime,
            nextReview: nextReviewText,
            wasCramming: isCramming,
            onStudyAgain: { studyAgain() },
            onDone: { dismiss() }
        )
    }

    // MARK: Modes

    private var canUseChoice: Bool {
        QuizChoices.isAvailable(answers: choiceAnswers)
    }

    private var availableModes: [StudyQuizMode] {
        StudyQuizMode.allCases.filter { $0 != .choice || canUseChoice }
    }

    // MARK: Actions

    private func prepareIfNeeded() {
        guard !hasPrepared, !isDeckGone else { return }
        hasPrepared = true
        loadQueue()
        choiceAnswers = QuizChoices.distinctAnswers(StudyCards.live(in: deck))
        mode = savedMode
        if mode == .choice && !canUseChoice {
            mode = .flip
        }
    }

    /// Due cards and today's new ones; every card (shuffled) when cramming
    /// or when nothing is due.
    private func loadQueue() {
        if cramsAllCards {
            plannedQueue = StudyStore.studyQueue(for: deck, includeAll: true).shuffled()
            isCramming = true
            fellBackToCramming = false
            return
        }
        let queue = StudyStore.studyQueue(for: deck)
        if queue.isEmpty {
            plannedQueue = StudyStore.studyQueue(for: deck, includeAll: true).shuffled()
            isCramming = true
            fellBackToCramming = !plannedQueue.isEmpty
        } else {
            plannedQueue = queue
            isCramming = false
            fellBackToCramming = false
        }
    }

    private func start() {
        savedMode = mode
        progress = StudySessionProgress(queue: plannedQueue)
        withAnimation(.snappy) {
            stage = progress.isFinished ? .finished : .studying
        }
    }

    private func answer(_ card: Flashcard, grade: ReviewGrade) {
        if !card.isDeleted && card.modelContext != nil {
            StudyStore.review(card, grade: grade, in: modelContext)
        }
        let animation: Animation? = reduceMotion ? nil : Animation.snappy
        withAnimation(animation) {
            progress.record(card, grade: grade)
        }
        if progress.isFinished {
            finish()
        }
    }

    private func finish() {
        withAnimation(.snappy) {
            stage = .finished
        }
        finishFeedback += 1
        UIAccessibility.post(notification: .announcement, argument: "Session complete")
    }

    private func studyAgain() {
        guard !isDeckGone else { return }
        loadQueue()
        choiceAnswers = QuizChoices.distinctAnswers(StudyCards.live(in: deck))
        if mode == .choice && !canUseChoice {
            mode = .flip
        }
        progress = StudySessionProgress(queue: plannedQueue)
        withAnimation(.snappy) {
            stage = plannedQueue.isEmpty ? .setup : .studying
        }
    }

    private func close() {
        if stage == .studying && progress.position > 0 && !progress.isFinished {
            showsEndConfirmation = true
        } else {
            dismiss()
        }
    }

    /// "Next review in 10 minutes", "3 cards still due", ...
    private var nextReviewText: String {
        guard !isDeckGone else { return "" }
        let now = Date.now
        let cards = StudyCards.live(in: deck)
        let stillDue = cards.filter { !$0.schedule.isNew && SpacedRepetition.isDue($0.schedule, now: now) }.count
        if stillDue > 0 {
            return stillDue == 1 ? "1 card is still due" : "\(stillDue) cards are still due"
        }
        let upcoming = cards.compactMap { $0.dueAt }.filter { $0 > now }.min()
        if let upcoming {
            return "Next review \(upcoming.formatted(.relative(presentation: .named)))"
        }
        if cards.contains(where: { $0.schedule.isNew }) {
            return "New cards are waiting"
        }
        return "Nothing scheduled yet"
    }
}

private enum StudySessionStage {
    case setup
    case studying
    case finished
}

// MARK: - Setup

/// Before the first card: what's in the session and how to answer.
private struct StudySessionSetupView: View {
    let queueCount: Int
    let reviewCount: Int
    let newCount: Int
    let isCramming: Bool
    let fellBackToCramming: Bool
    let modes: [StudyQuizMode]
    @Binding var mode: StudyQuizMode
    let onStart: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 52

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                overview
                if fellBackToCramming {
                    cramNote
                }
                modePicker
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .safeAreaInset(edge: .bottom) {
            Button {
                onStart()
            } label: {
                Text("Start")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private var overview: some View {
        VStack(spacing: 10) {
            Image(systemName: isCramming ? "arrow.triangle.2.circlepath" : "brain.head.profile")
                .font(.system(size: iconSize))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(StudyFormat.cards(queueCount))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .hakiCard()
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        if isCramming {
            return "Every card in the deck, shuffled."
        }
        return StudyFormat.breakdown(reviews: reviewCount, fresh: newCount)
    }

    private var cramNote: some View {
        Label {
            Text("Nothing is due right now, so this session goes through every card. Your answers still update when each card comes back.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.accentColor)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hakiCard()
    }

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("How do you want to answer?")
            VStack(spacing: 8) {
                ForEach(modes) { option in
                    Button {
                        mode = option
                    } label: {
                        StudyModeRow(mode: option, isSelected: mode == option)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(mode == option ? .isSelected : [])
                }
            }
            if !modes.contains(.choice) {
                Text("Multiple choice needs at least four cards with different answers.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .hakiCard()
    }
}

/// A mode to pick: icon, title, what it's like, and a check when chosen.
private struct StudyModeRow: View {
    let mode: StudyQuizMode
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            StudyIconTile(systemImage: mode.systemImage, tint: isSelected ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(mode.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
        }
        .padding(12)
        .background(
            isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Progress

/// The bar across the top: how far along, "3 of 12", and a note on repeats.
private struct StudySessionProgressHeader: View {
    let position: Int
    let total: Int
    let isRepeat: Bool

    var body: some View {
        VStack(spacing: 6) {
            ProgressView(value: Double(min(position, total)), total: Double(max(total, 1)))
                .tint(Color.accentColor)
                .animation(.snappy, value: position)
            HStack {
                Text("\(min(position + 1, max(total, 1))) of \(total)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                if isRepeat {
                    Label("Second try", systemImage: "arrow.uturn.backward")
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(accessibilityText)
    }

    private var accessibilityText: String {
        let card = "Card \(min(position + 1, max(total, 1))) of \(total)"
        return isRepeat ? "\(card), second try" : card
    }
}

// MARK: - Summary

private struct StudySessionSummaryView: View {
    let studied: Int
    let accuracy: Double?
    let forgotten: Int
    let nextReview: String
    let wasCramming: Bool
    let onStudyAgain: () -> Void
    let onDone: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                stats
                if !nextReview.isEmpty {
                    Label(nextReview, systemImage: "calendar.badge.clock")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hakiCard()
                }
            }
            .padding(.horizontal)
            .padding(.top, 32)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .safeAreaInset(edge: .bottom) { buttons }
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(Color.hakiPositive)
                .accessibilityHidden(true)
            Text(wasCramming ? "Practice complete" : "Session complete")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .multilineTextAlignment(.center)
            Text(encouragement)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    private var encouragement: String {
        guard let accuracy else { return "Nice work." }
        if accuracy >= 0.9 { return "Excellent recall!" }
        if accuracy >= 0.7 { return "Nice work. Keep it up." }
        return "Good practice. The tricky ones will come back soon."
    }

    private var stats: some View {
        HStack(spacing: 16) {
            StudyStatTile(title: "Studied", value: "\(studied)")
            StudyStatTile(title: "Accuracy", value: accuracyText)
            StudyStatTile(title: "Forgotten", value: "\(forgotten)")
        }
        .hakiCard()
    }

    private var accuracyText: String {
        guard let accuracy else { return "–" }
        return accuracy.formatted(.percent.precision(.fractionLength(0)))
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                onStudyAgain()
            } label: {
                Text("Study again")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            Button {
                onDone()
            } label: {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
        .background(Color.hakiBackground)
    }
}

#Preview {
    StudySessionView(deck: PreviewData.sampleDeck)
        .previewEnvironment()
}

#Preview("Cram") {
    StudySessionView(deck: PreviewData.sampleDeck, cramsAllCards: true)
        .previewEnvironment()
}
