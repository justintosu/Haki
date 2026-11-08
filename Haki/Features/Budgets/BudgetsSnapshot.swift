//
//  BudgetsSnapshot.swift
//  Haki
//
//  Everything the Budgets screen shows for one month, computed once per
//  render from the queried transactions and categories. All totals come from
//  `SpendingAnalytics`, so they match the rest of the app.
//

import Foundation
import SwiftData

/// One category's activity in a month: net spending for expense categories,
/// money received for income categories.
struct BudgetsCategoryLine: Identifiable {
    let category: TransactionCategory
    let cents: Int
    /// The monthly budget, or 0 when the category has none.
    let budgetCents: Int

    var id: UUID { category.id }

    var progress: BudgetProgress {
        BudgetProgress(budgetCents: budgetCents, spentCents: cents)
    }
}

struct BudgetsSnapshot {
    let month: MonthInterval
    let isCurrentMonth: Bool
    let daysInMonth: Int
    /// Days of the month that have started (the whole month for past months).
    let elapsedDays: Int

    /// Expense categories with a budget, in `sortOrder`.
    let budgetLines: [BudgetsCategoryLine]
    /// Expense categories without a budget that have spending this month, largest first.
    let unbudgetedLines: [BudgetsCategoryLine]
    /// Net spending with no category.
    let uncategorizedSpendingCents: Int
    /// Income categories with money received this month, largest first.
    let incomeLines: [BudgetsCategoryLine]
    /// Money in with no category.
    let uncategorizedIncomeCents: Int

    /// Sum of the budgets of expense categories.
    let totalBudgetCents: Int
    /// Spending in budgeted categories.
    let budgetedSpentCents: Int
    /// All spending this month, budgeted or not.
    let totalSpendingCents: Int
    let totalIncomeCents: Int

    /// Cumulative spending in budgeted categories by day: through today for
    /// the current month, the whole month otherwise.
    let budgetedDaily: [DailyTotal]

    /// The category to offer when the user has no budgets yet: the biggest
    /// unbudgeted spender this month, else the first spending category.
    let suggestedCategory: TransactionCategory?

    init(
        transactions: [TransactionRecord],
        categories: [TransactionCategory],
        month: MonthInterval,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let interval = month.dateInterval(in: calendar)
        let entries = SpendingAnalytics.entries(transactions, in: interval)
        let isCurrent = month == MonthInterval.current(calendar: calendar, now: now)
        let elapsed = month.elapsedDays(asOf: now, calendar: calendar)

        // Spending per category (expense categories and uncategorized money out).
        var spentByID: [String: Int] = [:]
        var uncategorizedSpending = 0
        for total in SpendingAnalytics.spendingByCategory(entries, in: interval) {
            if let categoryID = total.categoryID {
                spentByID[categoryID] = total.cents
            } else {
                uncategorizedSpending = total.cents
            }
        }

        // Income entries grouped by category; "" groups uncategorized money in.
        let incomeEntries = entries.filter { $0.ledgerFlow == .income }
        let incomeGroups: [String: [TransactionRecord]] = Dictionary(
            grouping: incomeEntries,
            by: { $0.ledgerCategoryID ?? "" }
        )

        var budgeted: [BudgetsCategoryLine] = []
        var unbudgeted: [BudgetsCategoryLine] = []
        var income: [BudgetsCategoryLine] = []
        for category in categories {
            switch category.kind {
            case .expense:
                let spent = spentByID[category.ledgerID] ?? 0
                if category.hasBudget {
                    let budget = category.monthlyBudgetCents ?? 0
                    budgeted.append(BudgetsCategoryLine(category: category, cents: spent, budgetCents: budget))
                } else if spent != 0 {
                    unbudgeted.append(BudgetsCategoryLine(category: category, cents: spent, budgetCents: 0))
                }
            case .income:
                let group = incomeGroups[category.ledgerID] ?? []
                let received = SpendingAnalytics.income(group, in: interval)
                if received != 0 {
                    income.append(BudgetsCategoryLine(category: category, cents: received, budgetCents: 0))
                }
            case .transfer:
                continue
            }
        }
        unbudgeted.sort { $0.cents > $1.cents }
        income.sort { $0.cents > $1.cents }

        let budgetedIDs = Set(budgeted.map { $0.category.ledgerID })
        let budgetedEntries = entries.filter { entry in
            guard let categoryID = entry.ledgerCategoryID else { return false }
            return budgetedIDs.contains(categoryID)
        }

        var suggestion: TransactionCategory? = unbudgeted.first?.category
        if suggestion == nil {
            suggestion = categories.first { $0.kind == .expense && !$0.hasBudget }
        }
        if suggestion == nil {
            suggestion = categories.first { $0.kind == .expense }
        }

        self.month = month
        self.isCurrentMonth = isCurrent
        self.daysInMonth = month.numberOfDays(in: calendar)
        self.elapsedDays = elapsed
        self.budgetLines = budgeted
        self.unbudgetedLines = unbudgeted
        self.uncategorizedSpendingCents = uncategorizedSpending
        self.incomeLines = income
        self.uncategorizedIncomeCents = SpendingAnalytics.income(incomeGroups[""] ?? [], in: interval)
        self.totalBudgetCents = budgeted.reduce(0) { $0 + $1.budgetCents }
        self.budgetedSpentCents = budgeted.reduce(0) { $0 + $1.cents }
        self.totalSpendingCents = SpendingAnalytics.spending(entries, in: interval)
        self.totalIncomeCents = SpendingAnalytics.income(entries, in: interval)
        self.budgetedDaily = SpendingAnalytics.cumulativeDailySpending(
            budgetedEntries,
            month: month,
            throughDay: isCurrent ? elapsed : nil,
            calendar: calendar
        )
        self.suggestedCategory = suggestion
    }

    // MARK: Derived values

    var hasBudgets: Bool { !budgetLines.isEmpty }

    var hasIncome: Bool { !incomeLines.isEmpty || uncategorizedIncomeCents != 0 }

    var hasUnbudgetedSpending: Bool { !unbudgetedLines.isEmpty || uncategorizedSpendingCents != 0 }

    /// All budgets together.
    var overall: BudgetProgress {
        BudgetProgress(budgetCents: totalBudgetCents, spentCents: budgetedSpentCents)
    }

    /// How much of the month has passed, only for the current month.
    var monthFraction: Double? {
        guard isCurrentMonth, daysInMonth > 0 else { return nil }
        return Double(elapsedDays) / Double(daysInMonth)
    }

    var pace: BudgetPace {
        overall.pace(elapsedDays: elapsedDays, daysInMonth: daysInMonth)
    }

    var projectedCents: Int {
        overall.projectedCents(elapsedDays: elapsedDays, daysInMonth: daysInMonth)
    }

    /// Spending outside budgets: unbudgeted categories plus uncategorized.
    var unbudgetedSpendingCents: Int { totalSpendingCents - budgetedSpentCents }

    var overBudgetCount: Int {
        budgetLines.filter { $0.progress.isOverBudget }.count
    }

    /// Days left in the current month, counting today.
    var remainingDays: Int { max(1, daysInMonth - elapsedDays + 1) }

    /// What an even pace would have spent by today.
    var evenPaceCents: Int {
        guard daysInMonth > 0 else { return 0 }
        let fraction = Double(min(elapsedDays, daysInMonth)) / Double(daysInMonth)
        return Int((Double(totalBudgetCents) * fraction).rounded())
    }
}
