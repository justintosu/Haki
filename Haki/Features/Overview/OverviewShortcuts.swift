//
//  OverviewShortcuts.swift
//  Haki
//
//  Shortcuts from Home to the money screens that don't have tabs of their
//  own, and a small investing summary that links to the Invest tab.
//

import Foundation
import SwiftUI

/// Budgets · Recurring · Accounts tiles at the top of Home.
struct OverviewShortcutsRow: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        HStack(spacing: 12) {
            tile("Budgets", systemImage: "chart.bar.fill", tint: .orange, destination: .budgets)
            tile("Recurring", systemImage: "arrow.triangle.2.circlepath", tint: .indigo, destination: .recurring)
            tile("Accounts", systemImage: "building.columns.fill", tint: .teal, destination: .accounts)
        }
    }

    private func tile(_ title: String, systemImage: String, tint: Color, destination: HomeDestination) -> some View {
        Button {
            router.showHome(destination)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(title)")
    }
}

/// Portfolio value and return, or a prompt to connect a brokerage. Opens Invest.
struct OverviewInvestingCard: View {
    @Environment(AppRouter.self) private var router
    @Environment(PortfolioService.self) private var portfolio

    var body: some View {
        Button {
            router.selectedTab = .invest
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Investments", systemImage: "chart.line.uptrend.xyaxis.circle.fill")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                if portfolio.hasConnections {
                    connectedSummary
                } else {
                    Text("Connect a brokerage to see your portfolio next to your spending, and share how it's doing with friends.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .foregroundStyle(.primary)
            .hakiCard()
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Invest")
        .task {
            if portfolio.lastLoaded == nil, !portfolio.isLoading {
                await portfolio.refresh()
            }
        }
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
