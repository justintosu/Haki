//
//  PeopleSearchView.swift
//  Haki
//
//  Find people by name or username. Before typing, shows suggested people
//  to follow.
//

import Foundation
import SwiftUI

struct PeopleSearchView: View {
    @Environment(SocialService.self) private var social
    @Environment(AuthService.self) private var auth

    @State private var query = ""
    @State private var results: [UserProfile] = []
    /// The query `results` belong to.
    @State private var resultsQuery: String?
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var searchAttempt = 0

    @State private var suggestions: [UserProfile] = []
    @State private var suggestionsLoaded = false
    @State private var suggestionsError: String?

    @State private var busyIDs: Set<UUID> = []
    @State private var errorMessage: String?

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if trimmedQuery.isEmpty {
                    suggestionsContent
                } else {
                    resultsContent
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle("Find people")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Name or @username"
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .task(id: searchKey) {
            await search()
        }
        .task {
            await loadSuggestionsIfNeeded()
        }
        .refreshable {
            await Task { await refresh() }.value
        }
        .profileErrorAlert($errorMessage)
    }

    // MARK: Suggestions

    @ViewBuilder
    private var suggestionsContent: some View {
        Text("Suggested for you")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 8)
        if !suggestionsLoaded {
            if let message = suggestionsError {
                ProfileInlineError(message: message) {
                    // Back to the spinner while retrying.
                    suggestionsError = nil
                    Task { await loadSuggestions() }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .accessibilityLabel("Loading suggestions")
            }
        } else if suggestions.isEmpty {
            ContentUnavailableView(
                "No suggestions right now",
                systemImage: "person.2",
                description: Text("Search for friends by their name or username.")
            )
            .hakiCard()
        } else {
            PeopleListCard(
                profiles: suggestions,
                currentUserID: auth.userID,
                busyIDs: busyIDs
            ) { id in
                Task { await toggleFollow(id) }
            }
        }
    }

    // MARK: Results

    @ViewBuilder
    private var resultsContent: some View {
        if let message = searchError {
            ProfileLoadFailedView(title: "Search didn't work", message: message) {
                searchAttempt += 1
            }
            .padding(.top, 40)
        } else if results.isEmpty {
            if isSearching || resultsQuery != trimmedQuery {
                ProgressView("Searching…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ContentUnavailableView.search(text: trimmedQuery)
                    .padding(.top, 40)
            }
        } else {
            HStack(spacing: 8) {
                Text("People")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if isSearching {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Searching")
                }
            }
            .padding(.top, 8)
            PeopleListCard(
                profiles: results,
                currentUserID: auth.userID,
                busyIDs: busyIDs
            ) { id in
                Task { await toggleFollow(id) }
            }
        }
    }

    // MARK: Derived

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Changes with every edit and every retry, restarting the debounced search.
    private var searchKey: String {
        "\(searchAttempt)|\(trimmedQuery)"
    }

    // MARK: Actions

    /// Debounced: waits ~300 ms after the last keystroke before asking the server.
    private func search() async {
        let text = trimmedQuery
        guard !text.isEmpty else {
            isSearching = false
            searchError = nil
            return
        }
        isSearching = true
        searchError = nil
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        do {
            let found = try await social.searchProfiles(text)
            guard !Task.isCancelled else { return }
            results = found
            resultsQuery = text
        } catch {
            guard !Task.isCancelled, !ProfileErrorInfo.isCancellation(error) else { return }
            searchError = ProfileErrorInfo.message(for: error)
        }
        isSearching = false
    }

    private func refresh() async {
        if trimmedQuery.isEmpty {
            await loadSuggestions()
        } else {
            searchAttempt += 1
        }
    }

    private func loadSuggestionsIfNeeded() async {
        guard !suggestionsLoaded else { return }
        await loadSuggestions()
    }

    private func loadSuggestions() async {
        do {
            let loaded = try await social.suggestedProfiles()
            suggestions = loaded.filter { $0.id != auth.userID }
            suggestionsLoaded = true
            suggestionsError = nil
        } catch {
            if Task.isCancelled || ProfileErrorInfo.isCancellation(error) { return }
            if suggestionsLoaded {
                errorMessage = ProfileErrorInfo.message(for: error)
            } else {
                suggestionsError = ProfileErrorInfo.message(for: error)
            }
        }
    }

    /// Optimistic, in both lists (the same person can be suggested and found).
    private func toggleFollow(_ id: UUID) async {
        guard !busyIDs.contains(id),
              let current = results.first(where: { $0.id == id }) ?? suggestions.first(where: { $0.id == id })
        else { return }
        let target = !current.followedByMe
        FollowToggle.set(target, userID: id, in: &results)
        FollowToggle.set(target, userID: id, in: &suggestions)
        busyIDs.insert(id)
        defer { busyIDs.remove(id) }
        do {
            try await social.setFollowing(target, userID: id)
        } catch {
            FollowToggle.set(!target, userID: id, in: &results)
            FollowToggle.set(!target, userID: id, in: &suggestions)
            if !ProfileErrorInfo.isCancellation(error) {
                errorMessage = ProfileErrorInfo.message(for: error)
            }
        }
    }
}

#Preview {
    NavigationStack {
        PeopleSearchView()
    }
    .previewEnvironment()
}
