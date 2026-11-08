//
//  FollowListView.swift
//  Haki
//
//  Who follows someone, or who they follow, with Follow buttons.
//

import Foundation
import SwiftUI

struct FollowListView: View {
    let userID: UUID
    let mode: FollowListMode

    @Environment(SocialService.self) private var social
    @Environment(AuthService.self) private var auth

    @State private var profiles: [UserProfile] = []
    @State private var didLoad = false
    @State private var loadError: String?
    @State private var filter = ""
    @State private var busyIDs: Set<UUID> = []
    @State private var errorMessage: String?

    init(userID: UUID, mode: FollowListMode) {
        self.userID = userID
        self.mode = mode
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $filter, prompt: "Search")
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task {
            await loadIfNeeded()
        }
        .refreshable {
            await Task { await load() }.value
        }
        .profileErrorAlert($errorMessage)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !didLoad {
            if let message = loadError {
                ProfileLoadFailedView(title: "Couldn't load this list", message: message) {
                    // Back to the spinner while retrying.
                    loadError = nil
                    Task { await load() }
                }
                .padding(.top, 60)
            } else {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 120)
                    .accessibilityLabel("Loading \(title.lowercased())")
            }
        } else if profiles.isEmpty {
            emptyState
                .padding(.top, 40)
        } else {
            if let message = loadError {
                ProfileInlineError(message: message) {
                    Task { await load() }
                }
            }
            if filteredProfiles.isEmpty {
                ContentUnavailableView.search(text: trimmedFilter)
            } else {
                PeopleListCard(
                    profiles: filteredProfiles,
                    currentUserID: auth.userID,
                    busyIDs: busyIDs
                ) { id in
                    Task { await toggleFollow(id) }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: mode == .followers ? "person.2" : "person.badge.plus")
        } description: {
            Text(emptyMessage)
        } actions: {
            if isOwnList {
                findPeopleLink
            }
        }
    }

    private var emptyTitle: String {
        switch mode {
        case .followers: "No followers yet"
        case .following: isOwnList ? "You're not following anyone yet" : "Not following anyone yet"
        }
    }

    private var emptyMessage: String {
        switch mode {
        case .followers:
            isOwnList
                ? "When people follow you, they'll show up here."
                : "When people follow this account, they'll show up here."
        case .following:
            isOwnList
                ? "Follow friends to see their trades and posts in your feed."
                : "Accounts they follow will show up here."
        }
    }

    private var findPeopleLink: some View {
        NavigationLink {
            PeopleSearchView()
        } label: {
            Label("Find people", systemImage: "magnifyingglass")
        }
        .buttonStyle(.borderedProminent)
    }

    // MARK: Derived

    private var title: String {
        switch mode {
        case .followers: "Followers"
        case .following: "Following"
        }
    }

    private var isOwnList: Bool {
        auth.userID == userID
    }

    private var trimmedFilter: String {
        filter.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
    }

    private var filteredProfiles: [UserProfile] {
        let needle = trimmedFilter
        guard !needle.isEmpty else { return profiles }
        return profiles.filter {
            $0.username.localizedCaseInsensitiveContains(needle)
                || $0.displayName.localizedCaseInsensitiveContains(needle)
        }
    }

    // MARK: Actions

    private func loadIfNeeded() async {
        guard !didLoad else { return }
        await load()
    }

    private func load() async {
        do {
            let loaded = try await social.followList(of: userID, mode: mode)
            profiles = loaded
            didLoad = true
            loadError = nil
        } catch {
            if Task.isCancelled || ProfileErrorInfo.isCancellation(error) { return }
            loadError = ProfileErrorInfo.message(for: error)
        }
    }

    /// Optimistic: flips the row right away, reverts on failure.
    private func toggleFollow(_ id: UUID) async {
        guard !busyIDs.contains(id), let current = profiles.first(where: { $0.id == id }) else { return }
        let target = !current.followedByMe
        FollowToggle.set(target, userID: id, in: &profiles)
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            try await social.setFollowing(target, userID: id)
        } catch {
            FollowToggle.set(!target, userID: id, in: &profiles)
            if !ProfileErrorInfo.isCancellation(error) {
                errorMessage = ProfileErrorInfo.message(for: error)
            }
        }
    }
}

#Preview("Following") {
    NavigationStack {
        FollowListView(userID: SocialPreviewData.profiles[0].id, mode: .following)
    }
    .previewEnvironment()
}

#Preview("Followers") {
    NavigationStack {
        FollowListView(userID: SocialPreviewData.profiles[2].id, mode: .followers)
    }
    .previewEnvironment()
}
