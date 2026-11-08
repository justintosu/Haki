//
//  OverviewShortcuts.swift
//  Haki
//
//  Shortcuts from Home to the money screens that don't have tabs of their
//  own, and a small investing summary that links to the Invest tab.
//

import Foundation
import SwiftUI

/// Transactions · Budgets · Recurring · Accounts tiles at the top of Home. At
/// accessibility text sizes the tiles don't fit side by side, so they become
/// full-width rows.
struct OverviewShortcutsRow: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// The tinted icon square, grown with the icon's text style.
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) {
                tiles
            }
        } else {
            HStack(spacing: 10) {
                tiles
            }
        }
    }

    @ViewBuilder
    private var tiles: some View {
        tile("Transactions", systemImage: "list.bullet.rectangle.portrait.fill", tint: .blue, destination: .transactions)
        tile("Budgets", systemImage: "chart.bar.fill", tint: .orange, destination: .budgets)
        tile("Recurring", systemImage: "arrow.triangle.2.circlepath", tint: .indigo, destination: .recurring)
        tile("Accounts", systemImage: "building.columns.fill", tint: .teal, destination: .accounts)
    }

    private func tile(_ title: String, systemImage: String, tint: Color, destination: HomeDestination) -> some View {
        Button {
            router.showHome(destination)
        } label: {
            if dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    icon(systemImage, tint: tint)
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    icon(systemImage, tint: tint)
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .padding(.horizontal, 4)
                .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title)")
    }

    private func icon(_ systemImage: String, tint: Color) -> some View {
        Image(systemName: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: iconSize, height: iconSize)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// Portfolio value and return, or a prompt to connect a brokerage. Opens
/// Invest. Until the first load finishes it shows a spinner (or a retry when
/// it failed) rather than the prompt, which would suggest a linked
/// brokerage was lost.
struct OverviewInvestingCard: View {
    @Environment(AppRouter.self) private var router
    @Environment(PortfolioService.self) private var portfolio

    var body: some View {
        Group {
            if loadFailed {
                failedCard
            } else {
                Button {
                    router.selectedTab = .invest
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        header(showsChevron: true)
                        summary
                    }
                    .foregroundStyle(.primary)
                    .hakiCard()
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens Invest")
            }
        }
        .task {
            if portfolio.lastLoaded == nil, !portfolio.isLoading {
                await portfolio.refresh()
            }
        }
    }

    /// Nothing has loaded yet and the last attempt failed.
    private var loadFailed: Bool {
        !portfolio.hasConnections && portfolio.lastLoaded == nil
            && !portfolio.isLoading && portfolio.errorMessage != nil
    }

    private func header(showsChevron: Bool) -> some View {
        HStack {
            Label("Investments", systemImage: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.headline)
            Spacer()
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var summary: some View {
        if portfolio.hasConnections {
            connectedSummary
        } else if portfolio.lastLoaded == nil {
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading your investments…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Connect a brokerage to see your portfolio next to your spending, and share how it's doing — as percentages, never amounts.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var failedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            header(showsChevron: false)
            Text("Couldn't load your investments. Check your connection and try again.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                Task { await portfolio.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .hakiCard()
    }

    private var connectedSummary: some View {
        let totals = portfolio.totals
        return HStack(alignment: .firstTextBaseline) {
            Text(Money.format(Int((totals.value * 100).rounded()), showsCents: false))
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                PercentChangeText(percent: totals.gainPct)
                    .font(.subheadline.weight(.semibold))
                Text(positionsText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var positionsText: String {
        let count = portfolio.positions.count
        return count == 1 ? "1 position" : "\(count) positions"
    }
}

#Preview {
    VStack(spacing: 16) {
        OverviewShortcutsRow()
        OverviewInvestingCard()
    }
    .padding()
    .background(Color.hakiBackground)
    .previewEnvironment()
}
