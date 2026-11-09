//
//  StudySessionCards.swift
//  Haki
//
//  The parts of a study session: the three ways to answer a card (flip it,
//  type the answer, pick from four), the grade buttons with the interval
//  each would give, and the session's queue ("Again" cards come back once
//  at the end).
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

// MARK: - Modes

/// How cards are asked. Remembered between sessions.
nonisolated enum StudyQuizMode: String, CaseIterable, Identifiable {
    case flip
    case typing
    case choice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flip: "Flip cards"
        case .typing: "Type the answer"
        case .choice: "Multiple choice"
        }
    }

    var detail: String {
        switch self {
        case .flip: "See the question, recall the answer, flip the card and grade yourself."
        case .typing: "Type what's on the back. Small typos and capitals don't count against you."
        case .choice: "Pick the right answer from four."
        }
    }

    var systemImage: String {
        switch self {
        case .flip: "rectangle.on.rectangle.angled"
        case .typing: "keyboard"
        case .choice: "list.bullet.rectangle"
        }
    }
}

// MARK: - Queue

/// Where a session is: the cards to ask (cards answered "Again" are added
/// to the end once), how far along it is, and how it's going.
struct StudySessionProgress {
    private(set) var queue: [Flashcard]
    private(set) var position = 0
    /// Cards in the queue before any "Again" cards were added back.
    let firstPassCount: Int
    private(set) var requeuedIDs: Set<UUID> = []
    private(set) var studiedIDs: Set<UUID> = []
    /// Cards remembered the first time they came up this session.
    private(set) var rememberedFirstTime = 0
    /// Cards answered "Again" the first time they came up.
    private(set) var forgottenFirstTime = 0

    init(queue: [Flashcard] = []) {
        self.queue = queue
        firstPassCount = queue.count
    }

    var current: Flashcard? {
        position < queue.count ? queue[position] : nil
    }

    var isFinished: Bool { position >= queue.count }

    /// Whether the current card is one coming back after "Again".
    var isRepeat: Bool { position >= firstPassCount }

    var studiedCount: Int { studiedIDs.count }

    /// Share of cards remembered the first time (nil before any answer).
    var accuracy: Double? {
        studiedIDs.isEmpty ? nil : Double(rememberedFirstTime) / Double(studiedIDs.count)
    }

    mutating func record(_ card: Flashcard, grade: ReviewGrade) {
        let id = card.id
        if !studiedIDs.contains(id) {
            studiedIDs.insert(id)
            if grade == .again {
                forgottenFirstTime += 1
            } else {
                rememberedFirstTime += 1
            }
        }
        if grade == .again && !requeuedIDs.contains(id) {
            requeuedIDs.insert(id)
            queue.append(card)
        }
        position += 1
    }
}

// MARK: - Multiple choice

enum QuizChoices {
    /// The deck's answers with near-duplicates (same once normalized) removed.
    static func distinctAnswers(_ cards: [Flashcard]) -> [String] {
        var seen = Set<String>()
        var answers: [String] = []
        for card in cards {
            let key = AnswerChecker.normalize(card.back)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            answers.append(card.back)
        }
        return answers
    }

    /// Multiple choice needs the right answer plus three different wrong ones.
    static func isAvailable(answers: [String]) -> Bool {
        answers.count >= 4
    }

    /// The right answer and up to three others from `pool`, shuffled.
    static func make(answer: String, from pool: [String]) -> [String] {
        var seen: Set<String> = [AnswerChecker.normalize(answer)]
        var distractors: [String] = []
        for candidate in pool.shuffled() {
            let key = AnswerChecker.normalize(candidate)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            distractors.append(candidate)
            if distractors.count == 3 { break }
        }
        return (distractors + [answer]).shuffled()
    }
}

// MARK: - Card face

/// One side of a flashcard: a small caption ("Question") over large text.
struct StudyCardFace: View {
    let caption: String
    let text: String
    var detail: String? = nil
    var tint: Color = .accentColor

    @ScaledMetric(relativeTo: .title2) private var minHeight: CGFloat = 230

    var body: some View {
        VStack(spacing: 14) {
            Text(caption.uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 12, x: 0, y: 4)
    }
}

// MARK: - Grade buttons

/// Again / Hard / Good / Easy, each with when the card would come back.
struct StudyGradeButtons: View {
    let intervals: [ReviewGrade: String]
    let onGrade: (ReviewGrade) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columnCount = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: columnCount)
        VStack(spacing: 10) {
            Text("How well did you know it?")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ReviewGrade.allCases) { grade in
                    gradeButton(grade)
                }
            }
        }
    }

    private func gradeButton(_ grade: ReviewGrade) -> some View {
        let interval = intervals[grade] ?? ""
        let tint = StudyGradeStyle.tint(grade)
        return Button {
            onGrade(grade)
        } label: {
            VStack(spacing: 3) {
                Text(grade.title)
                    .font(.subheadline.weight(.semibold))
                Text(interval)
                    .font(.caption)
                    .monospacedDigit()
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(grade.title)
        .accessibilityValue(interval.isEmpty ? "" : "Next review in \(StudyFormat.spokenInterval(interval))")
    }
}

enum StudyGradeStyle {
    static func tint(_ grade: ReviewGrade) -> Color {
        switch grade {
        case .again: return Color.hakiNegative
        case .hard: return Color.hakiWarning
        case .good: return Color.hakiPositive
        case .easy: return Color.blue
        }
    }
}

// MARK: - Flip

/// Shows the question; tap to flip it over (a 3D turn, or a fade with Reduce
/// Motion), then grade how well you knew it.
struct StudyFlipCard: View {
    let card: Flashcard
    let onGrade: (ReviewGrade) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isFlipped = false

    var body: some View {
        VStack(spacing: 20) {
            flippingCard
            controls
        }
    }

    private var flippingCard: some View {
        Button {
            flip()
        } label: {
            ZStack {
                StudyCardFace(caption: "Question", text: card.front)
                    .opacity(isFlipped ? 0 : 1)
                StudyCardFace(caption: "Answer", text: card.back, detail: card.front, tint: Color.hakiPositive)
                    .rotation3DEffect(.degrees(reduceMotion ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    .opacity(isFlipped ? 1 : 0)
            }
            .rotation3DEffect(.degrees(isFlipped && !reduceMotion ? 180 : 0), axis: (x: 0, y: 1, z: 0))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFlipped ? "Answer: \(card.back)" : "Question: \(card.front)")
        .accessibilityHint(isFlipped ? "Double-tap to see the question again" : "Double-tap to show the answer")
    }

    @ViewBuilder
    private var controls: some View {
        if isFlipped {
            StudyGradeButtons(
                intervals: SpacedRepetition.previewIntervals(card.schedule, now: .now),
                onGrade: onGrade
            )
            .transition(.opacity)
        } else {
            Button {
                flip()
            } label: {
                Text("Show answer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .transition(.opacity)
        }
    }

    private func flip() {
        let animation: Animation = reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.15)
        withAnimation(animation) {
            isFlipped.toggle()
        }
    }
}

// MARK: - Type the answer

/// Shows the question and a field for the answer. "Check" compares it with
/// `AnswerChecker` (forgiving about case, accents and a small typo); a wrong
/// answer counts as "Again" unless the person says they were right.
struct StudyTypeCard: View {
    let card: Flashcard
    let onGrade: (ReviewGrade) -> Void

    @State private var typed = ""
    @State private var verdict: StudyTypedVerdict? = nil
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(spacing: 20) {
            StudyCardFace(caption: "Question", text: card.front)
            if let verdict {
                result(verdict)
                    .transition(.opacity)
            } else {
                entry
                    .transition(.opacity)
            }
        }
    }

    private var trimmedTyped: String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var entry: some View {
        VStack(spacing: 12) {
            TextField("Type your answer", text: $typed)
                .font(.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFieldFocused)
                .onSubmit { check() }
                .padding(14)
                .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel("Your answer")
            HStack(spacing: 10) {
                Button {
                    reveal()
                } label: {
                    Text("I don't know")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                Button {
                    check()
                } label: {
                    Text("Check")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(trimmedTyped.isEmpty)
            }
        }
        .onAppear { isFieldFocused = true }
    }

    private func result(_ verdict: StudyTypedVerdict) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(verdict.isCorrect ? "Correct" : "Not quite", systemImage: verdict.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.headline)
                .foregroundStyle(verdict.isCorrect ? Color.hakiPositive : Color.hakiNegative)
            if !verdict.typed.isEmpty {
                answerLine(title: "You wrote", text: verdict.typed)
            }
            answerLine(title: "Answer", text: card.back)
            resultButtons(isCorrect: verdict.isCorrect)
        }
        .hakiCard()
    }

    private func answerLine(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func resultButtons(isCorrect: Bool) -> some View {
        if isCorrect {
            continueButton(grade: .good)
        } else {
            HStack(spacing: 10) {
                Button {
                    onGrade(.good)
                } label: {
                    Text("I was right")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .accessibilityHint("Counts this card as remembered")
                continueButton(grade: .again)
            }
        }
    }

    private func continueButton(grade: ReviewGrade) -> some View {
        Button {
            onGrade(grade)
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func check() {
        let answer = trimmedTyped
        guard !answer.isEmpty else { return }
        let isCorrect = AnswerChecker.isCorrect(typed: answer, expected: card.back)
        isFieldFocused = false
        withAnimation(.snappy) {
            verdict = StudyTypedVerdict(isCorrect: isCorrect, typed: answer)
        }
        UIAccessibility.post(notification: .announcement, argument: isCorrect ? "Correct" : "Not quite. The answer is \(card.back)")
    }

    private func reveal() {
        isFieldFocused = false
        withAnimation(.snappy) {
            verdict = StudyTypedVerdict(isCorrect: false, typed: "")
        }
    }
}

/// The result of checking a typed answer.
struct StudyTypedVerdict {
    let isCorrect: Bool
    let typed: String
}

// MARK: - Multiple choice

/// Shows the question and four answers. Picking one reveals which is right
/// (with a check or a cross, never color alone); "Continue" grades it Good
/// or Again.
struct StudyChoiceCard: View {
    let card: Flashcard
    let onGrade: (ReviewGrade) -> Void

    @State private var options: [String]
    @State private var chosenIndex: Int? = nil

    init(card: Flashcard, otherAnswers: [String], onGrade: @escaping (ReviewGrade) -> Void) {
        self.card = card
        self.onGrade = onGrade
        _options = State(initialValue: QuizChoices.make(answer: card.back, from: otherAnswers))
    }

    var body: some View {
        VStack(spacing: 16) {
            StudyCardFace(caption: "Question", text: card.front)
            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    optionButton(index: index, text: option)
                }
            }
            if let chosenIndex {
                continueButton(wasRight: isRight(chosenIndex))
                    .transition(.opacity)
            }
        }
    }

    private func isRight(_ index: Int) -> Bool {
        index < options.count && options[index] == card.back
    }

    private func optionButton(index: Int, text: String) -> some View {
        let look = optionLook(index)
        return Button {
            choose(index)
        } label: {
            HStack(spacing: 12) {
                Text(text)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let symbol = look.symbol {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(look.tint)
                        .accessibilityHidden(true)
                }
            }
            .padding(16)
            .background(look.tint.opacity(look.isHighlighted ? 0.14 : 0), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(look.isHighlighted ? look.tint : Color.secondary.opacity(0.2), lineWidth: look.isHighlighted ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(look.isDimmed ? 0.55 : 1)
        .accessibilityValue(look.spokenState)
        .accessibilityHint(chosenIndex == nil ? "Choose this answer" : "")
    }

    private func optionLook(_ index: Int) -> StudyChoiceLook {
        guard let chosenIndex else { return StudyChoiceLook.plain }
        if isRight(index) { return StudyChoiceLook.correct }
        if index == chosenIndex { return StudyChoiceLook.wrongPick }
        return StudyChoiceLook.dimmed
    }

    private func continueButton(wasRight: Bool) -> some View {
        Button {
            onGrade(wasRight ? .good : .again)
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func choose(_ index: Int) {
        guard chosenIndex == nil else { return }
        withAnimation(.snappy) {
            chosenIndex = index
        }
        let message = isRight(index) ? "Correct" : "Not quite. The answer is \(card.back)"
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

/// How an answer looks once one has been picked.
struct StudyChoiceLook {
    let symbol: String?
    let tint: Color
    let isHighlighted: Bool
    let isDimmed: Bool
    let spokenState: String

    static let plain = StudyChoiceLook(symbol: nil, tint: Color.accentColor, isHighlighted: false, isDimmed: false, spokenState: "")
    static let correct = StudyChoiceLook(symbol: "checkmark.circle.fill", tint: Color.hakiPositive, isHighlighted: true, isDimmed: false, spokenState: "Correct answer")
    static let wrongPick = StudyChoiceLook(symbol: "xmark.circle.fill", tint: Color.hakiNegative, isHighlighted: true, isDimmed: false, spokenState: "Your answer, incorrect")
    static let dimmed = StudyChoiceLook(symbol: nil, tint: Color.secondary, isHighlighted: false, isDimmed: true, spokenState: "")
}

// MARK: - Previews

#Preview("Flip") {
    ScrollView {
        if let card = PreviewData.sampleDeck.orderedCards.first {
            StudyFlipCard(card: card, onGrade: { _ in })
                .padding()
        }
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}

#Preview("Type the answer") {
    ScrollView {
        if let card = PreviewData.sampleDeck.orderedCards.first {
            StudyTypeCard(card: card, onGrade: { _ in })
                .padding()
        }
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}

#Preview("Multiple choice") {
    ScrollView {
        if let card = PreviewData.sampleDeck.orderedCards.first {
            StudyChoiceCard(
                card: card,
                otherAnswers: QuizChoices.distinctAnswers(PreviewData.sampleDeck.orderedCards),
                onGrade: { _ in }
            )
            .padding()
        }
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
