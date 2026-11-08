//
//  TransactionsSupport.swift
//  Haki
//
//  Filtering, searching and day grouping for the Transactions list, plus
//  amount-input helpers shared by the detail and editor screens.
//

import Foundation
import SwiftData

// MARK: - Day sections

/// One calendar day of transactions in the list, newest first.
struct TransactionsDaySection: Identifiable {
    /// Start of the day.
    let day: Date
    /// "Today", "Yesterday", "Mon, Nov 3"...
    let title: String
    let transactions: [TransactionRecord]
    /// Net spending of the transactions shown for this day (refunds reduce
    /// it, so it can be negative).
    let netSpendingCents: Int

    var id: Date { day }
}

// MARK: - Search

/// Search text prepared once per keystroke, then matched against many
/// transactions: merchant, notes, bank description, category, account and
/// amount ("12.5", "$1,234").
struct TransactionsSearchQuery {
    let text: String
    private let hasDigits: Bool
    /// Text such as "$12" or "1,234" that needs the fully formatted amount.
    private let needsFormattedAmount: Bool
    private let decimalSeparator: Character

    init(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = TransactionInput.decimalSeparator
        text = trimmed
        decimalSeparator = separator
        hasDigits = trimmed.contains(where: \.isNumber)
        needsFormattedAmount = trimmed.contains { character in
            !character.isNumber && character != separator
        }
    }

    var isEmpty: Bool { text.isEmpty }

    func matches(_ transaction: TransactionRecord) -> Bool {
        guard !text.isEmpty else { return true }
        if transaction.merchant.localizedStandardContains(text) { return true }
        if transaction.notes.localizedStandardContains(text) { return true }
        if transaction.originalDescription.localizedStandardContains(text) { return true }
        if let category = transaction.category {
            if category.name.localizedStandardContains(text) { return true }
        } else if "Uncategorized".localizedStandardContains(text) {
            return true
        }
        if let account = transaction.account, account.name.localizedStandardContains(text) { return true }
        if hasDigits {
            let magnitude = abs(transaction.amountCents)
            if needsFormattedAmount {
                if Money.format(magnitude).localizedStandardContains(text) { return true }
            } else if Self.plainAmount(magnitude, separator: decimalSeparator).contains(text) {
                return true
            }
        }
        return false
    }

    /// `1250` → `"12.50"`, without grouping, cheap enough to build for every row.
    private static func plainAmount(_ cents: Int, separator: Character) -> String {
        let whole = cents / 100
        let fraction = cents % 100
        let fractionText = fraction < 10 ? "0\(fraction)" : "\(fraction)"
        return "\(whole)\(separator)\(fractionText)"
    }
}

// MARK: - List logic

enum TransactionsListLogic {
    static func matches(_ transaction: TransactionRecord, filter: TransactionFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .needsReview:
            return !transaction.isReviewed
        case .excluded:
            return transaction.isExcluded
        case .category(let id):
            return transaction.category?.id == id
        case .uncategorized:
            return transaction.category == nil
        case .account(let id):
            return transaction.account?.id == id
        }
    }

    /// Groups transactions by calendar day, newest day first. Transactions
    /// keep their order within a day.
    static func daySections(
        _ transactions: [TransactionRecord],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [TransactionsDaySection] {
        let grouped = Dictionary(grouping: transactions) { transaction in
            calendar.startOfDay(for: transaction.date)
        }
        let days = grouped.keys.sorted(by: >)
        return days.map { day in
            let items = grouped[day] ?? []
            let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86_400)
            let interval = DateInterval(start: day, end: end)
            return TransactionsDaySection(
                day: day,
                title: dayTitle(for: day, now: now, calendar: calendar),
                transactions: items,
                netSpendingCents: SpendingAnalytics.spending(items, in: interval)
            )
        }
    }

    /// "Today", "Yesterday", "Tomorrow", "Mon, Nov 3", or "Mon, Nov 3, 2025"
    /// for other years.
    static func dayTitle(for day: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(day, inSameDayAs: tomorrow) {
            return "Tomorrow"
        }
        if calendar.isDate(day, equalTo: now, toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }
}

// MARK: - Amount input

enum TransactionInput {
    /// The user's decimal separator, for parsing typed amounts.
    static var decimalSeparator: Character {
        Locale.current.decimalSeparator?.first ?? "."
    }

    /// Parses typed text ("12.50", "$1,234.56") into cents, or `nil`.
    static func parseCents(_ text: String) -> Int? {
        Money.parseCents(text, decimalSeparator: decimalSeparator)
    }
}
