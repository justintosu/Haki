//
//  SpendingAnalytics.swift
//  Haki
//
//  Pure Foundation code (see Money.swift).
//

import Foundation

nonisolated struct CategoryTotal: Hashable {
    /// `nil` groups uncategorized transactions.
    let categoryID: String?
    let cents: Int
}

/// A running total for one day of a month.
nonisolated struct DailyTotal: Hashable, Identifiable {
    /// Day of the month, starting at 1.
    let day: Int
    /// Cumulative cents from the 1st through this day.
    let cents: Int

    var id: Int { day }
}

nonisolated struct MonthTotal: Hashable, Identifiable {
    let month: MonthInterval
    let cents: Int

    var id: String { month.id }
}

/// Totals over `LedgerEntry` values.
///
/// Every function returns spending as a positive number of cents (refunds
/// reduce it) and income as a positive number of cents (money received).
nonisolated enum SpendingAnalytics {
    static func entries<E: LedgerEntry>(_ entries: [E], in interval: DateInterval) -> [E] {
        entries.filter { $0.ledgerDate >= interval.start && $0.ledgerDate < interval.end }
    }

    /// Net spending in `interval`: purchases minus refunds in spending categories.
    static func spending<E: LedgerEntry>(_ entries: [E], in interval: DateInterval) -> Int {
        Self.entries(entries, in: interval)
            .filter { $0.ledgerFlow == .spending }
            .reduce(0) { $0 + $1.ledgerAmountCents }
    }

    /// Income received in `interval`, as a positive number.
    static func income<E: LedgerEntry>(_ entries: [E], in interval: DateInterval) -> Int {
        -Self.entries(entries, in: interval)
            .filter { $0.ledgerFlow == .income }
            .reduce(0) { $0 + $1.ledgerAmountCents }
    }

    /// Spending per category in `interval`, largest first. Categories whose
    /// refunds cancel out their purchases (a total of zero) are dropped.
    static func spendingByCategory<E: LedgerEntry>(_ entries: [E], in interval: DateInterval) -> [CategoryTotal] {
        var totals: [String?: Int] = [:]
        for entry in Self.entries(entries, in: interval) where entry.ledgerFlow == .spending {
            totals[entry.ledgerCategoryID, default: 0] += entry.ledgerAmountCents
        }
        return totals
            .filter { $0.value != 0 }
            .map { CategoryTotal(categoryID: $0.key, cents: $0.value) }
            .sorted { lhs, rhs in
                if lhs.cents != rhs.cents { return lhs.cents > rhs.cents }
                return (lhs.categoryID ?? "") < (rhs.categoryID ?? "")
            }
    }

    /// Spending in one category during `interval`.
    static func spending<E: LedgerEntry>(_ entries: [E], categoryID: String?, in interval: DateInterval) -> Int {
        Self.entries(entries, in: interval)
            .filter { $0.ledgerFlow == .spending && $0.ledgerCategoryID == categoryID }
            .reduce(0) { $0 + $1.ledgerAmountCents }
    }

    /// Cumulative spending for each day of `month`, for the "this month vs
    /// last month" line chart.
    /// - Parameter throughDay: stop after this day (e.g. today's day number
    ///   for the current month). `nil` covers the whole month.
    static func cumulativeDailySpending<E: LedgerEntry>(
        _ entries: [E],
        month: MonthInterval,
        throughDay: Int? = nil,
        calendar: Calendar = .current
    ) -> [DailyTotal] {
        let days = month.numberOfDays(in: calendar)
        let lastDay = min(days, max(0, throughDay ?? days))
        guard lastDay > 0 else { return [] }

        var perDay = Array(repeating: 0, count: days + 1)
        for entry in Self.entries(entries, in: month.dateInterval(in: calendar)) where entry.ledgerFlow == .spending {
            let day = calendar.component(.day, from: entry.ledgerDate)
            if day >= 1, day <= days { perDay[day] += entry.ledgerAmountCents }
        }

        var running = 0
        return (1...lastDay).map { day in
            running += perDay[day]
            return DailyTotal(day: day, cents: running)
        }
    }

    /// Totals per month, for bar charts. Pass `.income` for income; any other
    /// flow totals spending.
    static func monthlyTotals<E: LedgerEntry>(
        _ entries: [E],
        months: [MonthInterval],
        flow: LedgerFlow = .spending,
        calendar: Calendar = .current
    ) -> [MonthTotal] {
        months.map { month in
            let interval = month.dateInterval(in: calendar)
            let cents = flow == .income ? income(entries, in: interval) : spending(entries, in: interval)
            return MonthTotal(month: month, cents: cents)
        }
    }

    /// Spending per month in one category (`nil` = uncategorized).
    static func monthlyCategorySpending<E: LedgerEntry>(
        _ entries: [E],
        months: [MonthInterval],
        categoryID: String?,
        calendar: Calendar = .current
    ) -> [MonthTotal] {
        months.map { month in
            MonthTotal(month: month,
                       cents: spending(entries, categoryID: categoryID, in: month.dateInterval(in: calendar)))
        }
    }

    /// Expected net spending for the whole month, given what's been spent so far.
    ///
    /// The rest of the month is predicted from last month's spending over the
    /// same remaining days, so fixed bills early in the month (rent on the 1st)
    /// aren't extrapolated as if they repeated daily. Falls back to a straight
    /// line when last month has no spending.
    static func projectedSpending<E: LedgerEntry>(
        _ entries: [E],
        month: MonthInterval,
        asOf now: Date = .now,
        calendar: Calendar = .current
    ) -> Int {
        let days = month.numberOfDays(in: calendar)
        let elapsed = month.elapsedDays(asOf: now, calendar: calendar)
        let spentSoFar = cumulativeDailySpending(entries, month: month, throughDay: elapsed, calendar: calendar).last?.cents ?? 0
        guard elapsed < days else { return spentSoFar }

        let previous = cumulativeDailySpending(entries, month: month.previous, calendar: calendar)
        if let previousTotal = previous.last?.cents, previousTotal > 0 {
            let previousThroughToday = elapsed > 0 ? previous[min(elapsed, previous.count) - 1].cents : 0
            return spentSoFar + max(0, previousTotal - previousThroughToday)
        }
        return BudgetProgress(budgetCents: 0, spentCents: spentSoFar).projectedCents(elapsedDays: elapsed, daysInMonth: days)
    }

    /// Average of `monthlyTotals` over months that have any activity. Returns 0 if none.
    static func averageMonthlySpending<E: LedgerEntry>(
        _ entries: [E],
        months: [MonthInterval],
        calendar: Calendar = .current
    ) -> Int {
        let totals = monthlyTotals(entries, months: months, calendar: calendar).map(\.cents).filter { $0 != 0 }
        guard !totals.isEmpty else { return 0 }
        return Int((Double(totals.reduce(0, +)) / Double(totals.count)).rounded())
    }
}

// MARK: - Budgets

nonisolated enum BudgetPace: Hashable {
    /// Spending is at or below the budget's even pace through the month.
    case onTrack
    /// Still under budget, but spending faster than an even pace.
    case aheadOfPace
    /// Already spent more than the budget.
    case overBudget
}

nonisolated struct BudgetProgress: Hashable {
    let budgetCents: Int
    let spentCents: Int

    var remainingCents: Int { budgetCents - spentCents }
    var isOverBudget: Bool { spentCents > budgetCents }

    /// Spent ÷ budget, not clamped (1.25 means 25% over). A zero budget with
    /// any spending reports 1.
    var fractionUsed: Double {
        guard budgetCents > 0 else { return spentCents > 0 ? 1 : 0 }
        return max(0, Double(spentCents) / Double(budgetCents))
    }

    /// - Parameters:
    ///   - elapsedDays: days of the month that have started (see `MonthInterval.elapsedDays`).
    ///   - daysInMonth: length of the month.
    func pace(elapsedDays: Int, daysInMonth: Int) -> BudgetPace {
        if isOverBudget { return .overBudget }
        guard daysInMonth > 0, budgetCents > 0 else { return .onTrack }
        let evenPace = Double(budgetCents) * Double(min(elapsedDays, daysInMonth)) / Double(daysInMonth)
        // 10% leeway, and nothing is flagged until half the budget is used, so a
        // single early purchase doesn't flag the whole month. `BudgetBar` uses
        // the same thresholds for its warning color.
        return Double(spentCents) > evenPace * 1.1 && fractionUsed >= 0.5 ? .aheadOfPace : .onTrack
    }

    /// Month-end spending if the current daily rate continues.
    func projectedCents(elapsedDays: Int, daysInMonth: Int) -> Int {
        guard elapsedDays > 0 else { return spentCents }
        let rate = Double(spentCents) / Double(min(elapsedDays, daysInMonth))
        let projected = (rate * Double(daysInMonth)).rounded()
        // Clamp, so a huge stored amount can't trap the conversion to Int.
        guard projected.isFinite else { return spentCents }
        if projected >= Double(Int.max) { return Int.max }
        if projected <= -Double(Int.max) { return -Int.max }
        return Int(projected)
    }
}
