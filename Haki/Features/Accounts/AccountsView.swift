//
//  AccountsView.swift
//  Haki
//
//  The Accounts tab: net worth with its history, then every account grouped
//  by type (cash, credit cards, investments, loans, other assets).
//

import Foundation
import SwiftData
import SwiftUI

struct AccountsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)])
    private var accounts: [Account]

    @AppStorage("accountsNetWorthRange") private var range: ChartRange = .threeMonths
    @State private var showsNewAccount = false
    @State private var balanceTarget: Account?
    @State private var savedCount = 0

    init() {}

    var body: some View {
        content
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsNewAccount = true
                    } label: {
                        Label("Add Account", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showsNewAccount) {
                AccountEditorView(account: nil)
            }
            .sheet(item: $balanceTarget) { account in
                AccountBalanceUpdateView(account: account, onSave: { savedCount += 1 })
            }
            .sensoryFeedback(.success, trigger: savedCount)
    }

    @ViewBuilder
    private var content: some View {
        if accounts.isEmpty {
            emptyState
        } else {
            accountList
        }
    }

    // MARK: Accounts

    private var accountList: some View {
        let summary = NetWorthSummary(accounts: accounts, range: range)
        let sections = AccountsGroupSection.make(from: accounts)
        return ScrollView {
            VStack(spacing: 16) {
                AccountsNetWorthCard(summary: summary, range: $range)
                ForEach(sections) { section in
                    groupCard(section)
                }
                footerNote
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
    }

    private func groupCard(_ section: AccountsGroupSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.group.title)
                    .font(.headline)
                Spacer()
                Text(section.totalText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(section.accounts) { account in
                VStack(spacing: 0) {
                    if account.id != section.accounts.first?.id {
                        Divider()
                            .padding(.leading, 48)
                    }
                    NavigationLink {
                        AccountDetailView(account: account)
                    } label: {
                        AccountsRow(account: account)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        rowMenu(for: account)
                    }
                }
            }
        }
        .hakiCard()
    }

    @ViewBuilder
    private func rowMenu(for account: Account) -> some View {
        Button {
            balanceTarget = account
        } label: {
            Label("Update Balance", systemImage: "pencil")
        }
        Button {
            toggleNetWorth(account)
        } label: {
            if account.includeInNetWorth {
                Label("Hide from Net Worth", systemImage: "eye.slash")
            } else {
                Label("Include in Net Worth", systemImage: "eye")
            }
        }
    }

    private var footerNote: some View {
        Label {
            Text("Balances are entered manually — automatic bank sync isn't available yet. Update a balance from the account's page, or touch and hold an account for quick actions.")
        } icon: {
            Image(systemName: "info.circle")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: Empty state

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Accounts Yet", systemImage: "building.columns")
        } description: {
            Text("Add your checking and savings accounts, credit cards, loans and investments to see your net worth in one place. Balances are entered manually for now.")
        } actions: {
            Button {
                showsNewAccount = true
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Button("Load Sample Data") {
                withAnimation {
                    LedgerStore.loadSampleData(into: modelContext)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hakiBackground)
    }

    // MARK: Actions

    private func toggleNetWorth(_ account: Account) {
        withAnimation {
            account.includeInNetWorth.toggle()
        }
        LedgerStore.save(modelContext)
    }
}

// MARK: - Groups

/// The accounts of one `AccountGroup`, for one card on the screen.
private struct AccountsGroupSection: Identifiable {
    let group: AccountGroup
    let accounts: [Account]

    var id: Int { group.rawValue }

    /// Sum of every balance shown in the group (amount owed for liabilities).
    var totalCents: Int {
        accounts.reduce(0) { $0 + $1.balanceCents }
    }

    var totalText: String {
        let amount = Money.format(totalCents)
        return group.isLiability ? amount + " owed" : amount
    }

    /// Non-empty groups in `AccountGroup` order.
    static func make(from accounts: [Account]) -> [AccountsGroupSection] {
        AccountGroup.allCases.compactMap { group -> AccountsGroupSection? in
            let members = accounts.filter { $0.kind.group == group }
            return members.isEmpty ? nil : AccountsGroupSection(group: group, accounts: members)
        }
    }
}

// MARK: - Row

private struct AccountsRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: 12) {
            AccountKindIcon(kind: account.kind)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !account.includeInNetWorth {
                    Label("Hidden from net worth", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Money.format(account.balanceCents))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(balanceColor)
                    if account.isLiability {
                        Text("owed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(AccountsStyle.updatedText(account.balanceUpdatedAt))
                    .font(.caption)
                    .foregroundStyle(AccountsStyle.isStale(account.balanceUpdatedAt) ? Color.hakiWarning : Color.secondary)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var subtitle: String {
        account.subtitle.isEmpty ? account.kind.displayName : account.subtitle
    }

    private var balanceColor: Color {
        !account.isLiability && account.balanceCents < 0 ? Color.hakiNegative : Color.primary
    }

    private var accessibilityText: String {
        var parts = [account.name, account.kind.displayName]
        if !account.institution.isEmpty { parts.append(account.institution) }
        let balance = Money.format(account.balanceCents)
        parts.append(account.isLiability ? balance + " owed" : "Balance " + balance)
        parts.append(AccountsStyle.updatedText(account.balanceUpdatedAt))
        if !account.includeInNetWorth { parts.append("Hidden from net worth") }
        return parts.joined(separator: ", ")
    }
}

#Preview("Accounts") {
    NavigationStack { AccountsView() }
        .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack { AccountsView() }
        .previewEnvironment(empty: true)
}
