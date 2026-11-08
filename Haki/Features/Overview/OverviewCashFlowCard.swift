//
//  OverviewCashFlowCard.swift
//  Haki
//
//  Money in vs money out this month, and what's left over.
//

import Foundation
import SwiftUI

struct OverviewCashFlowCard: View {
    /// Income received this month, positive.
    let incomeCents: Int
    /// Net spending this month, positive.
    let spendingCents: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader("Cash flow this month", systemImage: "arrow.left.arrow.right")
            if incomeCents == 0 && spendingCents == 0 {
                Text("No income or spending yet this month.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                flowRow(
                    title: "Income",
                    amount: Money.format(incomeCents, alwaysShowsSign: true),
                    cents: incomeCents,
                    tint: Color.hakiPositive,
                    amountColor: Color.hakiPositive
                )
                flowRow(
                    title: "Spending",
                    amount: Money.format(spendingCents),
                    cents: spendingCents,
                    tint: Color.hakiWarning,
                    amountColor: Color.primary
                )
                Divider()
                netRow
            }
        }
        .hakiCard()
    }

    // MARK: Rows

    private var scaleCents: Int {
        max(incomeCents, spendingCents, 1)
    }

    private func flowRow(title: String, amount: String, cents: Int, tint: Color, amountColor: Color) -> some View {
        let fraction = Double(max(0, cents)) / Double(scaleCents)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.subheadline)
                Spacer(minLength: 8)
                Text(amount)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(amountColor)
            }
            OverviewMeterBar(fraction: fraction, tint: tint, height: 8)
        }
        .accessibilityElement(children: .combine)
    }

    private var netCents: Int {
        incomeCents - spendingCents
    }

    private var netText: String {
        netCents >= 0 ? "Saved \(Money.format(netCents))" : "Overspent \(Money.format(-netCents))"
    }

    /// "18% of income" when something was saved out of income.
    private var savingsRateText: String? {
        guard incomeCents > 0, netCents > 0 else { return nil }
        let percent = Int((Double(netCents) / Double(incomeCents) * 100).rounded())
        return "\(percent)% of income"
    }

    private var netRow: some View {
        let saved = netCents >= 0
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: saved ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(saved ? Color.hakiPositive : Color.hakiNegative)
                .accessibilityHidden(true)
            Text(netText)
                .font(.headline)
                .monospacedDigit()
            Spacer(minLength: 8)
            if let rate = savingsRateText {
                Text(rate)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            OverviewCashFlowCard(
                incomeCents: OverviewPreviewData.snapshot.incomeCents,
                spendingCents: OverviewPreviewData.snapshot.spentCents
            )
            OverviewCashFlowCard(incomeCents: 120_000, spendingCents: 185_050)
            OverviewCashFlowCard(incomeCents: 0, spendingCents: 0)
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
