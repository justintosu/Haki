//
//  CategoryDetailView.swift
//  Haki
//
//  One category for one month: spending against its budget (or income
//  received), the last six months as a bar chart with the budget as a dashed
//  rule, the average of the earlier months, and the month's transactions.
//

import Charts
import CoreGraphics
import Foundation
import SwiftData
import SwiftUI

struct CategoryDetailView: View {
    let category: TransactionCategory
    let month: MonthInterval

    /// Filtered in memory (a predicate can't follow the category relationship),
    /// so recategorized and edited transactions are always reflected.
    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var transactions: [TransactionRecord]

    @Environment(\.dismiss) private var dismiss

    @State private var displayedMonth: MonthInterval
    @State private var showsEditor = false
    /// The transaction opened from the list. Pushed from here, not from its
    /// row, so an edit that moves it out of this category or month (and
    /// removes the row) doesn't pop the detail screen.
    @State private var openedTransaction: TransactionRecord?

    init(category: TransactionCategory, month: MonthInterval) {
        self.category = category
        self.month = month
        _displayedMonth = State(initialValue: month)
    }

    var body: some View {
        Group {
            if isGone {
                ContentUnavailableView(
                    "Category deleted",
                    systemImage: "trash",
                    description: Text("This category no longer exists.")
                )
            } else {
                content(CategoryDetailData(category: category, transactions: transactions, month: displayedMonth))
            }
        }
        .background(Color.hakiBackground)
        .navigationTitle(isGone ? "" : category.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedTransaction) { transaction in
            TransactionDetailView(transaction: transaction)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showsEditor = true
                }
                .disabled(isGone)
            }
        }
        .sheet(isPresented: $showsEditor, onDismiss: { closeIfDeleted() }) {
            CategoryEditorView(category: category)
        }
    }

    /// The category was deleted (from the editor sheet or elsewhere). Checked
    /// before reading any of its properties.
    private var isGone: Bool {
        category.isDeleted || category.modelContext == nil
    }

    private func closeIfDeleted() {
        if isGone { dismiss() }
    }

    private var categoryColor: Color {
        Color(hex: category.colorHex)
    }

    private func content(_ data: CategoryDetailData) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard(data)
                historyCard(data)
                transactionsCard(data)
            }
            .padding(.horizontal)
            .padding(.bottom)
            .animation(.snappy, value: displayedMonth)
        }
    }

    // MARK: Header

    private func headerCard(_ data: CategoryDetailData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                CategoryIcon(category: category, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.name)
                        .font(.title2.weight(.bold))
                    Text(kindSubtitle(data))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)

            MonthSwitcher(month: $displayedMonth)

            amountBlock(data)
            budgetBlock(data)
        }
        .hakiCard()
    }

    private func kindSubtitle(_ data: CategoryDetailData) -> String {
        switch data.kind {
        case .expense:
            if let budget = data.budgetCents {
                return "Spending · \(Money.format(budget, showsCents: false)) a month"
            }
            return "Spending · No budget"
        case .income:
            return "Income"
        case .transfer:
            return "Transfer"
        }
    }

    private func amountBlock(_ data: CategoryDetailData) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(amountCaption(data))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(amountText(data))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(data.kind == .income && data.amountCents > 0 ? Color.hakiPositive : Color.primary)
            if let budgetLine = budgetLineText(data) {
                Text(budgetLine)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func amountCaption(_ data: CategoryDetailData) -> String {
        let monthName = data.month.title()
        switch data.kind {
        case .expense: return "Spent in \(monthName)"
        case .income: return "Received in \(monthName)"
        case .transfer: return "Moved in \(monthName)"
        }
    }

    private func amountText(_ data: CategoryDetailData) -> String {
        if data.kind == .income && data.amountCents > 0 {
            return Money.format(data.amountCents, alwaysShowsSign: true)
        }
        return Money.format(data.amountCents)
    }

    private func budgetLineText(_ data: CategoryDetailData) -> String? {
        guard let budget = data.budgetCents else { return nil }
        return "of \(Money.format(budget, showsCents: false)) budget"
    }

    @ViewBuilder
    private func budgetBlock(_ data: CategoryDetailData) -> some View {
        switch data.kind {
        case .expense:
            if let progress = data.progress {
                budgetProgress(progress, data: data)
            } else {
                noBudgetPrompt
            }
        case .income:
            Label("Income counts toward your cash flow, not your budgets.", systemImage: "arrow.down.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .transfer:
            Label("Transfers between your own accounts aren't counted as spending or income.", systemImage: "arrow.left.arrow.right")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func budgetProgress(_ progress: BudgetProgress, data: CategoryDetailData) -> some View {
        let pace = paceStyle(progress, data: data)
        return VStack(alignment: .leading, spacing: 10) {
            BudgetBar(
                progress: progress,
                tint: categoryColor,
                monthFraction: data.monthFraction,
                height: 10,
                pace: data.pace(progress)
            )
            Text(remainingText(progress))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(progress.isOverBudget ? Color.hakiNegative : Color.primary)
            Label(pace.title, systemImage: pace.systemImage)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(pace.color)
            if let projection = projectionText(progress, data: data) {
                Text(projection)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func remainingText(_ progress: BudgetProgress) -> String {
        let remaining = progress.remainingCents
        if remaining < 0 {
            return "\(Money.format(-remaining)) over budget"
        }
        return "\(Money.format(remaining)) left"
    }

    private func paceStyle(_ progress: BudgetProgress, data: CategoryDetailData) -> CategoryPaceStyle {
        switch data.pace(progress) {
        case .overBudget:
            return CategoryPaceStyle(title: "Over budget", systemImage: "exclamationmark.triangle.fill", color: Color.hakiNegative)
        case .aheadOfPace:
            return CategoryPaceStyle(title: "Spending faster than planned", systemImage: "speedometer", color: Color.hakiWarning)
        case .onTrack:
            let title = data.isCurrentMonth ? "On track" : "Stayed within budget"
            return CategoryPaceStyle(title: title, systemImage: "checkmark.circle.fill", color: Color.hakiPositive)
        }
    }

    private func projectionText(_ progress: BudgetProgress, data: CategoryDetailData) -> String? {
        guard let projected = data.projectedCents else { return nil }
        let text = "Projected: \(Money.format(projected, showsCents: false)) by month end"
        guard projected > progress.budgetCents else { return text }
        return "\(text), \(Money.format(projected - progress.budgetCents, showsCents: false)) over budget"
    }

    private var noBudgetPrompt: some View {
        HStack(spacing: 12) {
            Text("No monthly budget")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Set budget") {
                showsEditor = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: History

    private func historyCard(_ data: CategoryDetailData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Last 6 months", systemImage: "chart.bar.xaxis")
            if data.activeMonthCount == 0 && data.budgetCents == nil {
                Text(noHistoryText(data))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                CategoryHistoryChart(
                    totals: data.monthTotals,
                    selectedMonth: data.month,
                    budgetCents: data.budgetCents,
                    tint: categoryColor,
                    valueNoun: valueNoun(data.kind)
                )
                .frame(height: 180)
            }
            Divider()
            HStack(alignment: .top, spacing: 12) {
                CategoryDetailStat(
                    title: "Monthly average",
                    value: data.averageMonthCount == 0 ? "—" : Money.format(data.averageCents, showsCents: false)
                )
                CategoryDetailStat(
                    title: comparisonTitle(data),
                    value: comparisonText(data)
                )
            }
        }
        .hakiCard()
    }

    private func valueNoun(_ kind: CategoryKind) -> String {
        switch kind {
        case .expense: return "spent"
        case .income: return "received"
        case .transfer: return "moved"
        }
    }

    private func noHistoryText(_ data: CategoryDetailData) -> String {
        "Nothing \(valueNoun(data.kind)) in \(category.name) in the last 6 months."
    }

    private func comparisonTitle(_ data: CategoryDetailData) -> String {
        guard data.isCurrentMonth else { return "Compared with average" }
        return data.projectedCents != nil ? "Projected vs. average" : "So far vs. average"
    }

    /// "$45 below" / "$30 above" / "About average". In the current month a
    /// budgeted category compares its month-end projection (the figure in the
    /// budget card above) with the average of earlier, full months, rather
    /// than a partly finished month.
    private func comparisonText(_ data: CategoryDetailData) -> String {
        guard data.averageCents != 0 else { return "—" }
        let compared = data.isCurrentMonth ? (data.projectedCents ?? data.amountCents) : data.amountCents
        let difference = compared - data.averageCents
        if abs(difference) < 100 { return "About average" }
        let amount = Money.format(abs(difference), showsCents: false)
        return difference > 0 ? "\(amount) above" : "\(amount) below"
    }

    // MARK: Transactions

    private func transactionsCard(_ data: CategoryDetailData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Transactions")
                    .font(.headline)
                Spacer(minLength: 8)
                Text(countText(data.monthTransactions.count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if data.monthTransactions.isEmpty {
                Text(noTransactionsText(data))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                transactionRows(data.monthTransactions)
            }
        }
        .hakiCard()
    }

    private func transactionRows(_ rows: [TransactionRecord]) -> some View {
        let lastID = rows.last?.id
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(rows) { transaction in
                Button {
                    openedTransaction = transaction
                } label: {
                    TransactionRow(transaction: transaction, showsDate: true, showsCategory: false)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if transaction.id != lastID {
                    Divider()
                        .padding(.leading, 48)
                }
            }
        }
    }

    private func countText(_ count: Int) -> String {
        count == 1 ? "1 transaction" : "\(count) transactions"
    }

    private func noTransactionsText(_ data: CategoryDetailData) -> String {
        "No \(category.name) transactions in \(data.month.title())."
    }
}

// MARK: - Data

/// Everything the detail screen shows for the displayed month.
private struct CategoryDetailData {
    let month: MonthInterval
    let kind: CategoryKind
    /// Only for expense categories with a budget.
    let budgetCents: Int?
    /// Spent (expense), received (income) or moved out (transfer) this month.
    let amountCents: Int
    /// The six months ending with `month`, oldest first.
    let monthTotals: [MonthTotal]
    /// Average over the months before `month` (the faded bars) that have
    /// any activity. The displayed month is left out so a partly finished
    /// month doesn't pull down the figure it's compared against.
    let averageCents: Int
    /// How many earlier months `averageCents` covers (0 = no history).
    let averageMonthCount: Int
    /// Months in the whole six-month window with any activity.
    let activeMonthCount: Int
    /// This month's transactions in the category, newest first.
    let monthTransactions: [TransactionRecord]
    let isCurrentMonth: Bool
    let elapsedDays: Int
    let daysInMonth: Int
    /// Expected month-end spending, only for a budgeted expense category in
    /// the current month. The rest of the month is predicted from last
    /// month's same days, so a bill paid on the 1st isn't extrapolated as if
    /// it repeated daily.
    let projectedCents: Int?

    init(
        category: TransactionCategory,
        transactions: [TransactionRecord],
        month: MonthInterval,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let categoryID = category.id
        let own = transactions.filter { $0.category?.id == categoryID }
        let months = MonthInterval.trailing(6, endingAt: month)
        let kind = category.kind

        let totals: [MonthTotal]
        switch kind {
        case .expense:
            totals = SpendingAnalytics.monthlyCategorySpending(
                own, months: months, categoryID: category.ledgerID, calendar: calendar)
        case .income:
            totals = SpendingAnalytics.monthlyTotals(own, months: months, flow: .income, calendar: calendar)
        case .transfer:
            // Transfers never count as spending; show how much moved out.
            totals = months.map { (item: MonthInterval) -> MonthTotal in
                let inMonth = SpendingAnalytics.entries(own, in: item.dateInterval(in: calendar))
                let moved = inMonth
                    .filter { !$0.isExcluded && $0.amountCents > 0 }
                    .reduce(0) { $0 + $1.amountCents }
                return MonthTotal(month: item, cents: moved)
            }
        }

        let active = totals.map { $0.cents }.filter { $0 != 0 }
        let earlier = totals.dropLast().map { $0.cents }.filter { $0 != 0 }
        let earlierSum = earlier.reduce(0, +)
        let budget = kind == .expense && category.hasBudget ? category.monthlyBudgetCents : nil
        let amount = totals.last?.cents ?? 0
        let isCurrent = month == MonthInterval.current(calendar: calendar, now: now)
        let elapsed = month.elapsedDays(asOf: now, calendar: calendar)

        if budget != nil, isCurrent, elapsed > 0 {
            let estimate = SpendingAnalytics.projectedSpending(own, month: month, asOf: now, calendar: calendar)
            // Never project less than what's already been spent this month.
            self.projectedCents = max(amount, estimate)
        } else {
            self.projectedCents = nil
        }

        self.month = month
        self.kind = kind
        self.budgetCents = budget
        self.amountCents = amount
        self.monthTotals = totals
        self.activeMonthCount = active.count
        self.averageMonthCount = earlier.count
        self.averageCents = earlier.isEmpty ? 0 : Int((Double(earlierSum) / Double(earlier.count)).rounded())
        self.monthTransactions = SpendingAnalytics.entries(own, in: month.dateInterval(in: calendar))
        self.isCurrentMonth = isCurrent
        self.elapsedDays = elapsed
        self.daysInMonth = month.numberOfDays(in: calendar)
    }

    var progress: BudgetProgress? {
        guard let budgetCents else { return nil }
        return BudgetProgress(budgetCents: budgetCents, spentCents: amountCents)
    }

    /// `BudgetProgress.pace`, adjusted by the month-end projection for the
    /// current month, the same way as the Budgets screen.
    func pace(_ progress: BudgetProgress) -> BudgetPace {
        guard isCurrentMonth, let projectedCents else {
            return progress.pace(elapsedDays: elapsedDays, daysInMonth: daysInMonth)
        }
        return progress.pace(elapsedDays: elapsedDays, daysInMonth: daysInMonth, projectedCents: projectedCents)
    }

    /// How much of the month has passed, only for the current month.
    var monthFraction: Double? {
        guard isCurrentMonth, daysInMonth > 0 else { return nil }
        return Double(elapsedDays) / Double(daysInMonth)
    }
}

/// How a budget's pace reads: words, a symbol and a color.
private struct CategoryPaceStyle {
    let title: String
    let systemImage: String
    let color: Color
}

// MARK: - Stat

private struct CategoryDetailStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Chart

/// Six monthly bars in the category color; the displayed month is solid and
/// labeled with its amount, earlier months are faded. The budget is a
/// dashed rule.
private struct CategoryHistoryChart: View {
    let totals: [MonthTotal]
    let selectedMonth: MonthInterval
    let budgetCents: Int?
    let tint: Color
    /// "spent", "received" or "moved", for VoiceOver.
    let valueNoun: String

    var body: some View {
        Chart {
            ForEach(totals) { total in
                BarMark(
                    x: .value("Month", monthLabel(total)),
                    y: .value("Amount", dollars(total.cents))
                )
                .foregroundStyle(barColor(total))
                .cornerRadius(6)
                .annotation(position: .top) {
                    // Only the displayed month is labeled with its amount.
                    Text(barLabel(total))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            budgetMark
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    Text(yLabel(value))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Last 6 months")
        .accessibilityValue(accessibilitySummary)
    }

    @ChartContentBuilder
    private var budgetMark: some ChartContent {
        if let budgetCents {
            RuleMark(y: .value("Budget", dollars(budgetCents)))
                .foregroundStyle(Color.secondary)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Budget")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func dollars(_ cents: Int) -> Double {
        Double(cents) / 100
    }

    private func monthLabel(_ total: MonthTotal) -> String {
        total.month.shortTitle()
    }

    /// The displayed month is solid; the others are faded.
    private func barColor(_ total: MonthTotal) -> Color {
        let isSelected: Bool = total.month == selectedMonth
        return isSelected ? tint : tint.opacity(0.35)
    }

    private func barLabel(_ total: MonthTotal) -> String {
        let isSelected: Bool = total.month == selectedMonth
        return isSelected ? Money.compact(total.cents) : ""
    }

    private func yLabel(_ value: AxisValue) -> String {
        guard let amount = value.as(Double.self) else { return "" }
        return Money.compact(Int((amount * 100).rounded()))
    }

    private var yDomain: ClosedRange<Double> {
        var values = totals.map { $0.cents }
        if let budgetCents { values.append(budgetCents) }
        let highest = dollars(values.max() ?? 0)
        let lowest = dollars(min(0, values.min() ?? 0))
        // Headroom for the amount and "Budget" labels.
        let top = max(highest * 1.2, 10)
        return lowest...top
    }

    private var accessibilitySummary: String {
        var parts = totals.map { total in
            "\(total.month.title()), \(Money.format(total.cents)) \(valueNoun)"
        }
        if let budgetCents {
            parts.append("Monthly budget, \(Money.format(budgetCents))")
        }
        return parts.joined(separator: ". ")
    }
}

#Preview("Spending") {
    NavigationStack {
        CategoryDetailView(category: PreviewData.sampleCategory, month: .current())
    }
    .previewEnvironment()
}

#Preview("Income") {
    NavigationStack {
        if let income = LedgerStore.allCategories(in: PreviewData.context).first(where: { $0.kind == .income }) {
            CategoryDetailView(category: income, month: .current())
        }
    }
    .previewEnvironment()
}
