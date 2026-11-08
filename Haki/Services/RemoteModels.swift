//
//  RemoteModels.swift
//  Haki
//
//  Rows from the Supabase database (tables, views and RPC results), decoded
//  with the database client's decoder (see `Backend`): `timestamptz` columns
//  arrive as ISO-8601 strings and become `Date`s, `date` columns stay
//  "yyyy-MM-dd" strings, and `numeric` columns arrive as JSON numbers.
//

import Foundation

// MARK: - Profiles

/// A `profiles` row: the signed-in user's own editable profile.
nonisolated struct ProfileRecord: Codable, Hashable, Identifiable {
    let id: UUID
    var username: String
    var displayName: String
    var bio: String
    var avatarPath: String?
    var sharePortfolio: Bool
    var onboarded: Bool

    var avatarURL: URL? { BackendConfig.avatarURL(path: avatarPath) }

    /// The display name if there is one, else the username.
    var name: String { remoteDisplayName(displayName, fallback: username) }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case bio
        case avatarPath = "avatar_path"
        case sharePortfolio = "share_portfolio"
        case onboarded
    }
}

/// A `profile_stats` row: anyone's public profile with counts and the
/// viewer's follow state.
nonisolated struct UserProfile: Codable, Hashable, Identifiable {
    let id: UUID
    var username: String
    var displayName: String
    var bio: String
    var avatarPath: String?
    var sharePortfolio: Bool
    let createdAt: Date
    var followerCount: Int
    var followingCount: Int
    var postCount: Int
    var followedByMe: Bool

    var avatarURL: URL? { BackendConfig.avatarURL(path: avatarPath) }

    /// The display name if there is one, else the username.
    var name: String { remoteDisplayName(displayName, fallback: username) }

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case bio
        case avatarPath = "avatar_path"
        case sharePortfolio = "share_portfolio"
        case createdAt = "created_at"
        case followerCount = "follower_count"
        case followingCount = "following_count"
        case postCount = "post_count"
        case followedByMe = "followed_by_me"
    }
}

// MARK: - Posts

nonisolated enum PostKind: String, Codable, Hashable, CaseIterable {
    case post, trade, portfolio
}

nonisolated enum TradeSide: String, Codable, Hashable, CaseIterable {
    case buy, sell
}

/// A `feed_posts` row: a post with its author and the viewer's like state.
nonisolated struct FeedPost: Codable, Hashable, Identifiable {
    let id: UUID
    let authorID: UUID
    let kind: PostKind
    var caption: String
    let imagePath: String?
    let ticker: String?
    let tradeSide: TradeSide?
    /// Percentages-only portfolio snapshot, for `.portfolio` posts.
    let attachment: SharedPortfolio?
    var likeCount: Int
    var commentCount: Int
    let createdAt: Date
    let authorUsername: String
    let authorDisplayName: String
    let authorAvatarPath: String?
    var likedByMe: Bool
    /// Whether the author currently holds `ticker` (only known when they share their portfolio).
    let authorHoldsTicker: Bool

    var imageURL: URL? { BackendConfig.postImageURL(path: imagePath) }
    var authorAvatarURL: URL? { BackendConfig.avatarURL(path: authorAvatarPath) }
    var authorName: String { remoteDisplayName(authorDisplayName, fallback: authorUsername) }

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case kind
        case caption
        case imagePath = "image_path"
        case ticker
        case tradeSide = "trade_side"
        case attachment
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case createdAt = "created_at"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarPath = "author_avatar_path"
        case likedByMe = "liked_by_me"
        case authorHoldsTicker = "author_holds_ticker"
    }
}

// Decoding lives in an extension so the memberwise initializer stays available.
nonisolated extension FeedPost {
    /// Lenient where the database is lenient: `attachment` is free-form JSON, so a
    /// malformed one is dropped instead of failing the whole feed.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        authorID = try container.decode(UUID.self, forKey: .authorID)
        let kindValue = try container.decodeIfPresent(String.self, forKey: .kind) ?? ""
        kind = PostKind(rawValue: kindValue) ?? .post
        caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        imagePath = try container.decodeIfPresent(String.self, forKey: .imagePath)
        ticker = try container.decodeIfPresent(String.self, forKey: .ticker)
        let sideValue = try container.decodeIfPresent(String.self, forKey: .tradeSide)
        tradeSide = sideValue.flatMap { TradeSide(rawValue: $0) }
        attachment = (try? container.decodeIfPresent(SharedPortfolio.self, forKey: .attachment)) ?? nil
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        authorUsername = try container.decodeIfPresent(String.self, forKey: .authorUsername) ?? ""
        authorDisplayName = try container.decodeIfPresent(String.self, forKey: .authorDisplayName) ?? ""
        authorAvatarPath = try container.decodeIfPresent(String.self, forKey: .authorAvatarPath)
        likedByMe = try container.decodeIfPresent(Bool.self, forKey: .likedByMe) ?? false
        authorHoldsTicker = try container.decodeIfPresent(Bool.self, forKey: .authorHoldsTicker) ?? false
    }
}

/// A `comment_details` row: a comment with its author.
nonisolated struct PostComment: Codable, Hashable, Identifiable {
    let id: UUID
    let postID: UUID
    let authorID: UUID
    let body: String
    let createdAt: Date
    let authorUsername: String
    let authorDisplayName: String
    let authorAvatarPath: String?

    var authorAvatarURL: URL? { BackendConfig.avatarURL(path: authorAvatarPath) }
    var authorName: String { remoteDisplayName(authorDisplayName, fallback: authorUsername) }

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case body
        case createdAt = "created_at"
        case authorUsername = "author_username"
        case authorDisplayName = "author_display_name"
        case authorAvatarPath = "author_avatar_path"
    }
}

// MARK: - Activity

nonisolated enum ActivityKind: String, Codable, Hashable {
    case like, comment, follow
}

/// A `get_activity` row: someone liked or commented on your post, or followed you.
nonisolated struct ActivityItem: Codable, Hashable, Identifiable {
    let kind: ActivityKind
    let actorID: UUID
    let actorUsername: String
    let actorDisplayName: String
    let actorAvatarPath: String?
    let postID: UUID?
    let postImagePath: String?
    let commentBody: String?
    let createdAt: Date

    var id: String {
        "\(kind.rawValue)-\(actorID.uuidString)-\(postID?.uuidString ?? "none")-\(createdAt.timeIntervalSince1970)"
    }

    var actorAvatarURL: URL? { BackendConfig.avatarURL(path: actorAvatarPath) }
    var postImageURL: URL? { BackendConfig.postImageURL(path: postImagePath) }
    var actorName: String { remoteDisplayName(actorDisplayName, fallback: actorUsername) }

    enum CodingKeys: String, CodingKey {
        case kind
        case actorID = "actor_id"
        case actorUsername = "actor_username"
        case actorDisplayName = "actor_display_name"
        case actorAvatarPath = "actor_avatar_path"
        case postID = "post_id"
        case postImagePath = "post_image_path"
        case commentBody = "comment_body"
        case createdAt = "created_at"
    }
}

// MARK: - Public portfolios

/// A `public_portfolio` row: one position of someone's portfolio, as percentages only.
nonisolated struct PublicHolding: Codable, Hashable, Identifiable {
    let ticker: String
    let name: String?
    let securityType: String?
    /// Share of the portfolio, 0...100.
    let weightPct: Double?
    /// Return on cost, in percent.
    let gainPct: Double?

    var id: String { ticker }

    enum CodingKeys: String, CodingKey {
        case ticker
        case name
        case securityType = "security_type"
        case weightPct = "weight_pct"
        case gainPct = "gain_pct"
    }
}

/// The `public_portfolio_summary` row.
nonisolated struct PublicPortfolioSummary: Codable, Hashable {
    let positionCount: Int
    /// Whole-portfolio return on cost, in percent.
    let totalGainPct: Double?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case positionCount = "position_count"
        case totalGainPct = "total_gain_pct"
        case updatedAt = "updated_at"
    }
}

// MARK: - Brokerage data (the signed-in user's own)

/// A `brokerage_connections` row: one linked brokerage login.
nonisolated struct BrokerageConnection: Codable, Hashable, Identifiable {
    let id: UUID
    let institutionName: String
    /// "active" | "needs_attention" | "error"
    let status: String
    let errorMessage: String?
    let lastSyncedAt: Date?
    let createdAt: Date

    var needsAttention: Bool { status != "active" }

    enum CodingKeys: String, CodingKey {
        case id
        case institutionName = "institution_name"
        case status
        case errorMessage = "error_message"
        case lastSyncedAt = "last_synced_at"
        case createdAt = "created_at"
    }
}

/// An `investment_accounts` row.
nonisolated struct InvestmentAccount: Codable, Hashable, Identifiable {
    let id: UUID
    let connectionID: UUID
    let name: String
    let officialName: String?
    let mask: String?
    let type: String
    let subtype: String?
    let currentBalance: Double?
    let currency: String

    enum CodingKeys: String, CodingKey {
        case id
        case connectionID = "connection_id"
        case name
        case officialName = "official_name"
        case mask
        case type
        case subtype
        case currentBalance = "current_balance"
        case currency
    }
}

/// A `holdings` row. Amounts are in dollars (fractional shares, sub-cent prices).
nonisolated struct BrokerageHolding: Codable, Hashable, Identifiable {
    let id: UUID
    let accountID: UUID
    let securityID: String
    let ticker: String?
    let name: String
    let securityType: String?
    let quantity: Double
    let price: Double?
    /// "yyyy-MM-dd"
    let priceAsOf: String?
    let value: Double
    let costBasis: Double?
    let currency: String
    let updatedAt: Date

    /// This holding as `PortfolioMath` input.
    var input: HoldingInput {
        HoldingInput(
            ticker: ticker,
            name: name,
            securityType: securityType,
            quantity: quantity,
            value: value,
            costBasis: costBasis
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case securityID = "security_id"
        case ticker
        case name
        case securityType = "security_type"
        case quantity
        case price
        case priceAsOf = "price_as_of"
        case value
        case costBasis = "cost_basis"
        case currency
        case updatedAt = "updated_at"
    }
}

/// An `investment_transactions` row (buy, sell, dividend, fee, transfer...).
nonisolated struct InvestmentTransaction: Codable, Hashable, Identifiable {
    let id: UUID
    let accountID: UUID
    /// "yyyy-MM-dd"
    let date: String
    let name: String
    let ticker: String?
    let securityName: String?
    /// Plaid type: buy, sell, cancel, cash, fee, transfer.
    let type: String
    let subtype: String?
    let quantity: Double?
    let price: Double?
    let amount: Double?
    let fees: Double?
    let currency: String

    /// Noon local time on `date`.
    var day: Date? { remoteDay(from: date) }

    enum CodingKeys: String, CodingKey {
        case id
        case accountID = "account_id"
        case date
        case name
        case ticker
        case securityName = "security_name"
        case type
        case subtype
        case quantity
        case price
        case amount
        case fees
        case currency
    }
}

/// A `portfolio_snapshots` row: the portfolio's total on one day.
nonisolated struct PortfolioSnapshot: Codable, Hashable, Identifiable {
    /// "yyyy-MM-dd"
    let date: String
    let totalValue: Double
    let costBasis: Double?

    var id: String { date }

    /// Noon local time on `date`.
    var day: Date? { remoteDay(from: date) }

    enum CodingKeys: String, CodingKey {
        case date
        case totalValue = "total_value"
        case costBasis = "cost_basis"
    }
}

// MARK: - Composing

/// What the compose screen is building. `SocialService.createPost` turns it into a post.
nonisolated struct PostDraft: Hashable {
    var kind: PostKind = .post
    var caption: String = ""
    var imageJPEG: Data? = nil
    var ticker: String? = nil
    var tradeSide: TradeSide? = nil
    var attachment: SharedPortfolio? = nil

    /// Mirrors the database checks: a post needs a caption, an image or an
    /// attachment; captions are at most 2,200 characters; a ticker must be a
    /// valid symbol; a trade needs a ticker and a side; a portfolio post needs
    /// a portfolio to share.
    var isPostable: Bool {
        // Postgres counts characters as code points.
        guard caption.unicodeScalars.count <= 2200 else { return false }
        let hasCaption = !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // `SocialService.createPost` only sends the attachment with portfolio posts.
        let hasAttachment = kind == .portfolio && attachment != nil
        guard hasCaption || imageJPEG != nil || hasAttachment else { return false }

        let symbol = ticker?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !symbol.isEmpty, !Cashtags.isValidTicker(symbol) { return false }

        switch kind {
        case .post:
            return true
        case .trade:
            return !symbol.isEmpty && tradeSide != nil
        case .portfolio:
            guard let attachment else { return false }
            return !attachment.holdings.isEmpty
        }
    }
}

nonisolated enum FeedScope: String, CaseIterable, Identifiable {
    case following, explore

    var id: String { rawValue }

    var title: String {
        switch self {
        case .following: "Following"
        case .explore: "Explore"
        }
    }
}

nonisolated enum FollowListMode: String, Hashable {
    case followers, following
}

// MARK: - Helpers

nonisolated private func remoteDisplayName(_ displayName: String, fallback username: String) -> String {
    let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? username : trimmed
}

/// Noon local time on a "yyyy-MM-dd" day.
nonisolated private func remoteDay(from string: String) -> Date? {
    let parts = string.prefix(10).split(separator: "-")
    guard parts.count == 3,
          let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
    else { return nil }
    return Calendar.current.noon(year: year, month: month, day: day)
}
