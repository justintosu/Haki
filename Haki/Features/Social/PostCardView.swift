//
//  PostCardView.swift
//  Haki
//
//  One post in a feed: author header, photo (double-tap to like), the trade
//  or portfolio block, caption with highlighted cashtags, ticker chips, and
//  like / comment buttons. Likes are optimistic and reverted on failure.
//

import Foundation
import SwiftUI
// `.bounce` (for `.symbolEffect`) is declared in Symbols; member import visibility needs it imported here.
import Symbols
import UIKit

struct PostCardView: View {
    let post: FeedPost
    /// Called with the updated post after a like or caption edit, or `nil` after it was deleted.
    let onChange: (FeedPost?) -> Void
    /// When set (on the post's own detail screen), the comment button calls
    /// this instead of opening the detail screen, and the caption isn't truncated.
    private let commentAction: (() -> Void)?

    @Environment(SocialService.self) private var social
    @Environment(AuthService.self) private var auth

    /// The card's own latest version, for parents that don't apply `onChange`.
    /// Cleared whenever the parent passes a new `post`.
    @State private var localPost: FeedPost?
    /// The like state the user wants that hasn't been confirmed by the server yet.
    @State private var desiredLike: Bool?
    @State private var likeInFlight = false
    @State private var likeFeedback = 0
    @State private var showsHeartBurst = false
    @State private var captionExpanded = false
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var isEditingCaption = false
    @State private var reportTarget: SocialReportTarget?
    @State private var blockTarget: SocialBlockTarget?
    @State private var errorMessage: String?

    init(post: FeedPost, onChange: @escaping (FeedPost?) -> Void, commentAction: (() -> Void)? = nil) {
        self.post = post
        self.onChange = onChange
        self.commentAction = commentAction
    }

    private var shown: FeedPost { localPost ?? post }
    private var isOwnPost: Bool { auth.userID == post.authorID }
    private var isDetail: Bool { commentAction != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            photo
            kindBlock
            caption
            tickerChips
            footer
        }
        .hakiCard()
        .overlay {
            if isDeleting {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.hakiCardBackground.opacity(0.7))
                    .overlay { ProgressView("Deleting…") }
            }
        }
        .disabled(isDeleting)
        .sensoryFeedback(.impact(weight: .light), trigger: likeFeedback)
        .confirmationDialog("Delete this post?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete post", role: .destructive) {
                Task { await deletePost() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It will be removed for everyone, with its likes and comments. This can't be undone.")
        }
        .sheet(isPresented: $isEditingCaption) {
            PostCaptionEditor(post: shown) { caption in
                // Onto the card's latest version, so a like made meanwhile isn't undone.
                var latest = shown
                latest.caption = caption
                apply(latest)
            }
        }
        .socialModeration(report: $reportTarget, block: $blockTarget)
        .socialErrorAlert($errorMessage)
        .onChange(of: post) { _, _ in
            localPost = nil
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            NavigationLink {
                ProfileView(userID: shown.authorID)
            } label: {
                HStack(spacing: 10) {
                    AvatarView(url: shown.authorAvatarURL, name: shown.authorName, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(shown.authorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Text(headerSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(headerAccessibilityLabel)
            .accessibilityHint("Opens their profile")

            Spacer(minLength: 8)
            moreMenu
        }
    }

    private var headerSubtitle: String {
        let age = SocialTimeFormat.short(shown.createdAt)
        return shown.authorUsername.isEmpty ? age : "@\(shown.authorUsername) · \(age)"
    }

    private var headerAccessibilityLabel: String {
        var parts = [shown.authorName]
        if !shown.authorUsername.isEmpty { parts.append("@\(shown.authorUsername)") }
        parts.append(SocialTimeFormat.spoken(shown.createdAt))
        return parts.joined(separator: ", ")
    }

    private var authorBlockTarget: SocialBlockTarget {
        SocialBlockTarget(userID: shown.authorID, username: shown.authorUsername)
    }

    private var moreMenu: some View {
        Menu {
            Button {
                UIPasteboard.general.string = shown.caption
            } label: {
                Label("Copy text", systemImage: "doc.on.doc")
            }
            .disabled(shown.caption.isEmpty)

            if isOwnPost {
                Button {
                    isEditingCaption = true
                } label: {
                    Label("Edit caption", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete post", systemImage: "trash")
                }
            } else {
                Section {
                    Button {
                        reportTarget = .post(shown)
                    } label: {
                        Label("Report post", systemImage: "flag")
                    }
                    Button(role: .destructive) {
                        blockTarget = authorBlockTarget
                    } label: {
                        Label("Block \(authorBlockTarget.handle)", systemImage: "hand.raised")
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More options")
    }

    // MARK: Media and attachments

    @ViewBuilder private var photo: some View {
        if let url = shown.imageURL {
            Color.hakiBackground
                .aspectRatio(4.0 / 5.0, contentMode: .fit)
                .overlay {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            VStack(spacing: 6) {
                                Image(systemName: "photo")
                                    .font(.title2)
                                Text("Couldn't load the photo")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        default:
                            ProgressView()
                        }
                    }
                }
                .overlay { heartBurst }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { likeFromDoubleTap() }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Photo")
                .accessibilityAddTraits(.isImage)
                .accessibilityAction(named: "Like") { likeFromDoubleTap() }
        }
    }

    @ViewBuilder private var kindBlock: some View {
        switch shown.kind {
        case .trade:
            if let side = shown.tradeSide, let ticker = shown.ticker {
                NavigationLink {
                    TickerFeedView(ticker: ticker)
                } label: {
                    PostTradeBadge(side: side, ticker: ticker)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows posts about \(ticker)")
            }
        case .portfolio:
            if let attachment = shown.attachment, !attachment.holdings.isEmpty {
                PostPortfolioAttachmentView(portfolio: attachment)
                    .overlay { heartBurst }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { likeFromDoubleTap() }
            }
        case .post:
            EmptyView()
        }
    }

    private var heartBurst: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 84))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            .scaleEffect(showsHeartBurst ? 1 : 0.3)
            .opacity(showsHeartBurst ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: Caption and tickers

    @ViewBuilder private var caption: some View {
        let text = shown.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let isLong = text.count > 280 || text.filter { $0 == "\n" }.count > 5
            let truncates = isLong && !captionExpanded && !isDetail
            VStack(alignment: .leading, spacing: 4) {
                Text(PostCaptionFormatter.attributed(text))
                    .font(.body)
                    .lineLimit(truncates ? 6 : nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if truncates {
                    Button("Show more") {
                        withAnimation(.snappy) { captionExpanded = true }
                    }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var tickerChips: some View {
        let tickers = PostCaptionFormatter.tickers(for: shown)
        if !tickers.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tickers, id: \.self) { ticker in
                        NavigationLink {
                            TickerFeedView(ticker: ticker)
                        } label: {
                            TickerChip(ticker: ticker, isVerifiedHolder: isVerifiedHolder(of: ticker))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Shows posts about \(ticker)")
                    }
                }
            }
        }
    }

    private func isVerifiedHolder(of ticker: String) -> Bool {
        shown.authorHoldsTicker && ticker == shown.ticker?.uppercased()
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 22) {
            Button {
                setLiked(!shown.likedByMe)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: shown.likedByMe ? "heart.fill" : "heart")
                        .font(.title3)
                        .foregroundStyle(shown.likedByMe ? Color.red : Color.primary)
                        .symbolEffect(.bounce, value: shown.likedByMe)
                    if shown.likeCount > 0 {
                        Text(PostCaptionFormatter.compactCount(shown.likeCount))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                }
                .frame(minHeight: 32)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(shown.likedByMe ? "Unlike" : "Like")
            .accessibilityValue(shown.likeCount == 1 ? "1 like" : "\(shown.likeCount) likes")

            commentButton

            Spacer()
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .animation(.snappy, value: shown.likeCount)
    }

    @ViewBuilder private var commentButton: some View {
        if let commentAction {
            Button(action: commentAction) { commentLabel }
                .accessibilityLabel("Add a comment")
                .accessibilityValue(commentCountText)
        } else {
            NavigationLink {
                PostDetailView(post: shown)
            } label: {
                commentLabel
            }
            .accessibilityLabel("Comments")
            .accessibilityValue(commentCountText)
        }
    }

    private var commentLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "bubble.right")
                .font(.title3)
            if shown.commentCount > 0 {
                Text(PostCaptionFormatter.compactCount(shown.commentCount))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
    }

    private var commentCountText: String {
        shown.commentCount == 1 ? "1 comment" : "\(shown.commentCount) comments"
    }

    // MARK: Actions

    private func apply(_ updated: FeedPost) {
        localPost = updated
        PostChangeCenter.shared.update(updated)
        onChange(updated)
    }

    private func likeFromDoubleTap() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
            showsHeartBurst = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeOut(duration: 0.25)) {
                showsHeartBurst = false
            }
        }
        if !shown.likedByMe {
            setLiked(true)
        }
    }

    /// Optimistic: updates the card right away, then tells the server. Taps
    /// while a request is in flight are coalesced into one follow-up request.
    private func setLiked(_ liked: Bool) {
        let current = shown
        guard current.likedByMe != liked else { return }
        apply(Self.withLike(current, liked))
        if liked { likeFeedback += 1 }
        desiredLike = liked
        guard !likeInFlight else { return }
        likeInFlight = true
        let confirmed = current.likedByMe
        Task { await sendLikes(confirmed: confirmed) }
    }

    private func sendLikes(confirmed: Bool) async {
        var confirmed = confirmed
        while let desired = desiredLike, desired != confirmed {
            do {
                try await social.setLiked(desired, postID: post.id)
                confirmed = desired
            } catch {
                desiredLike = nil
                likeInFlight = false
                // Back to what the server last confirmed.
                apply(Self.withLike(shown, confirmed))
                if !Backend.isCancellation(error) {
                    errorMessage = error.localizedDescription
                }
                return
            }
        }
        desiredLike = nil
        likeInFlight = false
    }

    private static func withLike(_ post: FeedPost, _ liked: Bool) -> FeedPost {
        guard post.likedByMe != liked else { return post }
        var copy = post
        copy.likedByMe = liked
        copy.likeCount = max(0, copy.likeCount + (liked ? 1 : -1))
        return copy
    }

    private func deletePost() async {
        let target = shown
        isDeleting = true
        do {
            try await social.deletePost(target)
            isDeleting = false
            PostChangeCenter.shared.delete(target.id)
            onChange(nil)
        } catch {
            isDeleting = false
            if !Backend.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Caption editor

/// Sheet for editing a post's caption (the only editable part of a post).
private struct PostCaptionEditor: View {
    let post: FeedPost
    /// Called with the saved caption.
    let onSaved: (String) -> Void

    @Environment(SocialService.self) private var social
    @Environment(\.dismiss) private var dismiss
    @State private var caption: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    init(post: FeedPost, onSaved: @escaping (String) -> Void) {
        self.post = post
        self.onSaved = onSaved
        _caption = State(initialValue: post.caption)
    }

    private var trimmed: String {
        caption.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var length: Int { PostCaptionFormatter.length(of: trimmed) }

    private var canSave: Bool {
        guard !isSaving, trimmed != post.caption.trimmingCharacters(in: .whitespacesAndNewlines), length <= 2200 else {
            return false
        }
        // A post needs a caption unless it has a photo or a portfolio.
        return !trimmed.isEmpty || post.imagePath != nil || post.attachment != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Write a caption…", text: $caption, axis: .vertical)
                        .lineLimit(4...12)
                        .focused($isFocused)
                } footer: {
                    HStack {
                        Text("Use $ before a ticker to tag it, like $AAPL.")
                        Spacer()
                        Text("\(length)/2,200")
                            .monospacedDigit()
                            .foregroundStyle(length > 2200 ? Color.hakiNegative : Color.secondary)
                    }
                }
            }
            .navigationTitle("Edit caption")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await save() }
                        }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .socialErrorAlert($errorMessage)
            .onAppear { isFocused = true }
        }
    }

    private func save() async {
        let text = trimmed
        isSaving = true
        do {
            try await social.updateCaption(postID: post.id, caption: text)
            isSaving = false
            onSaved(text)
            dismiss()
        } catch {
            isSaving = false
            if !Backend.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview("Cards") {
    NavigationStack {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Array(SocialPreviewData.posts.prefix(4))) { post in
                    PostCardView(post: post) { _ in }
                }
            }
            .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
