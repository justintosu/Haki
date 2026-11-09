//
//  AssistantChatComponents.swift
//  Haki
//
//  The pieces of the "Ask Haki" chat: message bubbles, the "Looked at" row,
//  the typing indicator, the inline error card, the empty-state intro and
//  the composer.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Messages

/// One message: the person's on the right, Haki's on the left.
struct AssistantBubbleRow: View {
    let item: AssistantChatItem

    var body: some View {
        switch item.role {
        case .user:
            AssistantUserBubble(text: item.text)
        case .assistant:
            if item.isInterim {
                AssistantInterimNote(item: item)
            } else {
                AssistantAnswerBubble(item: item)
            }
        }
    }
}

private struct AssistantUserBubble: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(verbatim: text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "You: " + text))
        .accessibilityAction(named: Text("Copy")) {
            UIPasteboard.general.string = text
        }
    }
}

private struct AssistantAnswerBubble: View {
    let item: AssistantChatItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AssistantAvatar()
            VStack(alignment: .leading, spacing: 6) {
                AssistantMarkdownView(blocks: item.blocks)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                if !item.tools.isEmpty {
                    AssistantLookedAtRow(tools: item.tools)
                        .padding(.horizontal, 6)
                }
            }
            Spacer(minLength: 24)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
        .accessibilityAction(named: Text("Copy")) {
            UIPasteboard.general.string = plainText
        }
    }

    private var plainText: String {
        item.blocks.map(\.plainText).joined(separator: "\n")
    }

    private var accessibilityText: String {
        var parts = ["Haki: " + plainText]
        if !item.tools.isEmpty {
            parts.append(AssistantLookedAtRow.summary(for: item.tools))
        }
        return parts.joined(separator: ". ")
    }
}

/// Text that came with a lookup ("Let me check your budgets."), shown small.
private struct AssistantInterimNote: View {
    let item: AssistantChatItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(AssistantMarkdown.inline(item.text))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
        }
        .padding(.leading, 6)
        .accessibilityElement(children: .combine)
    }
}

/// Haki's small round badge next to its answers.
struct AssistantAvatar: View {
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 30

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

/// "Looked at: Spending · Budgets" with each tool's icon.
struct AssistantLookedAtRow: View {
    let tools: [AssistantTool]

    var body: some View {
        line
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(Self.summary(for: tools)))
    }

    private var line: Text {
        var result = Text("Looked at:")
        for (index, tool) in tools.enumerated() {
            let separator = index == 0 ? " " : "  ·  "
            let icon = Image(systemName: tool.systemImage)
            result = Text("\(result)\(separator)\(icon) \(tool.dataTitle)")
        }
        return result
    }

    /// "Looked at: Spending, Budgets"
    static func summary(for tools: [AssistantTool]) -> String {
        "Looked at: " + tools.map(\.dataTitle).joined(separator: ", ")
    }
}

// MARK: - Status

/// Shown while a request runs: what Haki is doing, and Cancel.
struct AssistantTypingIndicator: View {
    let activity: AssistantActivity
    /// False right after an interim note ("Let me check your budgets."),
    /// which already says what Haki is doing; VoiceOver still reads the status.
    var showsStatusText: Bool = true
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            AssistantAvatar()
            HStack(spacing: 8) {
                AssistantTypingDots()
                if showsStatusText {
                    Text(activity.statusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(activity.statusText))
            .accessibilityAddTraits(.updatesFrequently)
            Spacer(minLength: 8)
            Button("Cancel", action: onCancel)
                .font(.subheadline.weight(.semibold))
                .accessibilityHint("Stops this answer")
        }
        .animation(.easeInOut(duration: 0.2), value: activity)
        // Outside the animation: the row moves with the chat (e.g. when an
        // interim note is inserted above it); only its contents animate.
        .geometryGroup()
    }
}

/// Three dots that light up in turn (static with Reduce Motion).
private struct AssistantTypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var dotSize: CGFloat = 6

    var body: some View {
        if reduceMotion {
            dots(highlighted: -1)
        } else {
            PhaseAnimator([0, 1, 2]) { phase in
                dots(highlighted: phase)
            } animation: { _ in
                .easeInOut(duration: 0.35)
            }
        }
    }

    private func dots(highlighted: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(index == highlighted ? 1 : 0.35)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The last request ended without an answer: why, and a way to try again.
struct AssistantProblemCard: View {
    let problem: AssistantProblem
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label {
                Text(problem.message)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: problem.systemImage)
                    .foregroundStyle(problem.isError ? Color.hakiWarning : Color.secondary)
            }
            .font(.subheadline)
            Button(action: onRetry) {
                Label(problem.actionTitle, systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .hakiCard()
    }
}

// MARK: - Empty state

/// The first screen of a new chat: what Haki can do, the privacy promise,
/// and starter questions.
struct AssistantIntroView: View {
    let firstName: String?
    let onAsk: (String) -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 16) {
            header
            privacyNote
            suggestions
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: badgeSize * 0.45, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: badgeSize, height: badgeSize)
                .background(Color.accentColor.opacity(0.15), in: Circle())
                .accessibilityHidden(true)
            Text(greeting)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Text("Ask about your spending, budgets, bills, meals, workouts, notes or wardrobe. Haki answers from what's in the app and suggests what to do next.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var greeting: String {
        if let firstName {
            return "Hi \(firstName), what would you like to know?"
        }
        return "What would you like to know?"
    }

    private var privacyNote: some View {
        Label {
            Text("Haki looks things up on your iPhone only when a question needs it, and sends just that to Claude to answer. Nothing is saved on Haki's servers.")
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(Color.accentColor)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .hakiCard()
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Try asking", systemImage: "lightbulb")
            VStack(spacing: 8) {
                ForEach(AssistantSuggestedQuestions.all, id: \.self) { question in
                    AssistantSuggestionChip(question: question) {
                        onAsk(question)
                    }
                }
            }
        }
        .hakiCard()
    }
}

private struct AssistantSuggestionChip: View {
    let question: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: AssistantSuggestedQuestions.systemImage(for: question))
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
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Asks Haki this question")
    }
}

// MARK: - Composer

/// The text field and send button at the bottom of the chat.
struct AssistantComposer: View {
    let isBusy: Bool
    /// Returns whether the text was sent (the field is cleared then).
    let onSend: (String) -> Bool

    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var canSend: Bool {
        !isBusy && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask Haki anything…", text: $text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($isFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.hakiBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                sendButton
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.hakiCardBackground)
        .onChange(of: text) { _, newValue in
            if newValue.count > AssistantService.maxQuestionLength {
                text = String(newValue.prefix(AssistantService.maxQuestionLength))
            }
        }
    }

    private var sendButton: some View {
        Button(action: send) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .accessibilityLabel("Send")
        .accessibilityHint(sendHint)
    }

    private var sendHint: String {
        isBusy ? "Haki is still answering" : ""
    }

    private func send() {
        guard canSend else { return }
        if onSend(text) {
            text = ""
        }
    }
}

/// "Answers can be wrong. Not financial or medical advice."
struct AssistantDisclaimer: View {
    var body: some View {
        Text("Answers can be wrong. Not financial or medical advice.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }
}

// MARK: - Previews

#Preview("Bubbles") {
    ScrollView {
        VStack(spacing: 14) {
            AssistantBubbleRow(item: AssistantChatItem(
                id: UUID(), role: .user, text: "How much did I spend on restaurants?",
                blocks: [], tools: [], isInterim: false
            ))
            AssistantBubbleRow(item: AssistantChatItem(
                id: UUID(), role: .assistant, text: "Let me check your spending.",
                blocks: [], tools: [], isInterim: true
            ))
            AssistantBubbleRow(item: AssistantChatItem(
                id: UUID(), role: .assistant, text: "",
                blocks: AssistantMarkdown.blocks(from: "You've spent **$212.40** on restaurants.\n\n- 9 visits\n- Mostly weekends"),
                tools: [.spending, .budgets], isInterim: false
            ))
            AssistantTypingIndicator(activity: .lookingAt([.budgets]), onCancel: {})
            AssistantProblemCard(problem: .tooManySteps, onRetry: {})
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}

#Preview("Intro") {
    ScrollView {
        AssistantIntroView(firstName: "Sam", onAsk: { _ in })
            .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
