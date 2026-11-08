//
//  ProfilePostsGrid.swift
//  Haki
//
//  A profile's posts as a 3-column grid of square tiles. Photo posts show the
//  photo; trades, portfolio snapshots and text posts get a tinted tile.
//

import CoreGraphics
import Foundation
import SwiftUI

struct ProfilePostsGrid: View {
    let posts: [FeedPost]
    /// Called when the last tile appears, to load the next page.
    let onReachEnd: () -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 3), count: 3)

    init(posts: [FeedPost], onReachEnd: @escaping () -> Void = {}) {
        self.posts = posts
        self.onReachEnd = onReachEnd
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 3) {
            ForEach(posts) { post in
                NavigationLink {
                    PostDetailView(post: post)
                } label: {
                    ProfilePostTile(post: post)
                }
                .buttonStyle(.plain)
                .onAppear {
                    if post.id == posts.last?.id {
                        onReachEnd()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// One square grid tile.
struct ProfilePostTile: View {
    let post: FeedPost

    init(post: FeedPost) {
        self.post = post
    }

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                tileContent
            }
            .overlay(alignment: .topTrailing) {
                kindBadge
            }
            .clipped()
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    // MARK: Content

    @ViewBuilder
    private var tileContent: some View {
        if let url = post.imageURL {
            // Downscaled to tile size (and cached) rather than the full photo.
            SocialThumbnailImage(url: url, side: 200) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    ZStack {
                        Color.secondary.opacity(0.12)
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                case .loading:
                    ZStack {
                        Color.secondary.opacity(0.12)
                        ProgressView()
                    }
                }
            }
        } else {
            switch post.kind {
            case .trade:
                tradeTile
            case .portfolio:
                portfolioTile
            case .post:
                textTile
            }
        }
    }

    private var textTile: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.24), Color.accentColor.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(ProfileTextRules.firstLine(of: post.caption))
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(5)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var tradeTile: some View {
        let tint = isSell ? Color.hakiNegative : Color.hakiPositive
        return ZStack {
            tint.opacity(0.14)
            VStack(spacing: 4) {
                Image(systemName: isSell ? "arrow.down.right" : "arrow.up.right")
                    .font(.title3.weight(.bold))
                Text(tradeVerb)
                    .font(.caption.weight(.semibold))
                Text(tickerText)
                    .font(.headline.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .foregroundStyle(tint)
            .padding(6)
        }
    }

    private var portfolioTile: some View {
        let items = Array((post.attachment?.holdings ?? []).prefix(3))
        let maxWeight = items.map(\.weightPct).max() ?? 0
        return ZStack(alignment: .topLeading) {
            Color.accentColor.opacity(0.1)
            VStack(alignment: .leading, spacing: 5) {
                Image(systemName: "chart.pie.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                ForEach(items, id: \.ticker) { item in
                    ProfileMiniAllocationRow(
                        ticker: item.ticker,
                        fraction: maxWeight > 0 ? item.weightPct / maxWeight : 0
                    )
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Marks photo posts that are also trades or portfolio snapshots.
    @ViewBuilder
    private var kindBadge: some View {
        if post.imageURL != nil, let symbol = badgeSymbol {
            Image(systemName: symbol)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(5)
                .background(Color.black.opacity(0.4), in: Circle())
                .padding(6)
                .accessibilityHidden(true)
        }
    }

    // MARK: Text

    private var isSell: Bool {
        post.tradeSide == .sell
    }

    private var tradeVerb: String {
        isSell ? "Sold" : "Bought"
    }

    private var tickerText: String {
        guard let ticker = post.ticker, !ticker.isEmpty else { return "Trade" }
        return "$\(ticker)"
    }

    private var badgeSymbol: String? {
        switch post.kind {
        case .trade: isSell ? "arrow.down.right" : "arrow.up.right"
        case .portfolio: "chart.pie.fill"
        case .post: nil
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        switch post.kind {
        case .trade:
            parts.append("\(tradeVerb) \(post.ticker ?? "a stock")")
        case .portfolio:
            parts.append("Portfolio post")
        case .post:
            parts.append(post.imageURL == nil ? "Post" : "Photo post")
        }
        let caption = post.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !caption.isEmpty {
            parts.append(caption)
        }
        parts.append(post.createdAt.formatted(.relative(presentation: .named)))
        return parts.joined(separator: ", ")
    }
}

/// "VTI" over a bar sized relative to the largest holding.
private struct ProfileMiniAllocationRow: View {
    let ticker: String
    let fraction: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ticker)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(3, proxy.size.width * CGFloat(min(1, max(0, fraction)))))
            }
            .frame(height: 4)
        }
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            ProfilePostsGrid(posts: SocialPreviewData.posts)
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
