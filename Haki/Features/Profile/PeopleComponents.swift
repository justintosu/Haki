//
//  PeopleComponents.swift
//  Haki
//
//  People rows with Follow buttons, shared by profiles, follower lists and
//  people search.
//

import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Follow state

/// Optimistic follow changes: flip the state and keep the follower count in step.
enum FollowToggle {
    /// No-op when `profile` is already in the wanted state.
    static func set(_ following: Bool, on profile: inout UserProfile) {
        guard profile.followedByMe != following else { return }
        profile.followedByMe = following
        profile.followerCount = max(0, profile.followerCount + (following ? 1 : -1))
    }

    /// Applies the change to every copy of the user in `profiles`.
    static func set(_ following: Bool, userID: UUID, in profiles: inout [UserProfile]) {
        for index in profiles.indices where profiles[index].id == userID {
            set(following, on: &profiles[index])
        }
    }
}

// MARK: - Follow button

/// "Follow" (prominent) / "Following" (quiet). Tapping "Following" unfollows.
struct FollowButton: View {
    let isFollowing: Bool
    let isBusy: Bool
    /// Stretches to the available width (profile header) instead of a compact pill (rows).
    let fillsWidth: Bool
    /// Who the button is for, so VoiceOver says "Follow Dan Okafor" rather than just "Follow".
    let personName: String?
    let action: () -> Void

    init(
        isFollowing: Bool,
        isBusy: Bool = false,
        fillsWidth: Bool = false,
        personName: String? = nil,
        action: @escaping () -> Void
    ) {
        self.isFollowing = isFollowing
        self.isBusy = isBusy
        self.fillsWidth = fillsWidth
        self.personName = personName
        self.action = action
    }

    var body: some View {
        Group {
            if isFollowing {
                Button(action: action) {
                    label
                }
                .buttonStyle(.bordered)
                .tint(Color.primary)
            } else {
                Button(action: action) {
                    label
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .controlSize(fillsWidth ? ControlSize.regular : ControlSize.small)
        .disabled(isBusy)
        .animation(.snappy, value: isFollowing)
        .sensoryFeedback(.selection, trigger: isFollowing)
        .accessibilityLabel(spokenTitle)
        .accessibilityHint(hint)
    }

    private var title: String {
        isFollowing ? "Following" : "Follow"
    }

    private var spokenTitle: String {
        guard let personName, !personName.isEmpty else { return title }
        return "\(title) \(personName)"
    }

    private var hint: String {
        isFollowing ? "Double-tap to unfollow." : "Double-tap to follow."
    }

    private var label: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(minWidth: fillsWidth ? nil : CGFloat(76))
            .frame(maxWidth: fillsWidth ? CGFloat.infinity : nil)
    }
}

// MARK: - Rows

/// Avatar, name and @username (tapping opens the profile), with a Follow button.
struct PeopleRow: View {
    let profile: UserProfile
    let showsFollowButton: Bool
    let isFollowBusy: Bool
    let onToggleFollow: () -> Void

    init(profile: UserProfile, showsFollowButton: Bool, isFollowBusy: Bool = false, onToggleFollow: @escaping () -> Void) {
        self.profile = profile
        self.showsFollowButton = showsFollowButton
        self.isFollowBusy = isFollowBusy
        self.onToggleFollow = onToggleFollow
    }

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                ProfileView(userID: profile.id)
            } label: {
                identity
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens their profile.")

            if showsFollowButton {
                FollowButton(
                    isFollowing: profile.followedByMe,
                    isBusy: isFollowBusy,
                    personName: profile.name,
                    action: onToggleFollow
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            AvatarView(url: profile.avatarURL, name: profile.name, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let count = profile.followerCount.formatted(.number.notation(.compactName))
        let noun = profile.followerCount == 1 ? "follower" : "followers"
        return "@\(profile.username) · \(count) \(noun)"
    }
}

/// A card of `PeopleRow`s separated by dividers. No Follow button on your own row.
struct PeopleListCard: View {
    let profiles: [UserProfile]
    let currentUserID: UUID?
    let busyIDs: Set<UUID>
    let onToggleFollow: (UUID) -> Void

    init(profiles: [UserProfile], currentUserID: UUID?, busyIDs: Set<UUID>, onToggleFollow: @escaping (UUID) -> Void) {
        self.profiles = profiles
        self.currentUserID = currentUserID
        self.busyIDs = busyIDs
        self.onToggleFollow = onToggleFollow
    }

    var body: some View {
        LazyVStack(spacing: 0) {
            ForEach(profiles) { profile in
                VStack(spacing: 0) {
                    if profile.id != profiles.first?.id {
                        Divider()
                            .padding(.leading, 72)
                    }
                    PeopleRow(
                        profile: profile,
                        showsFollowButton: profile.id != currentUserID,
                        isFollowBusy: busyIDs.contains(profile.id)
                    ) {
                        onToggleFollow(profile.id)
                    }
                }
            }
        }
        .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview("People") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 16) {
                PeopleListCard(
                    profiles: SocialPreviewData.profiles,
                    currentUserID: SocialPreviewData.profiles.first?.id,
                    busyIDs: []
                ) { _ in }
                FollowButton(isFollowing: false, fillsWidth: true) {}
                FollowButton(isFollowing: true, fillsWidth: true) {}
            }
            .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
