//
//  PostAttachmentViews.swift
//  Haki
//
//  The kind-specific blocks of a post: the "Bought $AAPL" trade capsule and
//  the percentages-only portfolio card.
//

import Foundation
import SwiftUI

/// "Bought $AAPL" in green with an up arrow, or "Sold $AAPL" in red with a down arrow.
struct PostTradeBadge: View {
    let side: TradeSide
    let ticker: String

    var body: some View {
        Label(title, systemImage: side == .buy ? "arrow.up.right" : "arrow.down.right")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
    }

    private var title: String {
        side == .buy ? "Bought $\(ticker)" : "Sold $\(ticker)"
    }

    private var tint: Color {
        side == .buy ? Color.hakiPositive : Color.hakiNegative
    }
}

/// A shared portfolio: each holding's weight as a horizontal bar (accent
/// shades, largest first) and the total return. Never shows amounts.
struct PostPortfolioAttachmentView: View {
    let portfolio: SharedPortfolio

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            VStack(spacing: 10) {
                ForEach(Array(portfolio.holdings.enumerated()), id: \.offset) { index, item in
                    PostPortfolioBarRow(
                        item: item,
                        fraction: item.weightPct / largestWeight,
                        tint: tint(at: index, for: item)
                    )
                }
            }
            // An HStack rather than a Label: inside a Form (the compose preview)
            // a Label's icon gets a wide fixed column and drifts from its text.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "lock.fill")
                    .accessibilityHidden(true)
                Text("Percentages only. Amounts are never shared.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shared portfolio")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 8) {
                Image(systemName: "chart.pie.fill")
                    .accessibilityHidden(true)
                Text("Portfolio")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            Spacer(minLength: 8)
            if let gain = portfolio.totalGainPct {
                VStack(alignment: .trailing, spacing: 0) {
                    PercentChangeText(percent: gain)
                        .font(.headline)
                    Text("total return")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total return")
                .accessibilityValue(PercentChangeText.format(gain))
            }
        }
    }

    /// Bars are relative to the largest holding, so the list reads at a glance.
    private var largestWeight: Double {
        max(portfolio.holdings.map(\.weightPct).max() ?? 0, 1)
    }

    private func tint(at index: Int, for item: SharedPortfolio.Item) -> Color {
        if item.ticker == "Other" {
            return Color.secondary.opacity(0.45)
        }
        return Color.accentColor.opacity(max(0.35, 1 - Double(index) * 0.13))
    }
}

private struct PostPortfolioBarRow: View {
    let item: SharedPortfolio.Item
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.ticker)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(percentText)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(tint)
                        .frame(width: barWidth(in: proxy.size.width))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.ticker)
        .accessibilityValue("\(percentText) of the portfolio")
    }

    private var percentText: String {
        item.weightPct.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    /// At least a sliver, at most the full track.
    private func barWidth(in trackWidth: CGFloat) -> CGFloat {
        let clamped: Double = min(1.0, max(0.0, fraction))
        let width: CGFloat = trackWidth * CGFloat(clamped)
        return max(4, width)
    }
}

#Preview("Attachments") {
    ScrollView {
        VStack(spacing: 16) {
            PostTradeBadge(side: .buy, ticker: "AAPL")
            PostTradeBadge(side: .sell, ticker: "TSLA")
            if let portfolio = SocialPreviewData.posts.first(where: { $0.kind == .portfolio })?.attachment {
                PostPortfolioAttachmentView(portfolio: portfolio)
            }
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
