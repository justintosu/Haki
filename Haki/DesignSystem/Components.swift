//
//  Components.swift
//  Haki
//
//  Small views reused across features.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Category icon

/// The category's emoji on a tinted circle. Uncategorized shows a gray "?".
struct CategoryIcon: View {
    let category: TransactionCategory?
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
            if let category {
                Text(category.emoji)
                    .font(.system(size: size * 0.5))
            } else {
                Image(systemName: "questionmark")
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var tint: Color {
        category.map { Color(hex: $0.colorHex) } ?? .gray
    }
}

// MARK: - Amounts

/// A transaction amount: money out as "$12.34", money in as "+$12.34" in green.
struct TransactionAmountText: View {
    let cents: Int
    var isExcluded: Bool = false

    var body: some View {
        Text(cents < 0 ? Money.format(-cents, alwaysShowsSign: true) : Money.format(cents))
            .monospacedDigit()
            .foregroundStyle(isExcluded ? Color.secondary : (cents < 0 ? Color.hakiPositive : Color.primary))
            .strikethrough(isExcluded)
    }
}

// MARK: - Transaction row

/// One transaction in a list: icon, merchant, category and account, amount.
/// A dot marks transactions that still need review.
struct TransactionRow: View {
    let transaction: TransactionRecord
    /// Show the date under the merchant (for lists not grouped by day).
    var showsDate: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: transaction.category)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(transaction.merchant)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if transaction.isPending {
                        Text("Pending")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                TransactionAmountText(cents: transaction.amountCents, isExcluded: transaction.isExcluded)
                    .font(.body.weight(.medium))
                if !transaction.isReviewed {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("Needs review")
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts: [String] = []
        if showsDate { parts.append(transaction.date.formatted(.dateTime.month(.abbreviated).day())) }
        parts.append(transaction.category?.name ?? "Uncategorized")
        if let account = transaction.account { parts.append(account.name) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Budget bar

/// A horizontal progress bar for a budget. Turns orange when spending is
/// ahead of pace and red when over budget.
struct BudgetBar: View {
    let progress: BudgetProgress
    var tint: Color = .accentColor
    /// When set, a tick marks how much of the month has passed (0...1).
    var monthFraction: Double?
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(barColor)
                    .frame(width: width * min(1, progress.fractionUsed))
                if let monthFraction, monthFraction > 0, monthFraction < 1 {
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 2, height: height + 4)
                        .offset(x: width * monthFraction - 1)
                }
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Budget used")
        .accessibilityValue("\(Int((progress.fractionUsed * 100).rounded())) percent")
    }

    private var barColor: Color {
        if progress.isOverBudget { return .hakiNegative }
        if let monthFraction, progress.fractionUsed > monthFraction * 1.1, progress.fractionUsed > 0.5 {
            return .hakiWarning
        }
        return tint
    }
}

// MARK: - Month switcher

/// "‹ November 2026 ›". Can't move past the current month.
struct MonthSwitcher: View {
    @Binding var month: MonthInterval
    var now: Date = .now

    var body: some View {
        HStack {
            Button {
                month = month.previous
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Previous month")

            Spacer()
            Text(month.title())
                .font(.headline)
                .contentTransition(.numericText())
            Spacer()

            Button {
                month = month.next
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .disabled(month >= MonthInterval.current(now: now))
            .accessibilityLabel("Next month")
        }
        .animation(.snappy, value: month)
    }
}

// MARK: - Pickers

/// A list of categories grouped by kind, for pushing from a form. Selecting
/// a row updates the binding and pops back.
struct CategoryPickerView: View {
    @Binding var selection: TransactionCategory?
    var allowsNone: Bool = true

    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.name)])
    private var categories: [TransactionCategory]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if allowsNone {
                Section {
                    row(for: nil)
                }
            }
            ForEach(CategoryKind.allCases) { kind in
                let items = categories.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section(kind.displayName) {
                        ForEach(items) { category in
                            row(for: category)
                        }
                    }
                }
            }
        }
        .navigationTitle("Category")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(for category: TransactionCategory?) -> some View {
        Button {
            selection = category
            dismiss()
        } label: {
            HStack(spacing: 12) {
                CategoryIcon(category: category, size: 30)
                Text(category?.name ?? "Uncategorized")
                    .foregroundStyle(.primary)
                Spacer()
                if selection?.id == category?.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

/// A `Picker` row for choosing an account (or none) inside a `Form`.
struct AccountPicker: View {
    let title: String
    @Binding var selection: Account?
    var allowsNone: Bool = true

    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)])
    private var accounts: [Account]

    var body: some View {
        Picker(title, selection: $selection) {
            if allowsNone {
                Text("None").tag(Account?.none)
            }
            ForEach(accounts) { account in
                Text(account.name).tag(Account?.some(account))
            }
        }
    }
}
