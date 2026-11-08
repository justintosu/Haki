//
//  LedgerTypes.swift
//  Haki
//
//  Pure Foundation code (see Money.swift).
//

import Foundation

// MARK: - Categories

/// What a category represents. Only `.expense` categories count toward
/// spending and budgets; `.transfer` covers money moving between your own
/// accounts (credit card payments, savings transfers) and is ignored in totals.
nonisolated enum CategoryKind: String, CaseIterable, Codable, Identifiable {
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .expense: "Spending"
        case .income: "Income"
        case .transfer: "Transfer"
        }
    }
}

// MARK: - Ledger entries

/// How a single transaction counts toward totals.
nonisolated enum LedgerFlow: Hashable {
    /// Counts toward spending. Negative amounts here are refunds and reduce spending.
    case spending
    /// Counts toward income. Income is money in, so amounts are usually negative.
    case income
    /// Money moving between your own accounts. Not spending, not income.
    case transfer
    /// The user excluded it from all totals.
    case excluded

    /// - Parameters:
    ///   - categoryKind: the kind of the transaction's category, or `nil` if uncategorized.
    ///   - amountCents: used only for uncategorized transactions: money out
    ///     counts as spending, money in counts as income.
    static func resolve(categoryKind: CategoryKind?, isExcluded: Bool, amountCents: Int) -> LedgerFlow {
        if isExcluded { return .excluded }
        switch categoryKind {
        case .expense: return .spending
        case .income: return .income
        case .transfer: return .transfer
        case nil: return amountCents >= 0 ? .spending : .income
        }
    }
}

/// The read-only view of a transaction that analytics code works with.
///
/// The SwiftData `TransactionRecord` model conforms to this, and unit tests
/// use a plain struct, so analytics can be tested without SwiftData.
/// Members carry a `ledger` prefix so they never clash with model properties.
nonisolated protocol LedgerEntry {
    var ledgerDate: Date { get }
    /// Plaid sign convention: positive = money out. See `Money`.
    var ledgerAmountCents: Int { get }
    var ledgerFlow: LedgerFlow { get }
    /// A stable identifier of the category (the category's UUID string), or `nil`.
    var ledgerCategoryID: String? { get }
    /// The cleaned-up merchant name shown to the user.
    var ledgerMerchant: String { get }
    /// `MerchantNormalizer.key(for:)` of the merchant, precomputed and stored
    /// so grouping and matching never re-run normalization.
    var ledgerMerchantKey: String { get }
}

// MARK: - Accounts

nonisolated enum AccountKind: String, CaseIterable, Codable, Identifiable {
    case checking
    case savings
    case cash
    case creditCard
    case investment
    case loan
    case property
    case other

    var id: String { rawValue }

    /// Liabilities store the amount owed as a positive balance and subtract
    /// from net worth.
    var isLiability: Bool {
        switch self {
        case .creditCard, .loan: true
        default: false
        }
    }

    var displayName: String {
        switch self {
        case .checking: "Checking"
        case .savings: "Savings"
        case .cash: "Cash"
        case .creditCard: "Credit Card"
        case .investment: "Investment"
        case .loan: "Loan"
        case .property: "Property"
        case .other: "Other"
        }
    }

    /// SF Symbol name.
    var systemImage: String {
        switch self {
        case .checking: "building.columns"
        case .savings: "banknote"
        case .cash: "dollarsign.circle"
        case .creditCard: "creditcard"
        case .investment: "chart.line.uptrend.xyaxis"
        case .loan: "doc.text"
        case .property: "house"
        case .other: "square.stack.3d.up"
        }
    }

    var group: AccountGroup {
        switch self {
        case .checking, .savings, .cash: .cash
        case .creditCard: .credit
        case .investment: .investments
        case .loan: .loans
        case .property, .other: .otherAssets
        }
    }
}

/// Sections on the Accounts screen, in display order.
nonisolated enum AccountGroup: Int, CaseIterable, Identifiable, Comparable {
    case cash
    case credit
    case investments
    case loans
    case otherAssets

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .cash: "Cash"
        case .credit: "Credit Cards"
        case .investments: "Investments"
        case .loans: "Loans"
        case .otherAssets: "Other Assets"
        }
    }

    var isLiability: Bool { self == .credit || self == .loans }

    static func < (lhs: AccountGroup, rhs: AccountGroup) -> Bool { lhs.rawValue < rhs.rawValue }
}

// MARK: - Recurrence

nonisolated enum RecurrenceFrequency: String, CaseIterable, Codable, Identifiable {
    case weekly
    case biweekly
    case monthly
    case quarterly
    case yearly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .weekly: "Weekly"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        }
    }

    /// Suffix for amounts: "/wk", "/mo" ...
    var shortSuffix: String {
        switch self {
        case .weekly: "/wk"
        case .biweekly: "/2wk"
        case .monthly: "/mo"
        case .quarterly: "/qtr"
        case .yearly: "/yr"
        }
    }

    var approximateDays: Double {
        switch self {
        case .weekly: 7
        case .biweekly: 14
        case .monthly: 30.44
        case .quarterly: 91.31
        case .yearly: 365.25
        }
    }

    /// Interval lengths (in days) that count as this frequency when detecting
    /// recurring charges from history.
    var toleratedIntervalDays: ClosedRange<Int> {
        switch self {
        case .weekly: 5...9
        case .biweekly: 12...16
        case .monthly: 26...35
        case .quarterly: 80...100
        case .yearly: 350...380
        }
    }

    /// The calendar step for `n` periods.
    func step(_ n: Int) -> DateComponents {
        switch self {
        case .weekly: DateComponents(day: 7 * n)
        case .biweekly: DateComponents(day: 14 * n)
        case .monthly: DateComponents(month: n)
        case .quarterly: DateComponents(month: 3 * n)
        case .yearly: DateComponents(year: n)
        }
    }

    /// The equivalent monthly cost, rounded to the nearest cent.
    func monthlyCents(_ cents: Int) -> Int {
        let monthly: Double
        switch self {
        case .weekly: monthly = Double(cents) * 52 / 12
        case .biweekly: monthly = Double(cents) * 26 / 12
        case .monthly: monthly = Double(cents)
        case .quarterly: monthly = Double(cents) / 3
        case .yearly: monthly = Double(cents) / 12
        }
        return Int(monthly.rounded())
    }

    /// The equivalent yearly cost.
    func yearlyCents(_ cents: Int) -> Int {
        switch self {
        case .weekly: cents * 52
        case .biweekly: cents * 26
        case .monthly: cents * 12
        case .quarterly: cents * 4
        case .yearly: cents
        }
    }
}

/// Due dates of a recurring bill.
///
/// Occurrences are always computed from the anchor (`anchor + n × step`), not
/// by stepping from the previous occurrence, so a bill due on the 31st is due
/// on Feb 28 and then on Mar 31 again instead of drifting to the 28th forever.
nonisolated struct RecurringSchedule: Hashable {
    /// The first due date.
    let anchor: Date
    let frequency: RecurrenceFrequency

    /// The `n`th occurrence; `occurrence(0)` is the anchor.
    func occurrence(_ n: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: frequency.step(n), to: anchor) ?? anchor
    }

    /// The first occurrence on or after the start of `date`'s day.
    func nextOccurrence(onOrAfter date: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        if calendar.startOfDay(for: anchor) >= dayStart { return anchor }
        let elapsedDays = Double(calendar.daysBetween(anchor, dayStart))
        var n = max(0, Int((elapsedDays / frequency.approximateDays).rounded(.down)) - 1)
        while calendar.startOfDay(for: occurrence(n, calendar: calendar)) < dayStart {
            n += 1
        }
        return occurrence(n, calendar: calendar)
    }

    /// All occurrences whose day falls inside `interval` (`start ..< end`).
    func occurrences(in interval: DateInterval, calendar: Calendar = .current) -> [Date] {
        var result: [Date] = []
        var date = nextOccurrence(onOrAfter: interval.start, calendar: calendar)
        var guardCount = 0
        while date < interval.end, guardCount < 1_000 {
            result.append(date)
            guardCount += 1
            date = nextOccurrence(onOrAfter: calendar.date(byAdding: .day, value: 1, to: date) ?? interval.end,
                                  calendar: calendar)
        }
        return result
    }
}
