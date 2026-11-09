//
//  YouView.swift
//  Haki
//
//  The You tab: your profile at the top, then Ask Haki, your wardrobe and
//  your notes and flashcards. Activity and Settings are in the toolbar, as
//  they were on the old Profile tab.
//

import Foundation
import SwiftUI

struct YouView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SocialService.self) private var social

    @State private var showingSettings = false
    /// Your public profile with its counts, once loaded.
    @State private var stats: UserProfile?
    @State private var statsLoadedAt: Date?

    /// Coming back to the tab after this long reloads the counts.
    private static let staleInterval: TimeInterval = 30

    init() {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    profileCard
                    YouAskHakiCard()
                    WardrobeSummaryCard()
                    StudySummaryCard()
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.hakiBackground)
            .navigationTitle("You")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .refreshable {
                // Its own task, so the refresh isn't cancelled when the content redraws.
                await Task { await loadStats(force: true) }.value
            }
            .task(id: auth.userID) {
                await loadStats(force: false)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var profileCard: some View {
        if let userID = auth.userID {
            YouProfileCard(userID: userID, record: auth.profile, stats: stats)
        } else {
            YouSignedOutCard()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            AssistantToolbarButton()
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            NavigationLink {
                ActivityView()
            } label: {
                Image(systemName: "heart")
            }
            .accessibilityLabel("Activity")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: Loading

    /// Loads your post, follower and following counts. They're extra here:
    /// the card shows without them, and pulling to refresh tries again.
    private func loadStats(force: Bool) async {
        guard let userID = auth.userID else {
            stats = nil
            statsLoadedAt = nil
            return
        }
        if !force, stats?.id == userID, let statsLoadedAt,
           Date.now.timeIntervalSince(statsLoadedAt) < Self.staleInterval {
            return
        }
        do {
            let loaded = try await social.profile(id: userID)
            guard auth.userID == userID else { return }
            withAnimation(.snappy) {
                stats = loaded
            }
            statsLoadedAt = .now
        } catch {
            // Keep whatever counts were shown; the card works without them.
            return
        }
    }
}

#Preview {
    YouView()
        .previewEnvironment()
}

#Preview("No data") {
    YouView()
        .previewEnvironment(empty: true)
}
