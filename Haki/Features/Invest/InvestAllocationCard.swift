//
//  InvestAllocationCard.swift
//  Haki
//
//  A donut of the portfolio by asset class (stocks, ETFs, funds, crypto,
//  bonds, cash) with a legend of percentages.
//

import Charts
import Foundation
import SwiftUI

struct InvestAllocationCard: View {
    let slices: [AllocationSlice]
    let positionCount: Int
    let currency: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 20))

        VStack(alignment: .leading, spacing: 14) {
            CardHeader("Allocation", systemImage: "chart.pie")
            if slices.isEmpty {
                InvestInlineNote(
                    systemImage: "chart.pie",
                    text: "Your allocation appears once your brokerage reports holdings."
                )
            } else {
                layout {
                    donut
                        .frame(width: 148, height: 148)
                    legend
                }
            }
        }
        .hakiCard()
    }

    // MARK: Donut

    private var donut: some View {
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Value", slice.value),
                innerRadius: .ratio(0.62),
                angularInset: 1.5
            )
            .cornerRadius(3)
            .foregroundStyle(InvestStyle.color(for: slice.assetClass))
            .accessibilityLabel(slice.assetClass.displayName)
            .accessibilityValue(InvestFormat.percent(slice.weightPct))
        }
        .chartLegend(.hidden)
        .overlay {
            VStack(spacing: 0) {
                Text("\(positionCount)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text(positionCount == 1 ? "position" : "positions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // Stay inside the donut's hole at large Dynamic Type sizes.
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(width: 80)
            .accessibilityHidden(true)
        }
        .accessibilityLabel("Allocation by asset class")
    }

    // MARK: Legend

    private var legend: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(slices) { slice in
                legendRow(slice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendRow(_ slice: AllocationSlice) -> some View {
        HStack(spacing: 8) {
            Image(systemName: InvestStyle.systemImage(for: slice.assetClass))
                .font(.caption.weight(.semibold))
                .foregroundStyle(InvestStyle.color(for: slice.assetClass))
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(slice.assetClass.displayName)
                    .font(.subheadline)
                Text(InvestFormat.money(slice.value, currency: currency, showsCents: false))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            Text(InvestFormat.percent(slice.weightPct))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    let portfolio = PortfolioService.preview
    ScrollView {
        InvestAllocationCard(
            slices: portfolio.allocation,
            positionCount: portfolio.positions.count,
            currency: "USD"
        )
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
