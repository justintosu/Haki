//
//  OverviewBudgetsCard.swift
//  Haki
//
//  The budgets closest to (or past) their limit. Without budgets, the top
//  spending categories and a nudge to set some.
//
//  Rows don't push the category screen themselves: editing a budget there
//  re-sorts these rows (or swaps top spending for budgets), and a row's
//  `NavigationLink` going away pops the screen it opened. `OverviewView`
//  pushes it instead (see `onOpenCategory`).
//

import Foundation
import SwiftUI

struct OverviewBudgetsCard: View {
    let snapshot: OverviewSnapshot
    /// Opens a category's detail screen for `snapshot.month`.
    let onOpenCategory: (TransactionCategory) -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader("Budgets", systemImage: "chart.bar.fill", actionTitle: "See all") {
                showBudgets()
            }
            if !snapshot.budgetLines.isEmpty {
                budgetRows
            } else if !snapshot.topCategories.isEmpty {
                topSpending
            } else {
                setUpPrompt
            }
        }
        .hakiCard()
    }

    private func showBudgets() {
        router.showHome(.budgets)
    }

    // MARK: Budgets

    private var budgetRows: some View {
        let lines = Array(snapshot.budgetLines.prefix(4))
        return VStack(spacing: 16) {
            ForEach(lines) { line in
                Button {
                    onOpenCategory(line.category)
                } label: {
                    OverviewBudgetRow(line: line, monthFraction: snapshot.monthFraction)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: No budgets yet

    private var topSpending: some View {
        let maxCents = snapshot.topCategories.map { $0.cents }.max() ?? 0
        return VStack(alignment: .leading, spacing: 14) {
            Text("Top spending this month")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(snapshot.topCategories) { item in
                topSpendingLink(for: item, maxCents: maxCents)
            }
            Divider()
            budgetNudge
        }
    }

    @ViewBuilder
    private func topSpendingLink(for item: OverviewCategorySpend, maxCents: Int) -> some View {
        if let category = item.category {
            Button {
                onOpenCategory(category)
            } label: {
                OverviewCategorySpendRow(item: item, maxCents: maxCents)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                router.showTransactions(.uncategorized)
            } label: {
                OverviewCategorySpendRow(item: item, maxCents: maxCents)
            }
            .buttonStyle(.plain)
        }
    }

    private var budgetNudge: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text("Set monthly budgets to see how your spending is pacing.")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "lightbulb")
                    .foregroundStyle(Color.accentColor)
            }
            .font(.subheadline)
            Button("Set budgets") { showBudgets() }
                .buttonStyle(.bordered)
        }
    }

    private var setUpPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Give your spending categories a monthly budget and Haki will show how you're pacing as the month goes on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Set up budgets") { showBudgets() }
                .buttonStyle(.bordered)
        }
    }
}

// MARK: - Rows

/// Icon, name, "$spent of $budget", what's left, and a pace-aware budget bar.
private struct OverviewBudgetRow: View {
    let line: OverviewBudgetLine
    let monthFraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CategoryIcon(category: line.category, size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text(line.category.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(spentText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(line.progress.isOverBudget ? Color.hakiNegative : Color.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            BudgetBar(progress: line.progress, tint: Color(hex: line.category.colorHex), monthFraction: monthFraction, pace: line.pace)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var spentText: String {
        let spent = Money.format(line.progress.spentCents, showsCents: false)
        let budget = Money.format(line.progress.budgetCents, showsCents: false)
        return "\(spent) of \(budget)"
    }

    private var statusText: String {
        let remaining = line.progress.remainingCents
        if remaining < 0 {
            return "\(Money.format(-remaining, showsCents: false)) over"
        }
        return "\(Money.format(remaining, showsCents: false)) left"
    }
}

/// Icon, name and amount, with a bar relative to the biggest category.
private struct OverviewCategorySpendRow: View {
    let item: OverviewCategorySpend
    let maxCents: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CategoryIcon(category: item.category, size: 32)
                Text(item.category?.name ?? "Uncategorized")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Money.format(item.cents, showsCents: false))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            OverviewMeterBar(fraction: fraction, tint: tint)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var fraction: Double {
        guard maxCents > 0 else { return 0 }
        return Double(item.cents) / Double(maxCents)
    }

    private var tint: Color {
        guard let category = item.category else { return Color.gray }
        return Color(hex: category.colorHex)
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            OverviewBudgetsCard(snapshot: OverviewPreviewData.snapshot, onOpenCategory: { _ in })
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
