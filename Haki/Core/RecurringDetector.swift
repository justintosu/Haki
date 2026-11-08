//
//  RecurringDetector.swift
//  Haki
//
//  Pure Foundation code (see Money.swift).
//

import Foundation

/// A merchant that looks like a recurring bill, found in transaction history.
nonisolated struct RecurringCandidate: Hashable, Identifiable {
    let merchantKey: String
    let displayName: String
    let frequency: RecurrenceFrequency
    /// The most recent charge, since prices change over time.
    let typicalAmountCents: Int
    let lastDate: Date
    let nextExpectedDate: Date
    let occurrenceCount: Int
    /// The category used most often for this merchant, if any.
    let categoryID: String?

    var id: String { merchantKey }
}

nonisolated enum RecurringDetector {
    /// Finds merchants charged at a regular interval for a consistent amount.
    ///
    /// A merchant qualifies when it has at least three spending charges on
    /// different days, the median gap between charges matches a frequency,
    /// at least 75% of gaps fit that frequency, at least 75% of amounts are
    /// within 15% (or $2) of the median amount, and the last charge is recent
    /// enough that the bill still looks active. Varying amounts are what keep
    /// weekly grocery runs from being suggested.
    static func candidates<E: LedgerEntry>(
        from entries: [E],
        now: Date = .now,
        calendar: Calendar = .current,
        excludingMerchantKeys excluded: Set<String> = []
    ) -> [RecurringCandidate] {
        var groups: [String: [E]] = [:]
        for entry in entries where entry.ledgerFlow == .spending && entry.ledgerAmountCents > 0 {
            let key = entry.ledgerMerchantKey
            guard !key.isEmpty, !excluded.contains(key) else { continue }
            groups[key, default: []].append(entry)
        }

        var result: [RecurringCandidate] = []
        for (key, group) in groups {
            // One charge per day: two coffees on the same day are one visit.
            var byDay: [Date: E] = [:]
            for entry in group {
                let day = calendar.startOfDay(for: entry.ledgerDate)
                if byDay[day] == nil { byDay[day] = entry }
            }
            let charges = byDay.sorted { $0.key < $1.key }.map(\.value)
            guard charges.count >= 3 else { continue }

            let gaps = zip(charges, charges.dropFirst()).map { calendar.daysBetween($0.ledgerDate, $1.ledgerDate) }
            guard let medianGap = median(gaps),
                  let frequency = RecurrenceFrequency.allCases.first(where: { $0.toleratedIntervalDays.contains(medianGap) })
            else { continue }

            let fittingGaps = gaps.filter { frequency.toleratedIntervalDays.contains($0) }.count
            guard Double(fittingGaps) >= 0.75 * Double(gaps.count) else { continue }

            let amounts = charges.map(\.ledgerAmountCents)
            guard let medianAmount = median(amounts) else { continue }
            let tolerance = max(200, Int(Double(medianAmount) * 0.15))
            let consistentAmounts = amounts.filter { abs($0 - medianAmount) <= tolerance }.count
            guard Double(consistentAmounts) >= 0.75 * Double(amounts.count) else { continue }

            guard let last = charges.last else { continue }
            let daysSinceLast = calendar.daysBetween(last.ledgerDate, now)
            let staleAfter = Int(frequency.approximateDays * 1.5) + 7
            guard daysSinceLast <= staleAfter else { continue }

            let schedule = RecurringSchedule(anchor: last.ledgerDate, frequency: frequency)
            let next = schedule.nextOccurrence(onOrAfter: max(now, schedule.occurrence(1, calendar: calendar)),
                                               calendar: calendar)

            result.append(RecurringCandidate(
                merchantKey: key,
                displayName: last.ledgerMerchant,
                frequency: frequency,
                typicalAmountCents: last.ledgerAmountCents,
                lastDate: last.ledgerDate,
                nextExpectedDate: next,
                occurrenceCount: charges.count,
                categoryID: mostCommon(charges.map(\.ledgerCategoryID))
            ))
        }
        return result.sorted {
            $0.nextExpectedDate != $1.nextExpectedDate ? $0.nextExpectedDate < $1.nextExpectedDate : $0.merchantKey < $1.merchantKey
        }
    }

    private static func median(_ values: [Int]) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func mostCommon(_ values: [String?]) -> String? {
        var counts: [String: Int] = [:]
        for case let value? in values { counts[value, default: 0] += 1 }
        return counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key
    }
}

// MARK: - Matching bills to payments

nonisolated enum RecurringOccurrenceStatus: Hashable {
    /// A matching charge was found.
    case paid(on: Date, amountCents: Int)
    /// Due today or later.
    case upcoming
    /// The due date has passed and no matching charge was found.
    case late
}

nonisolated enum RecurringMatcher {
    /// Days on either side of a due date in which a charge counts as paying it.
    static func matchWindowDays(for frequency: RecurrenceFrequency) -> Int {
        switch frequency {
        case .weekly: 2
        case .biweekly: 4
        default: 6
        }
    }

    /// The status of one due date of a recurring bill.
    /// - Parameters:
    ///   - merchantKey: the bill's merchant key (`MerchantNormalizer.key(for:)`).
    ///   - entries: transactions to search; only money-out entries are considered.
    static func status<E: LedgerEntry>(
        dueDate: Date,
        merchantKey: String,
        frequency: RecurrenceFrequency,
        entries: [E],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> RecurringOccurrenceStatus {
        let window = matchWindowDays(for: frequency)
        let match = entries
            .filter { entry in
                entry.ledgerAmountCents > 0
                    && entry.ledgerFlow != .excluded
                    && abs(calendar.daysBetween(dueDate, entry.ledgerDate)) <= window
                    && Categorizer.ruleMatches(ruleKey: merchantKey, merchantKey: entry.ledgerMerchantKey)
            }
            .min { abs(calendar.daysBetween(dueDate, $0.ledgerDate)) < abs(calendar.daysBetween(dueDate, $1.ledgerDate)) }

        if let match {
            return .paid(on: match.ledgerDate, amountCents: match.ledgerAmountCents)
        }
        return calendar.startOfDay(for: dueDate) >= calendar.startOfDay(for: now) ? .upcoming : .late
    }
}
