//
//  InvestActivityView.swift
//  Haki
//
//  Every investment transaction from the connected brokerages, grouped by
//  month, with search and a type filter. Pushed from the Invest tab.
//

import Foundation
import SwiftUI

enum InvestActivityFilter: String, CaseIterable, Identifiable {
    case all, trades, income, fees, transfers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All activity"
        case .trades: "Buys & sells"
        case .income: "Dividends & interest"
        case .fees: "Fees"
        case .transfers: "Transfers"
        }
    }

    func includes(_ kind: InvestTransactionKind) -> Bool {
        switch self {
        case .all: true
        case .trades: kind == .buy || kind == .sell
        case .income: kind == .dividend || kind == .interest
        case .fees: kind == .fee
        case .transfers: kind == .deposit || kind == .withdrawal || kind == .transfer
        }
    }
}

/// Transactions of one calendar month, newest first.
struct InvestActivityGroup: Identifiable {
    let id: String
    let title: String
    let transactions: [InvestmentTransaction]

    /// Groups transactions (already newest first) by month; undated ones go last.
    static func make(from transactions: [InvestmentTransaction]) -> [InvestActivityGroup] {
        var order: [MonthInterval] = []
        var byMonth: [MonthInterval: [InvestmentTransaction]] = [:]
        var undated: [InvestmentTransaction] = []
        for transaction in transactions {
            guard let day = transaction.day else {
                undated.append(transaction)
                continue
            }
            let month = MonthInterval(containing: day)
            if byMonth[month] == nil { order.append(month) }
            byMonth[month, default: []].append(transaction)
        }
        var groups = order.sorted(by: >).map { month in
            InvestActivityGroup(id: month.id, title: month.title(), transactions: byMonth[month] ?? [])
        }
        if !undated.isEmpty {
            groups.append(InvestActivityGroup(id: "undated", title: "Other", transactions: undated))
        }
        return groups
    }
}

struct InvestActivityView: View {
    @Environment(PortfolioService.self) private var portfolio

    @State private var filter: InvestActivityFilter = .all
    @State private var query = ""

    var body: some View {
        let matching = filtered
        let groups = InvestActivityGroup.make(from: matching)
        let accountNames = Dictionary(portfolio.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let currency = InvestFormat.currencyCode(holdings: portfolio.holdings, accounts: portfolio.accounts)

        List {
            if filter != .all, !matching.isEmpty {
                Section {
                    filterBanner(count: matching.count)
                }
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.transactions) { transaction in
                        InvestTransactionRow(
                            transaction: transaction,
                            accountName: accountNames[transaction.accountID],
                            currency: currency
                        )
                    }
                } header: {
                    HStack {
                        Text(group.title)
                        Spacer()
                        Text(group.transactions.count == 1 ? "1 transaction" : "\(group.transactions.count) transactions")
                            .monospacedDigit()
                    }
                }
            }
            if !matching.isEmpty {
                Section {
                } footer: {
                    Text("Shows activity from the last 90 days, as reported by your brokerages.")
                }
            }
        }
        .overlay {
            emptyState(hasMatches: !matching.isEmpty)
        }
        .navigationTitle("Investment activity")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Name or ticker")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
        }
        .refreshable {
            if portfolio.hasConnections {
                try? await portfolio.sync()
            } else {
                await portfolio.refresh()
            }
        }
        .task {
            if portfolio.lastLoaded == nil {
                await portfolio.refresh()
            }
        }
    }

    // MARK: Filtering

    private var filtered: [InvestmentTransaction] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ticker = needle.hasPrefix("$") ? String(needle.dropFirst()) : needle
        return portfolio.transactions.filter { transaction in
            guard filter.includes(InvestTransactionKind(type: transaction.type, subtype: transaction.subtype)) else {
                return false
            }
            guard !ticker.isEmpty else { return true }
            if transaction.name.localizedCaseInsensitiveContains(ticker) { return true }
            if let symbol = transaction.ticker, symbol.localizedCaseInsensitiveContains(ticker) { return true }
            if let security = transaction.securityName, security.localizedCaseInsensitiveContains(ticker) { return true }
            return false
        }
    }

    private var filterMenu: some View {
        Menu {
            Picker("Show", selection: $filter) {
                ForEach(InvestActivityFilter.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } label: {
            Image(systemName: filter == .all
                  ? "line.3.horizontal.decrease.circle"
                  : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel("Filter activity")
        .accessibilityValue(filter.title)
    }

    private func filterBanner(count: Int) -> some View {
        HStack {
            Label("\(filter.title) · \(count)", systemImage: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.medium))
            Spacer()
            Button {
                filter = .all
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show all activity")
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private func emptyState(hasMatches: Bool) -> some View {
        if portfolio.transactions.isEmpty {
            if portfolio.lastLoaded == nil, portfolio.isLoading {
                ProgressView("Loading activity…")
            } else if !portfolio.hasConnections {
                ContentUnavailableView {
                    Label("No brokerage connected", systemImage: "building.columns")
                } description: {
                    Text("Connect a brokerage to see your buys, sells, dividends and transfers here.")
                } actions: {
                    BrokerageLinkButton()
                }
            } else {
                ContentUnavailableView(
                    "No investment activity yet",
                    systemImage: "clock",
                    description: Text("Buys, sells, dividends and transfers from the last 90 days show up here after your brokerage syncs.")
                )
            }
        } else if !hasMatches {
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ContentUnavailableView {
                    Label("Nothing here", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No \(filter.title.lowercased()) in the last 90 days.")
                } actions: {
                    Button("Show all activity") {
                        filter = .all
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }
}

#Preview("Activity") {
    NavigationStack {
        InvestActivityView()
    }
    .previewEnvironment()
}

#Preview("Not connected") {
    NavigationStack {
        InvestActivityView()
    }
    .environment(InvestActivityPreviewSupport.emptyPortfolio())
    .previewEnvironment()
}

private enum InvestActivityPreviewSupport {
    static func emptyPortfolio() -> PortfolioService {
        let service = PortfolioService(client: nil)
        service.reset()
        return service
    }
}
