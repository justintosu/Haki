//
//  InvestSummaryCard.swift
//  Haki
//
//  The top of the Invest tab: total value, total gain, sync status with a
//  sync button. Plus the "Sharing" card that opens a portfolio post
//  (percentages only) and shows whether the profile shows the holdings.
//

import Foundation
import SwiftUI

struct InvestSummaryCard: View {
    let totals: PortfolioTotals
    let positionCount: Int
    let accountCount: Int
    let lastSynced: Date?
    let isSyncing: Bool
    let needsAttentionCount: Int
    let currency: String
    let onSync: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Portfolio value")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(InvestFormat.money(totals.value, currency: currency))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                syncButton
            }

            gain

            if needsAttentionCount > 0 {
                Label(
                    needsAttentionCount == 1
                        ? "1 connection needs attention"
                        : "\(needsAttentionCount) connections need attention",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.hakiWarning)
            }

            Divider()

            HStack(alignment: .firstTextBaseline) {
                Label(isSyncing ? "Syncing…" : InvestFormat.syncedText(lastSynced), systemImage: "clock")
                Spacer(minLength: 8)
                Text(countsText)
                    .multilineTextAlignment(.trailing)
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .hakiCard()
        .animation(.snappy, value: totals.value)
    }

    @ViewBuilder
    private var gain: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Total gain")
                .font(.caption)
                .foregroundStyle(.secondary)
            InvestGainLabel(
                gain: totals.costBasis > 0 ? totals.gain : nil,
                gainPct: totals.gainPct,
                currency: currency,
                font: .headline
            )
            if totals.costBasis > 0, totals.valueWithCostBasis + 0.5 < totals.value {
                Text("Based on holdings that report what you paid.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var syncButton: some View {
        Button(action: onSync) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                if isSyncing {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .disabled(isSyncing)
        .accessibilityLabel(isSyncing ? "Syncing" : "Sync now")
    }

    private var countsText: String {
        let positions = positionCount == 1 ? "1 position" : "\(positionCount) positions"
        let accounts = accountCount == 1 ? "1 account" : "\(accountCount) accounts"
        return "\(positions) · \(accounts)"
    }
}

// MARK: - Share card

/// Invites the user to post their allocation; shows what would be shared,
/// and whether the profile shows the holdings.
struct InvestShareCard: View {
    let preview: SharedPortfolio
    let onShare: () -> Void

    /// Why "Share my portfolio" is unavailable when there's nothing to share.
    static let nothingToShareText = "Nothing to share yet: cash isn't included, and holdings appear after your brokerage's first sync."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Sharing", systemImage: "person.2")
            Text("Post your top holdings and overall return as percentages. Dollar amounts always stay private.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if preview.holdings.isEmpty {
                InvestInlineNote(systemImage: "info.circle", text: Self.nothingToShareText)
            } else {
                InvestShareStrip(items: preview.holdings)
            }
            Button(action: onShare) {
                Label("Share my portfolio", systemImage: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(preview.holdings.isEmpty)
            .accessibilityHint(preview.holdings.isEmpty ? Self.nothingToShareText : "")

            InvestProfileSharingToggle(isConnected: true, showsDivider: true)
        }
        .hakiCard()
    }
}

/// A stacked bar of shared weights with a ticker legend.
private struct InvestShareStrip: View {
    let items: [SharedPortfolio.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(shade(index))
                            .frame(width: max(2, segmentWidth(for: item, in: proxy.size.width)))
                    }
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
            .accessibilityHidden(true)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(shade(index))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(item.ticker == "Other" ? "Other" : "$\(item.ticker)")
                                .font(.caption.weight(.semibold))
                            Text(InvestFormat.percent(item.weightPct))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func shade(_ index: Int) -> Color {
        Color.accentColor.opacity(max(0.25, 1 - Double(index) * 0.14))
    }

    private func segmentWidth(for item: SharedPortfolio.Item, in totalWidth: CGFloat) -> CGFloat {
        let spacing = CGFloat(max(0, items.count - 1)) * 2
        let available = max(0, totalWidth - spacing)
        let fraction = max(0, min(1, item.weightPct / 100))
        return available * CGFloat(fraction)
    }
}

#Preview {
    let portfolio = PortfolioService.preview
    ScrollView {
        VStack(spacing: 16) {
            InvestSummaryCard(
                totals: portfolio.totals,
                positionCount: portfolio.positions.count,
                accountCount: portfolio.accounts.count,
                lastSynced: InvestFormat.lastSynced(portfolio.connections),
                isSyncing: false,
                needsAttentionCount: 1,
                currency: "USD",
                onSync: {}
            )
            InvestShareCard(preview: portfolio.sharedPortfolio(limit: 5), onShare: {})
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
