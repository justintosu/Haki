//
//  FeedPager.swift
//  Haki
//
//  Paged post lists (the home feed, ticker feeds) and the change center that
//  keeps every list on screen consistent: a like, comment, edit or delete on
//  one screen shows up on the screens underneath it in the navigation stack,
//  and a new post appears at the top of the feeds it belongs in.
//

import Foundation
import Observation

/// Edits to posts made anywhere in the app during this session.
///
/// Lists resolve the posts they loaded through it (`FeedPager.visiblePosts`),
/// so a change recorded after a list loaded wins over the list's copy, while a
/// fresher reload wins over older changes.
@Observable final class PostChangeCenter {
    static let shared = PostChangeCenter()

    struct Change {
        let post: FeedPost
        let revision: Int
    }

    /// Bumped by every recorded change.
    private(set) var revision = 0
    private(set) var changes: [UUID: Change] = [:]
    private(set) var deletedIDs: Set<UUID> = []
    /// Posts created this session, newest first.
    private(set) var created: [FeedPost] = []

    @ObservationIgnored private var ownerID: UUID?

    /// Forgets everything when a different account signs in (and loads that
    /// account's block list).
    func prepare(for userID: UUID?) {
        SocialBlockList.shared.prepare(for: userID)
        guard ownerID != userID else { return }
        ownerID = userID
        guard !changes.isEmpty || !deletedIDs.isEmpty || !created.isEmpty else { return }
        changes = [:]
        deletedIDs = []
        created = []
        revision += 1
    }

    func update(_ post: FeedPost) {
        revision += 1
        changes[post.id] = Change(post: post, revision: revision)
        if let index = created.firstIndex(where: { $0.id == post.id }) {
            created[index] = post
        }
    }

    func delete(_ postID: UUID) {
        revision += 1
        deletedIDs.insert(postID)
        changes[postID] = nil
        created.removeAll { $0.id == postID }
    }

    func add(_ post: FeedPost) {
        revision += 1
        created.removeAll { $0.id == post.id }
        created.insert(post, at: 0)
    }

    /// The version of `post` to show, or `nil` if it was deleted.
    /// - Parameter loadRevision: `revision` when the caller loaded its copy.
    func resolve(_ post: FeedPost, loadedAt loadRevision: Int) -> FeedPost? {
        if deletedIDs.contains(post.id) { return nil }
        if let change = changes[post.id], change.revision > loadRevision {
            return change.post
        }
        return post
    }

    func isDeleted(_ postID: UUID) -> Bool {
        deletedIDs.contains(postID)
    }
}

/// Newest-first pages of posts with pull-to-refresh and infinite scroll.
/// The owning view supplies the fetch (`before` cursor and page size).
@Observable final class FeedPager {
    private(set) var posts: [FeedPost] = []
    private(set) var phase: SocialLoadPhase = .idle
    private(set) var isLoadingMore = false
    /// The last page was short: there's nothing older.
    private(set) var reachedEnd = false
    private(set) var loadMoreError: String?
    /// A refresh failed while older posts are still showing.
    var bannerError: String?

    let pageSize: Int

    /// Bumped by every reload; results of older loads are dropped.
    @ObservationIgnored private var generation = 0
    /// `PostChangeCenter.revision` when each post was loaded.
    @ObservationIgnored private var loadRevisions: [UUID: Int] = [:]

    init(pageSize: Int = 20) {
        self.pageSize = pageSize
    }

    /// Loads the first page again. Shows a loading state only when there's nothing on screen yet.
    func reload(using fetch: (Date?, Int) async throws -> [FeedPost]) async {
        generation += 1
        let current = generation
        let revision = PostChangeCenter.shared.revision
        isLoadingMore = false
        loadMoreError = nil
        if posts.isEmpty {
            phase = .loading
        }
        do {
            let page = try await fetch(nil, pageSize)
            guard current == generation else { return }
            posts = Self.unique(page)
            loadRevisions = Dictionary(posts.map { ($0.id, revision) }, uniquingKeysWith: { first, _ in first })
            reachedEnd = page.count < pageSize
            phase = .loaded
            bannerError = nil
        } catch {
            guard current == generation else { return }
            if Backend.isCancellation(error) {
                // Try again the next time the screen appears.
                if posts.isEmpty { phase = .idle }
                return
            }
            if posts.isEmpty {
                phase = .failed(error.localizedDescription)
            } else {
                bannerError = error.localizedDescription
            }
        }
    }

    /// Appends the next page (older than the last post), unless one is loading or there's no more.
    func loadMore(using fetch: (Date?, Int) async throws -> [FeedPost]) async {
        guard phase == .loaded, !reachedEnd, !isLoadingMore, let last = posts.last else { return }
        let current = generation
        let revision = PostChangeCenter.shared.revision
        isLoadingMore = true
        loadMoreError = nil
        do {
            let page = try await fetch(last.createdAt, pageSize)
            guard current == generation else { return }
            let known = Set(posts.map(\.id))
            let fresh = Self.unique(page).filter { !known.contains($0.id) }
            posts.append(contentsOf: fresh)
            for post in fresh {
                loadRevisions[post.id] = revision
            }
            reachedEnd = page.count < pageSize
            isLoadingMore = false
        } catch {
            guard current == generation else { return }
            isLoadingMore = false
            if !Backend.isCancellation(error) {
                loadMoreError = error.localizedDescription
            }
        }
    }

    /// Applies a card's change (`nil` = deleted) to the loaded posts.
    func apply(_ updated: FeedPost?, for postID: UUID) {
        guard let index = posts.firstIndex(where: { $0.id == postID }) else { return }
        if let updated {
            posts[index] = updated
        } else {
            posts.remove(at: index)
            loadRevisions[postID] = nil
        }
    }

    /// The posts to show: posts created this session that belong in this list
    /// (newer than everything loaded), then the loaded posts, with changes made
    /// elsewhere applied, and deleted posts and posts by blocked people left out.
    func visiblePosts(includingCreated belongs: (FeedPost) -> Bool) -> [FeedPost] {
        let center = PostChangeCenter.shared
        let blockList = SocialBlockList.shared
        var result: [FeedPost] = []
        if phase == .loaded {
            let known = Set(posts.map(\.id))
            let newest = posts.first?.createdAt ?? .distantPast
            for post in center.created where !known.contains(post.id) && post.createdAt > newest && belongs(post) {
                if let resolved = center.resolve(post, loadedAt: 0) {
                    result.append(resolved)
                }
            }
        }
        for post in posts where !blockList.isBlocked(post.authorID) {
            if let resolved = center.resolve(post, loadedAt: loadRevisions[post.id] ?? 0) {
                result.append(resolved)
            }
        }
        return result
    }

    private static func unique(_ posts: [FeedPost]) -> [FeedPost] {
        var seen = Set<UUID>()
        return posts.filter { seen.insert($0.id).inserted }
    }
}
