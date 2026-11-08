//
//  InvestPerformanceCard.swift
//  Haki
//
//  Portfolio value over time from the daily snapshots the server records on
//  every sync, with the invested amount (cost basis) as a dashed comparison
//  line and a drag readout.
//

import Charts
import Foundation
import SwiftUI

/// One day of portfolio history.
nonisolated struct InvestChartPoint: Identifiable, Hashable {
    let date: Date
    let value: Double
    /// Invested amount (cost basis) that day, when reported.
    let invested: Double?

    var id: Date { date }

    /// Snapshots with a readable date, oldest first.
    static func points(from snapshots: [PortfolioSnapshot]) -> [InvestChartPoint] {
        snapshots
            .compactMap { snapshot -> InvestChartPoint? in
                guard let day = snapshot.day, snapshot.totalValue.isFinite else { return nil }
                let invested = snapshot.costBasis.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
                return InvestChartPoint(date: day, value: snapshot.totalValue, invested: invested)
            }
            .sorted { $0.date < $1.date }
    }

    /// The points inside `range`, ending now.
    static func filter(_ points: [InvestChartPoint], range: ChartRange, now: Date = .now) -> [InvestChartPoint] {
        guard let start = Calendar.current.date(byAdding: .month, value: -range.months, to: now) else { return points }
        let startDay = Calendar.current.startOfDay(for: start)
        return points.filter { $0.date >= startDay }
    }

    static func nearest(to date: Date?, in points: [InvestChartPoint]) -> InvestChartPoint? {
        guard let date else { return nil }
        return points.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }
}

struct InvestPerformanceCard: View {
    let snapshots: [PortfolioSnapshot]
    let currency: String

    @State private var range: ChartRange = .threeMonths
    @State private var selectedDate: Date?

    var body: some View {
        let allPoints = InvestChartPoint.points(from: snapshots)
        let points = InvestChartPoint.filter(allPoints, range: range)
        let selected = InvestChartPoint.nearest(to: selectedDate, in: points)

        VStack(alignment: .leading, spacing: 14) {
            CardHeader("Performance", systemImage: "chart.xyaxis.line")
            if allPoints.count >= 2 {
                readout(points: points, selected: selected)
                if points.count >= 2 {
                    InvestPerformanceChart(
                        points: points,
                        range: range,
                        currency: currency,
                        selectedDate: $selectedDate
                    )
                    .frame(height: 200)
                    legend(points: points)
                } else {
                    InvestInlineNote(
                        systemImage: "calendar.badge.clock",
                        text: "No history in this range yet. Try a longer range."
                    )
                }
                Picker("Range", selection: $range) {
                    ForEach(ChartRange.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Chart range")
            } else {
                InvestInlineNote(
                    systemImage: "chart.xyaxis.line",
                    text: "Your performance history builds up as Haki syncs your accounts each day. Check back tomorrow to see the first trend."
                )
            }
        }
        .hakiCard()
        .onChange(of: range) { _, _ in
            selectedDate = nil
        }
        .sensoryFeedback(.selection, trigger: selected?.date) { _, newValue in
            newValue != nil
        }
    }

    // MARK: Readout

    @ViewBuilder
    private func readout(points: [InvestChartPoint], selected: InvestChartPoint?) -> some View {
        if let selected {
            VStack(alignment: .leading, spacing: 2) {
                Text(selected.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(InvestFormat.money(selected.value, currency: currency, showsCents: false))
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    if let invested = selected.invested {
                        Text("Invested " + InvestFormat.money(invested, currency: currency, showsCents: false))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
            .accessibilityElement(children: .combine)
        } else if let first = points.first, let last = points.last, points.count >= 2 {
            let change = last.value - first.value
            VStack(alignment: .leading, spacing: 2) {
                Text("Change in value, \(periodText)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                InvestGainLabel(
                    gain: change,
                    gainPct: PortfolioMath.changePct(from: first.value, to: last.value),
                    currency: currency,
                    font: .title3.weight(.semibold)
                )
                Text("Includes money you added or withdrew.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var periodText: String {
        switch range {
        case .oneMonth: "past month"
        case .threeMonths: "past 3 months"
        case .sixMonths: "past 6 months"
        case .oneYear: "past year"
        }
    }

    @ViewBuilder
    private func legend(points: [InvestChartPoint]) -> some View {
        if points.contains(where: { $0.invested != nil }) {
            HStack(spacing: 16) {
                InvestLegendItem(title: "Value", color: .accentColor)
                InvestLegendItem(title: "Invested", color: .hakiComparison, dashed: true)
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Chart

private struct InvestPerformanceChart: View {
    let points: [InvestChartPoint]
    let range: ChartRange
    let currency: String
    @Binding var selectedDate: Date?

    var body: some View {
        let domain = yDomain
        let selected = InvestChartPoint.nearest(to: selectedDate, in: points)
        let investedPoints = points.filter { $0.invested != nil }

        Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Baseline", domain.lowerBound),
                    yEnd: .value("Value", point.value)
                )
                .foregroundStyle(gradient)
                .interpolationMethod(.monotone)
                .accessibilityHidden(true)

                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Value", point.value),
                    series: .value("Series", "Value")
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
                .accessibilityLabel(point.date.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue(InvestFormat.money(point.value, currency: currency, showsCents: false))
            }

            ForEach(investedPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Invested", point.invested ?? 0),
                    series: .value("Series", "Invested")
                )
                .foregroundStyle(Color.hakiComparison)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .interpolationMethod(.stepEnd)
                .accessibilityHidden(true)
            }

            if let selected {
                RuleMark(x: .value("Selected date", selected.date))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .accessibilityHidden(true)

                PointMark(
                    x: .value("Date", selected.date),
                    y: .value("Value", selected.value)
                )
                .foregroundStyle(Color.accentColor)
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
                        Text(InvestFormat.compact(dollars, currency: currency))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: axisDateFormat)
            }
        }
        .accessibilityLabel("Portfolio value chart")
    }

    private var axisDateFormat: Date.FormatStyle {
        switch range {
        case .oneMonth, .threeMonths: .dateTime.month(.abbreviated).day()
        case .sixMonths, .oneYear: .dateTime.month(.abbreviated)
        }
    }

    /// Padded so a flat line sits in the middle and curves don't touch the edges.
    private var yDomain: ClosedRange<Double> {
        var values = points.map(\.value)
        values.append(contentsOf: points.compactMap(\.invested))
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
            colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

#Preview("With history") {
    ScrollView {
        InvestPerformanceCard(snapshots: PortfolioService.preview.snapshots, currency: "USD")
            .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}

#Preview("No history yet") {
    ScrollView {
        InvestPerformanceCard(snapshots: [], currency: "USD")
            .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
