//
//  StudyComponents.swift
//  Haki
//
//  Pieces shared by the notes and flashcard screens: what's due in a deck
//  and across decks, formatting, the request that opens a study session,
//  and the rows and tiles the lists use.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Opening a session

/// What `StudySessionView` opens with, for `.fullScreenCover(item:)`. The id
/// is made up front, so presenting never has to read the deck.
struct StudySessionRequest: Identifiable {
    let id = UUID()
    let deck: FlashcardDeck
    var cramsAllCards: Bool = false
}

// MARK: - Counts

/// A deck's numbers right now: reviews due, new cards (all of them and the
/// ones today's allowance still lets in) and the total.
struct StudyDeckCounts {
    /// Studied cards whose review is due.
    let due: Int
    /// Cards never studied.
    let fresh: Int
    /// New cards today's allowance still lets in.
    let newToday: Int
    /// Every card in the deck.
    let total: Int

    init(deck: FlashcardDeck, now: Date = .now) {
        let dueCards = deck.dueCount(now: now)
        let newCards = deck.newCount
        let allowance = max(0, deck.newCardsPerDay - StudyStore.newCardsStudiedToday(deck, now: now))
        due = dueCards
        fresh = newCards
        newToday = min(newCards, allowance)
        total = deck.cards.count
    }

    /// Reviews due (at most 200, like the study queue) plus today's new cards.
    var toStudy: Int { min(due, 200) + newToday }

    /// Cards studied at least once.
    var learned: Int { max(0, total - fresh) }
}

/// What's due across every deck, and the deck with the most to study.
struct StudyDueTotals {
    let reviews: Int
    let fresh: Int
    let deckCount: Int
    /// The deck with the most to study now; nil when nothing is due.
    let busiestDeck: FlashcardDeck?
    let busiestCount: Int
    /// The soonest review still to come across all decks.
    let nextReviewAt: Date?

    init(decks: [FlashcardDeck], now: Date = .now) {
        var reviewCount = 0
        var freshCount = 0
        var busiest: FlashcardDeck?
        var mostToStudy = 0
        var soonest: Date?
        for deck in decks {
            let counts = StudyDeckCounts(deck: deck, now: now)
            reviewCount += min(counts.due, 200)
            freshCount += counts.newToday
            if counts.toStudy > mostToStudy {
                busiest = deck
                mostToStudy = counts.toStudy
            }
            for card in deck.cards {
                guard let dueAt = card.dueAt, dueAt > now else { continue }
                if let current = soonest, current <= dueAt { continue }
                soonest = dueAt
            }
        }
        reviews = reviewCount
        fresh = freshCount
        deckCount = decks.count
        busiestDeck = busiest
        busiestCount = mostToStudy
        nextReviewAt = soonest
    }

    /// Everything there is to study today.
    var total: Int { reviews + fresh }
}

// MARK: - Cards

enum StudyCards {
    /// The deck's cards in the order they were added, skipping any that were
    /// just deleted.
    static func live(in deck: FlashcardDeck) -> [Flashcard] {
        deck.cards
            .filter { !$0.isDeleted && $0.modelContext != nil }
            .sorted { first, second in
                first.createdAt == second.createdAt ? first.order < second.order : first.createdAt < second.createdAt
            }
    }
}

// MARK: - Formatting

enum StudyFormat {
    /// "1 card", "12 cards".
    static func cards(_ count: Int) -> String {
        count == 1 ? "1 card" : "\(count) cards"
    }

    /// "8 reviews · 4 new", or "Nothing to review right now".
    static func breakdown(reviews: Int, fresh: Int) -> String {
        var parts: [String] = []
        if reviews > 0 { parts.append(reviews == 1 ? "1 review" : "\(reviews) reviews") }
        if fresh > 0 { parts.append("\(fresh) new") }
        return parts.isEmpty ? "Nothing to review right now" : parts.joined(separator: " · ")
    }

    /// A note's edit time: "3:40 PM" today, "Yesterday", "Monday" this week,
    /// "Nov 3" this year, "Nov 3, 2025" before.
    static func noteDate(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days > 0 && days < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Studied yesterday", "Studied 3 hours ago", or "Not studied yet".
    static func lastStudied(_ date: Date?) -> String {
        guard let date else { return "Not studied yet" }
        return "Studied \(date.formatted(.relative(presentation: .named)))"
    }

    /// "New", "Due now" or "Due in 3d" for a card.
    static func dueText(_ schedule: CardSchedule, now: Date = .now) -> String {
        guard !schedule.isNew, let dueAt = schedule.dueAt else { return "New" }
        if dueAt <= now { return "Due now" }
        return "Due in \(SpacedRepetition.intervalText(days: daysUntil(dueAt, now: now)))"
    }

    /// The same as `dueText`, written out for VoiceOver ("Due in 3 days").
    static func spokenDueText(_ schedule: CardSchedule, now: Date = .now) -> String {
        guard !schedule.isNew, let dueAt = schedule.dueAt else { return "New card" }
        if dueAt <= now { return "Due now" }
        return "Due in \(spokenInterval(SpacedRepetition.intervalText(days: daysUntil(dueAt, now: now))))"
    }

    /// Days from `now` to `date`, to the nearest minute (so a card due in
    /// 23 h 59 m 58 s reads "1d", not "24h").
    private static func daysUntil(_ date: Date, now: Date) -> Double {
        let minutes = (date.timeIntervalSince(now) / 60).rounded()
        return max(1, minutes) / 1_440
    }

    /// A note's title for lists: its own title, or its first line without
    /// Markdown marks ("# Biology" reads "Biology").
    static func title(for note: Note) -> String {
        let own = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !own.isEmpty { return own }
        let cleaned = plainLine(note.displayTitle)
        return cleaned.isEmpty ? "New note" : cleaned
    }

    /// "10m" → "10 minutes", "1d" → "1 day", "4mo" → "4 months".
    static func spokenInterval(_ short: String) -> String {
        let units: [(suffix: String, word: String)] = [
            ("mo", "month"), ("m", "minute"), ("h", "hour"), ("d", "day"), ("w", "week"), ("y", "year"),
        ]
        for unit in units where short.hasSuffix(unit.suffix) {
            let number = String(short.dropLast(unit.suffix.count))
            return number == "1" ? "1 \(unit.word)" : "\(number) \(unit.word)s"
        }
        return short
    }

    /// A short preview of a note's text with the Markdown marks taken out.
    /// When the note has no title, its first line is the title, so it's skipped here.
    static func snippet(_ note: Note) -> String {
        var lines = note.body
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !lines.isEmpty {
            lines.removeFirst()
        }
        let text = lines.prefix(4).map { plainLine($0) }.filter { !$0.isEmpty }.joined(separator: " ")
        return String(text.prefix(160))
    }

    /// One line of Markdown as plain text: no list markers, heading marks,
    /// bold, italics or code ticks.
    static func plainLine(_ line: String) -> String {
        var text = line
        let markers = ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] ", "> ", "- ", "* ", "+ ", "• "]
        for marker in markers where text.hasPrefix(marker) {
            text = String(text.dropFirst(marker.count))
            break
        }
        while text.hasPrefix("#") {
            text.removeFirst()
        }
        for mark in ["**", "__", "~~", "`"] {
            text = text.replacingOccurrences(of: mark, with: "")
        }
        return text.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Rows and tiles

/// A tinted rounded square with a symbol, like the Health tab's rows.
struct StudyIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A number with a caption under it ("12" / "Due").
struct StudyStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// A capsule with how many cards are ready to study.
struct StudyDueBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.subheadline.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color.accentColor, in: Capsule())
            .accessibilityLabel("\(StudyFormat.cards(count)) to study")
    }
}

/// "12 cards due today" with the reviews / new split, for banners and cards.
struct StudyDueSummary: View {
    let totals: StudyDueTotals

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if totals.total > 0 {
                Text("\(totals.total)")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Color.accentColor)
            } else {
                Image(systemName: "checkmark.seal.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.hakiPositive)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if totals.total == 0 { return "All caught up" }
        return totals.total == 1 ? "card due today" : "cards due today"
    }

    private var subtitle: String {
        if totals.total > 0 {
            return StudyFormat.breakdown(reviews: totals.reviews, fresh: totals.fresh)
        }
        if let next = totals.nextReviewAt {
            return "Next review \(next.formatted(.relative(presentation: .named)))."
        }
        return "Nothing to review right now."
    }
}

/// A note in a list: title (pinned mark), date and a preview of the text.
struct NoteListRow: View {
    let note: Note

    var body: some View {
        let snippet = StudyFormat.snippet(note)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if note.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Pinned")
                }
                Text(StudyFormat.title(for: note))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(StudyFormat.noteDate(note.updatedAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .layoutPriority(1)
                Text(snippet.isEmpty ? "No additional text" : snippet)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A deck in a list: icon, name, what's due, and a badge with the count to study.
struct DeckListRow: View {
    let deck: FlashcardDeck
    let counts: StudyDeckCounts

    var body: some View {
        HStack(spacing: 12) {
            StudyIconTile(systemImage: "rectangle.on.rectangle.angled", tint: .indigo, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(deck.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 8)
            if counts.toStudy > 0 {
                StudyDueBadge(count: counts.toStudy)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "5 due · 12 new · 40 cards", "All caught up · 40 cards" or "No cards yet".
    private var summary: String {
        guard counts.total > 0 else { return "No cards yet" }
        var parts: [String] = []
        if counts.due > 0 { parts.append("\(counts.due) due") }
        if counts.fresh > 0 { parts.append("\(counts.fresh) new") }
        if parts.isEmpty { parts.append("All caught up") }
        parts.append(StudyFormat.cards(counts.total))
        return parts.joined(separator: " · ")
    }
}

#Preview("Rows") {
    List {
        NoteListRow(note: PreviewData.sampleNote)
        DeckListRow(deck: PreviewData.sampleDeck, counts: StudyDeckCounts(deck: PreviewData.sampleDeck))
        StudyDueSummary(totals: StudyDueTotals(decks: [PreviewData.sampleDeck]))
    }
    .previewEnvironment()
}
