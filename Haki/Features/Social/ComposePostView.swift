//
//  ComposePostView.swift
//  Haki
//
//  The "New post" sheet: a regular post (caption and photo), a trade
//  ("Bought $AAPL") or a percentages-only snapshot of your portfolio.
//

import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct ComposePostView: View {
    @Environment(SocialService.self) private var social
    @Environment(PortfolioService.self) private var portfolio
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var kind: PostKind
    @State private var caption: String
    @State private var imageJPEG: Data?
    @State private var previewImage: UIImage?
    @State private var tickerText: String
    @State private var tradeSide: TradeSide
    @State private var prefillAttachment: SharedPortfolio?
    @State private var photoItem: PhotosPickerItem?
    @State private var isLoadingPhoto = false
    @State private var isPosting = false
    @State private var postedCount = 0
    @State private var confirmingDiscard = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: ComposeField?

    private let initialCaption: String

    init(prefill: PostDraft? = nil) {
        let draft = prefill ?? PostDraft()
        initialCaption = draft.caption
        _kind = State(initialValue: draft.kind)
        _caption = State(initialValue: draft.caption)
        _imageJPEG = State(initialValue: draft.imageJPEG)
        _previewImage = State(initialValue: draft.imageJPEG.flatMap { UIImage(data: $0) })
        _tickerText = State(initialValue: ComposeTickerInput.clean(draft.ticker ?? ""))
        _tradeSide = State(initialValue: draft.tradeSide ?? .buy)
        _prefillAttachment = State(initialValue: draft.attachment)
    }

    var body: some View {
        NavigationStack {
            Form {
                authorSection
                kindSection
                switch kind {
                case .post:
                    captionSection
                    photoSection
                case .trade:
                    tradeSection
                    captionSection
                    photoSection
                case .portfolio:
                    portfolioSection
                    captionSection
                }
            }
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            // Swiping down mustn't throw away a draft; Cancel asks first.
            .interactiveDismissDisabled(isPosting || hasUnsavedContent)
            .disabled(isPosting)
            .task {
                await loadPortfolioIfNeeded()
            }
            .task {
                await focusInitialField()
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task { await loadPhoto(newItem) }
            }
            .onChange(of: tickerText) { _, newValue in
                let cleaned = ComposeTickerInput.clean(newValue)
                if cleaned != newValue {
                    tickerText = cleaned
                }
            }
            .onChange(of: kind) { _, newKind in
                if newKind == .trade, tickerText.isEmpty {
                    focusedField = .ticker
                }
            }
            .confirmationDialog("Discard this post?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep editing", role: .cancel) {}
            }
            .sensoryFeedback(.success, trigger: postedCount)
            .socialErrorAlert($errorMessage)
        }
    }

    // MARK: Draft

    /// What gets posted: only the parts that belong to the selected kind.
    private var draft: PostDraft {
        var draft = PostDraft(kind: kind, caption: caption)
        switch kind {
        case .post:
            draft.imageJPEG = imageJPEG
        case .trade:
            draft.imageJPEG = imageJPEG
            draft.ticker = tickerText.isEmpty ? nil : tickerText
            draft.tradeSide = tradeSide
        case .portfolio:
            draft.attachment = sharedPortfolio
        }
        return draft
    }

    /// Your live portfolio as percentages (the top 5 plus "Other").
    private var sharedPortfolio: SharedPortfolio? {
        portfolio.hasConnections ? portfolio.sharedPortfolio(limit: 5) : prefillAttachment
    }

    private var captionLength: Int { PostCaptionFormatter.length(of: caption) }

    private var hasUnsavedContent: Bool {
        caption.trimmingCharacters(in: .whitespacesAndNewlines) != initialCaption.trimmingCharacters(in: .whitespacesAndNewlines)
            || imageJPEG != nil
    }

    // MARK: Sections

    @ViewBuilder private var authorSection: some View {
        if let profile = auth.profile {
            Section {
                HStack(spacing: 12) {
                    AvatarView(url: profile.avatarURL, name: profile.name, size: 40)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(profile.name)
                            .font(.subheadline.weight(.semibold))
                        Text("@" + profile.username)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Posting as \(profile.name)")
            }
        }
    }

    private var kindSection: some View {
        Section {
            Picker("Kind of post", selection: $kind) {
                ForEach(PostKind.allCases, id: \.self) { kind in
                    Text(ComposeKindText.title(for: kind)).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        } footer: {
            Text(ComposeKindText.explanation(for: kind))
        }
    }

    private var captionSection: some View {
        Section {
            TextField(ComposeKindText.captionPrompt(for: kind), text: $caption, axis: .vertical)
                .lineLimit(3...10)
                .focused($focusedField, equals: .caption)
        } header: {
            Text("Caption")
        } footer: {
            captionFooter
        }
    }

    private var captionFooter: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(captionHint)
            Spacer(minLength: 8)
            Text("\(captionLength)/2,200")
                .monospacedDigit()
                .foregroundStyle(captionLength > 2200 ? Color.hakiNegative : Color.secondary)
                .accessibilityLabel("\(captionLength) of 2,200 characters")
        }
    }

    private var captionHint: String {
        let isEmpty = caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if kind == .trade, isEmpty, imageJPEG == nil {
            return "Add a few words or a photo to share this trade."
        }
        let tags: [String] = Cashtags.extract(from: caption).filter { Cashtags.isValidTicker($0) }
        guard !tags.isEmpty else { return "Use $ before a ticker to tag it, like $AAPL." }
        let list: String = tags.map { "$" + $0 }.joined(separator: ", ")
        return "Tagged: " + list
    }

    @ViewBuilder private var photoSection: some View {
        Section {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    // On the photo itself, so the remove button keeps its own label.
                    .accessibilityLabel("Selected photo")
                    .overlay(alignment: .topTrailing) {
                        Button {
                            removePhoto()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.white, Color.black.opacity(0.55))
                                .padding(8)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove photo")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            }
            if isLoadingPhoto {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing photo…")
                        .foregroundStyle(.secondary)
                }
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(previewImage == nil ? "Add a photo" : "Choose a different photo", systemImage: "photo.on.rectangle")
            }
            .disabled(isLoadingPhoto)
        } header: {
            Text(kind == .trade ? "Photo (optional)" : "Photo")
        }
    }

    /// Your holdings with a usable ticker, for one-tap picking.
    private var pickablePositions: [PortfolioPosition] {
        Array(portfolio.positions.filter { !$0.isCash && Cashtags.isValidTicker($0.symbol) }.prefix(10))
    }

    @ViewBuilder private var tradeSection: some View {
        let positions = pickablePositions
        Section {
            HStack {
                Text("$")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Ticker, like AAPL", text: $tickerText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .ticker)
                    .accessibilityLabel("Ticker")
            }
            Picker("Side", selection: $tradeSide) {
                Text("Buy").tag(TradeSide.buy)
                Text("Sell").tag(TradeSide.sell)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Buy or sell")

            if !positions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(positions) { position in
                            Button {
                                tickerText = position.symbol
                            } label: {
                                TickerChip(ticker: position.symbol)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Use \(position.symbol)")
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        } header: {
            Text("Trade")
        } footer: {
            tradeFooter
        }
    }

    @ViewBuilder private var tradeFooter: some View {
        if !tickerText.isEmpty, !Cashtags.isValidTicker(tickerText) {
            Label("Tickers start with a letter, like AAPL or BRK.B.", systemImage: "exclamationmark.circle")
                .foregroundStyle(Color.hakiNegative)
        } else if !tickerText.isEmpty, let position = portfolio.position(for: tickerText) {
            Label(holdingText(for: position), systemImage: "checkmark.seal.fill")
                .foregroundStyle(Color.accentColor)
        } else if !pickablePositions.isEmpty {
            Text("Tap one of your holdings, or type any ticker.")
        } else {
            Text("Share what you bought or sold. Only the ticker is shown — never amounts.")
        }
    }

    private func holdingText(for position: PortfolioPosition) -> String {
        let weight: String = position.weightPct.formatted(.number.precision(.fractionLength(1)))
        return "You hold this · \(weight)% of your portfolio"
    }

    @ViewBuilder private var portfolioSection: some View {
        if let shared = sharedPortfolio, !shared.holdings.isEmpty {
            Section {
                PostPortfolioAttachmentView(portfolio: shared)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            } header: {
                Text("Preview")
            } footer: {
                Text("When you post, Haki fills in these percentages from your connected brokerage, so they always match what you hold. Only percentages and your total return are shared — never amounts, share counts or account details. Your top 5 positions are shown; the rest are grouped as Other.")
            }
        } else if portfolio.isLoading || (portfolio.lastLoaded == nil && portfolio.errorMessage == nil) {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading your portfolio…")
                        .foregroundStyle(.secondary)
                }
            }
        } else if let message = portfolio.errorMessage, !portfolio.hasConnections {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Couldn't load your portfolio", systemImage: "wifi.exclamationmark")
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        Task { await portfolio.refresh() }
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 6)
            }
        } else if portfolio.hasConnections {
            Section {
                ContentUnavailableView(
                    "Nothing to share yet",
                    systemImage: "chart.pie",
                    description: Text("Your connected accounts don't hold any investments yet. Once they do, you can share them as percentages.")
                )
            }
        } else {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Connect a brokerage first", systemImage: "link")
                        .font(.headline)
                    Text("Haki reads your holdings through a secure, read-only connection, then shares only percentages — never amounts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    BrokerageLinkButton()
                }
                .padding(.vertical, 6)
            }
        }
    }

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if hasUnsavedContent {
                    confirmingDiscard = true
                } else {
                    dismiss()
                }
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if isPosting {
                ProgressView()
                    .accessibilityLabel("Posting")
            } else {
                Button("Post") {
                    Task { await submit() }
                }
                .fontWeight(.semibold)
                .disabled(!draft.isPostable || isLoadingPhoto)
            }
        }
    }

    // MARK: Actions

    /// Brings up the keyboard once the sheet has settled (not for a portfolio,
    /// where it would cover the preview).
    private func focusInitialField() async {
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled, focusedField == nil else { return }
        switch kind {
        case .post:
            focusedField = .caption
        case .trade:
            focusedField = tickerText.isEmpty ? .ticker : .caption
        case .portfolio:
            break
        }
    }

    /// The trade and portfolio options need your holdings.
    private func loadPortfolioIfNeeded() async {
        guard portfolio.lastLoaded == nil, !portfolio.isLoading else { return }
        await portfolio.refresh()
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Couldn't read that photo. Try another one."
                return
            }
            guard let jpeg = await ImageUpload.makeJPEG(from: data, maxDimension: 1440, quality: 0.8) else {
                errorMessage = "That file isn't a photo Haki can use."
                return
            }
            // The photo was removed (or replaced) while it was being prepared.
            guard photoItem == item else { return }
            imageJPEG = jpeg
            previewImage = UIImage(data: jpeg)
        } catch {
            if !Backend.isCancellation(error) {
                errorMessage = "Couldn't load that photo. Try another one."
            }
        }
    }

    /// `createPost` falls back to the bare row (no author name or photo) when
    /// the feed view can't be read right after posting; fill those in from
    /// your profile so the post doesn't appear nameless until the next refresh.
    private func withAuthorFallback(_ post: FeedPost) -> FeedPost {
        guard post.authorUsername.isEmpty, let profile = auth.profile, profile.id == post.authorID else {
            return post
        }
        return FeedPost(
            id: post.id,
            authorID: post.authorID,
            kind: post.kind,
            caption: post.caption,
            imagePath: post.imagePath,
            ticker: post.ticker,
            tradeSide: post.tradeSide,
            attachment: post.attachment,
            likeCount: post.likeCount,
            commentCount: post.commentCount,
            createdAt: post.createdAt,
            authorUsername: profile.username,
            authorDisplayName: profile.displayName,
            authorAvatarPath: profile.avatarPath,
            likedByMe: post.likedByMe,
            authorHoldsTicker: post.authorHoldsTicker
        )
    }

    private func removePhoto() {
        imageJPEG = nil
        previewImage = nil
        photoItem = nil
    }

    private func submit() async {
        let draft = self.draft
        guard draft.isPostable, !isPosting else { return }
        focusedField = nil
        isPosting = true
        do {
            let post = try await social.createPost(draft)
            PostChangeCenter.shared.add(withAuthorFallback(post))
            postedCount += 1
            isPosting = false
            dismiss()
        } catch {
            isPosting = false
            if !Backend.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Helpers

private nonisolated enum ComposeField: Hashable {
    case caption
    case ticker
}

/// Keeps the ticker field to what a symbol can contain: uppercase letters,
/// digits, "." and "-", at most 10 characters.
private nonisolated enum ComposeTickerInput {
    static func clean(_ text: String) -> String {
        let allowed = text.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        return String(allowed.prefix(10))
    }
}

private nonisolated enum ComposeKindText {
    static func title(for kind: PostKind) -> String {
        switch kind {
        case .post: "Post"
        case .trade: "Trade"
        case .portfolio: "Portfolio"
        }
    }

    static func explanation(for kind: PostKind) -> String {
        switch kind {
        case .post: "Share a thought, a question or a photo."
        case .trade: "Tell people what you bought or sold."
        case .portfolio: "Show how your portfolio is split, in percentages."
        }
    }

    static func captionPrompt(for kind: PostKind) -> String {
        switch kind {
        case .post: "What's on your mind?"
        case .trade: "Why did you make this trade?"
        case .portfolio: "Say something about your portfolio…"
        }
    }
}

#Preview("New post") {
    ComposePostView()
        .previewEnvironment()
}

#Preview("Trade") {
    ComposePostView(prefill: PostDraft(kind: .trade, ticker: "AAPL", tradeSide: .buy))
        .previewEnvironment()
}

#Preview("Portfolio") {
    ComposePostView(prefill: PostDraft(kind: .portfolio, attachment: PortfolioService.preview.sharedPortfolio(limit: 5)))
        .previewEnvironment()
}
