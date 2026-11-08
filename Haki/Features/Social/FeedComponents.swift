//
//  FeedComponents.swift
//  Haki
//
//  Building blocks for post lists: the rows with infinite scroll, the paging
//  footer, loading skeletons, a refresh-error banner, and the "people to
//  follow" suggestions shown on an empty Following feed.
//

import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Post rows

/// Post cards for a `FeedPager`'s visible posts, loading the next page when
/// the last one appears. Place inside a `LazyVStack`.
struct FeedPostRows: View {
    let posts: [FeedPost]
    let pager: FeedPager
    let loadMore: () async -> Void

    var body: some View {
        ForEach(posts) { post in
            PostCardView(post: post) { updated in
                pager.apply(updated, for: post.id)
            }
            .onAppear {
                if post.id == posts.last?.id {
                    Task { await loadMore() }
                }
            }
        }
        FeedPagingFooter(
            isLoading: pager.isLoadingMore,
            errorMessage: pager.loadMoreError,
            reachedEnd: pager.reachedEnd,
            retry: { Task { await loadMore() } }
        )
    }
}

/// Below the last post: a spinner while the next page loads, a retry after
/// a failure, or "You're all caught up" at the end.
struct FeedPagingFooter: View {
    let isLoading: Bool
    let errorMessage: String?
    let reachedEnd: Bool
    let retry: () -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .accessibilityLabel("Loading more posts")
            } else if let errorMessage {
                VStack(spacing: 8) {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try again", action: retry)
                        .font(.subheadline.weight(.semibold))
                }
            } else if reachedEnd {
                Label("You're all caught up", systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

// MARK: - Loading and errors

/// Placeholder cards while the first page loads.
struct FeedSkeletonList: View {
    var count: Int = 3
    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 16) {
            ForEach(0..<count, id: \.self) { index in
                FeedSkeletonCard(showsPhoto: index % 2 == 0)
            }
        }
        .opacity(isPulsing ? 0.55 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isPulsing)
        .onAppear { isPulsing = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading posts")
    }
}

private struct FeedSkeletonCard: View {
    let showsPhoto: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().frame(width: 120, height: 10)
                    Capsule().frame(width: 80, height: 8)
                }
            }
            if showsPhoto {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .frame(height: 220)
            }
            Capsule().frame(height: 10)
            Capsule().frame(width: 180, height: 10)
            HStack(spacing: 20) {
                Capsule().frame(width: 44, height: 12)
                Capsule().frame(width: 44, height: 12)
            }
        }
        .foregroundStyle(Color.secondary.opacity(0.16))
        .hakiCard()
    }
}

/// A dismissible warning shown above the posts when a refresh failed.
struct FeedErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.hakiWarning)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .hakiCard(padding: 12)
    }
}

// MARK: - Suggestions

/// The empty Following feed: an explanation, people to follow, and a way to Explore.
struct FeedSuggestionsView: View {
    /// Switches the feed to Explore.
    let onBrowseExplore: () -> Void
    /// Reloads the Following feed (offered once the user followed someone here).
    let onShowFollowedPosts: () -> Void

    @Environment(SocialService.self) private var social
    @State private var profiles: [UserProfile] = []
    @State private var phase: SocialLoadPhase = .idle
    @State private var pendingIDs: Set<UUID> = []
    @State private var followFeedback = 0
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            intro
            suggestions
            Button(action: onBrowseExplore) {
                Label("Browse Explore", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .task {
            await loadIfNeeded()
        }
        .sensoryFeedback(.success, trigger: followFeedback)
        .socialErrorAlert($errorMessage)
    }

    private var hasFollowedSomeone: Bool {
        profiles.contains(where: \.followedByMe)
    }

    /// The suggestions, without people you blocked.
    private var visibleProfiles: [UserProfile] {
        let blockList = SocialBlockList.shared
        return profiles.filter { !blockList.isBlocked($0.id) }
    }

    private var intro: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.accentColor)
                .padding(18)
                .background(Color.accentColor.opacity(0.12), in: Circle())
                .accessibilityHidden(true)
            Text("Your feed is quiet")
                .font(.title3.weight(.bold))
            Text("Follow friends and investors to see their trades, portfolios and posts here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if hasFollowedSomeone {
                Button(action: onShowFollowedPosts) {
                    Label("Show their posts", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .padding(.top, 16)
    }

    @ViewBuilder private var suggestions: some View {
        switch phase {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 160)
                .accessibilityLabel("Loading suggestions")
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await load() }
                }
                .font(.subheadline.weight(.semibold))
            }
        case .loaded:
            if !visibleProfiles.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Suggested for you")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(alignment: .top, spacing: 12) {
                            ForEach(visibleProfiles) { profile in
                                FeedSuggestedProfileCard(
                                    profile: profile,
                                    isUpdating: pendingIDs.contains(profile.id),
                                    onToggleFollow: { toggleFollow(profile.id) }
                                )
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }
        }
    }

    private func loadIfNeeded() async {
        guard phase == .idle else { return }
        await load()
    }

    private func load() async {
        phase = .loading
        do {
            profiles = try await social.suggestedProfiles()
            phase = .loaded
        } catch {
            phase = Backend.isCancellation(error) ? .idle : .failed(error.localizedDescription)
        }
    }

    /// Optimistic: flips the button right away and reverts if the server says no.
    private func toggleFollow(_ userID: UUID) {
        guard !pendingIDs.contains(userID), let profile = profiles.first(where: { $0.id == userID }) else { return }
        let follow = !profile.followedByMe
        setFollowing(follow, for: userID)
        pendingIDs.insert(userID)
        Task {
            do {
                try await social.setFollowing(follow, userID: userID)
                if follow { followFeedback += 1 }
            } catch {
                setFollowing(!follow, for: userID)
                if !Backend.isCancellation(error) {
                    errorMessage = error.localizedDescription
                }
            }
            pendingIDs.remove(userID)
        }
    }

    private func setFollowing(_ following: Bool, for userID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == userID }),
              profiles[index].followedByMe != following
        else { return }
        profiles[index].followedByMe = following
        profiles[index].followerCount = max(0, profiles[index].followerCount + (following ? 1 : -1))
    }
}

/// A suggested person: photo, names, follower count (all opening their
/// profile) and a Follow / Following button.
struct FeedSuggestedProfileCard: View {
    let profile: UserProfile
    let isUpdating: Bool
    let onToggleFollow: () -> Void

    /// Grows with the text size, so names and the button label aren't cut off.
    @ScaledMetric(relativeTo: .subheadline) private var cardWidth: CGFloat = 164

    var body: some View {
        VStack(spacing: 12) {
            NavigationLink {
                ProfileView(userID: profile.id)
            } label: {
                VStack(spacing: 4) {
                    AvatarView(url: profile.avatarURL, name: profile.name, size: 64)
                        .padding(.bottom, 4)
                    Text(profile.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Text("@" + profile.username)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(followersText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(profile.name), @\(profile.username), \(followersText)")
            .accessibilityHint("Opens their profile")

            followButton
                .controlSize(.small)
                .disabled(isUpdating)
        }
        .padding(14)
        .frame(width: min(cardWidth, 300))
        .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var followersText: String {
        let count = PostCaptionFormatter.compactCount(profile.followerCount)
        return profile.followerCount == 1 ? "1 follower" : "\(count) followers"
    }

    @ViewBuilder private var followButton: some View {
        if profile.followedByMe {
            Button(action: onToggleFollow) {
                Text("Following")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Following \(profile.name)")
            .accessibilityHint("Unfollows")
        } else {
            Button(action: onToggleFollow) {
                Text("Follow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel("Follow \(profile.name)")
        }
    }
}

#Preview("Suggestions") {
    NavigationStack {
        ScrollView {
            FeedSuggestionsView(onBrowseExplore: {}, onShowFollowedPosts: {})
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}

#Preview("Loading and footer") {
    ScrollView {
        VStack(spacing: 16) {
            FeedErrorBanner(message: "Couldn't load the feed. Try again.") {}
            FeedSkeletonList(count: 2)
            FeedPagingFooter(isLoading: false, errorMessage: nil, reachedEnd: true) {}
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
