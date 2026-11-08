//
//  MonthInterval.swift
//  Haki
//
//  Pure Foundation code (see Money.swift).
//

import Foundation

/// A calendar month, independent of time zone until you ask for its dates.
nonisolated struct MonthInterval: Hashable, Comparable, Identifiable, Codable {
    let year: Int
    /// 1...12
    let month: Int

    var id: String { "\(year)-\(month)" }

    /// Normalizes out-of-range months, so `MonthInterval(year: 2026, month: 13)`
    /// is January 2027 and `month: 0` is December of the previous year.
    init(year: Int, month: Int) {
        let total = year * 12 + (month - 1)
        let normalizedYear = total >= 0 ? total / 12 : (total - 11) / 12
        self.year = normalizedYear
        self.month = total - normalizedYear * 12 + 1
    }

    init(containing date: Date, calendar: Calendar = .current) {
        let components = calendar.dateComponents([.year, .month], from: date)
        self.init(year: components.year ?? 2000, month: components.month ?? 1)
    }

    static func current(calendar: Calendar = .current, now: Date = .now) -> MonthInterval {
        MonthInterval(containing: now, calendar: calendar)
    }

    // MARK: Navigation

    func adding(months: Int) -> MonthInterval {
        MonthInterval(year: year, month: month + months)
    }

    var next: MonthInterval { adding(months: 1) }
    var previous: MonthInterval { adding(months: -1) }

    /// `count` months ending with (and including) `last`, oldest first.
    static func trailing(_ count: Int, endingAt last: MonthInterval) -> [MonthInterval] {
        guard count > 0 else { return [] }
        return (0..<count).reversed().map { last.adding(months: -$0) }
    }

    // MARK: Dates

    /// Midnight on the first day of the month.
    func start(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
    }

    /// Midnight on the first day of the *next* month (exclusive end).
    func end(in calendar: Calendar = .current) -> Date {
        next.start(in: calendar)
    }

    /// `start ..< end`. Note that `DateInterval.contains` treats the end as
    /// inclusive; use `MonthInterval.contains(_:calendar:)` instead.
    func dateInterval(in calendar: Calendar = .current) -> DateInterval {
        DateInterval(start: start(in: calendar), end: end(in: calendar))
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        date >= start(in: calendar) && date < end(in: calendar)
    }

    func numberOfDays(in calendar: Calendar = .current) -> Int {
        calendar.range(of: .day, in: .month, for: start(in: calendar))?.count ?? 30
    }

    /// How many days of this month have started by `now`: the full length for
    /// past months, `0` for future months, today's day number for this month.
    func elapsedDays(asOf now: Date = .now, calendar: Calendar = .current) -> Int {
        let current = MonthInterval(containing: now, calendar: calendar)
        if self < current { return numberOfDays(in: calendar) }
        if self > current { return 0 }
        return calendar.component(.day, from: now)
    }

    // MARK: Display

    /// "November 2026"
    func title(calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle.dateTime.month(.wide).year()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return start(in: calendar).formatted(style)
    }

    /// "Nov"
    func shortTitle(calendar: Calendar = .current, locale: Locale = .current) -> String {
        var style = Date.FormatStyle.dateTime.month(.abbreviated)
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return start(in: calendar).formatted(style)
    }

    static func < (lhs: MonthInterval, rhs: MonthInterval) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

nonisolated extension Calendar {
    /// Noon on the same calendar day. Haki stores transaction dates at local
    /// noon so a calendar day survives small time-zone changes without
    /// slipping into the previous or next day.
    func noon(on date: Date) -> Date {
        let parts = dateComponents([.year, .month, .day], from: date)
        return self.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day, hour: 12))
            ?? date
    }

    /// Noon on a specific calendar day.
    func noon(year: Int, month: Int, day: Int) -> Date? {
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = self.date(from: components) else { return nil }
        // Reject impossible days such as February 30 instead of rolling over.
        let check = dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else { return nil }
        return date
    }

    /// Whole calendar days from `start` to `end` (negative if `end` is earlier).
    func daysBetween(_ start: Date, _ end: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: start), to: startOfDay(for: end)).day ?? 0
    }
}
