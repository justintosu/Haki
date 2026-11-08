//
//  RecurringScreenModel.swift
//  Haki
//
//  Everything the Recurring screen shows, computed in one pass from the
//  tracked bills and the transaction history.
//

import Foundation
import SwiftData

struct RecurringScreenModel {
    /// One due date of an active bill in the current month.
    struct Occurrence: Identifiable {
        let id: String
        let item: RecurringItem
        let dueDate: Date
        let status: RecurringOccurrenceStatus
        /// Calendar days from today to the due date (negative once it has passed).
        let daysUntil: Int

        var kind: RecurringStatusKind { RecurringStatusKind(status) }

        /// What was actually charged, for paid due dates.
        var paidCents: Int? {
            if case .paid(on: _, amountCents: let cents) = status { return cents }
            return nil
        }
    }

    /// A tracked bill with its next due date.
    struct Bill: Identifiable {
        let item: RecurringItem
        let nextDueDate: Date

        var id: UUID { item.id }
    }

    let now: Date
    let month: MonthInterval
    /// Active bills, soonest due first.
    let activeBills: [Bill]
    /// Paused bills, by name.
    let pausedBills: [Bill]
    /// Every due date of an active bill this month, by date.
    let occurrences: [Occurrence]
    let suggestions: [RecurringCandidate]
    /// Day of month → the most urgent status of the bills due that day.
    let dayMarks: [Int: RecurringStatusKind]
    let monthlyTotalCents: Int
    let yearlyTotalCents: Int
    /// What has been charged for this month's paid bills.
    let paidThisMonthCents: Int
    /// The expected amounts of this month's upcoming and late bills.
    let remainingThisMonthCents: Int
    let paidCount: Int
    let upcomingCount: Int
    let lateCount: Int

    var dueThisMonthCents: Int { paidThisMonthCents + remainingThisMonthCents }

    var paidFraction: Double {
        guard dueThisMonthCents > 0 else { return 0 }
        return Double(paidThisMonthCents) / Double(dueThisMonthCents)
    }

    var hasBills: Bool { !activeBills.isEmpty || !pausedBills.isEmpty }

    /// - Parameters:
    ///   - transactions: every transaction; only a window around this month is
    ///     used for payment matching, the whole history for suggestions.
    ///   - dismissedKeys: merchant keys of suggestions the user dismissed.
    init(
        items: [RecurringItem],
        transactions: [TransactionRecord],
        dismissedKeys: Set<String>,
        now: Date,
        calendar: Calendar = .current
    ) {
        self.now = now
        let currentMonth = MonthInterval.current(calendar: calendar, now: now)
        self.month = currentMonth

        // Bills
        var active: [Bill] = []
        var paused: [Bill] = []
        for item in items {
            let bill = Bill(item: item, nextDueDate: item.nextDueDate(onOrAfter: now, calendar: calendar))
            if item.isActive {
                active.append(bill)
            } else {
                paused.append(bill)
            }
        }
        active.sort { lhs, rhs in
            if lhs.nextDueDate != rhs.nextDueDate { return lhs.nextDueDate < rhs.nextDueDate }
            return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
        }
        paused.sort { lhs, rhs in
            lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
        }
        self.activeBills = active
        self.pausedBills = paused

        // Totals
        var monthly = 0
        var yearly = 0
        for bill in active {
            monthly += bill.item.monthlyCostCents
            yearly += bill.item.frequency.yearlyCents(bill.item.amountCents)
        }
        self.monthlyTotalCents = monthly
        self.yearlyTotalCents = yearly

        // This month's due dates, matched against nearby transactions.
        let interval = currentMonth.dateInterval(in: calendar)
        let windowStart = calendar.date(byAdding: .day, value: -7, to: interval.start) ?? interval.start
        let windowEnd = calendar.date(byAdding: .day, value: 7, to: interval.end) ?? interval.end
        let nearby = transactions.filter { $0.date >= windowStart && $0.date < windowEnd }

        var found: [Occurrence] = []
        for bill in active {
            let item = bill.item
            for dueDate in item.schedule.occurrences(in: interval, calendar: calendar) {
                let status = RecurringMatcher.status(
                    dueDate: dueDate,
                    merchantKey: item.merchantKey,
                    frequency: item.frequency,
                    entries: nearby,
                    now: now,
                    calendar: calendar
                )
                let id = "\(item.id.uuidString)-\(Int(dueDate.timeIntervalSince1970))"
                found.append(Occurrence(id: id, item: item, dueDate: dueDate, status: status,
                                        daysUntil: calendar.daysBetween(now, dueDate)))
            }
        }
        found.sort { lhs, rhs in
            if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
            return lhs.item.name.localizedCaseInsensitiveCompare(rhs.item.name) == .orderedAscending
        }
        self.occurrences = found

        var paidTotal = 0
        var remainingTotal = 0
        var paidTally = 0
        var upcomingTally = 0
        var lateTally = 0
        var marks: [Int: RecurringStatusKind] = [:]
        for occurrence in found {
            switch occurrence.status {
            case .paid(on: _, amountCents: let cents):
                paidTotal += cents
                paidTally += 1
            case .upcoming:
                remainingTotal += occurrence.item.amountCents
                upcomingTally += 1
            case .late:
                remainingTotal += occurrence.item.amountCents
                lateTally += 1
            }
            let day = calendar.component(.day, from: occurrence.dueDate)
            let kind = occurrence.kind
            if let existing = marks[day], existing.rawValue >= kind.rawValue { continue }
            marks[day] = kind
        }
        self.paidThisMonthCents = paidTotal
        self.remainingThisMonthCents = remainingTotal
        self.paidCount = paidTally
        self.upcomingCount = upcomingTally
        self.lateCount = lateTally
        self.dayMarks = marks

        // Suggestions: skip merchants already tracked (exactly or by a
        // matching rule key) and ones the user dismissed.
        let trackedKeys = items.map(\.merchantKey)
        let excluded = Set(trackedKeys).union(dismissedKeys)
        let candidates = RecurringDetector.candidates(
            from: transactions,
            now: now,
            calendar: calendar,
            excludingMerchantKeys: excluded
        )
        self.suggestions = candidates.filter { candidate in
            !trackedKeys.contains { Categorizer.ruleMatches(ruleKey: $0, merchantKey: candidate.merchantKey) }
        }
    }
}
