//
//  LifeTests.swift
//  Haki core tests
//
//  Flashcards (spaced repetition, answer checking), wardrobe types and the
//  assistant's message format. Called from main.swift.
//

import Foundation

private let lifeNow = Date(timeIntervalSince1970: 1_794_000_000) // 2026-11-06

private func lifeDecode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

func runLifeTests() {
    suite("SpacedRepetition") {
        let new = CardSchedule.new
        expect(new.isNew)
        expect(!SpacedRepetition.isDue(new, now: lifeNow), "new cards aren't due")

        let good1 = SpacedRepetition.review(new, grade: .good, now: lifeNow)
        expectEqual(good1.repetitions, 1)
        expectEqual(good1.intervalDays, 1)
        expectEqual(good1.dueAt, lifeNow.addingTimeInterval(86_400))
        expect(!good1.isNew)
        let good2 = SpacedRepetition.review(good1, grade: .good, now: lifeNow)
        expectEqual(good2.intervalDays, 3)
        let good3 = SpacedRepetition.review(good2, grade: .good, now: lifeNow)
        expectEqual(good3.intervalDays, 7.5, "3 × ease 2.5")
        expectEqual(good3.ease, 2.5)

        let again = SpacedRepetition.review(good3, grade: .again, now: lifeNow)
        expectEqual(again.repetitions, 0)
        expectEqual(again.lapses, 1)
        expectEqual(again.ease, 2.3)
        expect(abs(again.intervalDays - 10.0 / 1440) < 1e-9)
        let againNew = SpacedRepetition.review(new, grade: .again, now: lifeNow)
        expectEqual(againNew.lapses, 0, "forgetting a card never learned isn't a lapse")

        let hard = SpacedRepetition.review(good3, grade: .hard, now: lifeNow)
        expectEqual(hard.intervalDays, 9, "7.5 × 1.2")
        expectEqual(hard.ease, 2.35)
        expectEqual(SpacedRepetition.review(new, grade: .hard, now: lifeNow).intervalDays, 0.5)

        let easy = SpacedRepetition.review(new, grade: .easy, now: lifeNow)
        expectEqual(easy.intervalDays, 4)
        expectEqual(easy.ease, 2.65)

        // Ease never drops below the floor.
        var lowered = good3
        for _ in 0..<20 { lowered = SpacedRepetition.review(lowered, grade: .again, now: lifeNow) }
        expectEqual(lowered.ease, SpacedRepetition.minimumEase)
        // Intervals are capped at two years.
        var long = CardSchedule(repetitions: 9, intervalDays: 600, ease: 3, dueAt: lifeNow, lapses: 0, lastReviewedAt: lifeNow)
        long = SpacedRepetition.review(long, grade: .easy, now: lifeNow)
        expectEqual(long.intervalDays, 730)

        expect(SpacedRepetition.isDue(good1, now: lifeNow.addingTimeInterval(86_400)))
        expect(!SpacedRepetition.isDue(good1, now: lifeNow.addingTimeInterval(3_600)))
    }

    suite("SpacedRepetition.studyQueue") {
        let overdue = CardSchedule(repetitions: 2, intervalDays: 3, ease: 2.5, dueAt: lifeNow.addingTimeInterval(-86_400 * 2), lapses: 0, lastReviewedAt: lifeNow)
        let dueToday = CardSchedule(repetitions: 1, intervalDays: 1, ease: 2.5, dueAt: lifeNow.addingTimeInterval(-60), lapses: 0, lastReviewedAt: lifeNow)
        let later = CardSchedule(repetitions: 1, intervalDays: 1, ease: 2.5, dueAt: lifeNow.addingTimeInterval(86_400), lapses: 0, lastReviewedAt: lifeNow)
        let cards: [(id: String, schedule: CardSchedule)] = [
            ("today", dueToday), ("new1", .new), ("later", later), ("overdue", overdue), ("new2", .new), ("new3", .new),
        ]
        expectEqual(SpacedRepetition.studyQueue(cards, now: lifeNow), ["overdue", "today", "new1", "new2", "new3"])
        expectEqual(SpacedRepetition.studyQueue(cards, now: lifeNow, newLimit: 1, reviewLimit: 1), ["overdue", "new1"])
        expectEqual(SpacedRepetition.studyQueue(cards, now: lifeNow, newLimit: 0), ["overdue", "today"])
        expectEqual(SpacedRepetition.studyQueue([(id: "x", schedule: later)], now: lifeNow), [])
    }

    suite("SpacedRepetition.intervalText") {
        expectEqual(SpacedRepetition.intervalText(days: 10.0 / 1440), "10m")
        expectEqual(SpacedRepetition.intervalText(days: 0.5), "12h")
        expectEqual(SpacedRepetition.intervalText(days: 3), "3d")
        expectEqual(SpacedRepetition.intervalText(days: 21), "3w")
        expectEqual(SpacedRepetition.intervalText(days: 120), "4mo")
        expectEqual(SpacedRepetition.intervalText(days: 730), "2.0y")
        let previews = SpacedRepetition.previewIntervals(.new, now: lifeNow)
        expectEqual(previews[.again], "10m")
        expectEqual(previews[.good], "1d")
        expectEqual(previews[.easy], "4d")
    }

    suite("AnswerChecker") {
        expectEqual(AnswerChecker.normalize("  The Mitochondria! "), "mitochondria")
        expectEqual(AnswerChecker.normalize("Café crème"), "cafe creme")
        expectEqual(AnswerChecker.normalize("a"), "a", "a lone article stays")
        expect(AnswerChecker.isCorrect(typed: "mitochondria", expected: "The mitochondria"))
        expect(AnswerChecker.isCorrect(typed: "mitocondria", expected: "Mitochondria"), "one typo allowed")
        expect(!AnswerChecker.isCorrect(typed: "mitocon", expected: "Mitochondria"))
        expect(!AnswerChecker.isCorrect(typed: "cat", expected: "car"), "short answers must be exact")
        expect(AnswerChecker.isCorrect(typed: "Paris", expected: "paris"))
        expect(AnswerChecker.isCorrect(typed: "H2O", expected: "water / H2O"))
        expect(AnswerChecker.isCorrect(typed: "water", expected: "Water or H2O"))
        expect(AnswerChecker.isCorrect(typed: "photosinthesis", expected: "photosynthesis"))
        expect(AnswerChecker.isCorrect(typed: "photosinthesys", expected: "photosynthesis"), "two typos in a long word")
        expect(!AnswerChecker.isCorrect(typed: "", expected: "anything"))
        expect(!AnswerChecker.isCorrect(typed: "   ", expected: "anything"))
        expectEqual(AnswerChecker.levenshtein("kitten", "sitting"), 3)
        expectEqual(AnswerChecker.levenshtein("", "abc"), 3)
        expectEqual(AnswerChecker.levenshtein("same", "same"), 0)
    }

    suite("FlashcardDraftReport decoding") {
        let report = try lifeDecode(FlashcardDraftReport.self, #"{"cards": [{"front": "Capital of France?", "back": "Paris"}, {"front": " ", "back": "x"}], "notes": "ok"}"#)
        expectEqual(report.cards, [FlashcardDraft(front: "Capital of France?", back: "Paris")], "blank cards dropped")
        expectEqual(report.notes, "ok")
        expectEqual(try lifeDecode(FlashcardDraftReport.self, "{}").cards, [])
    }

    suite("ClothingCategory and OutfitRules") {
        expectEqual(ClothingCategory.guess("Graphic T-shirt"), .top)
        expectEqual(ClothingCategory.guess("slim jeans"), .bottom)
        expectEqual(ClothingCategory.guess("Chelsea boots"), .shoes)
        expectEqual(ClothingCategory.guess("denim jacket"), .outerwear)
        expectEqual(ClothingCategory.guess("maxi dress"), .dress)
        expectEqual(ClothingCategory.guess("leather belt"), .accessory)
        expectEqual(ClothingCategory.guess("outerwear"), .outerwear)
        expectEqual(ClothingCategory.guess("spaceship"), .other)

        expect(OutfitRules.isComplete([.top, .bottom, .shoes]))
        expect(OutfitRules.isComplete([.dress, .shoes, .bag]))
        expectEqual(OutfitRules.missing([.top]), [.bottom, .shoes])
        expectEqual(OutfitRules.missing([]), [.top, .bottom, .shoes])
        expectEqual(OutfitRules.hint([.top]), "Add a bottom and shoes")
        expectEqual(OutfitRules.hint([.top, .bottom]), "Add shoes")
        expectEqual(OutfitRules.hint([]), "Add a top, a bottom and shoes")
        expectEqual(OutfitRules.hint([.dress, .shoes]), nil)
    }

    suite("ClothingColor and seasons") {
        expectEqual(ClothingColor.guess("Charcoal"), .gray)
        expectEqual(ClothingColor.guess("light blue"), .lightBlue)
        expectEqual(ClothingColor.guess("light-blue"), .lightBlue)
        expectEqual(ClothingColor.guess("navy"), .navy)
        expectEqual(ClothingColor.guess("dark navy blue"), .navy)
        expectEqual(ClothingColor.guess("khaki"), .tan)
        expectEqual(ClothingColor.guess("chartreuse"), nil)
        expect(ClothingColor.navy.isNeutral && !ClothingColor.red.isNeutral)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        expectEqual(ClothingSeason.current(on: lifeNow, calendar: calendar), .fall)
        expectEqual(ClothingSeason.current(on: lifeNow, southernHemisphere: true, calendar: calendar), .spring)
    }

    suite("WardrobeStats") {
        expectEqual(WardrobeStats.costPerWearCents(priceCents: 6_000, timesWorn: 4), 1_500)
        expectEqual(WardrobeStats.costPerWearCents(priceCents: 6_000, timesWorn: 0), 6_000)
        expectEqual(WardrobeStats.costPerWearCents(priceCents: nil, timesWorn: 3), nil)
        let day = 86_400.0
        let items = [
            WardrobeWearInfo(id: "a", timesWorn: 10, lastWornAt: lifeNow.addingTimeInterval(-2 * day), priceCents: nil, addedAt: lifeNow.addingTimeInterval(-400 * day)),
            WardrobeWearInfo(id: "b", timesWorn: 0, lastWornAt: nil, priceCents: nil, addedAt: lifeNow.addingTimeInterval(-200 * day)),
            WardrobeWearInfo(id: "c", timesWorn: 3, lastWornAt: lifeNow.addingTimeInterval(-120 * day), priceCents: nil, addedAt: lifeNow.addingTimeInterval(-300 * day)),
            WardrobeWearInfo(id: "d", timesWorn: 10, lastWornAt: lifeNow.addingTimeInterval(-1 * day), priceCents: nil, addedAt: lifeNow.addingTimeInterval(-30 * day)),
            WardrobeWearInfo(id: "e", timesWorn: 0, lastWornAt: nil, priceCents: nil, addedAt: lifeNow.addingTimeInterval(-10 * day)),
        ]
        expectEqual(WardrobeStats.forgotten(items, days: 90, now: lifeNow), ["b", "c"])
        expectEqual(WardrobeStats.mostWorn(items, limit: 2), ["d", "a"])
    }

    suite("ClothingTags decoding") {
        let tags = try lifeDecode(ClothingTags.self, """
        {"is_clothing": true, "name": "Navy wool overcoat", "category": "coat", "colors": ["navy", "Navy", "charcoal", "chartreuse"],
         "pattern": "solid", "seasons": ["Autumn", "winter"], "styles": ["smart casual", "business"], "formality": 9, "warmth": 5}
        """)
        expectEqual(tags.category, .outerwear)
        expectEqual(tags.colors, [.navy, .gray], "deduped, unknown dropped")
        expectEqual(tags.seasons, [.fall, .winter])
        expectEqual(tags.styles, [.smartCasual, .business])
        expectEqual(tags.formality, 5, "clamped")
        let empty = try lifeDecode(ClothingTags.self, "{}")
        expect(empty.isClothing)
        expectEqual(empty.category, .other)
        expectEqual(empty.formality, 2)
    }

    suite("OutfitIdeaReport") {
        let report = try lifeDecode(OutfitIdeaReport.self, """
        {"outfits": [
          {"name": "Weekend", "item_ids": ["t1", "b1", "s1", "ghost"], "reason": "Easy"},
          {"name": "Too thin", "item_ids": ["t1", "ghost2"], "reason": ""},
          {"name": "Dupes", "item_ids": ["t1", "t1", "b1"], "reason": ""}
        ], "notes": "Bring a jacket"}
        """)
        let cleaned = report.keepingOnly(knownIDs: ["t1", "b1", "s1"])
        expectEqual(cleaned.outfits.map(\.name), ["Weekend", "Dupes"])
        expectEqual(cleaned.outfits[0].itemIDs, ["t1", "b1", "s1"])
        expectEqual(cleaned.outfits[1].itemIDs, ["t1", "b1"])
        expectEqual(cleaned.notes, "Bring a jacket")
        let summary = WardrobePieceSummary(id: "t1", name: "Tee", category: "top", colors: ["white"], seasons: ["summer"], styles: ["casual"], formality: 1, warmth: 1, timesWorn: 3)
        let json = String(decoding: try JSONEncoder().encode(summary), as: UTF8.self)
        expect(json.contains("\"times_worn\":3"))
    }

    suite("JSONValue") {
        let json = #"{"type":"tool_use","id":"toolu_1","name":"get_spending","input":{"month":"2026-11","limit":5,"ratio":0.25,"flag":true,"none":null,"list":[1,"a"]}}"#
        let value = try lifeDecode(JSONValue.self, json)
        expectEqual(value["name"]?.stringValue, "get_spending")
        expectEqual(value["input"]?["limit"]?.intValue, 5)
        expectEqual(value["input"]?["ratio"]?.numberValue, 0.25)
        expectEqual(value["input"]?["flag"]?.boolValue, true)
        expectEqual(value["input"]?["none"], .null)
        expectEqual(value["input"]?["list"]?.arrayValue?.count, 2)
        // Round trip keeps whole numbers whole.
        let text = value.jsonText
        expect(text.contains("\"limit\":5"))
        expect(!text.contains("5.0"))
        expectEqual(try lifeDecode(JSONValue.self, text), value)
        expectEqual(JSONValue.string("a/b").jsonText, "\"a/b\"")
    }

    suite("AssistantMessage") {
        let reply = try lifeDecode(AssistantReply.self, """
        {"stop_reason": "tool_use", "content": [
          {"type": "thinking", "thinking": "", "signature": "abc=="},
          {"type": "text", "text": "Let me check."},
          {"type": "tool_use", "id": "toolu_1", "name": "get_budgets", "input": {"month": "2026-11"}},
          {"type": "tool_use", "id": "toolu_2", "name": "get_spending", "input": {}}
        ]}
        """)
        expectEqual(reply.stopReason, "tool_use")
        let message = reply.message
        expectEqual(message.role, .assistant)
        expectEqual(message.text, "Let me check.")
        expectEqual(message.toolUses.map(\.name), ["get_budgets", "get_spending"])
        expectEqual(message.toolUses[0].string("month"), "2026-11")
        expectEqual(message.toolUses[1].string("month"), nil)
        // Thinking blocks survive a round trip byte-for-byte in their fields.
        let encoded = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(AssistantMessage.self, from: encoded)
        expectEqual(decoded.content[0]["signature"]?.stringValue, "abc==")

        let results = AssistantMessage.toolResults([
            AssistantToolResult(toolUseID: "toolu_1", content: "{\"ok\":true}", isError: false),
            AssistantToolResult(toolUseID: "toolu_2", content: "Not available", isError: true),
        ])
        expect(results.isToolResults)
        expectEqual(results.content[1]["is_error"]?.boolValue, true)
        expectEqual(results.content[0]["is_error"], nil)
        expect(!AssistantMessage.user("Hi").isToolResults)

        let conversation = [AssistantMessage.user("How much did I spend?"), message, results,
                            AssistantMessage(role: .assistant, content: [.object(["type": .string("text"), "text": .string("You spent $1,200.")])])]
        expectEqual(AssistantConversation.toolsUsedInLastAnswer(conversation), [.budgets, .spending])
        expectEqual(AssistantConversation.toolsUsedInLastAnswer(conversation + [.user("Thanks")]), [])
    }

    suite("AssistantConversation.trimmed") {
        let long = String(repeating: "x", count: 1_000)
        var messages: [AssistantMessage] = []
        for i in 0..<10 {
            messages.append(.user("q\(i) " + long))
            messages.append(AssistantMessage(role: .assistant, content: [.object(["type": .string("text"), "text": .string("a\(i) " + long)])]))
        }
        let trimmed = AssistantConversation.trimmed(messages, maxCharacters: 5_000)
        expect(trimmed.count < messages.count)
        expectEqual(trimmed.first?.role, .user)
        expect(trimmed.first?.text.hasPrefix("q") ?? false)
        expectEqual(trimmed.last, messages.last)
        expectEqual(AssistantConversation.trimmed(messages).count, messages.count, "fits: unchanged")
        // Never starts with tool results.
        let withTools = [AssistantMessage.user("old " + long), AssistantMessage(role: .assistant, content: [.object(["type": .string("tool_use"), "id": .string("t"), "name": .string("get_overview"), "input": .object([:])])]),
                         AssistantMessage.toolResults([AssistantToolResult(toolUseID: "t", content: long, isError: false)]),
                         AssistantMessage(role: .assistant, content: [.object(["type": .string("text"), "text": .string(long)])]),
                         AssistantMessage.user("new")]
        let cut = AssistantConversation.trimmed(withTools, maxCharacters: 1_500)
        expectEqual(cut.first?.text, "new")
    }

    suite("AssistantContext") {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let context = AssistantContext.current(now: lifeNow, firstName: "Sam", calendar: calendar, locale: Locale(identifier: "en_US"))
        expect(context.today.hasPrefix("2026-11-"))
        expectEqual(context.timeZone, "America/New_York")
        expectEqual(context.currency, "USD")
        let json = String(decoding: try JSONEncoder().encode(context), as: UTF8.self)
        expect(json.contains("\"time_zone\""))
        expect(json.contains("\"first_name\":\"Sam\""))
    }
}
