//
//  RecurringComponents.swift
//  Haki
//
//  Building blocks for the Recurring screens: status styling, formatting
//  helpers, bill and due-date rows, the "paid" ring and the month calendar.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Status

/// How one due date stands, simplified for display. Raw values grow with
/// urgency, so the calendar can show the most pressing status of a day.
enum RecurringStatusKind: Int, CaseIterable, Identifiable {
    case paid
    case upcoming
    case late

    var id: Int { rawValue }

    init(_ status: RecurringOccurrenceStatus) {
        switch status {
        case .paid: self = .paid
        case .upcoming: self = .upcoming
        case .late: self = .late
        }
    }

    var title: String {
        switch self {
        case .paid: "Paid"
        case .upcoming: "Upcoming"
        case .late: "Late"
        }
    }

    var systemImage: String {
        switch self {
        case .paid: "checkmark.circle.fill"
        case .upcoming: "clock"
        case .late: "exclamationmark.circle.fill"
        }
    }

    /// A small glyph for the month calendar. Each status has its own shape,
    /// so the calendar doesn't rely on color alone.
    var calendarSymbol: String {
        switch self {
        case .paid: "checkmark.circle.fill"
        case .upcoming: "circle.fill"
        case .late: "exclamationmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .paid: Color.hakiPositive
        case .upcoming: Color.accentColor
        case .late: Color.hakiNegative
        }
    }
}

// MARK: - Formatting

enum RecurringFormat {
    /// "Nov 22"
    static func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "$15.49/mo"
    static func amount(_ cents: Int, _ frequency: RecurrenceFrequency) -> String {
        Money.format(cents) + frequency.shortSuffix
    }

    /// "Due today", "Due tomorrow", "Due in 3 days", "Due Nov 22" or "Was due Nov 3".
    static func duePhrase(for date: Date, now: Date, calendar: Calendar = .current) -> String {
        let days = calendar.daysBetween(now, date)
        if days == 0 { return "Due today" }
        if days == 1 { return "Due tomorrow" }
        if days < 0 { return "Was due \(shortDate(date))" }
        if days < 7 { return "Due in \(days) days" }
        return "Due \(shortDate(date))"
    }

    /// "1 bill", "3 bills"
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        let noun = value == 1 ? singular : plural
        return "\(value) \(noun)"
    }

    /// "42%"
    static func percent(_ fraction: Double) -> String {
        let clamped = min(1, max(0, fraction))
        let value = Int((clamped * 100).rounded())
        return "\(value)%"
    }
}

// MARK: - Status chip and legend

/// "3 paid" with the status icon.
struct RecurringStatusChip: View {
    let kind: RecurringStatusKind
    let count: Int

    var body: some View {
        Label {
            Text(RecurringFormat.count(count, kind.title.lowercased(), kind.title.lowercased()))
        } icon: {
            Image(systemName: kind.systemImage)
                .foregroundStyle(kind.tint)
        }
        .font(.footnote.weight(.medium))
    }
}

/// Explains the calendar glyphs.
struct RecurringStatusLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            ForEach(RecurringStatusKind.allCases) { kind in
                Label {
                    Text(kind.title)
                } icon: {
                    Image(systemName: kind.calendarSymbol)
                        .imageScale(.small)
                        .foregroundStyle(kind.tint)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
}

// MARK: - Paid ring

/// A ring that fills as this month's bills get paid.
struct RecurringPaidRing: View {
    /// 0...1
    let fraction: Double

    var body: some View {
        let clamped = min(1, max(0, fraction))
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(clamped))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(RecurringFormat.percent(clamped))
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("paid")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(10)
        }
        .animation(.snappy, value: clamped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Paid this month")
        .accessibilityValue(RecurringFormat.percent(clamped))
    }
}

// MARK: - Date badge

/// A small calendar tile: weekday above the day number.
struct RecurringDateBadge: View {
    let date: Date
    var tint: Color = .accentColor

    var body: some View {
        VStack(spacing: 0) {
            Text(date.formatted(.dateTime.weekday(.abbreviated)))
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(tint)
            Text(date.formatted(.dateTime.day()))
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(minWidth: 46)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(date.formatted(date: .long, time: .omitted))
    }
}

// MARK: - Bill row

/// A tracked bill: category icon, name, next due date, amount. The amount's
/// suffix (/wk, /2wk, /mo, /qtr, /yr) carries the frequency, so the subtitle
/// leaves it out to stay on one line.
struct RecurringBillRow: View {
    let item: RecurringItem
    let nextDueDate: Date
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: item.category)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityLabel("\(item.frequency.displayName), \(subtitle)")
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(RecurringFormat.amount(item.amountCents, item.frequency))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                if item.frequency != .monthly {
                    Text(monthlyEquivalent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .opacity(item.isActive ? 1 : 0.65)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard item.isActive else { return "Paused" }
        return RecurringFormat.duePhrase(for: nextDueDate, now: now)
    }

    private var monthlyEquivalent: String {
        "≈ \(Money.format(item.monthlyCostCents))/mo"
    }
}

// MARK: - Due date row

/// One due date this month with its status: paid, upcoming or late.
struct RecurringOccurrenceRow: View {
    let occurrence: RecurringScreenModel.Occurrence

    var body: some View {
        HStack(spacing: 12) {
            RecurringDateBadge(date: occurrence.dueDate, tint: occurrence.kind.tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(occurrence.item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Label {
                    Text(statusText)
                } icon: {
                    Image(systemName: occurrence.kind.systemImage)
                }
                .font(.subheadline)
                .foregroundStyle(statusColor)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(amountCents))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(occurrence.kind == .late ? Color.hakiNegative : Color.primary)
                if let paid = occurrence.paidCents, paid != occurrence.item.amountCents {
                    Text(usualAmountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var usualAmountText: String {
        "Usually \(Money.format(occurrence.item.amountCents))"
    }

    /// What was charged for paid bills, the expected amount otherwise.
    private var amountCents: Int {
        occurrence.paidCents ?? occurrence.item.amountCents
    }

    private var statusText: String {
        switch occurrence.status {
        case .paid(on: let date, amountCents: _):
            return "Paid \(RecurringFormat.shortDate(date))"
        case .upcoming:
            switch occurrence.daysUntil {
            case 0: return "Due today"
            case 1: return "Due tomorrow"
            default: return "Due in \(occurrence.daysUntil) days"
            }
        case .late:
            let overdue = max(1, -occurrence.daysUntil)
            return "Late · \(RecurringFormat.count(overdue, "day", "days")) overdue"
        }
    }

    private var statusColor: Color {
        switch occurrence.kind {
        case .paid: return Color.hakiPositive
        case .late: return Color.hakiNegative
        case .upcoming: return occurrence.daysUntil == 0 ? Color.hakiWarning : Color.secondary
        }
    }
}

// MARK: - Month calendar

private struct RecurringCalendarWeekday: Identifiable {
    let id: Int
    let symbol: String
}

private struct RecurringCalendarDay: Identifiable {
    let id: Int
    /// `nil` for the blank cells before the 1st.
    let day: Int?
}

/// A compact month grid. Days with bills carry a status glyph; today is circled.
struct RecurringMonthCalendar: View {
    let month: MonthInterval
    /// Today's day number when `month` is the current month.
    let today: Int?
    /// The most urgent status of the bills due on each day of the month.
    let marks: [Int: RecurringStatusKind]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(weekdays) { weekday in
                Text(weekday.symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
            ForEach(days) { cell in
                dayView(cell)
            }
        }
    }

    private var calendar: Calendar { Calendar.current }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
    }

    private var weekdays: [RecurringCalendarWeekday] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return (0..<7).map { offset in
            let index = (first + offset) % 7
            let symbol = symbols.indices.contains(index) ? symbols[index] : ""
            // Negative ids keep the headers distinct from the day cells in the grid.
            return RecurringCalendarWeekday(id: -(offset + 1), symbol: symbol)
        }
    }

    private var days: [RecurringCalendarDay] {
        let start = month.start(in: calendar)
        let weekday = calendar.component(.weekday, from: start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let count = month.numberOfDays(in: calendar)
        var cells: [RecurringCalendarDay] = []
        for index in 0..<leading {
            cells.append(RecurringCalendarDay(id: index, day: nil))
        }
        for day in 1...max(1, count) {
            cells.append(RecurringCalendarDay(id: leading + day - 1, day: day))
        }
        return cells
    }

    @ViewBuilder
    private func dayView(_ cell: RecurringCalendarDay) -> some View {
        if let day = cell.day {
            let isToday = day == today
            VStack(spacing: 2) {
                Text(String(day))
                    .font(.footnote.weight(isToday ? .bold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.accentColor : Color.primary)
                    .frame(minWidth: 26, minHeight: 26)
                    .background {
                        if isToday {
                            Circle()
                                .fill(Color.accentColor.opacity(0.15))
                        }
                    }
                marker(for: marks[day])
            }
            .frame(maxWidth: .infinity)
        } else {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: 1)
        }
    }

    @ViewBuilder
    private func marker(for kind: RecurringStatusKind?) -> some View {
        if let kind {
            Image(systemName: kind.calendarSymbol)
                .font(.caption2)
                .imageScale(.small)
                .foregroundStyle(kind.tint)
        } else {
            Image(systemName: "circle.fill")
                .font(.caption2)
                .imageScale(.small)
                .hidden()
        }
    }
}

// MARK: - Previews

#Preview("Rows") {
    let item = PreviewData.sampleRecurringItem
    return ScrollView {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 0) {
                RecurringBillRow(item: item, nextDueDate: item.nextDueDate(), now: .now)
            }
            .hakiCard()

            HStack(spacing: 16) {
                RecurringPaidRing(fraction: 0.62)
                    .frame(width: 80, height: 80)
                VStack(alignment: .leading, spacing: 6) {
                    RecurringStatusChip(kind: .paid, count: 4)
                    RecurringStatusChip(kind: .upcoming, count: 3)
                    RecurringStatusChip(kind: .late, count: 1)
                }
            }
            .hakiCard()

            VStack(alignment: .leading, spacing: 12) {
                RecurringMonthCalendar(month: .current(), today: 8,
                                       marks: [1: .paid, 5: .paid, 7: .late, 12: .upcoming, 22: .upcoming])
                RecurringStatusLegend()
            }
            .hakiCard()
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
