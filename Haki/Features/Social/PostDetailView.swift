//
//  PostDetailView.swift
//  Haki
//
//  A post with its comments and a comment composer pinned to the bottom.
//  Long-press a comment to copy it, or to delete it if it's yours or it's on
//  your post.
//

import Foundation
import SwiftUI
import UIKit

struct PostDetailView: View {
    @Environment(SocialService.self) private var social
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var post: FeedPost
    @State private var isUnavailable = false
    @State private var hasAppeared = false
    @State private var comments: [PostComment] = []
    @State private var commentsPhase: SocialLoadPhase = .idle
    @State private var draft = ""
    @State private var isSending = false
    @State private var sentCount = 0
    @State private var scrollTarget: UUID?
    @State private var reportTarget: SocialReportTarget?
    @State private var blockTarget: SocialBlockTarget?
    @State private var errorMessage: String?
    @FocusState private var composerFocused: Bool

    init(post: FeedPost) {
        _post = State(initialValue: post)
    }

    var body: some View {
        Group {
            if isUnavailable {
                ContentUnavailableView(
                    "Post unavailable",
                    systemImage: "rectangle.slash",
                    description: Text("This post was deleted.")
                )
            } else if isAuthorBlocked {
                blockedAuthorView
            } else {
                content
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hakiBackground)
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadIfNeeded()
        }
        .onAppear {
            syncWithChangesMadeElsewhere()
        }
        .sensoryFeedback(.success, trigger: sentCount)
        .socialModeration(report: $reportTarget, block: $blockTarget)
        .socialErrorAlert($errorMessage)
    }

    private var isAuthorBlocked: Bool {
        post.authorID != auth.userID && SocialBlockList.shared.isBlocked(post.authorID)
    }

    private var blockedAuthorView: some View {
        let handle = SocialBlockTarget(userID: post.authorID, username: post.authorUsername).handle
        return ContentUnavailableView {
            Label("You blocked \(handle)", systemImage: "hand.raised")
        } description: {
            Text("Unblock them to see their posts and comments again.")
        } actions: {
            Button("Unblock") {
                Task { await SocialBlockList.shared.unblock(post.authorID, social: social) }
            }
            .buttonStyle(.bordered)
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    PostCardView(post: post, onChange: handleCardChange, commentAction: { composerFocused = true })
                    commentsHeader
                    commentsContent
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await Task { await load() }.value
            }
            .onChange(of: scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(.snappy) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerBar
        }
    }

    // MARK: Comments

    private var commentsHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Comments")
                .font(.headline)
            if post.commentCount > 0 {
                Text(PostCaptionFormatter.compactCount(post.commentCount))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// The comments, without those by people you blocked.
    private var visibleComments: [PostComment] {
        let blockList = SocialBlockList.shared
        return comments.filter { !blockList.isBlocked($0.authorID) }
    }

    @ViewBuilder private var commentsContent: some View {
        let visible = visibleComments
        switch commentsPhase {
        case .idle, .loading:
            ProgressView("Loading comments…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        case .failed(let message):
            VStack(spacing: 10) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await loadComments() }
                }
                .buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        case .loaded:
            if visible.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No comments yet")
                        .font(.headline)
                    Text("Start the conversation.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Add a comment") { composerFocused = true }
                        .font(.subheadline.weight(.semibold))
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityElement(children: .combine)
            } else {
                ForEach(visible) { comment in
                    PostCommentRow(
                        comment: comment,
                        isByPostAuthor: comment.authorID == post.authorID,
                        canDelete: canDelete(comment),
                        canReport: canReport(comment),
                        onDelete: { Task { await delete(comment) } },
                        onReport: { reportTarget = .comment(comment) },
                        onBlock: { blockTarget = SocialBlockTarget(userID: comment.authorID, username: comment.authorUsername) }
                    )
                    .id(comment.id)
                }
            }
        }
    }

    private func canDelete(_ comment: PostComment) -> Bool {
        guard let me = auth.userID else { return false }
        return comment.authorID == me || post.authorID == me
    }

    /// Someone else's comment.
    private func canReport(_ comment: PostComment) -> Bool {
        guard let me = auth.userID else { return false }
        return comment.authorID != me
    }

    // MARK: Composer

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var draftLength: Int { PostCaptionFormatter.length(of: trimmedDraft) }

    private var canSend: Bool {
        !isSending && !trimmedDraft.isEmpty && draftLength <= 1000
    }

    private var composerBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                AvatarView(url: auth.profile?.avatarURL, name: auth.profile?.name ?? "", size: 34)
                    .padding(.bottom, 2)
                VStack(alignment: .trailing, spacing: 2) {
                    TextField("Add a comment…", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .focused($composerFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.hakiBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    if draftLength > 900 {
                        Text("\(draftLength)/1,000")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(draftLength > 1000 ? Color.hakiNegative : Color.secondary)
                    }
                }
                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
                        }
                    }
                    .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel("Send comment")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color.hakiCardBackground)
    }

    // MARK: Loading and actions

    private func loadIfNeeded() async {
        PostChangeCenter.shared.prepare(for: auth.userID)
        guard commentsPhase == .idle else { return }
        if PostChangeCenter.shared.isDeleted(post.id) {
            isUnavailable = true
            return
        }
        await load()
    }

    /// Coming back from a screen pushed on top (a profile, a ticker feed) that
    /// may have liked, commented on or deleted this same post.
    private func syncWithChangesMadeElsewhere() {
        guard hasAppeared else {
            hasAppeared = true
            return
        }
        let center = PostChangeCenter.shared
        if center.isDeleted(post.id) {
            isUnavailable = true
        } else if let latest = center.changes[post.id]?.post, latest != post {
            let commentsChanged = latest.commentCount != post.commentCount
            post = latest
            if commentsChanged {
                Task { await loadComments() }
            }
        }
    }

    private func load() async {
        async let refresh: Void = refreshPost()
        await loadComments()
        await refresh
    }

    private func refreshPost() async {
        let center = PostChangeCenter.shared
        let revisionBeforeFetch = center.revision
        do {
            if let fresh = try await social.post(id: post.id) {
                // A like, comment or edit made while the request was out is newer
                // than the server's copy (read before it landed): keep it.
                if let change = center.changes[fresh.id], change.revision > revisionBeforeFetch {
                    return
                }
                post = fresh
                center.update(fresh)
            } else {
                isUnavailable = true
                PostChangeCenter.shared.delete(post.id)
            }
        } catch {
            // Keep showing the copy we have; the comments' state reports problems.
        }
    }

    private func loadComments() async {
        if comments.isEmpty {
            commentsPhase = .loading
        }
        do {
            comments = try await social.comments(postID: post.id)
            commentsPhase = .loaded
        } catch {
            if Backend.isCancellation(error) {
                if commentsPhase == .loading { commentsPhase = .idle }
                return
            }
            if comments.isEmpty {
                commentsPhase = .failed(error.localizedDescription)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func send() async {
        let text = trimmedDraft
        guard canSend else { return }
        isSending = true
        do {
            let created = try await social.addComment(postID: post.id, body: text)
            comments.append(withAuthorFallback(created))
            commentsPhase = .loaded
            draft = ""
            post.commentCount += 1
            PostChangeCenter.shared.update(post)
            sentCount += 1
            scrollTarget = created.id
        } catch {
            if !Backend.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
        isSending = false
    }

    /// Fills in the author from the signed-in profile if the server returned a bare row.
    private func withAuthorFallback(_ comment: PostComment) -> PostComment {
        guard comment.authorUsername.isEmpty, let profile = auth.profile else { return comment }
        return PostComment(
            id: comment.id,
            postID: comment.postID,
            authorID: comment.authorID,
            body: comment.body,
            createdAt: comment.createdAt,
            authorUsername: profile.username,
            authorDisplayName: profile.displayName,
            authorAvatarPath: profile.avatarPath
        )
    }

    private func delete(_ comment: PostComment) async {
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        comments.remove(at: index)
        post.commentCount = max(0, post.commentCount - 1)
        PostChangeCenter.shared.update(post)
        do {
            try await social.deleteComment(comment)
        } catch {
            comments.insert(comment, at: min(index, comments.count))
            post.commentCount += 1
            PostChangeCenter.shared.update(post)
            if !Backend.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleCardChange(_ updated: FeedPost?) {
        if let updated {
            post = updated
        } else {
            dismiss()
        }
    }
}

// MARK: - Comment row

private struct PostCommentRow: View {
    let comment: PostComment
    let isByPostAuthor: Bool
    let canDelete: Bool
    /// Someone else's comment: offer Report and Block.
    let canReport: Bool
    let onDelete: () -> Void
    let onReport: () -> Void
    let onBlock: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            NavigationLink {
                ProfileView(userID: comment.authorID)
            } label: {
                AvatarView(url: comment.authorAvatarURL, name: comment.authorName, size: 34)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(comment.authorName)'s profile")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if isByPostAuthor {
                        Text("Author")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                    Text(SocialTimeFormat.short(comment.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(PostCaptionFormatter.attributed(comment.body))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                UIPasteboard.general.string = comment.body
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete comment", systemImage: "trash")
                }
            }
            if canReport {
                Section {
                    Button(action: onReport) {
                        Label("Report comment", systemImage: "flag")
                    }
                    Button(role: .destructive, action: onBlock) {
                        Label("Block \(authorHandle)", systemImage: "hand.raised")
                    }
                }
            }
        }
        .accessibilityActions {
            if canDelete {
                Button("Delete comment", action: onDelete)
            }
            if canReport {
                Button("Report comment", action: onReport)
                Button("Block \(authorHandle)", action: onBlock)
            }
        }
    }

    private var authorHandle: String {
        SocialBlockTarget(userID: comment.authorID, username: comment.authorUsername).handle
    }

    private var accessibilityText: String {
        let author = isByPostAuthor ? "\(comment.authorName), author" : comment.authorName
        return "\(author), \(SocialTimeFormat.spoken(comment.createdAt)): \(comment.body)"
    }
}

#Preview("Post with comments") {
    NavigationStack {
        if let post = SocialPreviewData.posts.first {
            PostDetailView(post: post)
        }
    }
    .previewEnvironment()
}

#Preview("Portfolio post") {
    NavigationStack {
        if let post = SocialPreviewData.posts.first(where: { $0.kind == .portfolio }) {
            PostDetailView(post: post)
        }
    }
    .previewEnvironment()
}
