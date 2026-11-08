//
//  InvestHeroCard.swift
//  Haki
//
//  What the Invest tab shows before any brokerage is connected: what
//  connecting gives you, how sharing works, and the connect button.
//

import Foundation
import SwiftUI

struct InvestHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            InvestHeroArt()

            VStack(alignment: .leading, spacing: 8) {
                Text("Invest alongside your people")
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Connect your brokerage to see every holding in one place, then share how you invest with friends — in percentages, never dollar amounts.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 16) {
                InvestHeroFeature(
                    systemImage: "lock.shield.fill",
                    title: "Read-only and secure",
                    detail: "Connect through Plaid with read-only access. Your brokerage login is never shared with Haki."
                )
                InvestHeroFeature(
                    systemImage: "chart.pie.fill",
                    title: "All your holdings together",
                    detail: "Stocks, ETFs, funds and crypto across your accounts, with performance and allocation at a glance."
                )
                InvestHeroFeature(
                    systemImage: "person.2.fill",
                    title: "Share percentages, not amounts",
                    detail: "Show friends what you hold and how it's doing. How much you have stays private."
                )
            }

            BrokerageLinkButton()

            Label {
                Text("Haki can't place trades or move money. You can disconnect at any time.")
            } icon: {
                Image(systemName: "info.circle")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .hakiCard(padding: 20)
    }
}

private struct InvestHeroFeature: View {
    let systemImage: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A decorative allocation ring with a few sample weights.
private struct InvestHeroArt: View {
    private struct Sample: Identifiable {
        let ticker: String
        let weight: String
        let opacity: Double
        var id: String { ticker }
    }

    private let samples: [Sample] = [
        Sample(ticker: "$VTI", weight: "48%", opacity: 1.0),
        Sample(ticker: "$AAPL", weight: "21%", opacity: 0.75),
        Sample(ticker: "$BND", weight: "9%", opacity: 0.5),
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.accentColor, Color.accentColor.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            HStack(spacing: 22) {
                ring
                    .frame(width: 84, height: 84)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(samples) { sample in
                        HStack(spacing: 6) {
                            Text(sample.ticker)
                                .font(.caption.weight(.bold))
                            Text(sample.weight)
                                .font(.caption)
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .foregroundStyle(Color.white)
                        .background(Color.white.opacity(0.18 * sample.opacity + 0.06), in: Capsule())
                    }
                }
            }
            .padding(.vertical, 20)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 14)
            Circle()
                .trim(from: 0, to: 0.47)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 14))
            Circle()
                .trim(from: 0.49, to: 0.69)
                .stroke(Color.white.opacity(0.75), style: StrokeStyle(lineWidth: 14))
            Circle()
                .trim(from: 0.71, to: 0.79)
                .stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 14))
            Circle()
                .trim(from: 0.81, to: 0.98)
                .stroke(Color.white.opacity(0.32), style: StrokeStyle(lineWidth: 14))
        }
        .rotationEffect(.degrees(-90))
    }
}

#Preview {
    ScrollView {
        InvestHeroCard()
            .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
