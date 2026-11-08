//
//  HoldingDetailView.swift
//  Haki
//
//  One position across every connected account: value, shares, average
//  cost, gain, weight, which accounts hold it, recent activity, and ways to
//  talk about it (a trade post, a post, the ticker's feed). Pushed.
//

import Foundation
import SwiftUI

struct HoldingDetailView: View {
    let position: PortfolioPosition

    @Environment(PortfolioService.self) private var portfolio
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var compose: HoldingComposeRequest?

    var body: some View {
        // The latest values after a sync, or what we were given if it's gone.
        let live = portfolio.position(for: position.symbol)
        let current = live ?? position
        let holdings = portfolio.holdings(for: current.symbol)
        let currency = InvestFormat.currencyCode(holdings: portfolio.holdings, accounts: portfolio.accounts)
        let activity = relatedTransactions(for: current)
        let isShareable = InvestStyle.isShareableTicker(current)

        ScrollView {
            VStack(spacing: 16) {
                if live == nil, portfolio.lastLoaded != nil {
                    InvestInlineNote(
                        systemImage: "info.circle",
                        text: "This position no longer appears in your connected accounts. These are the last values Haki saw."
                    )
                }
                HoldingHeaderCard(position: current, currency: currency)
                HoldingStatsCard(position: current, holdings: holdings, currency: currency)
                if !holdings.isEmpty {
                    accountsCard(holdings, position: current, currency: currency)
                }
                activityCard(activity, position: current, currency: currency)
                if isShareable {
                    socialCard(symbol: current.symbol)
                }
                Text("Values come from your brokerage and may be delayed. Haki can't place trades.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .navigationTitle(InvestStyle.displaySymbol(for: current))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if isShareable {
                    shareMenu(symbol: current.symbol)
                }
            }
        }
        .refreshable {
            try? await portfolio.sync()
        }
        .sheet(item: $compose) { request in
            ComposePostView(prefill: request.draft)
        }
    }

    // MARK: Accounts

    private func accountsCard(_ holdings: [BrokerageHolding], position: PortfolioPosition, currency: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader("In accounts", systemImage: "building.columns")
            VStack(spacing: 0) {
                ForEach(Array(holdings.enumerated()), id: \.element.id) { index, holding in
                    if index > 0 {
                        Divider()
                    }
                    accountRow(holding, position: position, currency: currency)
                }
            }
        }
        .hakiCard()
    }

    @ViewBuilder
    private func accountRow(_ holding: BrokerageHolding, position: PortfolioPosition, currency: String) -> some View {
        let account = portfolio.account(id: holding.accountID)
        let institution = account.flatMap { account in
            portfolio.connections.first { $0.id == account.connectionID }?.institutionName
        }
        let holdingCurrency = holding.currency.count == 3 ? holding.currency.uppercased() : currency

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(accountTitle(account))
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                if let institution {
                    Text(institution)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(InvestFormat.money(holding.value, currency: holdingCurrency))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                if !position.isCash {
                    Text(InvestFormat.shares(holding.quantity, securityType: holding.securityType, symbol: position.symbol))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func accountTitle(_ account: InvestmentAccount?) -> String {
        guard let account else { return "Account" }
        let name = account.name.isEmpty ? (account.officialName ?? "Account") : account.name
        if let mask = account.mask, !mask.isEmpty {
            return "\(name) ••\(mask)"
        }
        return name
    }

    // MARK: Activity

    private func activityCard(_ transactions: [InvestmentTransaction], position: PortfolioPosition, currency: String) -> some View {
        let accountNames = Dictionary(portfolio.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let shown = Array(transactions.prefix(20))
        return VStack(alignment: .leading, spacing: 8) {
            CardHeader("Recent activity", systemImage: "clock.arrow.circlepath")
            if shown.isEmpty {
                InvestInlineNote(
                    systemImage: "clock",
                    text: "No buys, sells or dividends for \(InvestStyle.displaySymbol(for: position)) in the last 90 days."
                )
                .padding(.top, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, transaction in
                        if index > 0 {
                            Divider().padding(.leading, 48)
                        }
                        InvestTransactionRow(
                            transaction: transaction,
                            accountName: accountNames[transaction.accountID],
                            currency: currency
                        )
                    }
                }
            }
        }
        .hakiCard()
    }

    private func relatedTransactions(for position: PortfolioPosition) -> [InvestmentTransaction] {
        let symbol = position.symbol.uppercased()
        return portfolio.transactions.filter { transaction in
            if let ticker = transaction.ticker?.trimmingCharacters(in: .whitespaces), !ticker.isEmpty {
                return ticker.uppercased() == symbol
            }
            if let name = transaction.securityName, !name.isEmpty {
                return name == position.name
            }
            return false
        }
    }

    // MARK: Social

    private func socialCard(symbol: String) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))

        return VStack(alignment: .leading, spacing: 12) {
            CardHeader("Talk about $\(symbol)", systemImage: "bubble.left.and.bubble.right")
            Text("Share a trade or your take with friends. Posts show the ticker and what you write, never how much you hold.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            layout {
                Button {
                    compose = HoldingComposeRequest(draft: PostDraft(kind: .trade, ticker: symbol, tradeSide: .buy))
                } label: {
                    Label("Share a trade", systemImage: "arrow.left.arrow.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    compose = HoldingComposeRequest(draft: PostDraft(kind: .post, caption: "$\(symbol) "))
                } label: {
                    Label("Post about $\(symbol)", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .font(.subheadline.weight(.semibold))

            NavigationLink {
                TickerFeedView(ticker: symbol)
            } label: {
                HStack {
                    Label("See posts about $\(symbol)", systemImage: "text.bubble")
                        .font(.body.weight(.medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .hakiCard()
    }

    private func shareMenu(symbol: String) -> some View {
        Menu {
            Button {
                compose = HoldingComposeRequest(draft: PostDraft(kind: .trade, ticker: symbol, tradeSide: .buy))
            } label: {
                Label("Share a trade", systemImage: "arrow.left.arrow.right")
            }
            Button {
                compose = HoldingComposeRequest(draft: PostDraft(kind: .post, caption: "$\(symbol) "))
            } label: {
                Label("Post about $\(symbol)", systemImage: "square.and.pencil")
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Share")
    }
}

/// A compose sheet to open, with its prefilled draft.
struct HoldingComposeRequest: Identifiable {
    let id = UUID()
    let draft: PostDraft
}

// MARK: - Header

private struct HoldingHeaderCard: View {
    let position: PortfolioPosition
    let currency: String

    var body: some View {
        let assetClass = AssetClass(plaidType: position.securityType)
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                HoldingSymbolBadge(symbol: position.symbol, name: position.name, assetClass: assetClass, size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(InvestStyle.displaySymbol(for: position))
                        .font(.title2.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(position.name)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Label(assetClass.displayName, systemImage: InvestStyle.systemImage(for: assetClass))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(InvestStyle.color(for: assetClass))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(InvestStyle.color(for: assetClass).opacity(0.12), in: Capsule())
                }
            }
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 4) {
                Text("Market value")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(InvestFormat.money(position.value, currency: currency))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !position.isCash {
                    InvestGainLabel(gain: position.gain, gainPct: position.gainPct, currency: currency)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .hakiCard()
    }
}

// MARK: - Stats

private struct HoldingStatsCard: View {
    let position: PortfolioPosition
    let holdings: [BrokerageHolding]
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader("Details", systemImage: "list.bullet")
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
                if position.isCash {
                    GridRow {
                        InvestStatTile("Balance") {
                            Text(InvestFormat.money(position.value, currency: currency))
                        }
                        weightTile
                    }
                } else {
                    GridRow {
                        InvestStatTile(quantityTitle) {
                            Text(InvestFormat.quantity(position.quantity))
                        }
                        InvestStatTile("Price") {
                            Text(priceText)
                        }
                    }
                    GridRow {
                        InvestStatTile("Average cost") {
                            Text(averageCostText)
                        }
                        InvestStatTile("Total cost") {
                            Text(position.costBasis.map { InvestFormat.money($0, currency: currency) } ?? "—")
                        }
                    }
                    GridRow {
                        InvestStatTile("Total return") {
                            PercentChangeText(percent: position.gainPct)
                        }
                        weightTile
                    }
                }
            }
            if let asOf = priceAsOfText {
                Text(asOf)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !position.isCash, position.costBasis == nil {
                Text("Your brokerage didn't report what you paid, so gain can't be calculated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .hakiCard()
    }

    private var weightTile: some View {
        InvestStatTile("Portfolio weight") {
            Text(InvestFormat.percent(position.weightPct))
        }
    }

    private var quantityTitle: String {
        switch AssetClass(plaidType: position.securityType) {
        case .crypto, .bonds: "Units"
        default: "Shares"
        }
    }

    /// The brokerage's latest price, else value ÷ quantity.
    private var price: Double? {
        if let reported = holdings.compactMap(\.price).first(where: { $0.isFinite && $0 > 0 }) {
            return reported
        }
        guard position.quantity > 0 else { return nil }
        return position.value / position.quantity
    }

    private var priceText: String {
        price.map { InvestFormat.price($0, currency: currency) } ?? "—"
    }

    private var averageCostText: String {
        guard let costBasis = position.costBasis, position.quantity > 0 else { return "—" }
        return InvestFormat.price(costBasis / position.quantity, currency: currency)
    }

    private var priceAsOfText: String? {
        let dates = holdings.compactMap(\.priceAsOf).compactMap(InvestFormat.day(from:))
        guard let latest = dates.max() else { return nil }
        return "Price as of " + latest.formatted(date: .abbreviated, time: .omitted)
    }
}

#Preview("Stock") {
    NavigationStack {
        HoldingDetailView(position: PortfolioPosition(
            symbol: "VTI",
            name: "Vanguard Total Stock Market ETF",
            securityType: "etf",
            quantity: 110,
            value: 31_900,
            costBasis: 26_700,
            weightPct: 48.6
        ))
    }
    .previewEnvironment()
}

#Preview("Cash") {
    NavigationStack {
        HoldingDetailView(position: PortfolioPosition(
            symbol: "CUR:USD",
            name: "U.S. Dollar",
            securityType: "cash",
            quantity: 2_500,
            value: 2_500,
            costBasis: nil,
            weightPct: 3.8
        ))
    }
    .previewEnvironment()
}
