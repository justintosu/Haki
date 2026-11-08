//
//  OverviewSpendingCard.swift
//  Haki
//
//  "Spending this month": the headline number, how it compares with the
//  same point last month, and a cumulative chart of both months against the
//  total budget.
//

import Charts
import Foundation
import SwiftUI

struct OverviewSpendingCard: View {
    let snapshot: OverviewSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            OverviewSpendingChart(snapshot: snapshot)
                .frame(height: 190)
            legend
            if snapshot.hasBudgets {
                Divider()
                budgetSummary
            }
        }
        .hakiCard()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spending this month")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(snapshot.month.title())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(Money.format(snapshot.spentCents, showsCents: false))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
            comparison
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var comparison: some View {
        if snapshot.lastMonthHasSpending {
            let difference = snapshot.spentCents - snapshot.lastMonthSameDayCents
            Label {
                Text(comparisonText(difference))
            } icon: {
                Image(systemName: comparisonSymbol(difference))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(comparisonColor(difference))
        } else {
            Text("Nothing from last month to compare with yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// Differences under a dollar read as "about the same".
    private func isAboutTheSame(_ difference: Int) -> Bool {
        abs(difference) < 100
    }

    private func comparisonText(_ difference: Int) -> String {
        if isAboutTheSame(difference) { return "About the same as this time last month" }
        let amount = Money.format(abs(difference), showsCents: false)
        if difference < 0 {
            return "\(amount) less than this time last month"
        }
        return "\(amount) more than this time last month"
    }

    private func comparisonSymbol(_ difference: Int) -> String {
        if isAboutTheSame(difference) { return "equal" }
        return difference < 0 ? "arrow.down.right" : "arrow.up.right"
    }

    private func comparisonColor(_ difference: Int) -> Color {
        if isAboutTheSame(difference) { return Color.secondary }
        return difference < 0 ? Color.hakiPositive : Color.hakiNegative
    }

    // MARK: Legend

    private var legend: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                legendItems
            }
            VStack(alignment: .leading, spacing: 6) {
                legendItems
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var legendItems: some View {
        OverviewLegendItem(title: "This month", color: .accentColor)
        if snapshot.lastMonthHasSpending {
            OverviewLegendItem(title: "Last month", color: .hakiComparison, dash: [5, 4])
        }
        if snapshot.hasBudgets {
            OverviewLegendItem(title: "Budget", color: .secondary, dash: [1, 4])
        }
    }

    // MARK: Budget

    private var budgetSummary: some View {
        let remaining = snapshot.totalBudgetCents - snapshot.spentCents
        let isOver = remaining < 0
        return Label {
            Text(budgetText(remaining: remaining))
        } icon: {
            Image(systemName: isOver ? "exclamationmark.triangle.fill" : "target")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isOver ? Color.hakiNegative : Color.secondary)
    }

    private func budgetText(remaining: Int) -> String {
        if remaining < 0 {
            return "\(Money.format(-remaining, showsCents: false)) over budget"
        }
        let left = Money.format(remaining, showsCents: false)
        let total = Money.format(snapshot.totalBudgetCents, showsCents: false)
        return "\(left) left of \(total) budget"
    }
}

// MARK: - Chart

/// Cumulative spending by day: this month through today (solid, accent) and
/// all of last month (dashed, gray), with the total budget as a dotted rule.
private struct OverviewSpendingChart: View {
    let snapshot: OverviewSnapshot

    var body: some View {
        Chart {
            lastMonthMarks
            thisMonthMarks
            todayMark
            budgetMark
        }
        .chartXScale(domain: 1...max(snapshot.daysInMonth, 2))
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xAxisDays) { value in
                AxisValueLabel {
                    if let day = value.as(Int.self) {
                        Text(dayLabel(day))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(Money.compact(Int((amount * 100).rounded())))
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Spending chart")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Marks

    /// Hidden when last month had no spending, so a flat line at $0 doesn't
    /// read as a real comparison.
    @ChartContentBuilder
    private var lastMonthMarks: some ChartContent {
        if snapshot.lastMonthHasSpending {
            ForEach(snapshot.lastMonthDaily) { point in
                LineMark(
                    x: .value("Day", point.day),
                    y: .value("Spent", dollars(point.cents)),
                    series: .value("Period", "Last month")
                )
                .foregroundStyle(Color.hakiComparison)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
                .interpolationMethod(.monotone)
            }
        }
    }

    @ChartContentBuilder
    private var thisMonthMarks: some ChartContent {
        ForEach(snapshot.thisMonthDaily) { point in
            AreaMark(
                x: .value("Day", point.day),
                y: .value("Spent", dollars(point.cents))
            )
            .foregroundStyle(areaGradient)
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Day", point.day),
                y: .value("Spent", dollars(point.cents)),
                series: .value("Period", "This month")
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private var todayMark: some ChartContent {
        if let latest = snapshot.thisMonthDaily.last {
            PointMark(
                x: .value("Day", latest.day),
                y: .value("Spent", dollars(latest.cents))
            )
            .foregroundStyle(Color.accentColor)
            .symbolSize(90)
        }
    }

    @ChartContentBuilder
    private var budgetMark: some ChartContent {
        if snapshot.hasBudgets {
            RuleMark(y: .value("Budget", dollars(snapshot.totalBudgetCents)))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [1, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Budget")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.25), Color.accentColor.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: Scales

    private func dollars(_ cents: Int) -> Double {
        Double(cents) / 100
    }

    private var yDomain: ClosedRange<Double> {
        let thisMonth = snapshot.thisMonthDaily.map { $0.cents }
        let lastMonth = snapshot.lastMonthDaily.map { $0.cents }
        let values = thisMonth + lastMonth + [snapshot.totalBudgetCents]
        let highest = dollars(values.max() ?? 0)
        let lowest = dollars(min(0, values.min() ?? 0))
        // Headroom for the "Budget" label; at least $10 so an empty month isn't flat at the top.
        let top = max(highest * 1.15, 10)
        return lowest...top
    }

    private var yTicks: [Double] {
        let top = yDomain.upperBound
        let step = Self.niceStep(top / 3)
        guard step > 0 else { return [0] }
        return Array(stride(from: 0, through: top, by: step))
    }

    /// Rounds a step up to 1, 2 or 5 times a power of ten.
    private static func niceStep(_ rough: Double) -> Double {
        guard rough > 0, rough.isFinite else { return 0 }
        let magnitude = pow(10, log10(rough).rounded(.down))
        let fraction = rough / magnitude
        let multiplier: Double
        if fraction <= 1 {
            multiplier = 1
        } else if fraction <= 2 {
            multiplier = 2
        } else if fraction <= 5 {
            multiplier = 5
        } else {
            multiplier = 10
        }
        return multiplier * magnitude
    }

    private var xAxisDays: [Int] {
        let days = snapshot.daysInMonth
        return [1, 8, 15, 22, 29].filter { $0 <= days }
    }

    private func dayLabel(_ day: Int) -> String {
        day == 1 ? "\(snapshot.month.shortTitle()) 1" : "\(day)"
    }

    // MARK: Accessibility

    private var accessibilitySummary: String {
        var parts = ["This month, \(Money.format(snapshot.spentCents)) spent so far."]
        if snapshot.lastMonthHasSpending {
            parts.append("Last month, \(Money.format(snapshot.lastMonthSameDayCents)) by the same day.")
        }
        if snapshot.hasBudgets {
            parts.append("Monthly budget, \(Money.format(snapshot.totalBudgetCents)).")
        }
        return parts.joined(separator: " ")
    }
}

#Preview {
    ScrollView {
        OverviewSpendingCard(snapshot: OverviewPreviewData.snapshot)
            .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
