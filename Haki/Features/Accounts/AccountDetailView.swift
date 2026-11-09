//
//  AccountDetailView.swift
//  Haki
//
//  One account: its balance (with a quick "Update balance"), balance history,
//  recent transactions and details. Pushed from the Accounts tab.
//

import Charts
import Foundation
import SwiftData
import SwiftUI

struct AccountDetailView: View {
    let account: Account

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var range: ChartRange = .threeMonths
    @State private var showsBalanceUpdate = false
    @State private var showsEditor = false
    @State private var showsNewTransaction = false
    /// Set when the user deletes the account from the editor. The account is
    /// deleted only once this screen has gone, so nothing reads a deleted model.
    @State private var deletionRequested = false
    @State private var balanceSavedCount = 0
    /// The transaction opened from the list. Pushed from here, not from its
    /// row, so an edit that moves it to another account (and removes the
    /// row) doesn't pop the detail screen.
    @State private var openedTransaction: TransactionRecord?
    /// "See all in Transactions": the account's transactions, pushed on top
    /// of this screen so Back returns here.
    @State private var showsAllTransactions = false

    /// How many recent transactions the screen lists.
    private static let transactionLimit = 50

    init(account: Account) {
        self.account = account
    }

    var body: some View {
        if isAccountGone {
            // Deleted elsewhere (e.g. "Erase all data") while this screen was in the stack.
            ContentUnavailableView(
                "Account Deleted",
                systemImage: "building.columns",
                description: Text("This account is no longer in Haki.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hakiBackground)
        } else {
            detail
        }
    }

    private var isAccountGone: Bool {
        account.isDeleted || account.modelContext == nil
    }

    private var detail: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                AccountBalanceHistoryCard(
                    points: balancePoints,
                    isLiability: account.isLiability,
                    range: $range
                )
                transactionsCard
                detailsCard
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .navigationTitle(account.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $openedTransaction) { transaction in
            TransactionDetailView(transaction: transaction)
        }
        .navigationDestination(isPresented: $showsAllTransactions) {
            TransactionsView(initialFilter: .account(account.id))
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    showsEditor = true
                }
            }
        }
        .sheet(isPresented: $showsBalanceUpdate) {
            AccountBalanceUpdateView(account: account, onSave: { balanceSavedCount += 1 })
        }
        .sheet(isPresented: $showsNewTransaction) {
            TransactionEditorView(account: account)
        }
        .sheet(isPresented: $showsEditor, onDismiss: editorDismissed) {
            AccountEditorView(account: account, onDelete: { deletionRequested = true })
        }
        .sensoryFeedback(.success, trigger: balanceSavedCount)
        .onDisappear {
            deleteIfRequested()
        }
    }

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                AccountKindIcon(kind: account.kind, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.kind.displayName)
                        .font(.subheadline.weight(.semibold))
                    if !account.subtitle.isEmpty {
                        Text(account.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if !account.includeInNetWorth {
                    Label("Hidden", systemImage: "eye.slash")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel("Hidden from net worth")
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(account.isLiability ? "Amount owed" : "Current balance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(Money.format(account.balanceCents))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy, value: account.balanceCents)
                    .foregroundStyle(balanceColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                updatedLabel
            }
            .accessibilityElement(children: .combine)

            Button {
                showsBalanceUpdate = true
            } label: {
                Label("Update Balance", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .hakiCard()
    }

    @ViewBuilder
    private var updatedLabel: some View {
        let text = AccountsStyle.updatedText(account.balanceUpdatedAt)
        if AccountsStyle.isStale(account.balanceUpdatedAt) {
            Label(text + " — time for an update?", systemImage: "clock.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(Color.hakiWarning)
        } else {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var balanceColor: Color {
        !account.isLiability && account.balanceCents < 0 ? Color.hakiNegative : Color.primary
    }

    // MARK: History

    /// The balance at each sample date of the range, skipping dates before
    /// the first recorded balance. The last point is today's balance.
    private var balancePoints: [AccountsChartPoint] {
        let series = NetWorthCalculator.balanceSeries(
            observations: account.balanceObservations,
            at: range.sampleDates()
        )
        var points: [AccountsChartPoint] = []
        for item in series {
            guard let cents = item.balanceCents else { continue }
            points.append(AccountsChartPoint(date: item.date, cents: cents))
        }
        if let last = points.last {
            points[points.count - 1] = AccountsChartPoint(date: last.date, cents: account.balanceCents)
        }
        return points
    }

    // MARK: Transactions

    /// The account's transactions, leaving out any that are being deleted.
    private var liveTransactions: [TransactionRecord] {
        account.transactions.filter { !$0.isDeleted && $0.modelContext != nil }
    }

    private var transactionsCard: some View {
        let live = liveTransactions
        let all = live.sorted { $0.date > $1.date }
        let recent = Array(all.prefix(Self.transactionLimit))
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transactions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    showsNewTransaction = true
                } label: {
                    Label("Add", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Add transaction")
            }
            if recent.isEmpty {
                noTransactions
            } else {
                monthSummary(live)
                VStack(spacing: 0) {
                    ForEach(recent) { transaction in
                        VStack(spacing: 0) {
                            if transaction.id != recent.first?.id {
                                Divider()
                                    .padding(.leading, 48)
                            }
                            Button {
                                openedTransaction = transaction
                            } label: {
                                TransactionRow(transaction: transaction, showsDate: true)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Button {
                    showsAllTransactions = true
                } label: {
                    Text(seeAllTitle(total: all.count, shown: recent.count))
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .hakiCard()
    }

    private func seeAllTitle(total: Int, shown: Int) -> String {
        total > shown ? "See all \(total) in Transactions" : "Open in Transactions"
    }

    /// What this account spent and received this month.
    private func monthSummary(_ transactions: [TransactionRecord]) -> some View {
        let interval = MonthInterval.current().dateInterval()
        let spent = SpendingAnalytics.spending(transactions, in: interval)
        let received = SpendingAnalytics.income(transactions, in: interval)
        return HStack(spacing: 12) {
            monthStat(title: "Spent this month", value: Money.format(spent, showsCents: false), tint: Color.primary)
            monthStat(title: "Received", value: Money.format(received, showsCents: false),
                      tint: received > 0 ? Color.hakiPositive : Color.primary)
        }
        .padding(.bottom, 2)
    }

    private func monthStat(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var noTransactions: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle.portrait")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No transactions in this account yet.")
                .font(.subheadline.weight(.medium))
            Text("Add one by hand, or import a CSV export from your bank in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button {
                showsNewTransaction = true
            } label: {
                Label("Add Transaction", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    // MARK: Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Details")
            detailRow("Type", value: account.kind.displayName)
            if !account.institution.isEmpty {
                detailRow("Institution", value: account.institution)
            }
            if !account.mask.isEmpty {
                detailRow("Account number", value: AccountsStyle.maskText(account.mask))
            }
            detailRow("Net worth", value: account.includeInNetWorth ? "Included" : "Hidden")
            detailRow("Added", value: account.createdAt.formatted(date: .abbreviated, time: .omitted))
        }
        .hakiCard()
    }

    private func detailRow(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value)
            .font(.subheadline)
    }

    // MARK: Deleting

    private func editorDismissed() {
        guard deletionRequested else { return }
        // Pop back to Accounts; the account is deleted in `onDisappear`.
        dismiss()
    }

    private func deleteIfRequested() {
        guard deletionRequested else { return }
        deletionRequested = false
        withAnimation {
            LedgerStore.delete(account, in: modelContext)
        }
    }
}

// MARK: - Balance history card

/// The balance chart with its own drag selection, so scrubbing only redraws
/// this card.
private struct AccountBalanceHistoryCard: View {
    let points: [AccountsChartPoint]
    let isLiability: Bool
    @Binding var range: ChartRange

    @State private var selectedDate: Date?

    var body: some View {
        let selected = AccountsChartPoint.nearest(to: selectedDate, in: points)
        VStack(alignment: .leading, spacing: 12) {
            header(selected: selected)
            chart
            AccountsRangePicker(range: $range)
        }
        .hakiCard()
        // A tick for each new point under the finger, but not when it lifts.
        .sensoryFeedback(.selection, trigger: selected?.date) { _, newValue in
            newValue != nil
        }
    }

    private func header(selected: AccountsChartPoint?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(isLiability ? "Amount owed over time" : "Balance history")
                    .font(.headline)
                Spacer(minLength: 8)
                if let selected {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(Money.format(selected.cents, showsCents: false))
                            .font(.headline)
                            .monospacedDigit()
                        Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if let change = changeCents, let first = points.first {
                AccountsChangeLabel(
                    changeCents: change,
                    startCents: first.cents,
                    periodText: AccountsStyle.periodText(for: range),
                    decreaseIsGood: isLiability
                )
            }
        }
    }

    @ViewBuilder
    private var chart: some View {
        if points.count >= 2 {
            AccountsHistoryChart(
                points: points,
                range: range,
                seriesName: isLiability ? "Owed" : "Balance",
                tint: isLiability ? Color.hakiWarning : Color.accentColor,
                selectedDate: $selectedDate
            )
            .frame(height: 180)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Update the balance from time to time and its history will appear here.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var changeCents: Int? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.cents - first.cents
    }
}

#Preview {
    NavigationStack {
        AccountDetailView(account: PreviewData.sampleAccount)
    }
    .previewEnvironment()
}
