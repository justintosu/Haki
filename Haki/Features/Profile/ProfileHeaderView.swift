//
//  ProfileHeaderView.swift
//  Haki
//
//  The top of a profile: photo, counts, name, @username, bio, and Follow,
//  Unblock or Edit profile.
//

import Foundation
import SwiftUI

/// What the header shows. Counts are `nil` until the profile's stats load
/// (your own header can show right away from `AuthService.profile`).
nonisolated struct ProfileHeaderModel: Equatable {
    let id: UUID
    var username: String
    var name: String
    var bio: String
    var avatarURL: URL?
    var sharePortfolio: Bool
    var createdAt: Date?
    var postCount: Int?
    var followerCount: Int?
    var followingCount: Int?
    var followedByMe: Bool

    init(profile: UserProfile) {
        id = profile.id
        username = profile.username
        name = profile.name
        bio = profile.bio
        avatarURL = profile.avatarURL
        sharePortfolio = profile.sharePortfolio
        createdAt = profile.createdAt
        postCount = profile.postCount
        followerCount = profile.followerCount
        followingCount = profile.followingCount
        followedByMe = profile.followedByMe
    }

    init(record: ProfileRecord) {
        id = record.id
        username = record.username
        name = record.name
        bio = record.bio
        avatarURL = record.avatarURL
        sharePortfolio = record.sharePortfolio
        createdAt = nil
        postCount = nil
        followerCount = nil
        followingCount = nil
        followedByMe = false
    }

    /// Loaded stats with the signed-in user's latest edits on top, so changes
    /// made in Edit profile show immediately.
    init(profile: UserProfile, overlaying record: ProfileRecord) {
        self.init(profile: profile)
        username = record.username
        name = record.name
        bio = record.bio
        avatarURL = record.avatarURL
        sharePortfolio = record.sharePortfolio
    }
}

struct ProfileHeaderView: View {
    let model: ProfileHeaderModel
    let isSelf: Bool
    let isFollowBusy: Bool
    let onToggleFollow: () -> Void
    let onEditProfile: () -> Void
    /// Set while you've blocked this person: shows Unblock instead of Follow.
    let onUnblock: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        model: ProfileHeaderModel,
        isSelf: Bool,
        isFollowBusy: Bool = false,
        onToggleFollow: @escaping () -> Void = {},
        onEditProfile: @escaping () -> Void = {},
        onUnblock: (() -> Void)? = nil
    ) {
        self.model = model
        self.isSelf = isSelf
        self.isFollowBusy = isFollowBusy
        self.onToggleFollow = onToggleFollow
        self.onEditProfile = onEditProfile
        self.onUnblock = onUnblock
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            topRow
            identity
            actionButton
        }
        .hakiCard()
    }

    /// Photo beside the counts; at accessibility text sizes, the photo above
    /// the counts listed one per line, so they aren't truncated.
    @ViewBuilder
    private var topRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                AvatarView(url: model.avatarURL, name: model.name, size: 84)
                VStack(alignment: .leading, spacing: 6) {
                    stats(stacked: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                AvatarView(url: model.avatarURL, name: model.name, size: 84)
                HStack(spacing: 0) {
                    stats(stacked: false)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func stats(stacked: Bool) -> some View {
        ProfileStatView(value: model.postCount, singular: "post", plural: "posts", title: "Posts", isStacked: stacked)
        NavigationLink {
            FollowListView(userID: model.id, mode: .followers)
        } label: {
            ProfileStatView(value: model.followerCount, singular: "follower", plural: "followers", title: "Followers", isStacked: stacked)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows who follows \(model.username).")
        NavigationLink {
            FollowListView(userID: model.id, mode: .following)
        } label: {
            ProfileStatView(value: model.followingCount, singular: "following", plural: "following", title: "Following", isStacked: stacked)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows who \(model.username) follows.")
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.name)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("@\(model.username)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Username \(model.username)")
            if !model.bio.isEmpty {
                Text(model.bio)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            if let joined = joinedText {
                Label(joined, systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var actionButton: some View {
        if isSelf {
            Button(action: onEditProfile) {
                Text("Edit profile")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.primary)
        } else if let onUnblock {
            Button(action: onUnblock) {
                Text("Unblock")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Color.primary)
            .accessibilityLabel("Unblock \(model.name)")
        } else {
            FollowButton(
                isFollowing: model.followedByMe,
                isBusy: isFollowBusy,
                fillsWidth: true,
                personName: model.name,
                action: onToggleFollow
            )
        }
    }

    private var joinedText: String? {
        guard let createdAt = model.createdAt else { return nil }
        return "Joined \(createdAt.formatted(.dateTime.month(.wide).year()))"
    }
}

/// "128" over "Followers", or "128 Followers" on one line when stacked.
private struct ProfileStatView: View {
    let value: Int?
    let singular: String
    let plural: String
    let title: String
    /// One of a vertical list (accessibility text sizes) rather than a column.
    let isStacked: Bool

    var body: some View {
        Group {
            if isStacked {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    valueLabel
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 2) {
                    valueLabel
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenText)
    }

    private var valueLabel: some View {
        Text(valueText)
            .font(.headline)
            .monospacedDigit()
            .contentTransition(.numericText())
    }

    private var valueText: String {
        guard let value else { return "—" }
        return value.formatted(.number.notation(.compactName))
    }

    private var spokenText: String {
        guard let value else { return "\(title), loading" }
        return "\(value.formatted()) \(value == 1 ? singular : plural)"
    }
}

#Preview("Someone else") {
    NavigationStack {
        ScrollView {
            ProfileHeaderView(model: ProfileHeaderModel(profile: SocialPreviewData.profiles[1]), isSelf: false)
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}

#Preview("You") {
    NavigationStack {
        ScrollView {
            ProfileHeaderView(model: ProfileHeaderModel(profile: SocialPreviewData.profiles[0]), isSelf: true)
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
