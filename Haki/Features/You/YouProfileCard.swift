//
//  YouProfileCard.swift
//  Haki
//
//  The top of the You tab: your photo, name and @username, your post,
//  follower and following counts (once they load), and buttons to open your
//  full profile or edit it. When signed out, the same empty state the old
//  Profile tab showed.
//

import Foundation
import SwiftUI

struct YouProfileCard: View {
    let userID: UUID
    /// The signed-in profile (`AuthService.profile`), shown right away.
    let record: ProfileRecord?
    /// The profile's public stats, once loaded; only used when it's this user's.
    let stats: UserProfile?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title) private var avatarSize: CGFloat = 64

    @State private var showingEditProfile = false

    init(userID: UUID, record: ProfileRecord?, stats: UserProfile?) {
        self.userID = userID
        self.record = record
        self.stats = stats
    }

    var body: some View {
        let summary = YouProfileSummary(userID: userID, record: record, stats: stats)
        VStack(alignment: .leading, spacing: 16) {
            identity(summary)
            YouProfileStatsRow(summary: summary, isStacked: dynamicTypeSize.isAccessibilitySize)
            buttons
        }
        .hakiCard()
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
        }
    }

    // MARK: Identity

    /// Photo beside the name; at accessibility text sizes, the photo above it.
    @ViewBuilder
    private func identity(_ summary: YouProfileSummary) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) {
                AvatarView(url: summary.avatarURL, name: summary.name, size: avatarSize)
                names(summary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 14) {
                AvatarView(url: summary.avatarURL, name: summary.name, size: avatarSize)
                names(summary)
                Spacer(minLength: 0)
            }
        }
    }

    private func names(_ summary: YouProfileSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.name)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let username = summary.username {
                Text("@\(username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Username \(username)")
            }
            if !summary.bio.isEmpty {
                Text(summary.bio)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 2)
            }
        }
    }

    // MARK: Buttons

    /// Side by side; one above the other at accessibility text sizes.
    private var buttons: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 10) {
                    viewProfileButton
                    editProfileButton
                }
            } else {
                HStack(spacing: 10) {
                    viewProfileButton
                    editProfileButton
                }
            }
        }
        .controlSize(.large)
    }

    private var viewProfileButton: some View {
        NavigationLink {
            ProfileView(userID: userID, isTabRoot: false)
        } label: {
            Label("View profile", systemImage: "person.crop.square")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityHint("Shows your posts and portfolio")
    }

    private var editProfileButton: some View {
        Button {
            showingEditProfile = true
        } label: {
            Label("Edit profile", systemImage: "pencil")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(Color.primary)
        .accessibilityHint("Change your photo, name and bio")
    }
}

// MARK: - Signed out

/// The old Profile tab's signed-out state, as a card.
struct YouSignedOutCard: View {
    var body: some View {
        ContentUnavailableView(
            "You're signed out",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("Sign in to see your profile, posts and portfolio.")
        )
        .hakiCard()
    }
}

// MARK: - Summary

/// What the card shows: the signed-in profile's latest edits first, then the
/// loaded stats; counts stay `nil` until the stats load.
private struct YouProfileSummary {
    let userID: UUID
    let name: String
    let username: String?
    let bio: String
    let avatarURL: URL?
    let postCount: Int?
    let followerCount: Int?
    let followingCount: Int?

    init(userID: UUID, record: ProfileRecord?, stats: UserProfile?) {
        self.userID = userID
        var matchingStats: UserProfile?
        if let stats, stats.id == userID {
            matchingStats = stats
        }

        if let record, record.id == userID {
            name = record.name
            username = record.username
            bio = record.bio
            avatarURL = record.avatarURL
        } else if let matchingStats {
            name = matchingStats.name
            username = matchingStats.username
            bio = matchingStats.bio
            avatarURL = matchingStats.avatarURL
        } else {
            name = "You"
            username = nil
            bio = ""
            avatarURL = nil
        }

        postCount = matchingStats?.postCount
        followerCount = matchingStats?.followerCount
        followingCount = matchingStats?.followingCount
    }
}

// MARK: - Stats

/// Posts, followers and following; followers and following open the lists.
private struct YouProfileStatsRow: View {
    let summary: YouProfileSummary
    /// One per line (accessibility text sizes) instead of three columns.
    let isStacked: Bool

    var body: some View {
        Group {
            if isStacked {
                VStack(alignment: .leading, spacing: 4) {
                    stats
                }
            } else {
                HStack(spacing: 0) {
                    stats
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, isStacked ? 12 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var stats: some View {
        YouProfileStat(value: summary.postCount, title: "Posts", singular: "post", plural: "posts", isStacked: isStacked)

        NavigationLink {
            FollowListView(userID: summary.userID, mode: .followers)
        } label: {
            YouProfileStat(value: summary.followerCount, title: "Followers", singular: "follower", plural: "followers", isStacked: isStacked)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows who follows you")

        NavigationLink {
            FollowListView(userID: summary.userID, mode: .following)
        } label: {
            YouProfileStat(value: summary.followingCount, title: "Following", singular: "following", plural: "following", isStacked: isStacked)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows who you follow")
    }
}

/// "128" over "Followers", or "128 Followers" on one line when stacked.
private struct YouProfileStat: View {
    let value: Int?
    let title: String
    let singular: String
    let plural: String
    let isStacked: Bool

    var body: some View {
        Group {
            if isStacked {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    valueText
                    titleText
                        .font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 2) {
                    valueText
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    titleText
                        .font(.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var valueText: some View {
        Text(formattedValue)
            .font(.system(.headline, design: .rounded).weight(.bold))
            .monospacedDigit()
            .contentTransition(.numericText())
            .foregroundStyle(.primary)
    }

    private var titleText: some View {
        Text(title)
            .foregroundStyle(.secondary)
    }

    private var formattedValue: String {
        guard let value else { return "—" }
        return value.formatted(.number.notation(.compactName))
    }

    private var spokenText: String {
        guard let value else { return "\(title), loading" }
        return "\(value.formatted()) \(value == 1 ? singular : plural)"
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            VStack(spacing: 16) {
                YouProfileCard(
                    userID: SocialPreviewData.signedInProfile.id,
                    record: SocialPreviewData.signedInProfile,
                    stats: nil
                )
                YouSignedOutCard()
            }
            .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
