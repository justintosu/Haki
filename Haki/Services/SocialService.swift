//
//  SocialService.swift
//  Haki
//
//  Feed, posts, likes, comments, follows, people search, activity and public
//  portfolios. Stateless: views keep what they load in `@State`. Injected with
//  `.environment(SocialService.live)`, read with
//  `@Environment(SocialService.self) private var social`.
//

import Foundation
import Observation
import Supabase

@Observable final class SocialService {
    private let client: SupabaseClient?
    /// Preview mode only: an in-memory copy of `SocialPreviewData` that likes,
    /// follows, posts and comments change.
    @ObservationIgnored private var store = SocialPreviewStore()

    /// `nil` = preview mode: returns `SocialPreviewData`, no network.
    init(client: SupabaseClient?) {
        self.client = client
    }

    static let preview = SocialService(client: nil)
    static let live = SocialService(client: Backend.client)

    // MARK: Posts

    func feed(scope: FeedScope, before: Date?, limit: Int) async throws -> [FeedPost] {
        guard let client else {
            let posts = scope == .explore
                ? store.posts
                : store.posts.filter { $0.authorID == store.me || store.following.contains($0.authorID) }
            return Self.page(posts, before: before, limit: limit)
        }
        let params = SocialFeedParams(
            scope: scope.rawValue,
            before: before.map(socialTimestamp),
            limit: Self.clamp(limit, 1, 50)
        )
        do {
            return try await client.rpc("get_feed", params: params).execute().value
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load the feed. Try again.")
        }
    }

    func posts(byAuthor authorID: UUID, before: Date?, limit: Int) async throws -> [FeedPost] {
        guard let client else {
            return Self.page(store.posts.filter { $0.authorID == authorID }, before: before, limit: limit)
        }
        do {
            var query = client.from("feed_posts").select().eq("author_id", value: authorID)
            if let before {
                query = query.lt("created_at", value: socialTimestamp(before))
            }
            return try await query
                .order("created_at", ascending: false)
                .limit(Self.clamp(limit, 1, 100))
                .execute()
                .value
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load posts. Try again.")
        }
    }

    /// Posts about `ticker`: trades and posts tagged with it, and posts whose
    /// caption mentions it as a cashtag ("$AAPL").
    func posts(mentioning ticker: String, before: Date?, limit: Int) async throws -> [FeedPost] {
        let symbol = ticker.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
            .uppercased()
        guard Cashtags.isValidTicker(symbol) else { return [] }
        let pageSize = Self.clamp(limit, 1, 100)

        guard let client else {
            return Self.page(store.posts.filter { Self.post($0, mentions: symbol) }, before: before, limit: pageSize)
        }

        // The server narrows the candidates with a cashtag pattern; matches are
        // checked exactly here. Keep fetching until this page is full or the
        // candidates run out, so a short page really means the end (the feed
        // stops paging on one).
        let substringFilter = Self.cashtagSubstringFilter(for: symbol)
        var captionFilter = Self.cashtagPatternFilter(for: symbol)
        var result: [FeedPost] = []
        var seen = Set<UUID>()
        var cursor = before
        var batches = 0
        do {
            while batches < 8 {
                var query = client.from("feed_posts").select()
                    .or("ticker.eq.\(symbol),\(captionFilter)")
                if let cursor {
                    query = query.lt("created_at", value: socialTimestamp(cursor))
                }
                let batch: [FeedPost]
                do {
                    batch = try await query
                        .order("created_at", ascending: false)
                        .limit(pageSize)
                        .execute()
                        .value
                } catch let error as PostgrestError where captionFilter != substringFilter && Self.isRejectedFilter(error) {
                    // The pattern wasn't accepted: fall back to the looser substring match.
                    captionFilter = substringFilter
                    continue
                }
                batches += 1
                for post in batch where Self.post(post, mentions: symbol) && seen.insert(post.id).inserted {
                    result.append(post)
                }
                guard batch.count == pageSize, result.count < pageSize, let last = batch.last else { break }
                cursor = last.createdAt
            }
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load posts. Try again.")
        }
        return Array(result.prefix(pageSize))
    }

    func post(id: UUID) async throws -> FeedPost? {
        guard let client else {
            return store.posts.first { $0.id == id }
        }
        do {
            let rows: [FeedPost] = try await client.from("feed_posts").select().eq("id", value: id).limit(1).execute().value
            return rows.first
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load the post. Try again.")
        }
    }

    /// Uploads the image (if any) to post-images/<uid>/<uuid>.jpg, inserts the post, returns it as a FeedPost.
    func createPost(_ draft: PostDraft) async throws -> FeedPost {
        guard draft.isPostable else {
            throw BackendError(code: "invalid_post", message: Self.unpostableReason(draft))
        }
        let caption = draft.caption.trimmingCharacters(in: .whitespacesAndNewlines)
        let ticker = Self.postTicker(for: draft, caption: caption)
        let tradeSide = draft.kind == .trade ? draft.tradeSide : nil
        let attachment = draft.kind == .portfolio ? draft.attachment : nil

        guard let client else {
            let post = store.makePost(kind: draft.kind, caption: caption, ticker: ticker, tradeSide: tradeSide, attachment: attachment)
            store.posts.insert(post, at: 0)
            return post
        }
        guard let uid = client.auth.currentUser?.id else { throw AuthServiceError.notSignedIn }

        var imagePath: String?
        if let jpeg = draft.imageJPEG {
            let path = "\(uid.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            do {
                try await client.storage
                    .from(BackendConfig.postImagesBucket)
                    .upload(path, data: jpeg, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg"))
            } catch {
                throw Backend.userFacingError(error, fallback: "Couldn't upload the photo. Try again.")
            }
            imagePath = path
        }

        let newPost = SocialNewPost(
            kind: draft.kind.rawValue,
            caption: caption,
            imagePath: imagePath,
            ticker: ticker,
            tradeSide: tradeSide?.rawValue,
            attachment: attachment
        )
        let row: SocialPostRow
        do {
            row = try await client
                .from("posts")
                .insert(newPost, returning: .representation)
                .select()
                .single()
                .execute()
                .value
        } catch {
            if let imagePath {
                _ = try? await client.storage.from(BackendConfig.postImagesBucket).remove(paths: [imagePath])
            }
            throw Self.postError(error)
        }

        // The view adds the author and like state; fall back to the bare row if it can't be read right now.
        if let post = try? await self.post(id: row.id) {
            return post
        }
        return row.feedPost
    }

    func updateCaption(postID: UUID, caption: String) async throws {
        let text = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.unicodeScalars.count <= 2200 else {
            throw BackendError(code: "invalid_post", message: "Captions can be up to 2,200 characters.")
        }
        guard let client else {
            store.updatePost(postID) { $0.caption = text }
            return
        }
        do {
            try await client
                .from("posts")
                .update(SocialCaptionUpdate(caption: text), returning: .minimal)
                .eq("id", value: postID)
                .execute()
        } catch {
            throw Self.postError(error)
        }
    }

    /// Deletes the post and its image.
    func deletePost(_ post: FeedPost) async throws {
        guard let client else {
            store.posts.removeAll { $0.id == post.id }
            store.comments.removeAll { $0.postID == post.id }
            return
        }
        do {
            try await client.from("posts").delete(returning: .minimal).eq("id", value: post.id).execute()
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't delete the post. Try again.")
        }
        // Best effort: a leftover image is harmless.
        if let imagePath = post.imagePath, !imagePath.isEmpty {
            _ = try? await client.storage.from(BackendConfig.postImagesBucket).remove(paths: [imagePath])
        }
    }

    // MARK: Likes and comments

    /// Idempotent: liking a liked post or unliking an unliked one does nothing.
    func setLiked(_ liked: Bool, postID: UUID) async throws {
        guard let client else {
            store.updatePost(postID) { post in
                guard post.likedByMe != liked else { return }
                post.likedByMe = liked
                post.likeCount = max(0, post.likeCount + (liked ? 1 : -1))
            }
            return
        }
        guard let uid = client.auth.currentUser?.id else { throw AuthServiceError.notSignedIn }
        do {
            if liked {
                try await Self.insertIgnoringDuplicate(client.from("post_likes").insert(SocialLikeInsert(postID: postID), returning: .minimal))
            } else {
                try await client
                    .from("post_likes")
                    .delete(returning: .minimal)
                    .eq("post_id", value: postID)
                    .eq("user_id", value: uid)
                    .execute()
            }
        } catch {
            throw Backend.userFacingError(error, fallback: liked ? "Couldn't like the post. Try again." : "Couldn't unlike the post. Try again.")
        }
    }

    /// Oldest first: the newest 500, so recent comments are never cut off.
    func comments(postID: UUID) async throws -> [PostComment] {
        guard let client else {
            return store.comments.filter { $0.postID == postID }.sorted { $0.createdAt < $1.createdAt }
        }
        do {
            let newest: [PostComment] = try await client
                .from("comment_details")
                .select()
                .eq("post_id", value: postID)
                .order("created_at", ascending: false)
                .limit(500)
                .execute()
                .value
            return Array(newest.reversed())
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load comments. Try again.")
        }
    }

    func addComment(postID: UUID, body: String) async throws -> PostComment {
        let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw BackendError(code: "invalid_comment", message: "Write something first.")
        }
        guard text.unicodeScalars.count <= 1000 else {
            throw BackendError(code: "invalid_comment", message: "Comments can be up to 1,000 characters.")
        }
        guard let client else {
            let comment = store.makeComment(postID: postID, body: text)
            store.comments.append(comment)
            store.updatePost(postID) { $0.commentCount += 1 }
            return comment
        }
        let row: SocialCommentRow
        do {
            row = try await client
                .from("comments")
                .insert(SocialCommentInsert(postID: postID, body: text), returning: .representation)
                .select("id,post_id,author_id,body,created_at")
                .single()
                .execute()
                .value
        } catch {
            if let postgrestError = error as? PostgrestError, postgrestError.code == "23503" {
                throw BackendError(code: "23503", message: "This post was deleted.")
            }
            throw Backend.userFacingError(error, fallback: "Couldn't post your comment. Try again.")
        }
        if let rows: [PostComment] = try? await client.from("comment_details").select().eq("id", value: row.id).limit(1).execute().value,
           let comment = rows.first {
            return comment
        }
        return row.comment
    }

    func deleteComment(_ comment: PostComment) async throws {
        guard let client else {
            store.comments.removeAll { $0.id == comment.id }
            store.updatePost(comment.postID) { $0.commentCount = max(0, $0.commentCount - 1) }
            return
        }
        do {
            try await client.from("comments").delete(returning: .minimal).eq("id", value: comment.id).execute()
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't delete the comment. Try again.")
        }
    }

    // MARK: People

    func profile(id: UUID) async throws -> UserProfile {
        guard let client else {
            guard let profile = store.profile(id) else {
                throw BackendError(code: "not_found", message: "This profile isn't available.")
            }
            return profile
        }
        let rows: [UserProfile]
        do {
            rows = try await client.from("profile_stats").select().eq("id", value: id).limit(1).execute().value
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load the profile. Try again.")
        }
        guard let profile = rows.first else {
            throw BackendError(code: "not_found", message: "This profile isn't available.")
        }
        return profile
    }

    /// Idempotent: following someone you follow or unfollowing someone you don't does nothing.
    func setFollowing(_ following: Bool, userID: UUID) async throws {
        guard let client else {
            guard userID != store.me else { return }
            if following {
                store.following.insert(userID)
            } else {
                store.following.remove(userID)
            }
            return
        }
        guard let uid = client.auth.currentUser?.id else { throw AuthServiceError.notSignedIn }
        guard userID != uid else {
            throw BackendError(code: "invalid_follow", message: "You can't follow yourself.")
        }
        do {
            if following {
                try await Self.insertIgnoringDuplicate(client.from("follows").insert(SocialFollowInsert(followeeID: userID), returning: .minimal))
            } else {
                try await client
                    .from("follows")
                    .delete(returning: .minimal)
                    .eq("follower_id", value: uid)
                    .eq("followee_id", value: userID)
                    .execute()
            }
        } catch {
            if let postgrestError = error as? PostgrestError, postgrestError.code == "23503" {
                throw BackendError(code: "23503", message: "This account no longer exists.")
            }
            throw Backend.userFacingError(error, fallback: following ? "Couldn't follow. Try again." : "Couldn't unfollow. Try again.")
        }
    }

    /// Most recent first (up to 150).
    func followList(of userID: UUID, mode: FollowListMode) async throws -> [UserProfile] {
        guard let client else {
            return store.followList(of: userID, mode: mode)
        }
        let filterColumn = mode == .followers ? "followee_id" : "follower_id"
        do {
            let rows: [SocialFollowRow] = try await client
                .from("follows")
                .select("follower_id,followee_id,created_at")
                .eq(filterColumn, value: userID)
                .order("created_at", ascending: false)
                .limit(150)
                .execute()
                .value
            let ids = rows.map { mode == .followers ? $0.followerID : $0.followeeID }
            guard !ids.isEmpty else { return [] }
            let profiles: [UserProfile] = try await client
                .from("profile_stats")
                .select()
                .`in`("id", values: ids.map(\.uuidString))
                .execute()
                .value
            let byID = Dictionary(profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            return ids.compactMap { byID[$0] }
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load the list. Try again.")
        }
    }

    func searchProfiles(_ query: String) async throws -> [UserProfile] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard !text.isEmpty else { return [] }
        guard let client else {
            let needle = text.lowercased()
            return store.allProfiles().filter {
                $0.username.lowercased().contains(needle) || $0.displayName.lowercased().contains(needle)
            }
        }
        do {
            let found: [UserProfile] = try await client
                .rpc("search_profiles", params: SocialSearchParams(query: text, limit: 30))
                .execute()
                .value
            return try await Self.onlyOnboarded(found, client: client)
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't search. Try again.")
        }
    }

    /// Popular people you don't follow yet.
    func suggestedProfiles() async throws -> [UserProfile] {
        guard let client else {
            return store.allProfiles().filter { $0.id != store.me && !$0.followedByMe }
        }
        do {
            let suggested: [UserProfile] = try await client
                .rpc("suggested_profiles", params: SocialLimitParams(limit: 20))
                .execute()
                .value
            return try await Self.onlyOnboarded(suggested, client: client)
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load suggestions. Try again.")
        }
    }

    /// Likes, comments and follows involving you, newest first.
    func activity() async throws -> [ActivityItem] {
        guard let client else {
            return SocialPreviewData.activity
        }
        do {
            return try await client.rpc("get_activity", params: SocialLimitParams(limit: 50)).execute().value
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load activity. Try again.")
        }
    }

    // MARK: Public portfolios

    /// Someone's holdings as percentages; empty when they don't share their
    /// portfolio or haven't connected a brokerage. Largest first.
    func publicPortfolio(userID: UUID) async throws -> [PublicHolding] {
        guard let client else {
            return store.sharesPortfolio(userID) ? SocialPreviewData.publicHoldings : []
        }
        do {
            return try await client.rpc("public_portfolio", params: SocialUserParams(user: userID)).execute().value
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load the portfolio. Try again.")
        }
    }

    /// `nil` when there's nothing to show (no positions, or the portfolio is private).
    func publicPortfolioSummary(userID: UUID) async throws -> PublicPortfolioSummary? {
        guard let client else {
            guard store.sharesPortfolio(userID) else { return nil }
            return PublicPortfolioSummary(
                positionCount: SocialPreviewData.publicHoldings.count,
                totalGainPct: 14.2,
                updatedAt: Date.now.addingTimeInterval(-2 * 3600)
            )
        }
        do {
            let rows: [PublicPortfolioSummary] = try await client
                .rpc("public_portfolio_summary", params: SocialUserParams(user: userID))
                .execute()
                .value
            guard let summary = rows.first, summary.positionCount > 0 else { return nil }
            return summary
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't load the portfolio. Try again.")
        }
    }

    // MARK: - Helpers

    private static func clamp(_ value: Int, _ lower: Int, _ upper: Int) -> Int {
        min(max(value, lower), upper)
    }

    /// Newest-first paging over in-memory posts (preview mode).
    private static func page(_ posts: [FeedPost], before: Date?, limit: Int) -> [FeedPost] {
        let sorted = posts.sorted { $0.createdAt > $1.createdAt }
        let older = before.map { cursor in sorted.filter { $0.createdAt < cursor } } ?? sorted
        return Array(older.prefix(max(1, limit)))
    }

    private static func post(_ post: FeedPost, mentions symbol: String) -> Bool {
        if Cashtags.extract(from: post.caption).contains(symbol) { return true }
        // A regular post's `ticker` is the first cashtag its caption had when it
        // was posted, and can't change: after an edit only the caption counts.
        return post.kind != .post && post.ticker?.uppercased() == symbol
    }

    /// Server-side candidates for a cashtag: captions with "$SYMBOL" not followed
    /// by a letter or digit (a regular expression, so "$V" skips every "$VTI").
    /// Never stricter than `Cashtags`; `post(_:mentions:)` checks exactly.
    private static func cashtagPatternFilter(for symbol: String) -> String {
        let escaped = symbol.replacingOccurrences(of: ".", with: "[.]")
        // `Cashtags` stops after 10 characters, so a 10-character one may run on.
        let boundary = symbol.count >= 10 ? "" : "([^A-Za-z0-9]|$)"
        return "caption.imatch.\"[$]\(escaped)\(boundary)\""
    }

    /// The looser fallback: any caption containing "$SYMBOL".
    private static func cashtagSubstringFilter(for symbol: String) -> String {
        "caption.ilike.*$\(symbol)*"
    }

    /// Whether the server refused the filter itself (couldn't parse it, or the
    /// regular expression), rather than failing for another reason.
    private static func isRejectedFilter(_ error: PostgrestError) -> Bool {
        guard let code = error.code else { return false }
        return ["PGRST100", "2201B", "42883"].contains(code)
    }

    /// Leaves out accounts that never finished onboarding: their username and
    /// name come from the sign-up email and provider, not a choice to be found.
    private static func onlyOnboarded(_ profiles: [UserProfile], client: SupabaseClient) async throws -> [UserProfile] {
        guard !profiles.isEmpty else { return profiles }
        let rows: [SocialProfileID] = try await client
            .from("profiles")
            .select("id")
            .`in`("id", values: profiles.map(\.id.uuidString))
            .eq("onboarded", value: true)
            .execute()
            .value
        let onboarded = Set(rows.map(\.id))
        return profiles.filter { onboarded.contains($0.id) }
    }

    /// The `ticker` column: the draft's, or for a regular post the first cashtag
    /// in the caption (so "holds this" badges and ticker feeds pick it up).
    private static func postTicker(for draft: PostDraft, caption: String) -> String? {
        if let ticker = draft.ticker?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !ticker.isEmpty {
            return ticker
        }
        guard draft.kind == .post else { return nil }
        return Cashtags.extract(from: caption).first(where: Cashtags.isValidTicker)
    }

    private static func unpostableReason(_ draft: PostDraft) -> String {
        if draft.caption.unicodeScalars.count > 2200 { return "Captions can be up to 2,200 characters." }
        let ticker = draft.ticker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !ticker.isEmpty, !Cashtags.isValidTicker(ticker) { return "That ticker doesn't look right." }
        switch draft.kind {
        case .trade where ticker.isEmpty || draft.tradeSide == nil:
            return "Pick a ticker and whether you bought or sold."
        case .portfolio where draft.attachment?.holdings.isEmpty ?? true:
            return "There's no portfolio to share yet. Connect a brokerage first."
        default:
            return "Add a caption or a photo first."
        }
    }

    private static func postError(_ error: any Error) -> any Error {
        if let postgrestError = error as? PostgrestError, postgrestError.code == "23514" {
            return BackendError(code: "23514", message: "A post needs a caption, a photo or a portfolio, and a valid ticker.")
        }
        return Backend.userFacingError(error, fallback: "Couldn't share your post. Try again.")
    }

    /// Runs an insert, treating "already exists" (a unique violation) as success.
    private static func insertIgnoringDuplicate(_ builder: PostgrestFilterBuilder) async throws {
        do {
            try await builder.execute()
        } catch let error as PostgrestError where error.code == "23505" {
            return
        }
    }
}

// MARK: - Cursor timestamps

/// `created_at` cursor for "older than" queries, in UTC with microseconds so it
/// round-trips the database value exactly ("2026-11-08T17:04:05.123456Z").
nonisolated private func socialTimestamp(_ date: Date) -> String {
    let totalMicroseconds = Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    var seconds = totalMicroseconds / 1_000_000
    var microseconds = totalMicroseconds % 1_000_000
    if microseconds < 0 {
        microseconds += 1_000_000
        seconds -= 1
    }
    var days = seconds / 86_400
    var secondOfDay = seconds % 86_400
    if secondOfDay < 0 {
        secondOfDay += 86_400
        days -= 1
    }

    // Civil date from days since 1970-01-01 (proleptic Gregorian).
    let shifted = days + 719_468
    let era = (shifted >= 0 ? shifted : shifted - 146_096) / 146_097
    let dayOfEra = shifted - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let monthIndex = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * monthIndex + 2) / 5 + 1
    let month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)

    func pad(_ value: Int64, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
    let hour = secondOfDay / 3_600
    let minute = (secondOfDay % 3_600) / 60
    let second = secondOfDay % 60
    return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(pad(hour, 2)):\(pad(minute, 2)):\(pad(second, 2)).\(pad(microseconds, 6))Z"
}

// MARK: - Request and response bodies

nonisolated private struct SocialFeedParams: Encodable {
    let scope: String
    let before: String?
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case scope = "p_scope"
        case before = "p_before"
        case limit = "p_limit"
    }
}

nonisolated private struct SocialSearchParams: Encodable {
    let query: String
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case query = "p_query"
        case limit = "p_limit"
    }
}

nonisolated private struct SocialLimitParams: Encodable {
    let limit: Int

    enum CodingKeys: String, CodingKey {
        case limit = "p_limit"
    }
}

nonisolated private struct SocialUserParams: Encodable {
    let user: UUID

    enum CodingKeys: String, CodingKey {
        case user = "p_user"
    }
}

nonisolated private struct SocialNewPost: Encodable {
    let kind: String
    let caption: String
    let imagePath: String?
    let ticker: String?
    let tradeSide: String?
    let attachment: SharedPortfolio?

    enum CodingKeys: String, CodingKey {
        case kind
        case caption
        case imagePath = "image_path"
        case ticker
        case tradeSide = "trade_side"
        case attachment
    }
}

nonisolated private struct SocialCaptionUpdate: Encodable {
    let caption: String
}

nonisolated private struct SocialLikeInsert: Encodable {
    let postID: UUID

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
    }
}

nonisolated private struct SocialFollowInsert: Encodable {
    let followeeID: UUID

    enum CodingKeys: String, CodingKey {
        case followeeID = "followee_id"
    }
}

nonisolated private struct SocialCommentInsert: Encodable {
    let postID: UUID
    let body: String

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case body
    }
}

nonisolated private struct SocialProfileID: Decodable {
    let id: UUID
}

nonisolated private struct SocialFollowRow: Decodable {
    let followerID: UUID
    let followeeID: UUID

    enum CodingKeys: String, CodingKey {
        case followerID = "follower_id"
        case followeeID = "followee_id"
    }
}

/// A `posts` row as returned by the insert.
nonisolated private struct SocialPostRow: Decodable {
    let id: UUID
    let authorID: UUID
    let kind: String
    let caption: String
    let imagePath: String?
    let ticker: String?
    let tradeSide: String?
    let attachment: SharedPortfolio?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case kind
        case caption
        case imagePath = "image_path"
        case ticker
        case tradeSide = "trade_side"
        case attachment
        case createdAt = "created_at"
    }

    /// Without the author's name and photo, which only the `feed_posts` view has.
    var feedPost: FeedPost {
        FeedPost(
            id: id,
            authorID: authorID,
            kind: PostKind(rawValue: kind) ?? .post,
            caption: caption,
            imagePath: imagePath,
            ticker: ticker,
            tradeSide: tradeSide.flatMap { TradeSide(rawValue: $0) },
            attachment: attachment,
            likeCount: 0,
            commentCount: 0,
            createdAt: createdAt,
            authorUsername: "",
            authorDisplayName: "",
            authorAvatarPath: nil,
            likedByMe: false,
            authorHoldsTicker: false
        )
    }
}

/// A `comments` row as returned by the insert.
nonisolated private struct SocialCommentRow: Decodable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case body
        case createdAt = "created_at"
    }

    var comment: PostComment {
        PostComment(
            id: id,
            postID: postID,
            authorID: authorID,
            body: body,
            createdAt: createdAt,
            authorUsername: "",
            authorDisplayName: "",
            authorAvatarPath: nil
        )
    }
}

// MARK: - Preview mode

/// In-memory social graph for preview mode, seeded from `SocialPreviewData`.
private struct SocialPreviewStore {
    var posts: [FeedPost] = SocialPreviewData.posts
    var comments: [PostComment] = SocialPreviewData.comments
    var following: Set<UUID> = Set(SocialPreviewData.profiles.filter(\.followedByMe).map(\.id))
    let me: UUID = SocialPreviewData.signedInProfile.id

    func allProfiles() -> [UserProfile] {
        SocialPreviewData.profiles.map(adjusted)
    }

    func profile(_ id: UUID) -> UserProfile? {
        SocialPreviewData.profiles.first { $0.id == id }.map(adjusted)
    }

    func sharesPortfolio(_ id: UUID) -> Bool {
        SocialPreviewData.profiles.first { $0.id == id }?.sharePortfolio ?? false
    }

    func followList(of id: UUID, mode: FollowListMode) -> [UserProfile] {
        let others = allProfiles().filter { $0.id != id }
        guard id == me else { return Array(others.prefix(2)) }
        switch mode {
        case .following: return others.filter { following.contains($0.id) }
        case .followers: return Array(others.prefix(3))
        }
    }

    mutating func updatePost(_ id: UUID, _ change: (inout FeedPost) -> Void) {
        guard let index = posts.firstIndex(where: { $0.id == id }) else { return }
        change(&posts[index])
    }

    func makePost(kind: PostKind, caption: String, ticker: String?, tradeSide: TradeSide?, attachment: SharedPortfolio?) -> FeedPost {
        let author = SocialPreviewData.signedInProfile
        return FeedPost(
            id: UUID(),
            authorID: author.id,
            kind: kind,
            caption: caption,
            imagePath: nil,
            ticker: ticker,
            tradeSide: tradeSide,
            attachment: attachment,
            likeCount: 0,
            commentCount: 0,
            createdAt: .now,
            authorUsername: author.username,
            authorDisplayName: author.displayName,
            authorAvatarPath: author.avatarPath,
            likedByMe: false,
            authorHoldsTicker: ticker != nil
        )
    }

    func makeComment(postID: UUID, body: String) -> PostComment {
        let author = SocialPreviewData.signedInProfile
        return PostComment(
            id: UUID(),
            postID: postID,
            authorID: author.id,
            body: body,
            createdAt: .now,
            authorUsername: author.username,
            authorDisplayName: author.displayName,
            authorAvatarPath: author.avatarPath
        )
    }

    /// Applies the in-memory follow state and post counts.
    private func adjusted(_ profile: UserProfile) -> UserProfile {
        var result = profile
        if profile.id != me {
            let wasFollowed = profile.followedByMe
            let isFollowed = following.contains(profile.id)
            result.followedByMe = isFollowed
            result.followerCount = max(0, profile.followerCount + (isFollowed ? 1 : 0) - (wasFollowed ? 1 : 0))
        } else {
            result.followingCount = following.count
        }
        result.postCount = posts.filter { $0.authorID == profile.id }.count
        return result
    }
}

/// Sample data for previews and preview mode.
enum SocialPreviewData {
    /// The signed-in user in preview mode (`AuthService.preview`); also `profiles[0]`.
    static let signedInProfile = ProfileRecord(
        id: sampleID(1),
        username: "maya.invests",
        displayName: "Maya Chen",
        bio: "Index funds by day, chart nerd by night. Long-term only.",
        avatarPath: nil,
        sharePortfolio: true,
        onboarded: true
    )

    static let profiles: [UserProfile] = [
        UserProfile(
            id: signedInProfile.id,
            username: signedInProfile.username,
            displayName: signedInProfile.displayName,
            bio: signedInProfile.bio,
            avatarPath: nil,
            sharePortfolio: true,
            createdAt: hoursAgo(24 * 120),
            followerCount: 128,
            followingCount: 2,
            postCount: 3,
            followedByMe: false
        ),
        UserProfile(
            id: sampleID(2),
            username: "dividend_dan",
            displayName: "Dan Okafor",
            bio: "Collecting dividends like stamps. 🌱",
            avatarPath: nil,
            sharePortfolio: true,
            createdAt: hoursAgo(24 * 300),
            followerCount: 2_410,
            followingCount: 180,
            postCount: 2,
            followedByMe: true
        ),
        UserProfile(
            id: sampleID(3),
            username: "priya.k",
            displayName: "Priya Kapoor",
            bio: "Tech stocks, travel and too much coffee.",
            avatarPath: nil,
            sharePortfolio: true,
            createdAt: hoursAgo(24 * 90),
            followerCount: 860,
            followingCount: 95,
            postCount: 2,
            followedByMe: true
        ),
        UserProfile(
            id: sampleID(4),
            username: "sam_saves",
            displayName: "Sam Rivera",
            bio: "First-time investor, learning in public.",
            avatarPath: nil,
            sharePortfolio: false,
            createdAt: hoursAgo(24 * 20),
            followerCount: 47,
            followingCount: 210,
            postCount: 1,
            followedByMe: false
        ),
        UserProfile(
            id: sampleID(5),
            username: "theo.etf",
            displayName: "",
            bio: "",
            avatarPath: nil,
            sharePortfolio: true,
            createdAt: hoursAgo(24 * 45),
            followerCount: 312,
            followingCount: 40,
            postCount: 1,
            followedByMe: false
        ),
    ]

    static let posts: [FeedPost] = [
        samplePost(
            number: 1, author: 2, kind: .trade, hoursAgo: 1.5,
            caption: "Added to my $KO position after the dip. Steady payer, steady sleeper.",
            ticker: "KO", side: .buy, likes: 42, comments: 3, liked: true, holds: true
        ),
        samplePost(
            number: 2, author: 1, kind: .portfolio, hoursAgo: 5,
            caption: "Quarterly check-in: mostly index funds, a little $NVDA for fun.",
            attachment: SharedPortfolio(
                holdings: [
                    .init(ticker: "VTI", weightPct: 41.5),
                    .init(ticker: "VXUS", weightPct: 18.2),
                    .init(ticker: "AAPL", weightPct: 12.4),
                    .init(ticker: "NVDA", weightPct: 9.8),
                    .init(ticker: "BND", weightPct: 8.1),
                    .init(ticker: "Other", weightPct: 10.0),
                ],
                totalGainPct: 14.2
            ),
            likes: 18, comments: 2
        ),
        samplePost(
            number: 3, author: 3, kind: .post, hoursAgo: 9,
            caption: "Anyone else watching $AAPL and $MSFT into earnings next week? Feels like the bar is high.",
            ticker: "AAPL", likes: 64, comments: 1, holds: true
        ),
        samplePost(
            number: 4, author: 4, kind: .post, hoursAgo: 20,
            caption: "Set up my first automatic monthly investment today. Small, but it's a start!",
            likes: 120, comments: 0, liked: true
        ),
        samplePost(
            number: 5, author: 3, kind: .trade, hoursAgo: 30,
            caption: "Trimmed some $TSLA to rebalance. Still holding the rest.",
            ticker: "TSLA", side: .sell, likes: 23, comments: 0, holds: true
        ),
        samplePost(
            number: 6, author: 5, kind: .post, hoursAgo: 52,
            caption: "Reminder: fees compound too. Check your expense ratios.",
            likes: 210, comments: 0
        ),
        samplePost(
            number: 7, author: 1, kind: .trade, hoursAgo: 75,
            caption: "Monthly buy of $VTI done. Boring is beautiful.",
            ticker: "VTI", side: .buy, likes: 31, comments: 0, holds: true
        ),
        samplePost(
            number: 8, author: 2, kind: .post, hoursAgo: 120,
            caption: "Dividend day! $JNJ and $PG paid out this morning.",
            ticker: "JNJ", likes: 77, comments: 0
        ),
        samplePost(
            number: 9, author: 1, kind: .post, hoursAgo: 160,
            caption: "Reading list for the weekend: anything on behavioral finance?",
            likes: 12, comments: 0
        ),
    ]

    static let comments: [PostComment] = [
        sampleComment(number: 1, post: 1, author: 3, hoursAgo: 1.2, body: "Classic. $KO never goes out of style."),
        sampleComment(number: 2, post: 1, author: 1, hoursAgo: 1.0, body: "What's your target allocation for it?"),
        sampleComment(number: 3, post: 1, author: 2, hoursAgo: 0.8, body: "Around 5%. Just a steady base."),
        sampleComment(number: 4, post: 2, author: 2, hoursAgo: 4, body: "Love how simple this is."),
        sampleComment(number: 5, post: 2, author: 4, hoursAgo: 3, body: "How often do you rebalance?"),
        sampleComment(number: 6, post: 3, author: 1, hoursAgo: 8, body: "Holding through it either way."),
    ]

    static let activity: [ActivityItem] = [
        ActivityItem(
            kind: .comment, actorID: sampleID(4), actorUsername: "sam_saves", actorDisplayName: "Sam Rivera",
            actorAvatarPath: nil, postID: sampleID(102), postImagePath: nil,
            commentBody: "How often do you rebalance?", createdAt: hoursAgo(3)
        ),
        ActivityItem(
            kind: .like, actorID: sampleID(3), actorUsername: "priya.k", actorDisplayName: "Priya Kapoor",
            actorAvatarPath: nil, postID: sampleID(102), postImagePath: nil,
            commentBody: nil, createdAt: hoursAgo(4)
        ),
        ActivityItem(
            kind: .follow, actorID: sampleID(5), actorUsername: "theo.etf", actorDisplayName: "",
            actorAvatarPath: nil, postID: nil, postImagePath: nil,
            commentBody: nil, createdAt: hoursAgo(26)
        ),
        ActivityItem(
            kind: .like, actorID: sampleID(2), actorUsername: "dividend_dan", actorDisplayName: "Dan Okafor",
            actorAvatarPath: nil, postID: sampleID(107), postImagePath: nil,
            commentBody: nil, createdAt: hoursAgo(70)
        ),
    ]

    static let publicHoldings: [PublicHolding] = [
        PublicHolding(ticker: "VTI", name: "Vanguard Total Stock Market ETF", securityType: "etf", weightPct: 38.6, gainPct: 18.4),
        PublicHolding(ticker: "VXUS", name: "Vanguard Total International Stock ETF", securityType: "etf", weightPct: 16.9, gainPct: 7.2),
        PublicHolding(ticker: "AAPL", name: "Apple Inc.", securityType: "equity", weightPct: 11.5, gainPct: 32.1),
        PublicHolding(ticker: "NVDA", name: "NVIDIA Corporation", securityType: "equity", weightPct: 9.1, gainPct: 86.5),
        PublicHolding(ticker: "BND", name: "Vanguard Total Bond Market ETF", securityType: "etf", weightPct: 7.5, gainPct: -2.3),
        PublicHolding(ticker: "MSFT", name: "Microsoft Corporation", securityType: "equity", weightPct: 6.8, gainPct: 21.0),
        PublicHolding(ticker: "CASH", name: "Cash", securityType: "cash", weightPct: 9.6, gainPct: nil),
    ]

    // MARK: Builders

    private static func sampleID(_ number: Int) -> UUID {
        let suffix = String(number)
        let padded = String(repeating: "0", count: max(0, 12 - suffix.count)) + suffix
        return UUID(uuidString: "6A4B1C2D-0000-4000-8000-\(padded)") ?? UUID()
    }

    private static func hoursAgo(_ hours: Double) -> Date {
        Date.now.addingTimeInterval(-hours * 3600)
    }

    private static func samplePost(
        number: Int,
        author: Int,
        kind: PostKind,
        hoursAgo hours: Double,
        caption: String,
        ticker: String? = nil,
        side: TradeSide? = nil,
        attachment: SharedPortfolio? = nil,
        likes: Int,
        comments: Int,
        liked: Bool = false,
        holds: Bool = false
    ) -> FeedPost {
        let profile = profiles.first { $0.id == sampleID(author) }
        return FeedPost(
            id: sampleID(100 + number),
            authorID: sampleID(author),
            kind: kind,
            caption: caption,
            imagePath: nil,
            ticker: ticker,
            tradeSide: side,
            attachment: attachment,
            likeCount: likes,
            commentCount: comments,
            createdAt: hoursAgo(hours),
            authorUsername: profile?.username ?? "",
            authorDisplayName: profile?.displayName ?? "",
            authorAvatarPath: nil,
            likedByMe: liked,
            authorHoldsTicker: holds
        )
    }

    private static func sampleComment(number: Int, post: Int, author: Int, hoursAgo hours: Double, body: String) -> PostComment {
        let profile = profiles.first { $0.id == sampleID(author) }
        return PostComment(
            id: sampleID(200 + number),
            postID: sampleID(100 + post),
            authorID: sampleID(author),
            body: body,
            createdAt: hoursAgo(hours),
            authorUsername: profile?.username ?? "",
            authorDisplayName: profile?.displayName ?? "",
            authorAvatarPath: nil
        )
    }
}
