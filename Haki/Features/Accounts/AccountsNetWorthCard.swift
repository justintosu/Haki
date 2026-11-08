//
//  AccountsNetWorthCard.swift
//  Haki
//
//  The card at the top of the Accounts tab: net worth, its change over the
//  chosen range, an interactive history chart and the assets / liabilities
//  split.
//

import Charts
import Foundation
import SwiftData
import SwiftUI

// MARK: - Summary

/// Net worth numbers for the Accounts tab, computed once per render.
struct NetWorthSummary {
    /// Sum of `netWorthContributionCents` over every account.
    let netWorthCents: Int
    /// Balances of included asset accounts.
    let assetsCents: Int
    /// Amount owed on included liability accounts, positive.
    let liabilitiesCents: Int
    /// How many accounts count toward net worth.
    let includedCount: Int
    /// Net worth history over the range, oldest first. The last point is today.
    let points: [AccountsChartPoint]

    init(accounts: [Account], range: ChartRange, now: Date = .now) {
        var assets = 0
        var liabilities = 0
        var observations: [BalanceObservation] = []
        var included = 0
        for account in accounts where account.includeInNetWorth {
            included += 1
            if account.isLiability {
                liabilities += account.balanceCents
            } else {
                assets += account.balanceCents
            }
            let recorded = account.balanceObservations
            if recorded.isEmpty {
                // No recorded history: treat the current balance as known since its last update.
                observations.append(BalanceObservation(
                    accountID: account.id.uuidString,
                    date: min(account.balanceUpdatedAt, now),
                    balanceCents: account.balanceCents,
                    isLiability: account.isLiability
                ))
            } else {
                observations.append(contentsOf: recorded)
            }
        }

        let netWorth = accounts.reduce(0) { $0 + $1.netWorthContributionCents }
        netWorthCents = netWorth
        assetsCents = assets
        liabilitiesCents = liabilities
        includedCount = included

        let dates = range.sampleDates(now: now)
        let series = NetWorthCalculator.series(observations: observations, at: dates)
        // Before the first recorded balance there is nothing to show (not a net worth of zero).
        let earliest = observations.map(\.date).min()
        var history: [AccountsChartPoint] = []
        for point in series {
            guard let earliest, point.date >= earliest else { continue }
            history.append(AccountsChartPoint(date: point.date, cents: point.netCents))
        }
        // The last sample date is "now": use today's balances so the chart ends at the headline.
        if let last = history.last {
            history[history.count - 1] = AccountsChartPoint(date: last.date, cents: netWorth)
        }
        points = history
    }

    /// Change from the start of the range to today, if there is history.
    var changeCents: Int? {
        guard points.count >= 2, let first = points.first, let last = points.last else { return nil }
        return last.cents - first.cents
    }

    var startCents: Int { points.first?.cents ?? 0 }
}

// MARK: - Card

struct AccountsNetWorthCard: View {
    let summary: NetWorthSummary
    @Binding var range: ChartRange

    @State private var selectedDate: Date?

    init(summary: NetWorthSummary, range: Binding<ChartRange>) {
        self.summary = summary
        self._range = range
    }

    var body: some View {
        let selected = AccountsChartPoint.nearest(to: selectedDate, in: summary.points)
        VStack(alignment: .leading, spacing: 14) {
            headline(selected: selected)
            history
            AccountsRangePicker(range: $range)
            Divider()
            totals
        }
        .hakiCard()
        .sensoryFeedback(.selection, trigger: selected?.date)
    }

    // MARK: Headline

    private func headline(selected: AccountsChartPoint?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Net worth")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Money.format(selected?.cents ?? summary.netWorthCents, showsCents: false))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            subtitle(selected: selected)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func subtitle(selected: AccountsChartPoint?) -> some View {
        if let selected {
            Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        } else if let change = summary.changeCents {
            AccountsChangeLabel(
                changeCents: change,
                startCents: summary.startCents,
                periodText: AccountsStyle.periodText(for: range)
            )
        } else if summary.includedCount == 0 {
            Text("None of your accounts count toward net worth.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else {
            Text("Today")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Chart

    @ViewBuilder
    private var history: some View {
        if summary.points.count >= 2 {
            AccountsHistoryChart(
                points: summary.points,
                range: range,
                seriesName: "Net worth",
                selectedDate: $selectedDate
            )
            .frame(height: 190)
        } else {
            HStack(spacing: 10) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text("Your net worth history fills in as you update balances over time.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Totals

    private var totals: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                totalTile(title: "Assets", cents: summary.assetsCents,
                          systemImage: "arrow.up.circle.fill", tint: Color.hakiPositive)
                totalTile(title: "Liabilities", cents: summary.liabilitiesCents,
                          systemImage: "arrow.down.circle.fill", tint: Color.hakiNegative)
            }
            if summary.assetsCents > 0 || summary.liabilitiesCents > 0 {
                AccountsCompositionBar(assetsCents: summary.assetsCents, liabilitiesCents: summary.liabilitiesCents)
            }
        }
    }

    private func totalTile(title: String, cents: Int, systemImage: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(Money.format(cents, showsCents: false))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Composition bar

/// Assets (green) next to liabilities (red), proportional to their size.
private struct AccountsCompositionBar: View {
    let assetsCents: Int
    let liabilitiesCents: Int

    var body: some View {
        GeometryReader { proxy in
            let assets = Double(max(0, assetsCents))
            let liabilities = Double(max(0, liabilitiesCents))
            let total = assets + liabilities
            let assetFraction: CGFloat = total > 0 ? CGFloat(assets / total) : 1
            let usable: CGFloat = max(0, proxy.size.width - 3)
            HStack(spacing: 3) {
                Capsule()
                    .fill(Color.hakiPositive)
                    .frame(width: usable * assetFraction)
                Capsule()
                    .fill(Color.hakiNegative)
                    .frame(width: usable * (1 - assetFraction))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

private struct AccountsNetWorthCardPreview: View {
    @Query(sort: [SortDescriptor(\Account.sortOrder)]) private var accounts: [Account]
    @State private var range: ChartRange = .threeMonths

    var body: some View {
        ScrollView {
            AccountsNetWorthCard(summary: NetWorthSummary(accounts: accounts, range: range), range: $range)
                .padding()
        }
        .background(Color.hakiBackground)
    }
}

#Preview {
    AccountsNetWorthCardPreview()
        .previewEnvironment()
}
