//
//  AssistantService.swift
//  Haki
//
//  Runs the "Ask Haki" conversation loop for one thread: stores the
//  person's question, asks Claude (through `HakiAIService.chat`), runs the
//  lookups Claude asks for on the device (`AssistantToolExecutor`), sends the
//  results back, and stores the answer. Everything is saved through
//  `AssistantStore`.
//
//  One instance per chat screen (`@State private var service = AssistantService()`);
//  the screen passes its environment in with every request.
//

import Foundation
import Observation
import SwiftData

/// What the chat screen needs to run a request.
struct AssistantServiceDependencies {
    let context: ModelContext
    let hakiAI: HakiAIService
    let portfolio: PortfolioService
    let social: SocialService
    let auth: AuthService
}

/// What the assistant is doing while a request runs.
nonisolated enum AssistantActivity: Equatable {
    /// Waiting for Claude before any lookup.
    case thinking
    /// Looked these up on the device and waiting for Claude to answer
    /// (empty when Claude asked for something Haki doesn't know).
    case lookingAt([AssistantTool])

    /// "Looking at your budgets…"
    var statusText: String {
        switch self {
        case .thinking:
            return "Thinking…"
        case .lookingAt(let tools):
            let names = tools.map { tool in
                tool == .social ? "profile and feed" : tool.dataTitle.lowercased()
            }
            switch names.count {
            case 0:
                return "Looking things up…"
            case 1:
                return "Looking at your \(names[0])…"
            case 2:
                return "Looking at your \(names[0]) and \(names[1])…"
            default:
                return "Looking at your \(names[0]), \(names[1]) and more…"
            }
        }
    }

    var systemImage: String {
        switch self {
        case .thinking:
            return "sparkles"
        case .lookingAt(let tools):
            if tools.count == 1, let tool = tools.first {
                return tool.systemImage
            }
            return "magnifyingglass"
        }
    }
}

/// Why the last request ended without an answer.
nonisolated enum AssistantProblem: Equatable {
    /// A user-facing error message.
    case failed(String)
    /// Claude needed more than `AssistantService.maxRounds` rounds.
    case tooManySteps
    /// The person cancelled it.
    case stopped
    /// A saved chat whose last question never got an answer.
    case unanswered

    var message: String {
        switch self {
        case .failed(let text):
            return text
        case .tooManySteps:
            return "That took too many steps. Try a simpler question, or let Haki keep going."
        case .stopped:
            return "You stopped this answer."
        case .unanswered:
            return "This question didn't get an answer."
        }
    }

    var actionTitle: String {
        switch self {
        case .failed: return "Retry"
        case .tooManySteps: return "Keep going"
        case .stopped: return "Retry"
        case .unanswered: return "Get an answer"
        }
    }

    var systemImage: String {
        switch self {
        case .failed: return "exclamationmark.triangle.fill"
        case .tooManySteps: return "arrow.triangle.branch"
        case .stopped: return "stop.circle"
        case .unanswered: return "questionmark.bubble"
        }
    }

    /// Whether this is an error (shown with a warning color) rather than a note.
    var isError: Bool {
        switch self {
        case .failed, .tooManySteps: return true
        case .stopped, .unanswered: return false
        }
    }
}

/// One bubble in the chat, built from a stored message.
nonisolated struct AssistantChatItem: Identifiable, Equatable {
    let id: UUID
    let role: AssistantRole
    let text: String
    /// The assistant's text split into paragraphs and list rows (empty for the person's messages).
    let blocks: [AssistantMarkdownBlock]
    /// What was looked up to answer (final answers only).
    let tools: [AssistantTool]
    /// Assistant text that came with lookups ("Let me check your budgets."), not the answer.
    let isInterim: Bool
}

@MainActor
@Observable
final class AssistantService {
    /// The most calls to Claude for one question.
    static let maxRounds = 8
    /// The longest question that can be sent (the server allows 8,000 characters).
    static let maxQuestionLength = 4_000

    /// The open thread's id (nil for a new chat that hasn't been asked anything yet).
    private(set) var threadID: UUID?
    /// The visible messages of the open thread, oldest first.
    private(set) var items: [AssistantChatItem] = []
    /// Set while a request runs.
    private(set) var activity: AssistantActivity?
    /// Set when the last request ended without an answer.
    private(set) var problem: AssistantProblem?

    var isBusy: Bool { activity != nil }

    @ObservationIgnored private var thread: AssistantThread?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped whenever a request is started, cancelled or abandoned, so an
    /// older request never writes into the chat after that.
    @ObservationIgnored private var generation = 0

    init() {}

    // MARK: Threads

    /// Shows `thread` (cancels whatever was running).
    func open(_ thread: AssistantThread) {
        guard thread.id != threadID else { return }
        reset()
        self.thread = thread
        threadID = thread.id
        reloadItems()
        if thread.conversation.last?.role == .user {
            problem = .unanswered
        }
    }

    /// Starts over with an empty chat (the current thread stays in history).
    func startNewChat() {
        reset()
    }

    /// Call before the thread with `id` is deleted, so nothing touches it afterwards.
    func forgetThread(id: UUID) {
        guard id == threadID else { return }
        reset()
    }

    // MARK: Asking

    /// Stores `text` as the person's next message and asks for the answer.
    /// Returns false (and does nothing) when the text is empty or a request is running.
    @discardableResult
    func send(_ text: String, using dependencies: AssistantServiceDependencies) -> Bool {
        let question = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxQuestionLength))
        guard !question.isEmpty, !isBusy else { return false }

        let target: AssistantThread
        if let thread {
            target = thread
        } else {
            target = AssistantStore.createThread(title: Self.title(for: question), in: dependencies.context)
            thread = target
            threadID = target.id
        }
        AssistantStore.append(.user(question), to: target, in: dependencies.context)
        reloadItems()
        start(on: target, using: dependencies)
        return true
    }

    /// Sends the stored conversation again (never adds the question twice).
    func retry(using dependencies: AssistantServiceDependencies) {
        guard !isBusy, let thread else { return }
        start(on: thread, using: dependencies)
    }

    /// Stops the running request. Nothing more is stored for it.
    func cancel() {
        guard isBusy else { return }
        generation += 1
        task?.cancel()
        task = nil
        activity = nil
        problem = .stopped
    }

    // MARK: The loop

    private func reset() {
        generation += 1
        task?.cancel()
        task = nil
        thread = nil
        threadID = nil
        items = []
        activity = nil
        problem = nil
    }

    private func start(on thread: AssistantThread, using dependencies: AssistantServiceDependencies) {
        generation += 1
        let current = generation
        problem = nil
        activity = .thinking
        task = Task { [weak self] in
            guard let self else { return }
            await self.run(on: thread, using: dependencies, generation: current)
        }
    }

    private func run(on thread: AssistantThread, using dependencies: AssistantServiceDependencies, generation current: Int) async {
        let requestContext = AssistantContext.current(firstName: Self.firstName(from: dependencies.auth.profile?.displayName))
        var lookedAt: [AssistantTool] = []
        var round = 0

        while round < Self.maxRounds {
            round += 1
            let reply: AssistantReply
            do {
                reply = try await dependencies.hakiAI.chat(Self.recent(thread.conversation), context: requestContext)
            } catch {
                guard current == generation else { return }
                let outcome: AssistantProblem = Backend.isCancellation(error) ? .stopped : .failed(error.localizedDescription)
                activity = nil
                task = nil
                problem = outcome
                return
            }
            guard current == generation, !Task.isCancelled else { return }

            let message = reply.message
            switch reply.stopReason {
            case "tool_use":
                let uses = message.toolUses
                guard !uses.isEmpty else {
                    finish(with: message, on: thread, using: dependencies)
                    return
                }
                for use in uses {
                    if let tool = AssistantTool(rawValue: use.name), !lookedAt.contains(tool) {
                        lookedAt.append(tool)
                    }
                }
                activity = .lookingAt(lookedAt)
                let executor = AssistantToolExecutor(
                    context: dependencies.context,
                    portfolio: dependencies.portfolio,
                    social: dependencies.social,
                    auth: dependencies.auth,
                    now: .now
                )
                var results: [AssistantToolResult] = []
                for use in uses {
                    let result = await executor.run(use)
                    results.append(result)
                }
                guard current == generation, !Task.isCancelled else { return }
                // The reply and its results are stored together, so a stopped
                // request never leaves a lookup without its answer.
                AssistantStore.append(message, to: thread, in: dependencies.context)
                AssistantStore.append(.toolResults(results), to: thread, in: dependencies.context)
                reloadItems()
            case "pause_turn":
                // Claude paused a long turn: send it back as is to let it continue.
                if !message.content.isEmpty {
                    AssistantStore.append(message, to: thread, in: dependencies.context)
                    reloadItems()
                }
            default:
                finish(with: message, on: thread, using: dependencies)
                return
            }
        }

        guard current == generation else { return }
        activity = nil
        task = nil
        problem = .tooManySteps
    }

    /// Stores the final answer with the tools used to give it.
    private func finish(with message: AssistantMessage, on thread: AssistantThread, using dependencies: AssistantServiceDependencies) {
        activity = nil
        task = nil
        guard !message.text.isEmpty else {
            // Nothing to show; the conversation still ends with the person's
            // message, so Retry can ask again.
            problem = .failed("Haki didn't come up with an answer. Try again.")
            return
        }
        let tools = AssistantConversation.toolsUsedInLastAnswer(thread.conversation + [message])
        AssistantStore.append(message, toolsUsed: tools, to: thread, in: dependencies.context)
        reloadItems()
    }

    private func reloadItems() {
        guard let thread else {
            items = []
            return
        }
        items = Self.makeItems(from: thread.orderedMessages)
    }

    // MARK: Helpers

    /// Visible bubbles: the person's typed messages and the assistant's text
    /// (tool results and tool-call-only replies are hidden).
    static func makeItems(from records: [AssistantMessageRecord]) -> [AssistantChatItem] {
        records.compactMap { record -> AssistantChatItem? in
            guard record.isVisible else { return nil }
            let role = record.role
            let text = record.displayText
            if role == .user {
                return AssistantChatItem(id: record.id, role: .user, text: text, blocks: [], tools: [], isInterim: false)
            }
            let hasToolCalls = !(record.message?.toolUses.isEmpty ?? true)
            return AssistantChatItem(
                id: record.id,
                role: .assistant,
                text: text,
                blocks: AssistantMarkdown.blocks(from: text),
                tools: hasToolCalls ? [] : record.toolsUsed,
                isInterim: hasToolCalls
            )
        }
    }

    /// The thread title for a first question: its first line.
    static func title(for question: String) -> String {
        let firstLine = question
            .split(whereSeparator: { $0.isNewline })
            .first
            .map { String($0) } ?? question
        return firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first word of a display name ("Sam" from "Sam Rivera").
    static func firstName(from displayName: String?) -> String? {
        guard let displayName else { return nil }
        guard let first = displayName.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        let name = String(first)
        return name.isEmpty ? nil : String(name.prefix(40))
    }

    /// The latest messages, at most `maxCount` (the server allows 80), starting
    /// on a message the person typed.
    static func recent(_ messages: [AssistantMessage], maxCount: Int = 60) -> [AssistantMessage] {
        guard messages.count > maxCount else { return messages }
        var kept = Array(messages.suffix(maxCount))
        while let first = kept.first, first.role != .user || first.isToolResults {
            kept.removeFirst()
        }
        return kept.isEmpty ? messages : kept
    }
}
