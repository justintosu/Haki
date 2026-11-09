//
//  AccountsComponents.swift
//  Haki
//
//  Small pieces shared by the Accounts screens: the account-kind icon, the
//  negative-balance toggle, the interactive balance / net worth chart, the
//  change label and the range picker.
//

import Charts
import Foundation
import SwiftUI

// MARK: - Chart point

/// One value of a balance or net worth history.
nonisolated struct AccountsChartPoint: Identifiable, Hashable {
    let date: Date
    let cents: Int

    var id: Date { date }

    /// Charts plot money as dollars (`Double`), never as cents.
    var dollars: Double { Double(cents) / 100 }

    /// The point closest to `date`, for drag selection.
    static func nearest(to date: Date?, in points: [AccountsChartPoint]) -> AccountsChartPoint? {
        guard let date else { return nil }
        return points.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(date)) < abs(rhs.date.timeIntervalSince(date))
        }
    }
}

// MARK: - Style helpers

enum AccountsStyle {
    /// A tint per account kind, used for the icon circle.
    static func tint(for kind: AccountKind) -> Color {
        switch kind {
        case .checking: return Color(hex: "#4F8EF7")
        case .savings: return Color(hex: "#1FA67A")
        case .cash: return Color(hex: "#3FB97B")
        case .creditCard: return Color(hex: "#F2994A")
        case .investment: return Color(hex: "#6C63FF")
        case .loan: return Color(hex: "#EB5757")
        case .property: return Color(hex: "#A0673D")
        case .other: return Color(hex: "#8E8E93")
        }
    }

    /// "past 3 months", for change labels.
    static func periodText(for range: ChartRange) -> String {
        switch range {
        case .oneMonth: return "past month"
        case .threeMonths: return "past 3 months"
        case .sixMonths: return "past 6 months"
        case .oneYear: return "past year"
        }
    }

    /// What VoiceOver reads for a range segment.
    static func spokenName(for range: ChartRange) -> String {
        switch range {
        case .oneMonth: return "1 month"
        case .threeMonths: return "3 months"
        case .sixMonths: return "6 months"
        case .oneYear: return "1 year"
        }
    }

    /// Date labels on the chart's x axis.
    static func axisDateFormat(for range: ChartRange) -> Date.FormatStyle {
        switch range {
        case .oneMonth, .threeMonths: return .dateTime.month(.abbreviated).day()
        case .sixMonths, .oneYear: return .dateTime.month(.abbreviated)
        }
    }

    /// "Updated just now", "Updated 3 days ago".
    static func updatedText(_ date: Date, now: Date = .now) -> String {
        if abs(now.timeIntervalSince(date)) < 60 { return "Updated just now" }
        return "Updated " + date.formatted(.relative(presentation: .named))
    }

    /// A balance not updated for a month probably needs a look.
    static func isStale(_ date: Date, now: Date = .now) -> Bool {
        now.timeIntervalSince(date) > 30 * 86_400
    }

    /// Parses a typed amount in the user's locale.
    static func parseCents(_ text: String) -> Int? {
        Money.parseCents(text, decimalSeparator: Character(Locale.current.decimalSeparator ?? "."))
    }

    /// Applies a negative-balance toggle to a typed amount. A minus typed or
    /// pasted into the field still counts when the toggle is off.
    static func applyingSign(_ cents: Int, isNegative: Bool) -> Int {
        isNegative ? -abs(cents) : cents
    }

    /// "••4821", or an empty string.
    static func maskText(_ mask: String) -> String {
        mask.isEmpty ? "" : "••" + mask
    }
}

// MARK: - Negative balance toggle

/// The sign of a typed balance, since the decimal pad has no minus key: an
/// asset below zero (an overdrawn checking account) or a liability with a
/// credit balance (the card owes you after a refund).
struct AccountNegativeBalanceToggle: View {
    let isLiability: Bool
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isLiability ? "Credit balance" : "Negative balance")
                Text(isLiability ? "You're owed money, like after a refund." : "Below zero, like an overdrawn account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Kind icon

/// The account kind's SF Symbol on a tinted circle.
struct AccountKindIcon: View {
    let kind: AccountKind
    var size: CGFloat = 36

    var body: some View {
        let tint = AccountsStyle.tint(for: kind)
        ZStack {
            Circle()
                .fill(tint.opacity(0.16))
            Image(systemName: kind.systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Change label

/// "↗ +$1,234 (2.3%) past 3 months". Direction is shown by the arrow and the
/// sign as well as the color.
struct AccountsChangeLabel: View {
    let changeCents: Int
    /// The value at the start of the period, for the percentage.
    let startCents: Int
    let periodText: String
    /// For liabilities, owing less is the good direction.
    var decreaseIsGood: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if changeCents != 0 {
                Image(systemName: changeCents > 0 ? "arrow.up.right" : "arrow.down.right")
                    .fontWeight(.semibold)
            }
            Text(amountText)
                .monospacedDigit()
            Text(periodText)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(tint)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var isGood: Bool {
        decreaseIsGood ? changeCents < 0 : changeCents > 0
    }

    private var tint: Color {
        if changeCents == 0 { return Color.secondary }
        return isGood ? Color.hakiPositive : Color.hakiNegative
    }

    private var percentText: String? {
        guard startCents != 0, changeCents != 0 else { return nil }
        let fraction: Double = Double(abs(changeCents)) / Double(abs(startCents))
        return fraction.formatted(.percent.precision(.fractionLength(1)))
    }

    private var amountText: String {
        if changeCents == 0 { return "No change" }
        let amount = Money.format(changeCents, showsCents: false, alwaysShowsSign: true)
        if let percentText { return amount + " (" + percentText + ")" }
        return amount
    }

    private var spokenText: String {
        if changeCents == 0 { return "No change over the " + periodText }
        let direction = changeCents > 0 ? "Up" : "Down"
        var text = direction + " " + Money.format(abs(changeCents), showsCents: false)
        if let percentText { text += ", " + percentText }
        return text + ", over the " + periodText
    }
}

// MARK: - Range picker

/// Segmented 1M / 3M / 6M / 1Y picker.
struct AccountsRangePicker: View {
    @Binding var range: ChartRange

    var body: some View {
        Picker("Time range", selection: $range) {
            ForEach(ChartRange.allCases) { option in
                Text(option.rawValue)
                    .accessibilityLabel(AccountsStyle.spokenName(for: option))
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}

// MARK: - History chart

/// A line with a gradient area underneath, with drag selection. The parent
/// reads `selectedDate` to show the value under the finger.
struct AccountsHistoryChart: View {
    let points: [AccountsChartPoint]
    let range: ChartRange
    /// "Net worth", "Balance", "Owed" — used for accessibility and the y value.
    let seriesName: String
    let tint: Color
    @Binding var selectedDate: Date?

    init(points: [AccountsChartPoint], range: ChartRange, seriesName: String, tint: Color = .accentColor,
         selectedDate: Binding<Date?>) {
        self.points = points
        self.range = range
        self.seriesName = seriesName
        self.tint = tint
        self._selectedDate = selectedDate
    }

    var body: some View {
        let domain = yDomain
        let selected = AccountsChartPoint.nearest(to: selectedDate, in: points)
        let dateFormat = AccountsStyle.axisDateFormat(for: range)

        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Baseline", domain.lowerBound),
                    yEnd: .value(seriesName, point.dollars)
                )
                .foregroundStyle(gradient)
                .interpolationMethod(.monotone)
                .accessibilityHidden(true)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value(seriesName, point.dollars)
                )
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue(Money.format(point.cents))
            }

            if let selected {
                RuleMark(x: .value("Selected date", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .accessibilityHidden(true)

                PointMark(
                    x: .value("Date", selected.date),
                    y: .value(seriesName, selected.dollars)
                )
                .foregroundStyle(tint)
                .symbolSize(90)
                .accessibilityHidden(true)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: domain)
        .chartXScale(domain: xDomain)
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let dollars = value.as(Double.self) {
                        Text(Money.compact(Int((dollars * 100).rounded())))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                // A date near the end (the 3M "Nov 1") ends at its tick, so it
                // doesn't run into the value labels and truncate to "No…".
                AxisValueLabel(format: dateFormat, anchor: ChartAxis.dateLabelAnchor(for: value, in: xDomain))
            }
        }
    }

    /// Padded so a flat line sits in the middle and curves don't touch the edges.
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.dollars)
        let low = values.min() ?? 0
        let high = values.max() ?? 0
        let padding = max((high - low) * 0.15, max(abs(high) * 0.01, 1))
        return (low - padding)...(high + padding)
    }

    private var xDomain: ClosedRange<Date> {
        if let first = points.first?.date, let last = points.last?.date, first < last {
            return first...last
        }
        let now = Date.now
        return now.addingTimeInterval(-86_400)...now
    }

    private var gradient: LinearGradient {
        LinearGradient(
            colors: [tint.opacity(0.28), tint.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Previews

private struct AccountsComponentsPreview: View {
    @State private var range: ChartRange = .threeMonths
    @State private var selectedDate: Date?

    private var points: [AccountsChartPoint] {
        let now = Date.now
        return range.sampleDates(now: now).enumerated().map { index, date in
            let wave = sin(Double(index) / 2.5) * 40_000
            return AccountsChartPoint(date: date, cents: 12_000_000 + index * 25_000 + Int(wave))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    ForEach(AccountKind.allCases) { kind in
                        AccountKindIcon(kind: kind, size: 34)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    AccountsChangeLabel(changeCents: 245_000, startCents: 11_800_000,
                                        periodText: AccountsStyle.periodText(for: range))
                    AccountsHistoryChart(points: points, range: range, seriesName: "Net worth",
                                         selectedDate: $selectedDate)
                        .frame(height: 190)
                    AccountsRangePicker(range: $range)
                }
                .hakiCard()
            }
            .padding()
        }
        .background(Color.hakiBackground)
    }
}

#Preview {
    AccountsComponentsPreview()
        .previewEnvironment()
}
