//
//  AssistantSuggestedQuestions.swift
//  Haki
//
//  Starter questions for "Ask Haki", across money, health, workouts,
//  wardrobe and notes. The chat's empty state shows all of them; other
//  screens (the You tab's card) show the first few, which cover different
//  parts of the app.
//

import Foundation

nonisolated enum AssistantSuggestedQuestions {
    static let all: [String] = suggestions.map(\.question)

    /// An SF Symbol for a suggested question ("sparkles" for any other text).
    static func systemImage(for question: String) -> String {
        suggestions.first(where: { $0.question == question })?.systemImage ?? "sparkles"
    }

    private static let suggestions: [AssistantSuggestion] = [
        AssistantSuggestion(question: "How much have I spent this month, and on what?", systemImage: "chart.pie"),
        AssistantSuggestion(question: "How's my protein this week compared with my goal?", systemImage: "fork.knife"),
        AssistantSuggestion(question: "What should I wear to a casual dinner this weekend?", systemImage: "hanger"),
        AssistantSuggestion(question: "Am I on track with my budgets?", systemImage: "chart.bar"),
        AssistantSuggestion(question: "How have my workouts been going lately?", systemImage: "dumbbell"),
        AssistantSuggestion(question: "Which flashcards should I study today?", systemImage: "rectangle.on.rectangle.angled"),
        AssistantSuggestion(question: "What bills are coming up in the next two weeks?", systemImage: "arrow.triangle.2.circlepath"),
        AssistantSuggestion(question: "Where could I cut back to save more next month?", systemImage: "lightbulb"),
        AssistantSuggestion(question: "What did I write about in my recent notes?", systemImage: "note.text"),
        AssistantSuggestion(question: "How are my investments doing?", systemImage: "chart.line.uptrend.xyaxis"),
    ]
}

private nonisolated struct AssistantSuggestion: Sendable {
    let question: String
    let systemImage: String
}
