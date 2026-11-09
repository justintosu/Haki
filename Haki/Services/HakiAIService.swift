//
//  HakiAIService.swift
//  Haki
//
//  Talks to the "haki-ai" edge function (supabase/functions/haki-ai): the
//  "Ask Haki" assistant, clothing photo tagging, outfit ideas and flashcards
//  made from notes.
//
//  Injected at the root: `.environment(HakiAIService.live)`; read with
//  `@Environment(HakiAIService.self) private var hakiAI`. The preview
//  instance answers with sample data and never touches the network (its
//  chat asks for one lookup, then answers, so the tool loop can be tried).
//

import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class HakiAIService {
    private let client: SupabaseClient?

    init(client: SupabaseClient?) {
        self.client = client
    }

    static let preview = HakiAIService(client: nil)
    /// Uses `Backend.client`.
    static let live = HakiAIService(client: Backend.client)

    var isPreview: Bool { client == nil }

    // MARK: Assistant

    /// One round of the assistant: sends the conversation (ending with the
    /// person's message or tool results) and returns Claude's reply. When the
    /// reply's `stopReason` is "tool_use", run the lookups on the device and
    /// call again with the results appended; "pause_turn" means call again
    /// with the reply appended as is.
    func chat(_ messages: [AssistantMessage], context: AssistantContext) async throws -> AssistantReply {
        let conversation = AssistantConversation.trimmed(messages)
        guard let client else {
            try await Task.sleep(for: .seconds(1))
            return HakiAIPreviewSamples.reply(to: conversation)
        }
        let request = HakiAIChatRequest(action: "chat", messages: conversation, context: context)
        do {
            return try await client.functions.invoke(
                "haki-ai",
                options: FunctionInvokeOptions(body: request, timeoutInterval: 140),
                decoder: JSONDecoder()
            )
        } catch {
            throw Backend.userFacingError(error, fallback: "The assistant couldn't answer right now. Try again.")
        }
    }

    // MARK: Wardrobe

    /// Reads a clothing photo (JPEG, ideally ~1024 px) and suggests its name,
    /// category, colors, seasons, styles, formality and warmth.
    func tagClothing(photoJPEG: Data) async throws -> ClothingTags {
        guard let client else {
            try await Task.sleep(for: .seconds(1))
            return HakiAIPreviewSamples.tags
        }
        let request = HakiAIImageRequest(action: "tag_clothing", imageBase64: photoJPEG.base64EncodedString(), mediaType: "image/jpeg")
        do {
            return try await client.functions.invoke(
                "haki-ai",
                options: FunctionInvokeOptions(body: request, timeoutInterval: 60),
                decoder: JSONDecoder()
            )
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't tag that photo. Fill in the details yourself.")
        }
    }

    /// Outfit ideas from `pieces` for `occasion` (and optional weather).
    /// Ideas naming pieces that don't exist are cleaned up.
    func suggestOutfits(pieces: [WardrobePieceSummary], occasion: String, weather: String? = nil, count: Int = 3) async throws -> OutfitIdeaReport {
        let known = Set(pieces.map(\.id))
        guard let client else {
            try await Task.sleep(for: .seconds(1.5))
            return HakiAIPreviewSamples.outfits(from: pieces).keepingOnly(knownIDs: known)
        }
        let request = HakiAIOutfitRequest(action: "suggest_outfits", pieces: pieces, occasion: occasion, weather: weather, count: count)
        do {
            let report: OutfitIdeaReport = try await client.functions.invoke(
                "haki-ai",
                options: FunctionInvokeOptions(body: request, timeoutInterval: 100),
                decoder: JSONDecoder()
            )
            return report.keepingOnly(knownIDs: known)
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't come up with outfits right now. Try again.")
        }
    }

    // MARK: Flashcards

    /// Flashcards made from a note's text (at most `count`).
    func makeFlashcards(title: String?, text: String, count: Int = 12) async throws -> FlashcardDraftReport {
        guard let client else {
            try await Task.sleep(for: .seconds(1.5))
            return HakiAIPreviewSamples.flashcards
        }
        let request = HakiAIFlashcardRequest(action: "make_flashcards", title: title, text: String(text.prefix(24_000)), count: count)
        do {
            return try await client.functions.invoke(
                "haki-ai",
                options: FunctionInvokeOptions(body: request, timeoutInterval: 100),
                decoder: JSONDecoder()
            )
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't make flashcards right now. Try again.")
        }
    }
}

// MARK: - Requests

private struct HakiAIChatRequest: Encodable {
    var action: String
    var messages: [AssistantMessage]
    var context: AssistantContext
}

private struct HakiAIImageRequest: Encodable {
    var action: String
    var imageBase64: String
    var mediaType: String

    enum CodingKeys: String, CodingKey {
        case action
        case imageBase64 = "image_base64"
        case mediaType = "media_type"
    }
}

private struct HakiAIOutfitRequest: Encodable {
    var action: String
    var pieces: [WardrobePieceSummary]
    var occasion: String
    var weather: String?
    var count: Int
}

private struct HakiAIFlashcardRequest: Encodable {
    var action: String
    var title: String?
    var text: String
    var count: Int
}

// MARK: - Preview samples

enum HakiAIPreviewSamples {
    static let tags = ClothingTags(
        name: "Navy crew-neck sweater", category: .top, colors: [.navy], pattern: "solid",
        seasons: [.fall, .winter], styles: [.casual, .smartCasual], formality: 2, warmth: 4
    )

    static let flashcards = FlashcardDraftReport(cards: [
        FlashcardDraft(front: "What does the mitochondria produce?", back: "ATP, the cell's energy"),
        FlashcardDraft(front: "Where does photosynthesis happen?", back: "In the chloroplasts"),
        FlashcardDraft(front: "What carries genetic information?", back: "DNA"),
        FlashcardDraft(front: "What is osmosis?", back: "Water moving across a membrane toward higher solute concentration"),
    ], notes: "")

    /// Up to three ideas from whatever pieces exist: a top, a bottom and shoes.
    static func outfits(from pieces: [WardrobePieceSummary]) -> OutfitIdeaReport {
        func ids(_ category: String) -> [String] { pieces.filter { $0.category == category }.map(\.id) }
        let tops = ids("top"), bottoms = ids("bottom"), shoes = ids("shoes"), outer = ids("outerwear")
        var ideas: [OutfitIdea] = []
        for index in 0..<3 {
            var chosen: [String] = []
            if !tops.isEmpty { chosen.append(tops[index % tops.count]) }
            if !bottoms.isEmpty { chosen.append(bottoms[index % bottoms.count]) }
            if !shoes.isEmpty { chosen.append(shoes[index % shoes.count]) }
            if index == 1, let jacket = outer.first { chosen.append(jacket) }
            guard chosen.count >= 2 else { break }
            ideas.append(OutfitIdea(name: ["Easy weekend", "Layered for a cool day", "Simple and sharp"][index], itemIDs: chosen, reason: "These colors work together and suit the occasion."))
        }
        return OutfitIdeaReport(outfits: ideas, notes: ideas.isEmpty ? "Add a few tops, bottoms and shoes to get outfit ideas." : "")
    }

    /// Asks for an overview first, then answers from it.
    static func reply(to conversation: [AssistantMessage]) -> AssistantReply {
        guard let last = conversation.last else {
            return AssistantReply(content: [text("Ask me anything about your money, health, workouts, notes or wardrobe.")], stopReason: "end_turn")
        }
        if last.isToolResults {
            let summary = overviewSummary(last.content.first?["content"]?.stringValue)
            return AssistantReply(content: [text("Here's what I found in Haki (sample answer in preview mode):\n\n\(summary)\n- **Tip:** set a budget for your top spending category to keep it in check.")], stopReason: "end_turn")
        }
        let toolUse: JSONValue = .object([
            "type": .string("tool_use"),
            "id": .string("toolu_preview_\(conversation.count)"),
            "name": .string(AssistantTool.overview.rawValue),
            "input": .object([:]),
        ])
        return AssistantReply(content: [text("Let me look at your overview."), toolUse], stopReason: "tool_use")
    }

    /// A few readable lines from the overview lookup's JSON (the real
    /// assistant writes its own; this keeps preview answers from showing raw JSON).
    private static func overviewSummary(_ json: String?) -> String {
        guard let json, let overview = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)) else {
            return "- Your overview couldn't be read this time."
        }
        let code = overview["currency"]?.stringValue ?? "USD"
        func money(_ value: JSONValue?) -> String? {
            value?.numberValue.map { $0.formatted(.currency(code: code)) }
        }
        var lines: [String] = []
        if let spent = money(overview["spending_this_month"]?["spent"]) {
            lines.append("- You've spent **\(spent)** so far this month.")
        }
        let budgets = overview["budgets_this_month"]
        if let left = money(budgets?["left"]), let total = money(budgets?["total_budget"]) {
            lines.append("- \(left) is left of your \(total) monthly budget.")
        }
        if let review = overview["transactions_to_review"]?.intValue, review > 0 {
            lines.append("- \(review) transaction\(review == 1 ? "" : "s") to review.")
        }
        return lines.isEmpty ? "- Your overview has nothing new yet." : lines.joined(separator: "\n")
    }

    private static func text(_ value: String) -> JSONValue {
        .object(["type": .string("text"), "text": .string(value)])
    }
}
