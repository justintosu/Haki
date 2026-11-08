//
//  BudgetsView.swift
//  Haki
//
//  The Budgets tab: a month at a glance, every budget with its progress,
//  spending outside budgets, and income received.
//

import Foundation
import SwiftData
import SwiftUI

struct BudgetsView: View {
    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.name)])
    private var categories: [TransactionCategory]

    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var transactions: [TransactionRecord]

    @Environment(AppRouter.self) private var router

    @State private var month: MonthInterval = .current()
    @State private var editorTarget: BudgetsEditorTarget? = nil

    var body: some View {
        content(snapshot)
            .navigationTitle("Budgets")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorTarget = .new
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New category")
                }
            }
            .sheet(item: $editorTarget) { target in
                CategoryEditorView(category: target.category)
            }
    }

    private var snapshot: BudgetsSnapshot {
        BudgetsSnapshot(transactions: transactions, categories: categories, month: month)
    }

    private func content(_ snapshot: BudgetsSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                MonthSwitcher(month: $month)
                    .padding(.horizontal, 4)
                    .hakiCard(padding: 4)
                if snapshot.hasBudgets {
                    BudgetsSummaryCard(snapshot: snapshot)
                    budgetsCard(snapshot)
                } else {
                    emptyState(snapshot)
                }
                if snapshot.hasUnbudgetedSpending {
                    notBudgetedCard(snapshot)
                }
                if snapshot.hasIncome {
                    incomeCard(snapshot)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .animation(.snappy, value: month)
        }
        .background(Color.hakiBackground)
    }

    // MARK: Budgets

    private func budgetsCard(_ snapshot: BudgetsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader("Budgets", systemImage: "chart.bar.fill")
            ForEach(snapshot.budgetLines) { line in
                budgetLink(line, snapshot: snapshot)
                if line.id != snapshot.budgetLines.last?.id {
                    Divider()
                        .padding(.leading, 52)
                }
            }
        }
        .hakiCard()
    }

    private func budgetLink(_ line: BudgetsCategoryLine, snapshot: BudgetsSnapshot) -> some View {
        NavigationLink {
            CategoryDetailView(category: line.category, month: snapshot.month)
        } label: {
            BudgetsBudgetRow(line: line, monthFraction: snapshot.monthFraction)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editorTarget = .edit(line.category)
            } label: {
                Label("Edit Budget", systemImage: "pencil")
            }
        }
    }

    // MARK: Empty state

    private func emptyState(_ snapshot: BudgetsSnapshot) -> some View {
        ContentUnavailableView {
            Label("No budgets yet", systemImage: "chart.bar.doc.horizontal")
        } description: {
            Text(emptyDescription(snapshot))
        } actions: {
            Button {
                startFirstBudget(snapshot)
            } label: {
                Text(firstBudgetTitle(snapshot))
            }
            .buttonStyle(.borderedProminent)
        }
        .hakiCard()
    }

    private func emptyDescription(_ snapshot: BudgetsSnapshot) -> String {
        let intro = "Give a spending category a monthly limit and Haki tracks every purchase against it: what's left, and whether you're on pace."
        guard snapshot.totalSpendingCents > 0 else { return intro }
        let spent = Money.format(snapshot.totalSpendingCents, showsCents: false)
        let monthName = snapshot.month.title()
        if snapshot.isCurrentMonth {
            return "\(intro) You've spent \(spent) so far in \(monthName)."
        }
        return "\(intro) You spent \(spent) in \(monthName)."
    }

    private func firstBudgetTitle(_ snapshot: BudgetsSnapshot) -> String {
        if let category = snapshot.suggestedCategory {
            return "Set a budget for \(category.name)"
        }
        return "Create a spending category"
    }

    private func startFirstBudget(_ snapshot: BudgetsSnapshot) {
        if let category = snapshot.suggestedCategory {
            editorTarget = .edit(category)
        } else {
            editorTarget = .new
        }
    }

    // MARK: Not budgeted

    private func notBudgetedCard(_ snapshot: BudgetsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            BudgetsSectionHeader(
                title: "Not budgeted",
                amount: Money.format(snapshot.unbudgetedSpendingCents),
                amountColor: Color.secondary
            )
            ForEach(snapshot.unbudgetedLines) { line in
                unbudgetedRow(line, month: snapshot.month)
            }
            if snapshot.uncategorizedSpendingCents != 0 {
                Button {
                    router.showTransactions(.uncategorized)
                } label: {
                    BudgetsCategoryRowLabel(
                        category: nil,
                        title: "Uncategorized",
                        subtitle: "Categorize these to track them",
                        amountText: Money.format(snapshot.uncategorizedSpendingCents)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows uncategorized transactions")
            }
        }
        .hakiCard()
    }

    private func unbudgetedRow(_ line: BudgetsCategoryLine, month: MonthInterval) -> some View {
        let setBudgetLabel = "Set budget for \(line.category.name)"
        return HStack(spacing: 10) {
            NavigationLink {
                CategoryDetailView(category: line.category, month: month)
            } label: {
                BudgetsCategoryRowLabel(
                    category: line.category,
                    title: line.category.name,
                    subtitle: "\(Money.format(line.cents)) spent",
                    showsChevron: false
                )
            }
            .buttonStyle(.plain)

            Button("Set budget") {
                editorTarget = .edit(line.category)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel(setBudgetLabel)
        }
    }

    // MARK: Income

    private func incomeCard(_ snapshot: BudgetsSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            BudgetsSectionHeader(
                title: "Income",
                amount: incomeText(snapshot.totalIncomeCents),
                amountColor: snapshot.totalIncomeCents > 0 ? Color.hakiPositive : Color.secondary
            )
            ForEach(snapshot.incomeLines) { line in
                NavigationLink {
                    CategoryDetailView(category: line.category, month: snapshot.month)
                } label: {
                    BudgetsCategoryRowLabel(
                        category: line.category,
                        title: line.category.name,
                        amountText: incomeText(line.cents),
                        amountColor: line.cents > 0 ? Color.hakiPositive : Color.primary
                    )
                }
                .buttonStyle(.plain)
            }
            if snapshot.uncategorizedIncomeCents != 0 {
                Button {
                    router.showTransactions(.uncategorized)
                } label: {
                    BudgetsCategoryRowLabel(
                        category: nil,
                        title: "Uncategorized",
                        subtitle: "Money in without a category",
                        amountText: incomeText(snapshot.uncategorizedIncomeCents),
                        amountColor: snapshot.uncategorizedIncomeCents > 0 ? Color.hakiPositive : Color.primary
                    )
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows uncategorized transactions")
            }
        }
        .hakiCard()
    }

    /// Money received as "+$X" (income totals are positive for money in).
    private func incomeText(_ cents: Int) -> String {
        cents > 0 ? Money.format(cents, alwaysShowsSign: true) : Money.format(cents)
    }
}

// MARK: - Editor target

/// Which category the editor sheet opens for. The id is captured up front so
/// identifying the sheet never reads a model that was just deleted.
private struct BudgetsEditorTarget: Identifiable {
    let id: String
    let category: TransactionCategory?

    static var new: BudgetsEditorTarget {
        BudgetsEditorTarget(id: "new", category: nil)
    }

    static func edit(_ category: TransactionCategory) -> BudgetsEditorTarget {
        BudgetsEditorTarget(id: category.id.uuidString, category: category)
    }
}

// MARK: - Rows

/// Icon, name, what's left, a pace-aware bar in the category color and
/// "$spent of $budget".
private struct BudgetsBudgetRow: View {
    let line: BudgetsCategoryLine
    let monthFraction: Double?

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: line.category, size: 40)
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(line.category.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(remainingText)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(line.progress.isOverBudget ? Color.hakiNegative : Color.secondary)
                }
                BudgetBar(
                    progress: line.progress,
                    tint: Color(hex: line.category.colorHex),
                    monthFraction: monthFraction
                )
                Text(spentText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var remainingText: String {
        let remaining = line.progress.remainingCents
        if remaining < 0 {
            return "\(Money.format(-remaining, showsCents: false)) over"
        }
        return "\(Money.format(remaining, showsCents: false)) left"
    }

    private var spentText: String {
        let spent = Money.format(line.cents, showsCents: false)
        let budget = Money.format(line.budgetCents, showsCents: false)
        return "\(spent) of \(budget)"
    }
}

/// Icon, title, optional subtitle, optional trailing amount and chevron.
private struct BudgetsCategoryRowLabel: View {
    let category: TransactionCategory?
    let title: String
    var subtitle: String? = nil
    var amountText: String? = nil
    var amountColor: Color = .primary
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let amountText {
                Text(amountText)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A card title with a total on the right.
private struct BudgetsSectionHeader: View {
    let title: String
    let amount: String
    let amountColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
            Spacer(minLength: 8)
            Text(amount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(amountColor)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Budgets") {
    NavigationStack { BudgetsView() }
        .previewEnvironment()
}

#Preview("No budgets") {
    NavigationStack { BudgetsView() }
        .previewEnvironment(empty: true)
}
