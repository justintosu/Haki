//
//  AssistantMessages.swift
//  Haki
//
//  Pure Foundation code (see Money.swift): the conversation format for the
//  "Ask Haki" assistant. Messages use the Claude Messages API shape and are
//  kept verbatim (including Claude's thinking blocks, which must be sent back
//  unchanged), so content blocks are stored as raw JSON values.
//
//  The assistant's tools run on the device: when Claude answers with
//  `tool_use` blocks, the app looks the data up locally and sends back
//  `tool_result` blocks. Only what a question needs leaves the phone.
//

import Foundation

/// Any JSON value, preserved exactly enough to send it back.
nonisolated enum JSONValue: Equatable, Hashable, Codable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a JSON value")
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value):
            // Whole numbers go out as integers ("50", not "50.0").
            if value.rounded() == value, abs(value) < 1e15 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let object) = self { return object[key] }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var intValue: Int? { numberValue.map { Int($0.rounded()) } }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    /// Compact JSON text (sorted keys, so it's stable).
    var jsonText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }
}

nonisolated enum AssistantRole: String, Codable, Sendable {
    case user, assistant
}

/// One message in the conversation, in the Messages API shape.
nonisolated struct AssistantMessage: Equatable, Codable, Sendable {
    var role: AssistantRole
    /// Content blocks as raw JSON objects (`{"type": "text", ...}` etc.).
    var content: [JSONValue]

    init(role: AssistantRole, content: [JSONValue]) {
        self.role = role
        self.content = content
    }

    static func user(_ text: String) -> AssistantMessage {
        AssistantMessage(role: .user, content: [.object(["type": .string("text"), "text": .string(text)])])
    }

    /// Text the person should see (text blocks joined).
    var text: String {
        content.compactMap { block -> String? in
            guard block["type"]?.stringValue == "text" else { return nil }
            return block["text"]?.stringValue
        }
        .joined(separator: "\n\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `tool_use` blocks: what Claude wants looked up on the device.
    var toolUses: [AssistantToolUse] {
        content.compactMap { block in
            guard block["type"]?.stringValue == "tool_use",
                  let id = block["id"]?.stringValue,
                  let name = block["name"]?.stringValue
            else { return nil }
            return AssistantToolUse(id: id, name: name, input: block["input"] ?? .object([:]))
        }
    }

    /// Whether this is the user's answer to tool calls rather than something they typed.
    var isToolResults: Bool {
        role == .user && !content.isEmpty && content.allSatisfy { $0["type"]?.stringValue == "tool_result" }
    }

    /// A user message answering `uses` with `results` (same order).
    static func toolResults(_ results: [AssistantToolResult]) -> AssistantMessage {
        AssistantMessage(role: .user, content: results.map { result in
            var block: [String: JSONValue] = [
                "type": .string("tool_result"),
                "tool_use_id": .string(result.toolUseID),
                "content": .string(result.content),
            ]
            if result.isError { block["is_error"] = .bool(true) }
            return .object(block)
        })
    }
}

nonisolated struct AssistantToolUse: Equatable, Sendable {
    let id: String
    let name: String
    let input: JSONValue

    func string(_ key: String) -> String? {
        guard let value = input[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    func int(_ key: String) -> Int? { input[key]?.intValue }
}

nonisolated struct AssistantToolResult: Equatable, Sendable {
    let toolUseID: String
    /// Usually compact JSON text.
    let content: String
    let isError: Bool
}

/// The tools the assistant can call; they run on the device. The server
/// declares the same names and input schemas (supabase/functions/haki-ai).
nonisolated enum AssistantTool: String, CaseIterable, Sendable {
    case overview = "get_overview"
    case spending = "get_spending"
    case transactions = "search_transactions"
    case budgets = "get_budgets"
    case bills = "get_recurring_bills"
    case accounts = "get_accounts"
    case investments = "get_investments"
    case nutrition = "get_nutrition"
    case workouts = "get_workouts"
    case notes = "search_notes"
    case flashcards = "get_flashcards"
    case wardrobe = "get_wardrobe"
    case social = "get_social"

    /// Shown as "Looked at: Spending, Budgets" under an answer.
    var dataTitle: String {
        switch self {
        case .overview: "Overview"
        case .spending: "Spending"
        case .transactions: "Transactions"
        case .budgets: "Budgets"
        case .bills: "Bills"
        case .accounts: "Accounts"
        case .investments: "Investments"
        case .nutrition: "Food log"
        case .workouts: "Workouts"
        case .notes: "Notes"
        case .flashcards: "Flashcards"
        case .wardrobe: "Wardrobe"
        case .social: "Profile & feed"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .spending: "chart.pie"
        case .transactions: "list.bullet.rectangle.portrait"
        case .budgets: "chart.bar"
        case .bills: "arrow.triangle.2.circlepath"
        case .accounts: "building.columns"
        case .investments: "chart.line.uptrend.xyaxis"
        case .nutrition: "fork.knife"
        case .workouts: "dumbbell"
        case .notes: "note.text"
        case .flashcards: "rectangle.on.rectangle.angled"
        case .wardrobe: "hanger"
        case .social: "person.2"
        }
    }
}

/// Facts about the person's device sent with every chat request, so dates
/// and money are read correctly.
nonisolated struct AssistantContext: Equatable, Codable, Sendable {
    var today: String
    var timeZone: String
    var locale: String
    var currency: String
    var firstName: String?

    enum CodingKeys: String, CodingKey {
        case today, locale, currency
        case timeZone = "time_zone"
        case firstName = "first_name"
    }

    static func current(now: Date = .now, firstName: String? = nil, calendar: Calendar = .current, locale: Locale = .current) -> AssistantContext {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd EEEE HH:mm"
        return AssistantContext(
            today: formatter.string(from: now),
            timeZone: calendar.timeZone.identifier,
            locale: locale.identifier,
            currency: locale.currency?.identifier ?? "USD",
            firstName: firstName
        )
    }
}

/// One step of the conversation loop: Claude's reply and why it stopped.
nonisolated struct AssistantReply: Equatable, Codable, Sendable {
    var content: [JSONValue]
    /// "end_turn", "tool_use", "pause_turn", "max_tokens" or "refusal".
    var stopReason: String

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }

    var message: AssistantMessage { AssistantMessage(role: .assistant, content: content) }
}

nonisolated enum AssistantConversation {
    /// The longest a conversation sent to the server may be, in characters of
    /// JSON (older turns are dropped first, keeping whole exchanges).
    static let maxCharacters = 180_000

    /// Drops the oldest exchanges until the conversation fits, never
    /// starting on a tool result or an assistant message.
    static func trimmed(_ messages: [AssistantMessage], maxCharacters: Int = maxCharacters) -> [AssistantMessage] {
        var kept = messages
        func size(_ list: [AssistantMessage]) -> Int {
            list.reduce(0) { $0 + $1.content.reduce(0) { $0 + $1.jsonText.count } }
        }
        while kept.count > 1, size(kept) > maxCharacters {
            kept.removeFirst()
            while let first = kept.first, first.role != .user || first.isToolResults {
                kept.removeFirst()
            }
        }
        return kept
    }

    /// The tools used to answer the last question (for "Looked at: ...").
    static func toolsUsedInLastAnswer(_ messages: [AssistantMessage]) -> [AssistantTool] {
        var tools: [AssistantTool] = []
        for message in messages.reversed() {
            if message.role == .user, !message.isToolResults { break }
            for use in message.toolUses.reversed() {
                if let tool = AssistantTool(rawValue: use.name), !tools.contains(tool) { tools.insert(tool, at: 0) }
            }
        }
        return tools
    }
}
