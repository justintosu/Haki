//
//  YouAskHakiCard.swift
//  Haki
//
//  The You tab's "Ask Haki" card: three starter questions (a different set
//  each day) that open the assistant already asking them, and "Open chat"
//  for a blank conversation.
//

import Foundation
import SwiftUI

struct YouAskHakiCard: View {
    @State private var chatRequest: YouChatRequest?
    @ScaledMetric(relativeTo: .title3) private var badgeSize: CGFloat = 44

    init() {}

    var body: some View {
        let questions = Self.questions(forDay: Self.dayNumber(for: .now))
        VStack(alignment: .leading, spacing: 14) {
            header
            if !questions.isEmpty {
                suggestionList(questions)
            }
            openChatButton
            disclaimer
        }
        .hakiCard()
        .sheet(item: $chatRequest) { request in
            AssistantChatView(initialQuestion: request.question)
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: badgeSize, height: badgeSize)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Ask Haki")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text("Questions about your spending, meals, workouts, wardrobe and notes, answered from what's on your iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private func suggestionList(_ questions: [String]) -> some View {
        VStack(spacing: 8) {
            ForEach(questions, id: \.self) { question in
                YouSuggestionButton(question: question, systemImage: Self.systemImage(for: question)) {
                    chatRequest = YouChatRequest(question: question)
                }
            }
        }
    }

    private var openChatButton: some View {
        Button {
            chatRequest = YouChatRequest(question: nil)
        } label: {
            Label("Open chat", systemImage: "bubble.left.and.bubble.right")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityHint("Starts a new conversation with Haki")
    }

    private var disclaimer: some View {
        Text("Answers can be wrong. Not financial or medical advice.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .multilineTextAlignment(.center)
    }

    // MARK: Helpers

    /// How many starter questions the card shows.
    private static let suggestionCount = 3

    /// Today's starter questions: consecutive ones from the list (which mixes
    /// topics), starting at a different place each day.
    private static func questions(forDay day: Int) -> [String] {
        let all = AssistantSuggestedQuestions.all
        guard !all.isEmpty else { return [] }
        let count = min(suggestionCount, all.count)
        let start = ((day * count) % all.count + all.count) % all.count
        var result: [String] = []
        for offset in 0..<count {
            result.append(all[(start + offset) % all.count])
        }
        return result
    }

    /// Days since a fixed reference date, in the current calendar.
    private static func dayNumber(for date: Date) -> Int {
        Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
    }

    /// An SF Symbol matching a question's topic.
    private static func systemImage(for question: String) -> String {
        let text = question.lowercased()
        for topic in YouQuestionTopic.all {
            for keyword in topic.keywords where text.contains(keyword) {
                return topic.systemImage
            }
        }
        return "sparkles"
    }
}

/// Words that mark a question's topic, and the topic's icon. Checked in
/// order, so the more specific topics come first.
private nonisolated struct YouQuestionTopic: Sendable {
    let keywords: [String]
    let systemImage: String

    static let all: [YouQuestionTopic] = [
        YouQuestionTopic(keywords: ["invest", "portfolio", "stock"], systemImage: "chart.line.uptrend.xyaxis"),
        YouQuestionTopic(keywords: ["budget"], systemImage: "chart.bar"),
        YouQuestionTopic(keywords: ["bill", "subscription"], systemImage: "arrow.triangle.2.circlepath"),
        YouQuestionTopic(keywords: ["cut back", "save"], systemImage: "lightbulb"),
        YouQuestionTopic(keywords: ["spent", "spend", "money"], systemImage: "chart.pie"),
        YouQuestionTopic(keywords: ["protein", "calorie", "meal", "food", "nutrition"], systemImage: "fork.knife"),
        YouQuestionTopic(keywords: ["workout", "gym", "lift"], systemImage: "dumbbell"),
        YouQuestionTopic(keywords: ["wear", "outfit", "wardrobe"], systemImage: "hanger"),
        YouQuestionTopic(keywords: ["flashcard", "study", "quiz"], systemImage: "rectangle.on.rectangle.angled"),
        YouQuestionTopic(keywords: ["note"], systemImage: "note.text"),
    ]
}

/// A question the assistant should start with (`nil` opens a blank chat).
private nonisolated struct YouChatRequest: Identifiable {
    let id = UUID()
    let question: String?
}

/// One starter question as a tappable row.
private struct YouSuggestionButton: View {
    let question: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(question)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Asks Haki this question")
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            YouAskHakiCard()
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
