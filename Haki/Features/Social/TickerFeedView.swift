//
//  TickerFeedView.swift
//  Haki
//
//  Everything about one ticker: your position in it (if you hold it) and
//  the posts that mention it, newest first.
//

import Foundation
import SwiftUI

struct TickerFeedView: View {
    let ticker: String

    @Environment(SocialService.self) private var social
    @Environment(PortfolioService.self) private var portfolio
    @Environment(AuthService.self) private var auth

    @State private var pager = FeedPager()
    @State private var showingCompose = false
    @State private var createdCountWhenComposing = 0

    private var symbol: String { PostCaptionFormatter.normalizedSymbol(ticker) }
    private var cashtag: String { "$" + symbol }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                TickerPositionCard(symbol: symbol)
                postsHeader
                postsContent
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .navigationTitle(cashtag)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openCompose()
                } label: {
                    Label("Post about \(cashtag)", systemImage: "square.and.pencil")
                }
            }
        }
        .refreshable {
            await Task { await reload() }.value
        }
        .task {
            await loadPostsIfNeeded()
        }
        .task {
            await loadPortfolioIfNeeded()
        }
        .sheet(isPresented: $showingCompose, onDismiss: composeDismissed) {
            ComposePostView(prefill: PostDraft(kind: .post, caption: cashtag + " "))
        }
    }

    private var postsHeader: some View {
        Text("Posts about \(cashtag)")
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var postsContent: some View {
        let symbol = self.symbol
        let posts = pager.visiblePosts { PostCaptionFormatter.post($0, mentions: symbol) }
        if posts.isEmpty {
            switch pager.phase {
            case .idle, .loading:
                FeedSkeletonList(count: 2)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load posts", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") {
                        Task { await reload() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 24)
            case .loaded:
                ContentUnavailableView {
                    Label("No posts about \(cashtag) yet", systemImage: "number")
                } description: {
                    Text("Share a trade, an idea or a question about \(cashtag).")
                } actions: {
                    Button("Post about \(cashtag)") { openCompose() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.top, 24)
            }
        } else {
            if let banner = pager.bannerError {
                FeedErrorBanner(message: banner) {
                    pager.bannerError = nil
                }
            }
            FeedPostRows(posts: posts, pager: pager) {
                await loadMore()
            }
        }
    }

    private func loadPostsIfNeeded() async {
        PostChangeCenter.shared.prepare(for: auth.userID)
        guard pager.phase == .idle else { return }
        await reload()
    }

    private func loadPortfolioIfNeeded() async {
        guard portfolio.lastLoaded == nil, !portfolio.isLoading else { return }
        await portfolio.refresh()
    }

    private func reload() async {
        let symbol = self.symbol
        await pager.reload { before, limit in
            try await social.posts(mentioning: symbol, before: before, limit: limit)
        }
    }

    private func loadMore() async {
        let symbol = self.symbol
        await pager.loadMore { before, limit in
            try await social.posts(mentioning: symbol, before: before, limit: limit)
        }
    }

    private func openCompose() {
        createdCountWhenComposing = PostChangeCenter.shared.created.count
        showingCompose = true
    }

    private func composeDismissed() {
        guard PostChangeCenter.shared.created.count != createdCountWhenComposing else { return }
        Task { await reload() }
    }
}

// MARK: - Position card

/// Your position in a ticker (value, return, gain, weight) or a note that you don't hold it.
struct TickerPositionCard: View {
    let symbol: String

    @Environment(PortfolioService.self) private var portfolio

    var body: some View {
        if let position = portfolio.position(for: symbol) {
            held(position)
        } else {
            notHeld
        }
    }

    private func held(_ position: PortfolioPosition) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader("Your position", systemImage: "checkmark.seal.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text(TickerMoney.format(position.value))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(position.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .accessibilityElement(children: .combine)

            HStack(alignment: .top, spacing: 12) {
                stat("Return") {
                    PercentChangeText(percent: position.gainPct)
                }
                stat("Gain") {
                    Text(gainText(position.gain))
                        .monospacedDigit()
                        .foregroundStyle(gainColor(position.gain))
                }
                stat("Weight") {
                    Text(weightText(position))
                        .monospacedDigit()
                }
            }

            HStack {
                Text(sharesText(position))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                NavigationLink {
                    HoldingDetailView(position: position)
                } label: {
                    HStack(spacing: 4) {
                        Text("Details")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Holding details")
            }
        }
        .hakiCard()
    }

    private var notHeld: some View {
        HStack(spacing: 14) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("You don't hold $" + symbol)
                    .font(.headline)
                Text(notHeldDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .hakiCard()
        .accessibilityElement(children: .combine)
    }

    private var notHeldDetail: String {
        if portfolio.lastLoaded == nil && portfolio.isLoading {
            return "Checking your portfolio…"
        }
        if !portfolio.hasConnections {
            return "Connect a brokerage in Invest to see your position here."
        }
        return "It isn't in your connected accounts."
    }

    private func stat<Value: View>(_ title: String, @ViewBuilder value: () -> Value) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            value()
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func gainText(_ gain: Double?) -> String {
        guard let gain else { return "—" }
        return TickerMoney.format(gain, alwaysShowsSign: true)
    }

    private func gainColor(_ gain: Double?) -> Color {
        guard let gain, gain != 0 else { return Color.secondary }
        return gain > 0 ? Color.hakiPositive : Color.hakiNegative
    }

    private func weightText(_ position: PortfolioPosition) -> String {
        let weight: String = position.weightPct.formatted(.number.precision(.fractionLength(1)))
        return weight + "%"
    }

    private func sharesText(_ position: PortfolioPosition) -> String {
        let quantity = position.quantity.formatted(.number.precision(.fractionLength(0...4)))
        return position.quantity == 1 ? "1 share" : "\(quantity) shares"
    }
}

/// Dollar amounts from brokerage data (Doubles) in the app's money format.
private nonisolated enum TickerMoney {
    static func format(_ dollars: Double, alwaysShowsSign: Bool = false) -> String {
        Money.format(Int((dollars * 100).rounded()), alwaysShowsSign: alwaysShowsSign)
    }
}

#Preview("Held") {
    NavigationStack {
        TickerFeedView(ticker: "AAPL")
    }
    .previewEnvironment()
}

#Preview("Not held") {
    NavigationStack {
        TickerFeedView(ticker: "KO")
    }
    .previewEnvironment()
}
