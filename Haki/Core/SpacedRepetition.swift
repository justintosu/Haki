//
//  SpacedRepetition.swift
//  Haki
//
//  Pure Foundation code (see Money.swift): flashcard scheduling (an SM-2
//  style spaced-repetition scheduler), the study queue, and checking typed
//  answers.
//

import Foundation

nonisolated enum ReviewGrade: Int, CaseIterable, Codable, Identifiable, Sendable {
    case again = 0, hard, good, easy

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .again: "Again"
        case .hard: "Hard"
        case .good: "Good"
        case .easy: "Easy"
        }
    }
}

/// Where a card stands in its review schedule.
nonisolated struct CardSchedule: Equatable, Codable, Sendable {
    /// Successful reviews in a row (reset by "Again").
    var repetitions: Int = 0
    /// Days until the next review after the last one.
    var intervalDays: Double = 0
    /// How fast intervals grow (SM-2's ease factor), 1.3...3.0.
    var ease: Double = 2.5
    /// When it's next due; nil for a card never studied.
    var dueAt: Date?
    /// Times it was forgotten after being learned.
    var lapses: Int = 0
    var lastReviewedAt: Date?

    static let new = CardSchedule()

    var isNew: Bool { lastReviewedAt == nil }

    /// Learned well enough to have an interval of three weeks or more.
    var isMature: Bool { intervalDays >= 21 }
}

nonisolated enum SpacedRepetition {
    static let minimumEase = 1.3
    static let maximumEase = 3.0
    /// "Again" brings a card back in ten minutes.
    static let relearnDays = 10.0 / (24 * 60)

    /// The schedule after answering a card with `grade` at `now`.
    static func review(_ schedule: CardSchedule, grade: ReviewGrade, now: Date) -> CardSchedule {
        var next = schedule
        next.lastReviewedAt = now
        switch grade {
        case .again:
            if schedule.repetitions > 0 { next.lapses += 1 }
            next.repetitions = 0
            next.intervalDays = relearnDays
            next.ease = max(minimumEase, schedule.ease - 0.2)
        case .hard:
            next.intervalDays = schedule.repetitions == 0 ? 0.5 : max(1, schedule.intervalDays * 1.2)
            next.repetitions = schedule.repetitions + 1
            next.ease = max(minimumEase, schedule.ease - 0.15)
        case .good:
            next.intervalDays = goodInterval(schedule)
            next.repetitions = schedule.repetitions + 1
        case .easy:
            next.intervalDays = max(4, goodInterval(schedule) * 1.3)
            next.repetitions = schedule.repetitions + 1
            next.ease = min(maximumEase, schedule.ease + 0.15)
        }
        next.intervalDays = min(next.intervalDays, 365 * 2)
        next.dueAt = now.addingTimeInterval(next.intervalDays * 86_400)
        return next
    }

    private static func goodInterval(_ schedule: CardSchedule) -> Double {
        switch schedule.repetitions {
        case 0: 1
        case 1: 3
        default: max(schedule.intervalDays * schedule.ease, schedule.intervalDays + 1)
        }
    }

    /// Whether a studied card is due at `now` (new cards are never "due").
    static func isDue(_ schedule: CardSchedule, now: Date) -> Bool {
        guard let dueAt = schedule.dueAt else { return false }
        return dueAt <= now
    }

    /// What to study next: due cards (most overdue first, at most
    /// `reviewLimit`), then new cards in the order given (at most `newLimit`).
    static func studyQueue<ID: Hashable>(
        _ cards: [(id: ID, schedule: CardSchedule)],
        now: Date,
        newLimit: Int = 20,
        reviewLimit: Int = 200
    ) -> [ID] {
        let due = cards
            .filter { !$0.schedule.isNew && isDue($0.schedule, now: now) }
            .sorted { ($0.schedule.dueAt ?? now) < ($1.schedule.dueAt ?? now) }
            .prefix(max(reviewLimit, 0))
            .map(\.id)
        let fresh = cards.filter { $0.schedule.isNew }.prefix(max(newLimit, 0)).map(\.id)
        return Array(due) + Array(fresh)
    }

    /// "10m", "12h", "1d", "3d", "2w", "4mo" for an interval in days.
    static func intervalText(days: Double) -> String {
        let minutes = days * 24 * 60
        if minutes < 60 { return "\(max(1, Int(minutes.rounded())))m" }
        if days < 1 { return "\(Int((days * 24).rounded()))h" }
        if days < 14 { return "\(Int(days.rounded()))d" }
        if days < 60 { return "\(Int((days / 7).rounded()))w" }
        if days < 365 { return "\(Int((days / 30).rounded()))mo" }
        return String(format: "%.1fy", days / 365)
    }

    /// The interval each grade would give, for the grade buttons.
    static func previewIntervals(_ schedule: CardSchedule, now: Date) -> [ReviewGrade: String] {
        var result: [ReviewGrade: String] = [:]
        for grade in ReviewGrade.allCases {
            result[grade] = intervalText(days: review(schedule, grade: grade, now: now).intervalDays)
        }
        return result
    }
}

/// Checks typed answers in quiz mode: forgiving about case, accents,
/// punctuation, articles and a small typo.
nonisolated enum AnswerChecker {
    /// Lowercase, no diacritics, punctuation turned into spaces, leading
    /// "the/a/an" dropped, single spaces.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US"))
        let cleaned = String(folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " })
        var words = cleaned.split(separator: " ").map(String.init)
        if words.count > 1, let first = words.first, ["the", "a", "an"].contains(first) {
            words.removeFirst()
        }
        return words.joined(separator: " ")
    }

    /// The accepted answers in `expected`: split on "/", ";" or " or ".
    static func alternatives(_ expected: String) -> [String] {
        let separated = expected
            .replacingOccurrences(of: " or ", with: "/")
            .replacingOccurrences(of: ";", with: "/")
            .split(separator: "/")
            .map { normalize(String($0)) }
            .filter { !$0.isEmpty }
        let whole = normalize(expected)
        return separated.isEmpty ? [whole] : Array(Set(separated + [whole]))
    }

    /// Whether `typed` matches `expected`, allowing one typo in answers of
    /// 5+ characters and two in answers of 12+.
    static func isCorrect(typed: String, expected: String) -> Bool {
        let answer = normalize(typed)
        guard !answer.isEmpty else { return false }
        for candidate in alternatives(expected) {
            if answer == candidate { return true }
            let allowed = candidate.count >= 12 ? 2 : (candidate.count >= 5 ? 1 : 0)
            if allowed > 0, abs(answer.count - candidate.count) <= allowed, levenshtein(answer, candidate) <= allowed {
                return true
            }
        }
        return false
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let x = Array(a)
        let y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var previous = Array(0...y.count)
        var current = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            current[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[y.count]
    }
}

/// AI-made flashcards ("haki-ai" make_flashcards), before the person keeps them.
nonisolated struct FlashcardDraft: Equatable, Hashable, Codable, Sendable {
    var front: String
    var back: String
}

nonisolated struct FlashcardDraftReport: Equatable, Codable, Sendable {
    var cards: [FlashcardDraft]
    var notes: String

    init(cards: [FlashcardDraft], notes: String = "") {
        self.cards = cards
        self.notes = notes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cards = (try container.decodeIfPresent([FlashcardDraft].self, forKey: .cards) ?? [])
            .filter { !$0.front.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.back.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    enum CodingKeys: String, CodingKey { case cards, notes }
}
