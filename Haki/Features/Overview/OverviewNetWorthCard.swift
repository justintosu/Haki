//
//  OverviewNetWorthCard.swift
//  Haki
//
//  Current net worth, its change over the last month and a three-month
//  sparkline. Tapping opens Accounts.
//

import Charts
import Foundation
import SwiftUI

struct OverviewNetWorthCard: View {
    let snapshot: OverviewSnapshot
    /// Shown in the no-accounts state.
    let onAddAccount: () -> Void

    @Environment(AppRouter.self) private var router

    var body: some View {
        if snapshot.hasAccounts {
            Button {
                router.showHome(.accounts)
            } label: {
                summary
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens Accounts")
        } else {
            noAccounts
        }
    }

    // MARK: Summary

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Net worth", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(Money.format(snapshot.netWorthCents, showsCents: false))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                changeLabel
            }
            if snapshot.netWorthPoints.count >= 2 {
                OverviewSparkline(points: snapshot.netWorthPoints)
                    .frame(height: 64)
                    .accessibilityHidden(true)
            }
        }
        .hakiCard()
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    @ViewBuilder
    private var changeLabel: some View {
        if let change = snapshot.netWorthChangeCents {
            if change == 0 {
                Text("No change over the past month")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label {
                    Text(changeText(change))
                } icon: {
                    Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(change > 0 ? Color.hakiPositive : Color.hakiNegative)
            }
        } else {
            Text("Keep your balances up to date to see the trend.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func changeText(_ change: Int) -> String {
        let amount = Money.format(change, showsCents: false, alwaysShowsSign: true)
        return "\(amount) over the past month"
    }

    // MARK: No accounts

    private var noAccounts: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader("Net worth", systemImage: "chart.line.uptrend.xyaxis")
            Text("Add your bank accounts, cards, loans and investments to follow your net worth over time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                onAddAccount()
            } label: {
                Label("Add an account", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .hakiCard()
    }
}

// MARK: - Sparkline

/// A small line with a gradient fill and no axes.
private struct OverviewSparkline: View {
    let points: [NetWorthPoint]
    private let domain: ClosedRange<Double>

    init(points: [NetWorthPoint]) {
        self.points = points
        let values = points.map { Double($0.netCents) / 100 }
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        // Pad the range so a flat line sits in the middle and curves don't touch the edges.
        let padding = max((high - low) * 0.15, max(abs(high) * 0.01, 1))
        domain = (low - padding)...(high + padding)
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Baseline", domain.lowerBound),
                    yEnd: .value("Net worth", Double(point.netCents) / 100)
                )
                .foregroundStyle(gradient)
                .interpolationMethod(.catmullRom)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Net worth", Double(point.netCents) / 100)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: domain)
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.3), Color.accentColor.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            OverviewNetWorthCard(snapshot: OverviewPreviewData.snapshot, onAddAccount: {})
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
