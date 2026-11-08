//
//  ProfileView.swift
//  Haki
//
//  Anyone's profile: header with counts and Follow (or Edit profile for
//  yourself), then their posts as a grid or their portfolio as percentages.
//  Pushed from the feed, people lists and search; `MyProfileView` shows it as
//  the Profile tab's root.
//

import Foundation
import SwiftUI

struct ProfileView: View {
    let userID: UUID
    /// Shown as the Profile tab's root (large title) rather than pushed.
    private let isTabRoot: Bool

    @Environment(AuthService.self) private var auth
    @Environment(SocialService.self) private var social
    @Environment(PortfolioService.self) private var portfolio

    @State private var loadedUserID: UUID?
    @State private var profile: UserProfile?
    @State private var profileError: String?
    @State private var lastLoaded: Date?
    @State private var selectedTab: ProfileContentTab = .posts

    @State private var posts: [FeedPost] = []
    @State private var postsLoaded = false
    @State private var postsError: String?
    @State private var canLoadMore = false
    @State private var isLoadingMore = false
    @State private var loadMoreError: String?

    @State private var portfolioState: ProfilePortfolioState = .idle

    @State private var isFollowBusy = false
    @State private var showingEditProfile = false
    @State private var showingCompose = false
    @State private var errorMessage: String?

    /// A multiple of the grid's 3 columns.
    private static let pageSize = 24
    /// Coming back to a profile after this long reloads it.
    private static let staleInterval: TimeInterval = 60

    init(userID: UUID, isTabRoot: Bool = false) {
        self.userID = userID
        self.isTabRoot = isTabRoot
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                content
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(isTabRoot ? NavigationBarItem.TitleDisplayMode.large : NavigationBarItem.TitleDisplayMode.inline)
        .refreshable {
            // Its own task, so the refresh isn't cancelled when the content redraws.
            await Task { await reloadAll() }.value
        }
        .task(id: userID) {
            await loadIfNeeded()
        }
        .task(id: selectedTab) {
            await loadPortfolioIfNeeded()
        }
        .onChange(of: portfolio.lastLoaded) {
            // Your own brokerage data changed (linked, synced or removed).
            guard isSelf, portfolioState.isLoaded else { return }
            Task { await loadPortfolio() }
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
        }
        .sheet(isPresented: $showingCompose, onDismiss: {
            Task { await reloadAll() }
        }) {
            ComposePostView()
        }
        .profileErrorAlert($errorMessage)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if let header = headerModel {
            loadedContent(header)
        } else if let message = profileError {
            ProfileLoadFailedView(title: "Couldn't load this profile", message: message) {
                // Back to the spinner while retrying.
                profileError = nil
                Task { await reloadAll() }
            }
            .padding(.top, 60)
        } else {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.top, 120)
                .accessibilityLabel("Loading profile")
        }
    }

    @ViewBuilder
    private func loadedContent(_ header: ProfileHeaderModel) -> some View {
        if let message = profileError {
            ProfileInlineError(message: message) {
                Task { await reloadAll() }
            }
        }
        ProfileHeaderView(
            model: header,
            isSelf: isSelf,
            isFollowBusy: isFollowBusy,
            onToggleFollow: { Task { await toggleFollow() } },
            onEditProfile: { showingEditProfile = true }
        )
        tabPicker
        switch selectedTab {
        case .posts:
            postsSection
        case .portfolio:
            ProfilePortfolioSection(
                state: portfolioState,
                username: header.username,
                isSelf: isSelf,
                sharesPortfolio: header.sharePortfolio
            ) {
                Task { await loadPortfolio() }
            }
        }
    }

    private var tabPicker: some View {
        Picker("Show", selection: $selectedTab) {
            ForEach(ProfileContentTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var postsSection: some View {
        if !postsLoaded {
            if let message = postsError {
                ProfileInlineError(message: message) {
                    Task { await reloadPosts() }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .accessibilityLabel("Loading posts")
            }
        } else {
            if let message = postsError {
                ProfileInlineError(message: message) {
                    Task { await reloadPosts() }
                }
            }
            if posts.isEmpty {
                emptyPosts
            } else {
                ProfilePostsGrid(posts: posts) {
                    Task { await loadMore() }
                }
                loadMoreFooter
            }
        }
    }

    @ViewBuilder
    private var emptyPosts: some View {
        if isSelf {
            ContentUnavailableView {
                Label("Share your first post", systemImage: "square.and.pencil")
            } description: {
                Text("Trades, portfolio snapshots and thoughts you share show up here.")
            } actions: {
                Button("New post") {
                    showingCompose = true
                }
                .buttonStyle(.borderedProminent)
            }
            .hakiCard()
        } else {
            ContentUnavailableView(
                "No posts yet",
                systemImage: "square.grid.3x3",
                description: Text("When they share something, it'll show up here.")
            )
            .hakiCard()
        }
    }

    @ViewBuilder
    private var loadMoreFooter: some View {
        if isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .accessibilityLabel("Loading more posts")
        } else if let message = loadMoreError {
            ProfileInlineError(message: message) {
                loadMoreError = nil
                Task { await loadMore() }
            }
        }
    }

    // MARK: Derived

    private var isSelf: Bool {
        auth.userID == userID
    }

    /// Loaded stats, with your own latest edits on top; for yourself, the
    /// signed-in profile right away while the stats load.
    private var headerModel: ProfileHeaderModel? {
        let record = ownRecord
        if let profile {
            if let record {
                return ProfileHeaderModel(profile: profile, overlaying: record)
            }
            return ProfileHeaderModel(profile: profile)
        }
        guard let record else { return nil }
        return ProfileHeaderModel(record: record)
    }

    /// The signed-in user's own profile row, when this is their profile.
    private var ownRecord: ProfileRecord? {
        guard isSelf, let record = auth.profile, record.id == userID else { return nil }
        return record
    }

    private var title: String {
        if let username = headerModel?.username {
            return username
        }
        return isTabRoot ? "Profile" : ""
    }

    // MARK: Loading

    private func loadIfNeeded() async {
        if loadedUserID != userID {
            resetForNewUser()
            loadedUserID = userID
        }
        if let lastLoaded, Date.now.timeIntervalSince(lastLoaded) < Self.staleInterval {
            return
        }
        await reloadAll()
    }

    /// Reloads the profile and the first page of posts in parallel, and the
    /// portfolio if it's been looked at.
    private func reloadAll() async {
        let social = self.social
        let id = userID
        let limit = Self.pageSize
        let includesPortfolio = selectedTab == .portfolio || portfolioState.isLoaded

        async let fetchedProfile = social.profile(id: id)
        async let fetchedPosts = social.posts(byAuthor: id, before: nil, limit: limit)

        var succeeded = true
        do {
            let loaded = try await fetchedProfile
            guard id == userID else { return }
            profile = loaded
            profileError = nil
        } catch {
            if Task.isCancelled || ProfileErrorInfo.isCancellation(error) { return }
            profileError = ProfileErrorInfo.message(for: error)
            succeeded = false
        }

        do {
            let page = try await fetchedPosts
            guard id == userID else { return }
            applyFirstPage(page)
        } catch {
            if Task.isCancelled || ProfileErrorInfo.isCancellation(error) { return }
            postsError = ProfileErrorInfo.message(for: error)
            succeeded = false
        }

        if includesPortfolio {
            await loadPortfolio()
        }
        if succeeded {
            lastLoaded = .now
        }
    }

    private func reloadPosts() async {
        postsError = nil
        let id = userID
        do {
            let page = try await social.posts(byAuthor: id, before: nil, limit: Self.pageSize)
            guard id == userID else { return }
            applyFirstPage(page)
        } catch {
            if Task.isCancelled || ProfileErrorInfo.isCancellation(error) { return }
            postsError = ProfileErrorInfo.message(for: error)
        }
    }

    private func applyFirstPage(_ page: [FeedPost]) {
        posts = page
        postsLoaded = true
        postsError = nil
        loadMoreError = nil
        canLoadMore = page.count >= Self.pageSize
    }

    /// The next page, older than the last post shown. Stops after a short
    /// page, and after a failure until the user taps Retry.
    private func loadMore() async {
        guard postsLoaded, canLoadMore, !isLoadingMore, loadMoreError == nil, let last = posts.last else { return }
        let id = userID
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await social.posts(byAuthor: id, before: last.createdAt, limit: Self.pageSize)
            guard id == userID else { return }
            let known = Set(posts.map(\.id))
            posts.append(contentsOf: page.filter { !known.contains($0.id) })
            canLoadMore = page.count >= Self.pageSize
        } catch {
            if ProfileErrorInfo.isCancellation(error) { return }
            loadMoreError = ProfileErrorInfo.message(for: error)
        }
    }

    private func loadPortfolioIfNeeded() async {
        guard selectedTab == .portfolio else { return }
        switch portfolioState {
        case .idle, .failed:
            await loadPortfolio()
        case .loading, .loaded:
            return
        }
    }

    private func loadPortfolio() async {
        // Someone else's private portfolio: nothing to fetch.
        if !isSelf, let profile, !profile.sharePortfolio {
            portfolioState = .loaded(summary: nil, holdings: [])
            return
        }
        if !portfolioState.isLoaded {
            portfolioState = .loading
        }
        let social = self.social
        let id = userID

        async let fetchedSummary = social.publicPortfolioSummary(userID: id)
        async let fetchedHoldings = social.publicPortfolio(userID: id)
        do {
            let summary = try await fetchedSummary
            let holdings = try await fetchedHoldings
            guard id == userID else { return }
            portfolioState = .loaded(summary: summary, holdings: holdings)
        } catch {
            if Task.isCancelled || ProfileErrorInfo.isCancellation(error) {
                if portfolioState.isLoading {
                    portfolioState = .idle
                }
                return
            }
            if portfolioState.isLoaded {
                errorMessage = ProfileErrorInfo.message(for: error)
            } else {
                portfolioState = .failed(ProfileErrorInfo.message(for: error))
            }
        }
    }

    private func resetForNewUser() {
        profile = nil
        profileError = nil
        lastLoaded = nil
        posts = []
        postsLoaded = false
        postsError = nil
        canLoadMore = false
        isLoadingMore = false
        loadMoreError = nil
        portfolioState = .idle
        isFollowBusy = false
    }

    // MARK: Actions

    /// Optimistic: flips the button and count right away, reverts on failure.
    private func toggleFollow() async {
        guard !isSelf, !isFollowBusy, var current = profile else { return }
        let target = !current.followedByMe
        FollowToggle.set(target, on: &current)
        profile = current
        isFollowBusy = true
        defer { isFollowBusy = false }
        do {
            try await social.setFollowing(target, userID: current.id)
        } catch {
            if var reverted = profile, reverted.id == current.id {
                FollowToggle.set(!target, on: &reverted)
                profile = reverted
            }
            if !ProfileErrorInfo.isCancellation(error) {
                errorMessage = ProfileErrorInfo.message(for: error)
            }
        }
    }
}

private nonisolated enum ProfileContentTab: String, CaseIterable, Identifiable, Hashable {
    case posts
    case portfolio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .posts: "Posts"
        case .portfolio: "Portfolio"
        }
    }
}

#Preview("Someone else") {
    NavigationStack {
        ProfileView(userID: SocialPreviewData.profiles[1].id)
    }
    .previewEnvironment()
}

#Preview("Private portfolio") {
    NavigationStack {
        ProfileView(userID: SocialPreviewData.profiles[3].id)
    }
    .previewEnvironment()
}
