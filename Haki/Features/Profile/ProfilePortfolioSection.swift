//
//  ProfilePortfolioSection.swift
//  Haki
//
//  The "Portfolio" side of a profile: total return and each holding's share
//  of the portfolio. Percentages only, never amounts.
//

import CoreGraphics
import Foundation
import SwiftUI

/// Loading state of a profile's public portfolio.
nonisolated enum ProfilePortfolioState: Equatable {
    case idle
    case loading
    case failed(String)
    case loaded(summary: PublicPortfolioSummary?, holdings: [PublicHolding])

    var isLoaded: Bool {
        if case .loaded = self { return true }
        return false
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

struct ProfilePortfolioSection: View {
    let state: ProfilePortfolioState
    let username: String
    let isSelf: Bool
    let sharesPortfolio: Bool
    let onRetry: () -> Void

    @Environment(PortfolioService.self) private var portfolio

    init(state: ProfilePortfolioState, username: String, isSelf: Bool, sharesPortfolio: Bool, onRetry: @escaping () -> Void) {
        self.state = state
        self.username = username
        self.isSelf = isSelf
        self.sharesPortfolio = sharesPortfolio
        self.onRetry = onRetry
    }

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Loading portfolio…")
                .frame(maxWidth: .infinity, minHeight: 160)
        case .failed(let message):
            ProfileInlineError(message: message, retry: onRetry)
        case .loaded(let summary, let holdings):
            if holdings.isEmpty {
                emptyState
                    .hakiCard()
            } else {
                VStack(spacing: 16) {
                    summaryCard(summary: summary, holdings: holdings)
                    holdingsCard(holdings)
                }
            }
        }
    }

    // MARK: Cards

    private func summaryCard(summary: PublicPortfolioSummary?, holdings: [PublicHolding]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader("Portfolio", systemImage: "chart.pie")
            VStack(alignment: .leading, spacing: 2) {
                Text("Total return")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                PercentChangeText(percent: summary?.totalGainPct, decimals: 1)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .contentTransition(.numericText())
            }
            .accessibilityElement(children: .combine)
            Text(detailLine(summary: summary, holdings: holdings))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("Percentages only. Dollar amounts are never shared.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if isSelf && !sharesPortfolio {
                Label("Only you can see this. Turn on portfolio sharing in Edit profile to show it on your profile.", systemImage: "eye.slash")
                    .font(.footnote)
                    .foregroundStyle(Color.hakiWarning)
            }
        }
        .hakiCard()
    }

    private func holdingsCard(_ holdings: [PublicHolding]) -> some View {
        let maxWeight = holdings.compactMap(\.weightPct).max() ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader("Holdings", systemImage: "list.bullet")
            ForEach(holdings) { holding in
                VStack(spacing: 12) {
                    if holding.id != holdings.first?.id {
                        Divider()
                    }
                    holdingRow(holding, maxWeight: maxWeight)
                }
            }
        }
        .hakiCard()
    }

    @ViewBuilder
    private func holdingRow(_ holding: PublicHolding, maxWeight: Double) -> some View {
        if let ticker = linkableTicker(for: holding) {
            NavigationLink {
                TickerFeedView(ticker: ticker)
            } label: {
                ProfileHoldingRow(holding: holding, maxWeight: maxWeight, showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows posts about \(ticker).")
        } else {
            ProfileHoldingRow(holding: holding, maxWeight: maxWeight, showsChevron: false)
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private var emptyState: some View {
        if isSelf {
            if portfolio.hasConnections {
                ContentUnavailableView(
                    "No positions to show yet",
                    systemImage: "chart.pie",
                    description: Text("Your holdings show up here once your brokerage finishes syncing.")
                )
            } else {
                ContentUnavailableView {
                    Label("No brokerage connected yet", systemImage: "building.columns")
                } description: {
                    Text("Connect a brokerage to show what you hold as percentages. Dollar amounts are never shared.")
                } actions: {
                    BrokerageLinkButton()
                }
            }
        } else if !sharesPortfolio {
            ContentUnavailableView(
                "@\(username) keeps their portfolio private",
                systemImage: "lock.fill",
                description: Text("Only they can see what they hold.")
            )
        } else {
            ContentUnavailableView(
                "No brokerage connected yet",
                systemImage: "building.columns",
                description: Text("@\(username) hasn't shared any holdings yet.")
            )
        }
    }

    // MARK: Helpers

    private func detailLine(summary: PublicPortfolioSummary?, holdings: [PublicHolding]) -> String {
        let count = summary?.positionCount ?? holdings.count
        var parts = [count == 1 ? "1 position" : "\(count) positions"]
        if let updatedAt = summary?.updatedAt {
            parts.append("updated \(updatedAt.formatted(.relative(presentation: .named)))")
        }
        return parts.joined(separator: " · ")
    }

    /// The symbol to open a ticker feed for, if the holding has a real ticker (not cash).
    private func linkableTicker(for holding: PublicHolding) -> String? {
        guard AssetClass(plaidType: holding.securityType) != .cash else { return nil }
        let symbol = holding.ticker.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return Cashtags.isValidTicker(symbol) ? symbol : nil
    }
}

/// Ticker and name, weight and return, and a bar showing the weight.
private struct ProfileHoldingRow: View {
    let holding: PublicHolding
    let maxWeight: Double
    let showsChevron: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(holding.ticker)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    if let name = secondaryName {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(weightText)
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                    PercentChangeText(percent: holding.gainPct)
                        .font(.caption)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            ProfileWeightBar(fraction: fraction)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var secondaryName: String? {
        guard let name = holding.name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty, name != holding.ticker
        else { return nil }
        return name
    }

    private var weightText: String {
        guard let weight = holding.weightPct else { return "—" }
        return weight.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    private var fraction: Double {
        guard maxWeight > 0, let weight = holding.weightPct else { return 0 }
        return min(1, max(0, weight / maxWeight))
    }

    private var accessibilityText: String {
        var parts = [holding.ticker]
        if let name = secondaryName { parts.append(name) }
        parts.append("\(weightText) of the portfolio")
        if holding.gainPct != nil {
            parts.append("return \(PercentChangeText.format(holding.gainPct))")
        }
        return parts.joined(separator: ", ")
    }
}

private struct ProfileWeightBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(4, proxy.size.width * CGFloat(fraction)))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

#Preview("Shared portfolio") {
    NavigationStack {
        ScrollView {
            ProfilePortfolioSection(
                state: .loaded(
                    summary: PublicPortfolioSummary(positionCount: 7, totalGainPct: 14.2, updatedAt: Date.now.addingTimeInterval(-7200)),
                    holdings: SocialPreviewData.publicHoldings
                ),
                username: "dividend_dan",
                isSelf: false,
                sharesPortfolio: true
            ) {}
            .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}

#Preview("Private") {
    NavigationStack {
        ScrollView {
            ProfilePortfolioSection(
                state: .loaded(summary: nil, holdings: []),
                username: "sam_saves",
                isSelf: false,
                sharesPortfolio: false
            ) {}
            .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
