//
//  SocialSupport.swift
//  Haki
//
//  Small helpers shared by the social screens: load phases, compact
//  timestamps ("2h"), captions with highlighted cashtags, and the standard
//  error alert.
//
//  This file deliberately doesn't import UIKit, so the attributed-string
//  attributes below resolve to SwiftUI's (not UIKit's) attribute scope.
//

import Foundation
import SwiftUI

/// Where a screen's remote content is: not requested yet, loading, shown, or failed.
nonisolated enum SocialLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    /// A user-facing message.
    case failed(String)
}

// MARK: - Time

nonisolated enum SocialTimeFormat {
    /// Compact age for post headers and comments: "now", "5m", "2h", "3d",
    /// then "Nov 3" (or "Nov 3, 2025" for other years).
    static func short(_ date: Date, now: Date = .now) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60:
            return "now"
        case ..<3_600:
            return "\(Int(seconds / 60))m"
        case ..<86_400:
            return "\(Int(seconds / 3_600))h"
        case ..<604_800:
            return "\(Int(seconds / 86_400))d"
        default:
            if Calendar.current.isDate(date, equalTo: now, toGranularity: .year) {
                return date.formatted(.dateTime.month(.abbreviated).day())
            }
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }

    /// For VoiceOver: "2 hours ago", "yesterday".
    static func spoken(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }
}

// MARK: - Captions

enum PostCaptionFormatter {
    /// The text with every cashtag ("$AAPL") in the accent color and bold.
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        var cursor = text.startIndex
        for range in Cashtags.ranges(in: text) {
            if cursor < range.lowerBound {
                result.append(AttributedString(String(text[cursor..<range.lowerBound])))
            }
            var tag = AttributedString(String(text[range]))
            tag.foregroundColor = Color.accentColor
            tag.inlinePresentationIntent = .stronglyEmphasized
            result.append(tag)
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result.append(AttributedString(String(text[cursor...])))
        }
        return result
    }

    /// Distinct, valid tickers a post is about: its tag (`taggedTicker`) first,
    /// then the caption's cashtags in order of appearance.
    static func tickers(for post: FeedPost) -> [String] {
        let mentioned = Cashtags.extract(from: post.caption).filter { Cashtags.isValidTicker($0) }
        var result: [String] = []
        if let ticker = taggedTicker(of: post, mentioned: mentioned) {
            result.append(ticker)
        }
        for ticker in mentioned where !result.contains(ticker) {
            result.append(ticker)
        }
        return result
    }

    /// Whether the post is about `symbol` (tagged with it or mentions it as a cashtag).
    static func post(_ post: FeedPost, mentions symbol: String) -> Bool {
        let mentioned = Cashtags.extract(from: post.caption)
        return mentioned.contains(symbol) || taggedTicker(of: post, mentioned: mentioned) == symbol
    }

    /// The post's `ticker` while it still applies. A trade is always about its
    /// ticker. A regular post's ticker is just its caption's first cashtag when
    /// it was shared, and only the caption can be edited, so it counts only
    /// while the caption still mentions it.
    private static func taggedTicker(of post: FeedPost, mentioned: [String]) -> String? {
        guard let ticker = post.ticker?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              Cashtags.isValidTicker(ticker)
        else { return nil }
        if post.kind == .post && !mentioned.contains(ticker) {
            return nil
        }
        return ticker
    }

    /// "AAPL" from "$aapl ", for ticker screens and prefills.
    static func normalizedSymbol(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "$"))
            .uppercased()
    }

    /// Characters in a caption or comment as the database counts them (code points).
    static func length(of text: String) -> Int {
        text.unicodeScalars.count
    }

    /// "1.2K" style counts for likes, comments and followers.
    static func compactCount(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName))
    }
}

// MARK: - Errors

extension View {
    /// The app's standard "Something went wrong" alert, shown while `message` isn't nil.
    func socialErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
