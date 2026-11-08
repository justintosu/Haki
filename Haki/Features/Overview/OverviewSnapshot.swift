//
//  OverviewSnapshot.swift
//  Haki
//
//  Everything the Overview dashboard shows, computed once per render from
//  the queried models so the cards themselves only lay out values.
//

import Foundation

/// A budgeted expense category and how much of its budget this month used.
struct OverviewBudgetLine: Identifiable {
    let id: UUID
    let category: TransactionCategory
    let progress: BudgetProgress
}

/// This month's spending in one category, or in no category.
struct OverviewCategorySpend: Identifiable {
    let id: String
    /// `nil` for uncategorized spending.
    let category: TransactionCategory?
    let cents: Int
}

/// A recurring bill that's due soon, or overdue.
struct OverviewUpcomingBill: Identifiable {
    /// The bill and its due date: a weekly bill can be late and due again soon.
    let id: String
    let item: RecurringItem
    let dueDate: Date
    /// Whole days from today; 0 is today, negative when overdue.
    let daysUntil: Int
    /// A matching charge was already found for this due date.
    let isPaid: Bool
    /// The due date has passed and no matching charge was found.
    let isLate: Bool

    init(item: RecurringItem, dueDate: Date, daysUntil: Int, isPaid: Bool, isLate: Bool) {
        self.id = "\(item.id.uuidString)-\(Int(dueDate.timeIntervalSince1970))"
        self.item = item
        self.dueDate = dueDate
        self.daysUntil = daysUntil
        self.isPaid = isPaid
        self.isLate = isLate
    }
}

struct OverviewSnapshot {
    /// How far ahead "Upcoming bills" looks.
    static let upcomingBillDays = 14
    /// How far back "Upcoming bills" looks for bills that went unpaid.
    static let lateBillDays = 7

    // MARK: Month

    let month: MonthInterval
    let daysInMonth: Int
    /// Today's day of the month, starting at 1.
    let dayOfMonth: Int

    // MARK: Spending and cash flow

    /// Net spending this month (purchases minus refunds).
    let spentCents: Int
    /// Income received this month, as a positive number.
    let incomeCents: Int
    /// Cumulative spending for each day of this month through today.
    let thisMonthDaily: [DailyTotal]
    /// Last month's cumulative spending, cut to this month's length so it fits the chart.
    let lastMonthDaily: [DailyTotal]
    /// Last month's cumulative spending at the same day of the month as today.
    let lastMonthSameDayCents: Int
    let lastMonthHasSpending: Bool

    // MARK: Budgets

    /// Sum of the budgets of expense categories that have one; 0 when there are none.
    let totalBudgetCents: Int
    /// Net spending this month in the categories that have a budget: what
    /// `totalBudgetCents` is measured against (as on the Budgets screen).
    let budgetedSpentCents: Int
    /// Cumulative spending in budgeted categories for each day of this month
    /// through today; empty without budgets.
    let budgetedDaily: [DailyTotal]
    /// Every budgeted category, most used first.
    let budgetLines: [OverviewBudgetLine]
    /// The biggest spending categories this month, up to four.
    let topCategories: [OverviewCategorySpend]

    // MARK: Bills

    let hasRecurringItems: Bool
    /// Active bills that are overdue (from the last `lateBillDays`) or due
    /// within `upcomingBillDays`, soonest (so overdue ones) first, up to four.
    let upcomingBills: [OverviewUpcomingBill]

    // MARK: Net worth

    let hasAccounts: Bool
    let netWorthCents: Int
    /// Net worth over the last three months, starting at the first recorded balance.
    let netWorthPoints: [NetWorthPoint]
    /// Change over the last month; `nil` when there's no balance history that old.
    let netWorthChangeCents: Int?

    // MARK: Derived

    var hasBudgets: Bool { totalBudgetCents > 0 }

    /// Some of this month's spending is in categories without a budget (or
    /// uncategorized), so the budgeted line differs from the total.
    var hasUnbudgetedSpending: Bool { hasBudgets && budgetedDaily != thisMonthDaily }

    /// This month's spending outside the budgeted categories.
    var unbudgetedSpentCents: Int { spentCents - budgetedSpentCents }

    /// How much of the month has passed (0...1), for budget pace ticks.
    var monthFraction: Double {
        guard daysInMonth > 0 else { return 0 }
        return min(1, Double(dayOfMonth) / Double(daysInMonth))
    }

    // MARK: Building

    init(
        accounts: [Account],
        transactions: [TransactionRecord],
        categories: [TransactionCategory],
        recurringItems: [RecurringItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let month = MonthInterval.current(calendar: calendar, now: now)
        let lastMonth = month.previous
        let days = month.numberOfDays(in: calendar)
        let today = max(1, min(days, calendar.component(.day, from: now)))
        let interval = month.dateInterval(in: calendar)
        let lastInterval = lastMonth.dateInterval(in: calendar)

        self.month = month
        self.daysInMonth = days
        self.dayOfMonth = today

        // Spending only looks at this month and last month, so filter once.
        let windowStart = lastInterval.start
        let windowEnd = interval.end
        let recent = transactions.filter { $0.date >= windowStart && $0.date < windowEnd }

        spentCents = SpendingAnalytics.spending(recent, in: interval)
        incomeCents = SpendingAnalytics.income(recent, in: interval)
        thisMonthDaily = SpendingAnalytics.cumulativeDailySpending(
            recent, month: month, throughDay: today, calendar: calendar)

        let lastMonthFull = SpendingAnalytics.cumulativeDailySpending(recent, month: lastMonth, calendar: calendar)
        lastMonthDaily = lastMonthFull.filter { $0.day <= days }
        let compareDay = min(today, lastMonth.numberOfDays(in: calendar))
        lastMonthSameDayCents = lastMonthFull.first(where: { $0.day == compareDay })?.cents ?? 0
        lastMonthHasSpending = recent.contains { entry in
            entry.flow == .spending && entry.date >= lastInterval.start && entry.date < lastInterval.end
        }

        // Budgets
        let categoryTotals = SpendingAnalytics.spendingByCategory(recent, in: interval)
        var spentByCategory: [String: Int] = [:]
        for total in categoryTotals {
            if let id = total.categoryID { spentByCategory[id] = total.cents }
        }
        var categoryByID: [String: TransactionCategory] = [:]
        for category in categories {
            categoryByID[category.ledgerID] = category
        }

        let budgeted = categories.filter { $0.kind == .expense && $0.hasBudget }
        totalBudgetCents = budgeted.reduce(0) { $0 + ($1.monthlyBudgetCents ?? 0) }
        budgetedSpentCents = budgeted.reduce(0) { $0 + (spentByCategory[$1.ledgerID] ?? 0) }
        let budgetedIDs = Set(budgeted.map { $0.ledgerID })
        if budgetedIDs.isEmpty {
            budgetedDaily = []
        } else {
            let budgetedEntries = recent.filter { entry in
                guard let categoryID = entry.ledgerCategoryID else { return false }
                return budgetedIDs.contains(categoryID)
            }
            budgetedDaily = SpendingAnalytics.cumulativeDailySpending(
                budgetedEntries, month: month, throughDay: today, calendar: calendar)
        }
        budgetLines = budgeted
            .map { category in
                OverviewBudgetLine(
                    id: category.id,
                    category: category,
                    progress: BudgetProgress(budgetCents: category.monthlyBudgetCents ?? 0,
                                             spentCents: spentByCategory[category.ledgerID] ?? 0)
                )
            }
            .sorted { lhs, rhs in
                if lhs.progress.fractionUsed != rhs.progress.fractionUsed {
                    return lhs.progress.fractionUsed > rhs.progress.fractionUsed
                }
                return lhs.category.sortOrder < rhs.category.sortOrder
            }
        topCategories = categoryTotals
            .filter { $0.cents > 0 }
            .prefix(4)
            .map { total in
                OverviewCategorySpend(
                    id: total.categoryID ?? "uncategorized",
                    category: total.categoryID.flatMap { categoryByID[$0] },
                    cents: total.cents
                )
            }

        // Bills: a charge up to a week either side of a due date can pay it,
        // so look a week further back than the oldest overdue date.
        hasRecurringItems = !recurringItems.isEmpty
        let todayStart = calendar.startOfDay(for: now)
        let lateStart = calendar.date(byAdding: .day, value: -Self.lateBillDays, to: todayStart) ?? todayStart
        let matchStart = calendar.date(byAdding: .day, value: -(Self.lateBillDays + 7), to: todayStart) ?? todayStart
        let matchEntries = transactions.filter { $0.date >= matchStart }
        var bills: [OverviewUpcomingBill] = []
        for item in recurringItems where item.isActive {
            // Recent due dates that passed without a matching charge.
            let pastDue = item.schedule.occurrences(in: DateInterval(start: lateStart, end: todayStart), calendar: calendar)
            for due in pastDue {
                let status = RecurringMatcher.status(
                    dueDate: due, merchantKey: item.merchantKey, frequency: item.frequency,
                    entries: matchEntries, now: now, calendar: calendar)
                guard case .late = status else { continue }
                bills.append(OverviewUpcomingBill(
                    item: item, dueDate: due, daysUntil: calendar.daysBetween(now, due), isPaid: false, isLate: true))
            }

            let due = item.nextDueDate(onOrAfter: now, calendar: calendar)
            let daysUntil = calendar.daysBetween(now, due)
            guard daysUntil >= 0, daysUntil <= Self.upcomingBillDays else { continue }
            let status = RecurringMatcher.status(
                dueDate: due, merchantKey: item.merchantKey, frequency: item.frequency,
                entries: matchEntries, now: now, calendar: calendar)
            let isPaid: Bool
            switch status {
            case .paid:
                isPaid = true
            case .upcoming, .late:
                isPaid = false
            }
            bills.append(OverviewUpcomingBill(item: item, dueDate: due, daysUntil: daysUntil, isPaid: isPaid, isLate: false))
        }
        bills.sort { lhs, rhs in
            if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
            return lhs.item.name.localizedStandardCompare(rhs.item.name) == .orderedAscending
        }
        upcomingBills = Array(bills.prefix(4))

        // Net worth. The history ends at the current balances, not the latest
        // snapshot before `now`: a snapshot can be dated later today (sample
        // data records them at noon), and the line should end at the headline.
        hasAccounts = !accounts.isEmpty
        let included = accounts.filter { $0.includeInNetWorth }
        let assets = included.filter { !$0.isLiability }.reduce(0) { $0 + $1.balanceCents }
        let liabilities = included.filter { $0.isLiability }.reduce(0) { $0 + $1.balanceCents }
        let current = NetWorthPoint(date: now, assetsCents: assets, liabilitiesCents: liabilities)
        netWorthCents = accounts.reduce(0) { $0 + $1.netWorthContributionCents }

        let observations = included.flatMap { $0.balanceObservations }
        if let earliest = observations.map({ $0.date }).min() {
            let history = ChartRange.threeMonths.sampleDates(now: now, calendar: calendar)
                .dropLast()
                .filter { $0 >= earliest }
            netWorthPoints = NetWorthCalculator.series(observations: observations, at: history) + [current]
        } else {
            netWorthPoints = []
        }
        if let monthAgo = calendar.date(byAdding: .month, value: -1, to: now),
           observations.contains(where: { $0.date <= monthAgo }),
           let start = NetWorthCalculator.series(observations: observations, at: [monthAgo]).first {
            netWorthChangeCents = current.netCents - start.netCents
        } else {
            netWorthChangeCents = nil
        }
    }
}
