//
//  SocialModeration.swift
//  Haki
//
//  Reporting posts, comments and people, and blocking people.
//
//  Blocking hides the person's posts, comments and activity everywhere in
//  the app right away and unfollows them. The block list is kept on this
//  device for each account, and mirrored to the server's `blocks` table so
//  the server can enforce it too. Reports go to the `reports` table, which
//  Haki's team reviews.
//

import Foundation
import Observation
import Supabase
import SwiftUI

// MARK: - Block list

/// The people the signed-in user blocked. Lists read it while they render
/// (`isBlocked`), so blocking someone hides their content on every screen.
@Observable final class SocialBlockList {
    static let shared = SocialBlockList()

    private(set) var blockedIDs: Set<UUID> = []

    @ObservationIgnored private var ownerID: UUID?

    /// Loads the list saved for `userID` when a different account signs in.
    func prepare(for userID: UUID?) {
        guard ownerID != userID else { return }
        ownerID = userID
        guard let userID else {
            blockedIDs = []
            return
        }
        let saved = UserDefaults.standard.stringArray(forKey: Self.storageKey(for: userID)) ?? []
        blockedIDs = Set(saved.compactMap { UUID(uuidString: $0) })
    }

    func isBlocked(_ userID: UUID) -> Bool {
        blockedIDs.contains(userID)
    }

    /// Hides the person's content right away, then unfollows them and tells
    /// the server (best effort: the block holds on this device either way).
    func block(_ userID: UUID, social: SocialService) async {
        guard !blockedIDs.contains(userID) else { return }
        blockedIDs.insert(userID)
        save()
        try? await social.setFollowing(false, userID: userID)
        await SocialModerationAPI.setBlocked(true, userID: userID, social: social)
    }

    func unblock(_ userID: UUID, social: SocialService) async {
        guard blockedIDs.contains(userID) else { return }
        blockedIDs.remove(userID)
        save()
        await SocialModerationAPI.setBlocked(false, userID: userID, social: social)
    }

    private func save() {
        guard let ownerID else { return }
        UserDefaults.standard.set(blockedIDs.map(\.uuidString), forKey: Self.storageKey(for: ownerID))
    }

    private static func storageKey(for userID: UUID) -> String {
        "social.blockedUsers." + userID.uuidString.lowercased()
    }
}

// MARK: - Targets

nonisolated enum SocialReportKind: Hashable {
    case post
    case comment
    case profile
}

/// What's being reported: a post, a comment or a profile, and whose it is.
nonisolated struct SocialReportTarget: Identifiable, Hashable {
    let kind: SocialReportKind
    /// The person who posted it (or whose profile it is).
    let userID: UUID
    let username: String
    let postID: UUID?
    let commentID: UUID?

    var id: String {
        switch kind {
        case .post: "post-" + (postID?.uuidString ?? "")
        case .comment: "comment-" + (commentID?.uuidString ?? "")
        case .profile: "profile-" + userID.uuidString
        }
    }

    static func post(_ post: FeedPost) -> SocialReportTarget {
        SocialReportTarget(kind: .post, userID: post.authorID, username: post.authorUsername, postID: post.id, commentID: nil)
    }

    static func comment(_ comment: PostComment) -> SocialReportTarget {
        SocialReportTarget(
            kind: .comment,
            userID: comment.authorID,
            username: comment.authorUsername,
            postID: comment.postID,
            commentID: comment.id
        )
    }

    static func profile(userID: UUID, username: String) -> SocialReportTarget {
        SocialReportTarget(kind: .profile, userID: userID, username: username, postID: nil, commentID: nil)
    }

    var dialogTitle: String {
        switch kind {
        case .post: "Report this post"
        case .comment: "Report this comment"
        case .profile: username.isEmpty ? "Report this account" : "Report @\(username)"
        }
    }

    var blockTarget: SocialBlockTarget {
        SocialBlockTarget(userID: userID, username: username)
    }
}

/// Someone to block.
nonisolated struct SocialBlockTarget: Identifiable, Hashable {
    let userID: UUID
    let username: String

    var id: UUID { userID }

    /// "@dan" or "this person".
    var handle: String {
        username.isEmpty ? "this person" : "@" + username
    }
}

/// Why something is being reported. The raw value is what the server stores.
nonisolated enum SocialReportReason: String, CaseIterable, Identifiable {
    case spam
    case harassment
    case hate
    case scam
    case sexual
    case violence
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harassment or bullying"
        case .hate: "Hate speech or symbols"
        case .scam: "Scam or fraud"
        case .sexual: "Nudity or sexual content"
        case .violence: "Violence or self-harm"
        case .other: "Something else"
        }
    }
}

// MARK: - Dialogs

extension View {
    /// The report and block flows: set `report` to show the report reasons,
    /// `block` to confirm blocking someone.
    func socialModeration(report: Binding<SocialReportTarget?>, block: Binding<SocialBlockTarget?>) -> some View {
        modifier(SocialModerationDialogs(report: report, block: block))
    }
}

private struct SocialModerationDialogs: ViewModifier {
    @Binding var report: SocialReportTarget?
    @Binding var block: SocialBlockTarget?

    @Environment(SocialService.self) private var social

    /// The report that was just sent, for the thank-you alert.
    @State private var sentReport: SocialReportTarget?
    @State private var sentFeedback = 0
    @State private var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                report?.dialogTitle ?? "Report",
                isPresented: isPresenting($report),
                titleVisibility: .visible,
                presenting: report
            ) { target in
                ForEach(SocialReportReason.allCases) { reason in
                    Button(reason.title) {
                        Task { await send(target, reason: reason) }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Why are you reporting this? Haki's team reviews every report. The person won't know who reported them.")
            }
            .confirmationDialog(
                "Block \(block?.handle ?? "this person")?",
                isPresented: isPresenting($block),
                titleVisibility: .visible,
                presenting: block
            ) { target in
                Button("Block", role: .destructive) {
                    Task { await SocialBlockList.shared.block(target.userID, social: social) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("You won't see their posts, comments or activity, and you'll stop following them. You can unblock them from their profile.")
            }
            .alert(
                "Thanks for letting us know",
                isPresented: isPresenting($sentReport),
                presenting: sentReport
            ) { target in
                if !SocialBlockList.shared.isBlocked(target.userID) {
                    Button("Block \(target.blockTarget.handle)", role: .destructive) {
                        Task { await SocialBlockList.shared.block(target.userID, social: social) }
                    }
                }
                Button("Done", role: .cancel) {}
            } message: { _ in
                Text("We'll review your report and take action if it breaks Haki's community guidelines.")
            }
            .sensoryFeedback(.success, trigger: sentFeedback)
            .socialErrorAlert($errorMessage)
    }

    private func send(_ target: SocialReportTarget, reason: SocialReportReason) async {
        do {
            try await SocialModerationAPI.report(target, reason: reason, social: social)
            sentFeedback += 1
            sentReport = target
        } catch {
            if !Backend.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func isPresenting<Value>(_ value: Binding<Value?>) -> Binding<Bool> {
        Binding(
            get: { value.wrappedValue != nil },
            set: { if !$0 { value.wrappedValue = nil } }
        )
    }
}

// MARK: - Server calls

/// The `reports` and `blocks` tables. Preview mode (`SocialService.preview`)
/// never touches the network.
private enum SocialModerationAPI {
    static func report(_ target: SocialReportTarget, reason: SocialReportReason, social: SocialService) async throws {
        guard social !== SocialService.preview else { return }
        let client = Backend.client
        guard client.auth.currentUser != nil else { throw AuthServiceError.notSignedIn }
        let row = SocialReportInsert(
            reportedUserID: target.userID,
            postID: target.postID,
            commentID: target.commentID,
            reason: reason.rawValue
        )
        do {
            try await client.from("reports").insert(row, returning: .minimal).execute()
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't send your report. Try again.")
        }
    }

    /// Best effort: the block already holds on this device.
    static func setBlocked(_ blocked: Bool, userID: UUID, social: SocialService) async {
        guard social !== SocialService.preview else { return }
        let client = Backend.client
        guard let uid = client.auth.currentUser?.id, uid != userID else { return }
        if blocked {
            _ = try? await client.from("blocks").insert(SocialBlockInsert(blockedID: userID), returning: .minimal).execute()
        } else {
            _ = try? await client
                .from("blocks")
                .delete(returning: .minimal)
                .eq("blocker_id", value: uid)
                .eq("blocked_id", value: userID)
                .execute()
        }
    }
}

nonisolated private struct SocialReportInsert: Encodable {
    let reportedUserID: UUID
    let postID: UUID?
    let commentID: UUID?
    let reason: String

    enum CodingKeys: String, CodingKey {
        case reportedUserID = "reported_user_id"
        case postID = "post_id"
        case commentID = "comment_id"
        case reason
    }
}

nonisolated private struct SocialBlockInsert: Encodable {
    let blockedID: UUID

    enum CodingKeys: String, CodingKey {
        case blockedID = "blocked_id"
    }
}

private struct SocialModerationPreview: View {
    @State private var report: SocialReportTarget?
    @State private var block: SocialBlockTarget?

    var body: some View {
        VStack(spacing: 16) {
            if let post = SocialPreviewData.posts.last {
                Button("Report a post") { report = .post(post) }
                Button("Block @\(post.authorUsername)") { block = SocialBlockTarget(userID: post.authorID, username: post.authorUsername) }
            }
        }
        .socialModeration(report: $report, block: $block)
    }
}

#Preview("Report and block") {
    SocialModerationPreview()
        .previewEnvironment()
}
