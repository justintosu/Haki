//
//  AssistantToolData.swift
//  Haki
//
//  Pure helpers for the "Ask Haki" device tools (`AssistantToolExecutor`):
//  reading tool inputs (days, months, numbers, names), building compact JSON
//  with `JSONValue`, matching search text, and keeping a result under the
//  size the server accepts. Foundation and Core types only (no SwiftData, no
//  services), so every function here is easy to reason about and test.
//

import Foundation

/// A span of whole days read from a tool's "from"/"to" inputs.
nonisolated struct AssistantToolDayRange: Equatable, Sendable {
    /// Midnight at the start of the first day.
    let start: Date
    /// Midnight at the start of the day after the last day (exclusive end).
    let end: Date
    /// The first and last day, for display.
    let firstDay: Date
    let lastDay: Date
    /// Number of days covered.
    let dayCount: Int
    /// What was assumed or corrected, for the assistant to mention.
    let notes: [String]
}

/// One merchant's spending in a period.
nonisolated struct AssistantToolMerchantTotal: Equatable, Sendable {
    let key: String
    let name: String
    let cents: Int
    let count: Int
}

nonisolated enum AssistantToolData {
    /// The most a tool result may hold, in UTF-16 characters of JSON (the
    /// server accepts 40,000; this leaves room for the rest of the request).
    static let maxCharacters = 30_000

    // MARK: - JSON values

    /// Text, trimmed and clipped to `limit` characters.
    static func text(_ value: String, limit: Int = 500) -> JSONValue {
        .string(clipped(value, limit: limit))
    }

    static func int(_ value: Int) -> JSONValue {
        .number(Double(value))
    }

    /// `value` rounded to `places` decimals; null when it isn't finite.
    static func number(_ value: Double, places: Int = 1) -> JSONValue {
        guard value.isFinite else { return .null }
        return .number(rounded(value, places: places))
    }

    /// Cents as a decimal amount in the currency: 1250 → 12.5.
    static func money(_ cents: Int) -> JSONValue {
        .number(Double(cents) / 100)
    }

    /// A brokerage amount (already in currency units), to the cent.
    static func dollars(_ value: Double) -> JSONValue {
        number(value, places: 2)
    }

    /// A fraction (0.256) as a percentage with one decimal (25.6).
    static func percent(_ fraction: Double) -> JSONValue {
        number(fraction * 100, places: 1)
    }

    /// "YYYY-MM-DD" in `calendar`'s time zone.
    static func day(_ date: Date, calendar: Calendar) -> JSONValue {
        .string(dayString(date, calendar: calendar))
    }

    /// "YYYY-MM-DDTHH:MM", local time.
    static func dateTime(_ date: Date, calendar: Calendar) -> JSONValue {
        .string(dateTimeString(date, calendar: calendar))
    }

    static func strings(_ values: [String]) -> JSONValue {
        .array(values.map { JSONValue.string($0) })
    }

    static func objects(_ values: [[String: JSONValue]]) -> JSONValue {
        .array(values.map { JSONValue.object($0) })
    }

    static func rounded(_ value: Double, places: Int) -> Double {
        var factor = 1.0
        for _ in 0..<max(0, min(places, 8)) { factor *= 10 }
        return (value * factor).rounded() / factor
    }

    // MARK: - Dates

    static func dayString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))"
    }

    static func dateTimeString(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(pad(parts.year, 4))-\(pad(parts.month, 2))-\(pad(parts.day, 2))T\(pad(parts.hour, 2)):\(pad(parts.minute, 2))"
    }

    /// "YYYY-MM".
    static func monthString(_ month: MonthInterval) -> String {
        "\(pad(month.year, 4))-\(pad(month.month, 2))"
    }

    private static func pad(_ value: Int?, _ width: Int) -> String {
        let number = value ?? 0
        let digits = String(abs(number))
        let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
        return number < 0 ? "-" + padded : padded
    }

    // MARK: - Reading inputs

    /// "YYYY-MM-DD" (a longer ISO date-time is cut to its date) → midnight
    /// at the start of that day; nil when it isn't a real date.
    static func parseDay(_ text: String?, calendar: Calendar) -> Date? {
        guard let parts = dateParts(text), parts.count == 3, (1900...2200).contains(parts[0]),
              let noon = calendar.noon(year: parts[0], month: parts[1], day: parts[2])
        else { return nil }
        return calendar.startOfDay(for: noon)
    }

    /// "YYYY-MM" (or a full date) → that month; nil when it isn't one.
    static func parseMonth(_ text: String?) -> MonthInterval? {
        guard let parts = dateParts(text), parts.count >= 2,
              (1900...2200).contains(parts[0]), (1...12).contains(parts[1])
        else { return nil }
        return MonthInterval(year: parts[0], month: parts[1])
    }

    /// The numbers of "2026-11-09" or "2026-11" (anything after the date,
    /// such as "T10:00", is ignored).
    private static func dateParts(_ text: String?) -> [Int]? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let datePart = trimmed.prefix(while: { $0.isASCII && ($0.isNumber || $0 == "-") })
        let pieces = datePart.split(separator: "-", omittingEmptySubsequences: false)
        guard (2...3).contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.count <= 4, let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        return numbers
    }

    /// `value` limited to `range`, or `fallback` when missing.
    static func clamped(_ value: Int?, to range: ClosedRange<Int>, default fallback: Int) -> Int {
        guard let value else { return fallback }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    /// A number input that may arrive as a JSON number or as text ("25", "$25.50").
    static func decimal(_ value: JSONValue?) -> Double? {
        if let number = value?.numberValue {
            return number.isFinite ? number : nil
        }
        guard let text = value?.stringValue else { return nil }
        let cleaned = text.filter { $0.isASCII && ($0.isNumber || $0 == "." || $0 == "-") }
        guard let number = Double(cleaned), number.isFinite else { return nil }
        return number
    }

    /// Whole cents for an amount in currency units, ignoring the sign; nil
    /// for amounts too large to be real.
    static func cents(fromAmount amount: Double) -> Int? {
        let magnitude = abs(amount)
        guard magnitude.isFinite, magnitude < 1_000_000_000_000 else { return nil }
        return Int((magnitude * 100).rounded())
    }

    /// The days from "from" to "to" (inclusive). Missing ends default to
    /// today and `defaultDays` back; invalid ones are ignored with a note;
    /// reversed ends are swapped; spans longer than `maxDays` keep the
    /// latest `maxDays` days.
    static func dayRange(
        from fromText: String?,
        to toText: String?,
        defaultDays: Int,
        maxDays: Int,
        now: Date,
        calendar: Calendar
    ) -> AssistantToolDayRange {
        var notes: [String] = []
        let today = calendar.startOfDay(for: now)
        let parsedFrom = parseDay(fromText, calendar: calendar)
        let parsedTo = parseDay(toText, calendar: calendar)
        if let fromText, parsedFrom == nil {
            notes.append("\"from\" (\(clipped(fromText, limit: 30))) isn't a date like \(dayString(today, calendar: calendar)), so it was ignored.")
        }
        if let toText, parsedTo == nil {
            notes.append("\"to\" (\(clipped(toText, limit: 30))) isn't a date like \(dayString(today, calendar: calendar)), so it was ignored.")
        }
        let span = max(1, defaultDays)
        var lastDay = parsedTo ?? today
        var firstDay = parsedFrom ?? (calendar.date(byAdding: .day, value: -(span - 1), to: lastDay) ?? lastDay)
        if parsedFrom != nil, parsedTo == nil, firstDay > today {
            // Only a start in the future: show that one day.
            lastDay = firstDay
        }
        if firstDay > lastDay {
            swap(&firstDay, &lastDay)
            notes.append("\"from\" was after \"to\", so they were swapped.")
        }
        let limit = max(1, maxDays)
        if calendar.daysBetween(firstDay, lastDay) + 1 > limit {
            firstDay = calendar.date(byAdding: .day, value: -(limit - 1), to: lastDay) ?? firstDay
            notes.append("At most \(limit) days at a time, so this starts on \(dayString(firstDay, calendar: calendar)).")
        }
        if parsedFrom == nil, parsedTo == nil {
            notes.append("No dates given, so this is the last \(span) day\(span == 1 ? "" : "s") through today.")
        }
        let end = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay.addingTimeInterval(86_400)
        return AssistantToolDayRange(
            start: firstDay,
            end: end,
            firstDay: firstDay,
            lastDay: lastDay,
            dayCount: calendar.daysBetween(firstDay, lastDay) + 1,
            notes: notes
        )
    }

    // MARK: - Text

    /// Trimmed, and cut to `limit` characters with an ellipsis.
    static func clipped(_ text: String, limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard limit > 0, trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(max(1, limit - 1))) + "…"
    }

    /// Lowercased, without accents, for matching what someone typed.
    static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// The words of a search, folded.
    static func searchWords(_ query: String?) -> [String] {
        guard let query else { return [] }
        return folded(query)
            .split(whereSeparator: { $0.isWhitespace || $0 == "," })
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    /// Whether every word appears somewhere in `fields` (always true without words).
    static func matches(_ words: [String], in fields: [String]) -> Bool {
        guard !words.isEmpty else { return true }
        let haystack = fields.map { folded($0) }.joined(separator: "\n")
        return words.allSatisfy { haystack.contains($0) }
    }

    /// The index of the name that best matches `query`: the same name, then
    /// the same word ignoring a plural ("groceries" / "Grocery"), then one
    /// starting with it, containing it, or contained in it.
    static func bestMatch(_ query: String, in names: [String]) -> Int? {
        let wanted = folded(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !wanted.isEmpty else { return nil }
        let candidates = names.map { folded($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let index = candidates.firstIndex(of: wanted) { return index }
        let wantedStem = stem(wanted)
        let stems = candidates.map { stem($0) }
        if let index = stems.firstIndex(of: wantedStem) { return index }
        if let index = stems.firstIndex(where: { $0.hasPrefix(wantedStem) }) { return index }
        if let index = stems.firstIndex(where: { $0.contains(wantedStem) }) { return index }
        if let index = stems.firstIndex(where: { $0.count >= 3 && wantedStem.contains($0) }) { return index }
        return nil
    }

    /// A rough singular: "groceries" → "grocery", "bills" → "bill".
    private static func stem(_ text: String) -> String {
        if text.hasSuffix("ies"), text.count > 4 { return String(text.dropLast(3)) + "y" }
        if text.hasSuffix("s"), !text.hasSuffix("ss"), text.count > 3 { return String(text.dropLast()) }
        return text
    }

    // MARK: - Ledger

    static func flowName(_ flow: LedgerFlow) -> String {
        switch flow {
        case .spending: "spending"
        case .income: "income"
        case .transfer: "transfer"
        case .excluded: "excluded"
        }
    }

    static func paceName(_ pace: BudgetPace) -> String {
        switch pace {
        case .onTrack: "on_track"
        case .aheadOfPace: "ahead_of_pace"
        case .overBudget: "over_budget"
        }
    }

    /// Spending per merchant, largest first. Pass entries newest first so
    /// each merchant is named as it was most recently.
    static func topMerchants<E: LedgerEntry>(_ entries: [E], limit: Int) -> [AssistantToolMerchantTotal] {
        var order: [String] = []
        var names: [String: String] = [:]
        var totals: [String: Int] = [:]
        var counts: [String: Int] = [:]
        for entry in entries where entry.ledgerFlow == .spending {
            let key = entry.ledgerMerchantKey.isEmpty ? folded(entry.ledgerMerchant) : entry.ledgerMerchantKey
            if names[key] == nil {
                names[key] = entry.ledgerMerchant
                order.append(key)
            }
            totals[key, default: 0] += entry.ledgerAmountCents
            counts[key, default: 0] += 1
        }
        let merchants = order.compactMap { key -> AssistantToolMerchantTotal? in
            let cents = totals[key] ?? 0
            guard cents > 0 else { return nil }
            return AssistantToolMerchantTotal(key: key, name: names[key] ?? key, cents: cents, count: counts[key] ?? 0)
        }
        let sorted = merchants.sorted { lhs, rhs in
            if lhs.cents != rhs.cents { return lhs.cents > rhs.cents }
            return lhs.name < rhs.name
        }
        return Array(sorted.prefix(max(0, limit)))
    }

    /// One due date of a recurring bill and whether it was paid.
    static func occurrence(dueDate: Date, status: RecurringOccurrenceStatus, calendar: Calendar) -> [String: JSONValue] {
        var fields: [String: JSONValue] = ["due": day(dueDate, calendar: calendar)]
        switch status {
        case .paid(on: let date, amountCents: let cents):
            fields["status"] = .string("paid")
            fields["paid_on"] = day(date, calendar: calendar)
            fields["paid_amount"] = money(cents)
        case .upcoming:
            fields["status"] = .string("upcoming")
        case .late:
            fields["status"] = .string("late (no matching charge found)")
        }
        return fields
    }

    // MARK: - Workouts

    /// "60 kg × 8", "12 reps", "45s", "1.20 km in 6:30", with warm-up /
    /// drop-set / failure and RPE marks.
    static func setText(_ set: SetValues, weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> String {
        var parts: [String] = []
        if let weight = set.weightKg, weight > 0 {
            parts.append("\(weightUnit.format(kilograms: weight)) \(weightUnit.symbol)")
        }
        if let reps = set.reps, reps > 0 {
            parts.append(parts.isEmpty ? "\(reps) reps" : "× \(reps)")
        }
        if let meters = set.distanceMeters, meters > 0 {
            parts.append("\(distanceUnit.format(meters: meters)) \(distanceUnit.symbol)")
        }
        if let seconds = set.durationSeconds, seconds > 0 {
            let time = WorkoutMath.formatTimer(seconds: seconds)
            parts.append(parts.isEmpty ? time : "in \(time)")
        }
        if parts.isEmpty { parts.append("empty set") }
        switch set.kind {
        case .normal: break
        case .warmup: parts.append("(warm-up)")
        case .dropset: parts.append("(drop set)")
        case .failure: parts.append("(to failure)")
        }
        if let rpe = set.rpe, rpe > 0 {
            parts.append("@RPE \(rounded(rpe, places: 1))")
        }
        if !set.isCompleted { parts.append("(not done)") }
        return parts.joined(separator: " ")
    }

    /// A weight in the person's unit.
    static func weight(_ kilograms: Double, unit: WeightUnit) -> JSONValue {
        number(unit.fromKilograms(kilograms), places: 1)
    }

    static func records(_ records: PersonalRecords, unit: WeightUnit) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        if let value = records.heaviestWeightKg { fields["heaviest_weight"] = weight(value, unit: unit) }
        if let value = records.bestOneRepMaxKg { fields["best_estimated_1rm"] = weight(value, unit: unit) }
        if let value = records.mostReps { fields["most_reps"] = int(value) }
        if let value = records.bestSetVolumeKg { fields["best_set_volume"] = weight(value, unit: unit) }
        return fields
    }

    /// Records that `after` beats compared with `before` (which must have
    /// one: the first time isn't a personal record).
    static func improvedRecords(before: PersonalRecords, after: PersonalRecords) -> [RecordKind] {
        var kinds: [RecordKind] = []
        if let old = before.heaviestWeightKg, let new = after.heaviestWeightKg, new > old + 0.001 { kinds.append(.heaviestWeight) }
        if let old = before.bestOneRepMaxKg, let new = after.bestOneRepMaxKg, new > old + 0.001 { kinds.append(.bestOneRepMax) }
        if let old = before.mostReps, let new = after.mostReps, new > old { kinds.append(.mostReps) }
        if let old = before.bestSetVolumeKg, let new = after.bestSetVolumeKg, new > old + 0.001 { kinds.append(.bestSetVolume) }
        return kinds
    }

    // MARK: - Wardrobe

    static func clothingCategory(_ text: String) -> ClothingCategory? {
        let wanted = folded(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !wanted.isEmpty else { return nil }
        for category in ClothingCategory.allCases
        where wanted == category.rawValue || wanted == folded(category.title) || wanted == folded(category.singularTitle) {
            return category
        }
        let guessed = ClothingCategory.guess(wanted)
        if guessed != .other { return guessed }
        return wanted.contains("other") ? .other : nil
    }

    static func clothingSeason(_ text: String) -> ClothingSeason? {
        let wanted = folded(text)
        if wanted.contains("autumn") { return .fall }
        return ClothingSeason.allCases.first(where: { wanted.contains($0.rawValue) })
    }

    static func clothingStyle(_ text: String) -> ClothingStyle? {
        let wanted = folded(text)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        for style in ClothingStyle.allCases
        where wanted == style.rawValue.replacingOccurrences(of: "_", with: " ") || wanted == folded(style.title) {
            return style
        }
        // Most specific first: "smart casual" before "casual".
        let table: [(ClothingStyle, [String])] = [
            (.smartCasual, ["smart casual", "smart", "business casual"]),
            (.business, ["business", "work", "office", "professional"]),
            (.formal, ["formal", "black tie", "wedding", "dressy", "gala"]),
            (.athletic, ["athletic", "gym", "sport", "workout", "running", "training"]),
            (.lounge, ["lounge", "home", "relax", "sleep"]),
            (.party, ["party", "going out", "night out", "club", "date"]),
            (.outdoor, ["outdoor", "hiking", "hike", "camping", "rain"]),
            (.casual, ["casual", "everyday", "weekend", "relaxed"]),
        ]
        for (style, words) in table where words.contains(where: { wanted.contains($0) }) {
            return style
        }
        return nil
    }

    // MARK: - Fitting the size limit

    /// `fields` as compact JSON of at most `maxCharacters` UTF-16
    /// characters: while it's too big, the biggest list (searching nested
    /// values) is halved, or the longest text clipped, and the result is
    /// marked `"truncated": true`.
    static func fitted(_ fields: [String: JSONValue], maxCharacters: Int = maxCharacters) -> String {
        var value = JSONValue.object(fields)
        var text = value.jsonText
        var rounds = 0
        while text.utf16.count > maxCharacters, rounds < 60, let smaller = shrunk(value) {
            value = markedTruncated(smaller)
            text = value.jsonText
            rounds += 1
        }
        guard text.utf16.count <= maxCharacters else {
            let fallback: [String: JSONValue] = [
                "truncated": .bool(true),
                "note": .string("The result was too large to send. Ask about a shorter period or fewer items."),
            ]
            return JSONValue.object(fallback).jsonText
        }
        return text
    }

    /// A smaller version of `value`, or nil when nothing can shrink.
    static func shrunk(_ value: JSONValue) -> JSONValue? {
        switch value {
        case .array(let items):
            if items.count > 1 {
                return .array(Array(items.prefix(items.count / 2)))
            }
            guard let first = items.first, let smaller = shrunk(first) else { return nil }
            return .array([smaller])
        case .object(let fields):
            var sizes: [String: Int] = [:]
            for (key, child) in fields {
                sizes[key] = child.jsonText.utf16.count
            }
            let keys = fields.keys.sorted { lhs, rhs in
                let left = sizes[lhs] ?? 0
                let right = sizes[rhs] ?? 0
                if left != right { return left > right }
                return lhs < rhs
            }
            for key in keys {
                guard let child = fields[key], let smaller = shrunk(child) else { continue }
                var copy = fields
                copy[key] = smaller
                return .object(copy)
            }
            return nil
        case .string(let text):
            guard text.count > 120 else { return nil }
            return .string(String(text.prefix(text.count / 2)) + "…")
        case .null, .bool, .number:
            return nil
        }
    }

    private static func markedTruncated(_ value: JSONValue) -> JSONValue {
        guard case .object(var fields) = value else { return value }
        fields["truncated"] = .bool(true)
        return .object(fields)
    }
}
