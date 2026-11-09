//
//  FeedView.swift
//  Haki
//
//  The Feed tab: posts from people you follow (and yourself) or from
//  everyone (Explore), newest first, with pull to refresh and infinite scroll.
//

import Foundation
import SwiftUI

struct FeedView: View {
    @Environment(SocialService.self) private var social
    @Environment(AuthService.self) private var auth

    @AppStorage("social.feedScope") private var scope: FeedScope = .following
    /// One pager per scope, so switching back and forth keeps each list and its scroll position.
    @State private var followingPager = FeedPager()
    @State private var explorePager = FeedPager()
    @State private var showingCompose = false
    @State private var createdCountWhenComposing = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    scopePicker
                    content
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.hakiBackground)
            .navigationTitle("Feed")
            .toolbar { toolbarContent }
            .refreshable {
                // Its own task, so the refresh isn't cancelled when the list redraws.
                await Task { await refreshCurrentScope() }.value
            }
            .task(id: scope) {
                await loadCurrentScopeIfNeeded()
            }
            .sheet(isPresented: $showingCompose, onDismiss: composeDismissed) {
                ComposePostView()
            }
        }
    }

    // MARK: Pieces

    private var scopePicker: some View {
        Picker("Feed", selection: $scope) {
            ForEach(FeedScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            AssistantToolbarButton()
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink {
                PeopleSearchView()
            } label: {
                Label("Search people", systemImage: "magnifyingglass")
            }
            NavigationLink {
                ActivityView()
            } label: {
                Label("Activity", systemImage: "heart")
            }
            Button {
                openCompose()
            } label: {
                Label("New post", systemImage: "plus.square")
            }
        }
    }

    @ViewBuilder private var content: some View {
        let current = pager(for: scope)
        let me = auth.userID
        let posts = current.visiblePosts { $0.authorID == me }
        if posts.isEmpty {
            switch current.phase {
            case .idle, .loading:
                FeedSkeletonList()
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load the feed", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") {
                        Task { await reload(scope) }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 40)
            case .loaded:
                emptyState
            }
        } else {
            if let banner = current.bannerError {
                FeedErrorBanner(message: banner) {
                    current.bannerError = nil
                }
            }
            FeedPostRows(posts: posts, pager: current) {
                await loadMore(scope)
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        switch scope {
        case .following:
            FeedSuggestionsView(
                onBrowseExplore: {
                    withAnimation(.snappy) { scope = .explore }
                },
                onShowFollowedPosts: {
                    Task { await reload(.following) }
                }
            )
        case .explore:
            ContentUnavailableView {
                Label("No posts yet", systemImage: "rectangle.stack")
            } description: {
                Text("Be the first to share a trade, your portfolio or an idea.")
            } actions: {
                Button("New post") { openCompose() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 40)
        }
    }

    // MARK: Loading

    private func pager(for scope: FeedScope) -> FeedPager {
        scope == .following ? followingPager : explorePager
    }

    private func loadCurrentScopeIfNeeded() async {
        PostChangeCenter.shared.prepare(for: auth.userID)
        let scope = self.scope
        guard pager(for: scope).phase == .idle else { return }
        await reload(scope)
    }

    private func refreshCurrentScope() async {
        await reload(scope)
    }

    private func reload(_ scope: FeedScope) async {
        await pager(for: scope).reload { before, limit in
            try await social.feed(scope: scope, before: before, limit: limit)
        }
    }

    private func loadMore(_ scope: FeedScope) async {
        await pager(for: scope).loadMore { before, limit in
            try await social.feed(scope: scope, before: before, limit: limit)
        }
    }

    private func openCompose() {
        createdCountWhenComposing = PostChangeCenter.shared.created.count
        showingCompose = true
    }

    /// A new post was shared: refresh so it shows at the top with the server's data.
    private func composeDismissed() {
        guard PostChangeCenter.shared.created.count != createdCountWhenComposing else { return }
        let scope = self.scope
        Task { await reload(scope) }
    }
}

#Preview {
    FeedView()
        .previewEnvironment()
}
