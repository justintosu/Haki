//
//  AssistantStore.swift
//  Haki
//
//  Saved "Ask Haki" conversations (on the device only). Screens read threads
//  with @Query; `AssistantService` appends messages through these helpers.
//

import Foundation
import SwiftData

enum AssistantStore {
    @discardableResult
    static func createThread(title: String, in context: ModelContext) -> AssistantThread {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let thread = AssistantThread(title: trimmed.isEmpty ? "New chat" : String(trimmed.prefix(80)))
        context.insert(thread)
        LedgerStore.save(context)
        return thread
    }

    /// Appends `message` (and, for an assistant answer, the tools it used).
    @discardableResult
    static func append(_ message: AssistantMessage, toolsUsed: [AssistantTool] = [], to thread: AssistantThread, now: Date = .now, in context: ModelContext) -> AssistantMessageRecord {
        let record = AssistantMessageRecord(order: (thread.messages.map(\.order).max() ?? -1) + 1, message: message)
        record.toolsUsed = toolsUsed
        record.createdAt = now
        context.insert(record)
        record.thread = thread
        thread.updatedAt = now
        LedgerStore.save(context)
        return record
    }

    static func rename(_ thread: AssistantThread, to title: String, in context: ModelContext) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        thread.title = String(trimmed.prefix(80))
        LedgerStore.save(context)
    }

    static func deleteThread(_ thread: AssistantThread, in context: ModelContext) {
        context.delete(thread)
        LedgerStore.save(context)
    }

    static func eraseAll(in context: ModelContext) {
        for thread in (try? context.fetch(FetchDescriptor<AssistantThread>())) ?? [] { context.delete(thread) }
        LedgerStore.save(context)
    }
}
