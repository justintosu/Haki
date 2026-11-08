//
//  BudgetsSummaryCard.swift
//  Haki
//
//  The month at a glance on the Budgets tab: what's left to spend, the
//  overall budget bar, pace and projection, a cumulative chart against an
//  even pace, and total spending including categories without a budget.
//

import Charts
import CoreGraphics
import Foundation
import SwiftData
import SwiftUI

struct BudgetsSummaryCard: View {
    let snapshot: BudgetsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            BudgetBar(progress: snapshot.overall, monthFraction: snapshot.monthFraction, height: 10)
            paceDetails
            BudgetsPaceChart(snapshot: snapshot)
                .frame(height: 160)
            legend
            Divider()
            totals
        }
        .hakiCard()
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(headlineCaption)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(timeLeftText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(Money.format(abs(snapshot.overall.remainingCents), showsCents: false))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(snapshot.overall.isOverBudget ? Color.hakiNegative : Color.primary)
            Text(spentOfBudgetText)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var headlineCaption: String {
        if snapshot.overall.isOverBudget { return "Over budget by" }
        return snapshot.isCurrentMonth ? "Left to spend" : "Left over"
    }

    private var timeLeftText: String {
        guard snapshot.isCurrentMonth else { return "Month ended" }
        let days = snapshot.remainingDays
        return days == 1 ? "Last day" : "\(days) days left"
    }

    private var spentOfBudgetText: String {
        let spent = Money.format(snapshot.budgetedSpentCents, showsCents: false)
        let budget = Money.format(snapshot.totalBudgetCents, showsCents: false)
        return "\(spent) spent of \(budget) budgeted"
    }

    // MARK: Pace

    private var paceDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(paceTitle, systemImage: paceSymbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(paceColor)
            if let projection = projectionText {
                Text(projection)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let allowance = allowanceText {
                Text(allowance)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let overCount = overCountText {
                Text(overCount)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var paceTitle: String {
        switch snapshot.pace {
        case .overBudget:
            return "Over budget"
        case .aheadOfPace:
            return "Spending faster than planned"
        case .onTrack:
            return snapshot.isCurrentMonth ? "On track" : "Stayed within budget"
        }
    }

    private var paceSymbol: String {
        switch snapshot.pace {
        case .overBudget: return "exclamationmark.triangle.fill"
        case .aheadOfPace: return "speedometer"
        case .onTrack: return "checkmark.circle.fill"
        }
    }

    private var paceColor: Color {
        switch snapshot.pace {
        case .overBudget: return Color.hakiNegative
        case .aheadOfPace: return Color.hakiWarning
        case .onTrack: return Color.hakiPositive
        }
    }

    private var projectionText: String? {
        guard snapshot.isCurrentMonth else { return nil }
        let projected = Money.format(snapshot.projectedCents, showsCents: false)
        return "Projected: \(projected) by month end"
    }

    /// "About $42 a day for the next 12 days", while there's budget left.
    private var allowanceText: String? {
        guard snapshot.isCurrentMonth, !snapshot.overall.isOverBudget else { return nil }
        let days = snapshot.remainingDays
        let perDay = snapshot.overall.remainingCents / days
        guard perDay > 0 else { return nil }
        let amount = Money.format(perDay, showsCents: false)
        if days == 1 { return "\(amount) left to spend today" }
        return "About \(amount) a day for the next \(days) days"
    }

    private var overCountText: String? {
        let over = snapshot.overBudgetCount
        guard over > 0 else { return nil }
        let total = snapshot.budgetLines.count
        if over == 1 { return "1 of \(total) budgets is over its limit" }
        return "\(over) of \(total) budgets are over their limit"
    }

    // MARK: Legend

    private var legend: some View {
        HStack(spacing: 16) {
            BudgetsPaceLegendItem(title: "Spent", color: Color.accentColor, isDashed: false)
            BudgetsPaceLegendItem(title: "Even pace", color: Color.hakiComparison, isDashed: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Totals

    private var totals: some View {
        HStack(alignment: .top, spacing: 12) {
            BudgetsSummaryStat(
                title: "All spending",
                value: Money.format(snapshot.totalSpendingCents, showsCents: false)
            )
            BudgetsSummaryStat(
                title: "Outside budgets",
                value: Money.format(snapshot.unbudgetedSpendingCents, showsCents: false)
            )
        }
    }
}

// MARK: - Stat

private struct BudgetsSummaryStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Legend item

/// A short solid or dashed line next to a label, so the chart's two lines
/// can be told apart without relying on color.
private struct BudgetsPaceLegendItem: View {
    let title: String
    let color: Color
    let isDashed: Bool

    var body: some View {
        HStack(spacing: 6) {
            swatch
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var swatch: some View {
        if isDashed {
            HStack(spacing: 2) {
                Capsule().fill(color).frame(width: 5, height: 3)
                Capsule().fill(color).frame(width: 5, height: 3)
                Capsule().fill(color).frame(width: 5, height: 3)
            }
            .accessibilityHidden(true)
        } else {
            Capsule()
                .fill(color)
                .frame(width: 19, height: 3)
                .accessibilityHidden(true)
        }
    }
}

// MARK: - Chart

/// Cumulative spending in budgeted categories (solid, accent) against an
/// even pace from the 1st to the total budget at month end (dashed, gray).
private struct BudgetsPaceChart: View {
    let snapshot: BudgetsSnapshot

    private struct PacePoint: Identifiable {
        let day: Int
        let dollars: Double

        var id: Int { day }
    }

    var body: some View {
        Chart {
            evenPaceMarks
            spentMarks
            todayMark
            budgetMark
        }
        .chartXScale(domain: 1...max(snapshot.daysInMonth, 2))
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: xAxisDays) { value in
                AxisValueLabel {
                    Text(xLabel(value))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    Text(yLabel(value))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Budget pace chart")
        .accessibilityValue(accessibilitySummary)
    }

    // MARK: Marks

    @ChartContentBuilder
    private var evenPaceMarks: some ChartContent {
        ForEach(evenPacePoints) { point in
            LineMark(
                x: .value("Day", point.day),
                y: .value("Amount", point.dollars),
                series: .value("Line", "Even pace")
            )
            .foregroundStyle(Color.hakiComparison)
            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, dash: [5, 4]))
        }
    }

    @ChartContentBuilder
    private var spentMarks: some ChartContent {
        ForEach(spentPoints) { point in
            AreaMark(
                x: .value("Day", point.day),
                y: .value("Amount", point.dollars)
            )
            .foregroundStyle(areaGradient)
            .interpolationMethod(.monotone)

            LineMark(
                x: .value("Day", point.day),
                y: .value("Amount", point.dollars),
                series: .value("Line", "Spent")
            )
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private var todayMark: some ChartContent {
        if snapshot.isCurrentMonth, let latest = spentPoints.last {
            PointMark(
                x: .value("Day", latest.day),
                y: .value("Amount", latest.dollars)
            )
            .foregroundStyle(Color.accentColor)
            .symbolSize(80)
        }
    }

    @ChartContentBuilder
    private var budgetMark: some ChartContent {
        RuleMark(y: .value("Budget", dollars(snapshot.totalBudgetCents)))
            .foregroundStyle(Color.secondary.opacity(0.6))
            .lineStyle(StrokeStyle(lineWidth: 1))
            .annotation(position: .top, alignment: .leading) {
                Text("Budget")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: Data

    private var spentPoints: [PacePoint] {
        snapshot.budgetedDaily.map { PacePoint(day: $0.day, dollars: dollars($0.cents)) }
    }

    private var evenPacePoints: [PacePoint] {
        let days = max(snapshot.daysInMonth, 2)
        let budget = dollars(snapshot.totalBudgetCents)
        return [
            PacePoint(day: 1, dollars: budget / Double(days)),
            PacePoint(day: days, dollars: budget),
        ]
    }

    private func dollars(_ cents: Int) -> Double {
        Double(cents) / 100
    }

    // MARK: Scales

    private var yDomain: ClosedRange<Double> {
        let spent = snapshot.budgetedDaily.map { $0.cents }
        let values = spent + [snapshot.totalBudgetCents]
        let highest = dollars(values.max() ?? 0)
        let lowest = dollars(min(0, values.min() ?? 0))
        // Headroom for the "Budget" label.
        let top = max(highest * 1.15, 10)
        return lowest...top
    }

    private var xAxisDays: [Int] {
        let days = snapshot.daysInMonth
        return [1, 8, 15, 22, 29].filter { $0 <= days }
    }

    /// "Nov 1", "8", "15"...
    private func xLabel(_ value: AxisValue) -> String {
        guard let day = value.as(Int.self) else { return "" }
        return day == 1 ? "\(snapshot.month.shortTitle()) 1" : String(day)
    }

    private func yLabel(_ value: AxisValue) -> String {
        guard let amount = value.as(Double.self) else { return "" }
        return Money.compact(Int((amount * 100).rounded()))
    }

    // MARK: Accessibility

    private var accessibilitySummary: String {
        let spent = Money.format(snapshot.budgetedSpentCents)
        let budget = Money.format(snapshot.totalBudgetCents)
        var parts = ["\(spent) spent of a \(budget) budget."]
        if snapshot.isCurrentMonth {
            parts.append("An even pace would be \(Money.format(snapshot.evenPaceCents)) by today.")
        }
        return parts.joined(separator: " ")
    }
}

#Preview {
    ScrollView {
        BudgetsSummaryCard(
            snapshot: BudgetsSnapshot(
                transactions: (try? PreviewData.context.fetch(FetchDescriptor<TransactionRecord>())) ?? [],
                categories: LedgerStore.allCategories(in: PreviewData.context),
                month: .current()
            )
        )
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
