//
//  ActivityView.swift
//  Haki
//
//  Likes, comments and follows involving you, newest first, grouped into
//  Today / This week / Earlier. Tap a person for their profile, or a post to
//  open it.
//

import Foundation
import SwiftUI

struct ActivityView: View {
    @Environment(SocialService.self) private var social
    @Environment(AuthService.self) private var auth

    @State private var items: [ActivityItem] = []
    @State private var phase: SocialLoadPhase = .idle
    @State private var refreshError: String?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                if let refreshError, !items.isEmpty {
                    FeedErrorBanner(message: refreshError) {
                        self.refreshError = nil
                    }
                }
                content
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .navigationTitle("Activity")
        .refreshable {
            await Task { await load() }.value
        }
        .task {
            await loadIfNeeded()
        }
    }

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            switch phase {
            case .idle, .loading:
                ProgressView("Loading activity…")
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn't load activity", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") {
                        Task { await load() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 40)
            case .loaded:
                ContentUnavailableView(
                    "No activity yet",
                    systemImage: "heart",
                    description: Text("When people like or comment on your posts, or start following you, you'll see it here.")
                )
                .padding(.top, 40)
            }
        } else {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        ForEach(section.items) { item in
                            ActivityRow(item: item)
                            if item.id != section.items.last?.id {
                                Divider()
                                    .padding(.leading, 70)
                            }
                        }
                    }
                    .hakiCard(padding: 0)
                }
            }
        }
    }

    private var sections: [ActivitySection] {
        let calendar = Calendar.current
        let now = Date.now
        var today: [ActivityItem] = []
        var thisWeek: [ActivityItem] = []
        var earlier: [ActivityItem] = []
        for item in items {
            if calendar.isDateInToday(item.createdAt) {
                today.append(item)
            } else if now.timeIntervalSince(item.createdAt) < 7 * 86_400 {
                thisWeek.append(item)
            } else {
                earlier.append(item)
            }
        }
        return [
            ActivitySection(title: "Today", items: today),
            ActivitySection(title: "This week", items: thisWeek),
            ActivitySection(title: "Earlier", items: earlier),
        ]
        .filter { !$0.items.isEmpty }
    }

    private func loadIfNeeded() async {
        PostChangeCenter.shared.prepare(for: auth.userID)
        guard phase == .idle else { return }
        await load()
    }

    private func load() async {
        if items.isEmpty {
            phase = .loading
        }
        do {
            let loaded = try await social.activity()
            // The same event can't appear twice in a list.
            var seen = Set<String>()
            items = loaded.filter { seen.insert($0.id).inserted }
            phase = .loaded
            refreshError = nil
        } catch {
            if Backend.isCancellation(error) {
                if items.isEmpty { phase = .idle }
                return
            }
            if items.isEmpty {
                phase = .failed(error.localizedDescription)
            } else {
                refreshError = error.localizedDescription
            }
        }
    }
}

private nonisolated struct ActivitySection: Identifiable {
    let title: String
    let items: [ActivityItem]
    var id: String { title }
}

// MARK: - Row

private struct ActivityRow: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                ProfileView(userID: item.actorID)
            } label: {
                avatar
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.actorName)'s profile")

            NavigationLink {
                primaryDestination
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                    Text(SocialTimeFormat.short(item.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint(item.postID == nil ? "Opens their profile" : "Opens the post")

            if let postID = item.postID {
                NavigationLink {
                    ActivityPostDestinationView(postID: postID)
                } label: {
                    thumbnail
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View post")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder private var primaryDestination: some View {
        if let postID = item.postID {
            ActivityPostDestinationView(postID: postID)
        } else {
            ProfileView(userID: item.actorID)
        }
    }

    private var avatar: some View {
        AvatarView(url: item.actorAvatarURL, name: item.actorName, size: 44)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: badgeSymbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
                    .background(badgeColor, in: Circle())
                    .overlay(Circle().strokeBorder(Color.hakiCardBackground, lineWidth: 2))
                    .offset(x: 3, y: 3)
                    .accessibilityHidden(true)
            }
    }

    private var badgeSymbol: String {
        switch item.kind {
        case .like: "heart.fill"
        case .comment: "bubble.right.fill"
        case .follow: "person.fill.badge.plus"
        }
    }

    private var badgeColor: Color {
        switch item.kind {
        case .like: Color.red
        case .comment: Color.accentColor
        case .follow: Color.hakiPositive
        }
    }

    @ViewBuilder private var thumbnail: some View {
        Group {
            if let url = item.postImageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        thumbnailPlaceholder
                    default:
                        ProgressView()
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var thumbnailPlaceholder: some View {
        ZStack {
            Color.accentColor.opacity(0.12)
            Image(systemName: "text.alignleft")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
    }

    /// "**Name** liked your post." with the name in bold.
    private var message: AttributedString {
        var name = AttributedString(item.actorName)
        name.inlinePresentationIntent = .stronglyEmphasized
        var text = name
        switch item.kind {
        case .like:
            text.append(AttributedString(" liked your post."))
        case .comment:
            let body = item.commentBody?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let suffix: String = body.isEmpty ? " commented on your post." : " commented: “\(body)”"
            text.append(AttributedString(suffix))
        case .follow:
            text.append(AttributedString(" started following you."))
        }
        return text
    }

    private var accessibilityText: String {
        let time = SocialTimeFormat.spoken(item.createdAt)
        switch item.kind {
        case .like:
            return "\(item.actorName) liked your post, \(time)"
        case .comment:
            return "\(item.actorName) commented: \(item.commentBody ?? ""), \(time)"
        case .follow:
            return "\(item.actorName) started following you, \(time)"
        }
    }
}

// MARK: - Post destination

/// Loads a post by id (from an activity item) and shows it.
struct ActivityPostDestinationView: View {
    let postID: UUID

    @Environment(SocialService.self) private var social
    @State private var post: FeedPost?
    @State private var phase: SocialLoadPhase = .idle

    var body: some View {
        Group {
            if let post {
                PostDetailView(post: post)
            } else {
                switch phase {
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Couldn't load the post", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try again") {
                            Task { await load() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                case .loaded:
                    ContentUnavailableView(
                        "Post unavailable",
                        systemImage: "rectangle.slash",
                        description: Text("This post was deleted.")
                    )
                case .idle, .loading:
                    ProgressView("Loading post…")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hakiBackground)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard phase == .idle else { return }
        await load()
    }

    private func load() async {
        phase = .loading
        if PostChangeCenter.shared.isDeleted(postID) {
            phase = .loaded
            return
        }
        do {
            post = try await social.post(id: postID)
            phase = .loaded
        } catch {
            phase = Backend.isCancellation(error) ? .idle : .failed(error.localizedDescription)
        }
    }
}

#Preview {
    NavigationStack {
        ActivityView()
    }
    .previewEnvironment()
}
