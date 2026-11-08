//
//  NetWorth.swift
//  Haki
//
//  Pure Foundation code (see Money.swift).
//

import Foundation

/// An account balance recorded at a point in time.
nonisolated struct BalanceObservation: Hashable {
    /// Stable account identifier (the account's UUID string).
    let accountID: String
    let date: Date
    /// For liabilities this is the amount owed, as a positive number.
    let balanceCents: Int
    let isLiability: Bool
}

nonisolated struct NetWorthPoint: Hashable, Identifiable {
    let date: Date
    let assetsCents: Int
    /// Amount owed, positive.
    let liabilitiesCents: Int

    var netCents: Int { assetsCents - liabilitiesCents }
    var id: Date { date }
}

/// Time spans offered by the net worth and balance charts.
nonisolated enum ChartRange: String, CaseIterable, Identifiable {
    case oneMonth = "1M"
    case threeMonths = "3M"
    case sixMonths = "6M"
    case oneYear = "1Y"

    var id: String { rawValue }

    var months: Int {
        switch self {
        case .oneMonth: 1
        case .threeMonths: 3
        case .sixMonths: 6
        case .oneYear: 12
        }
    }

    /// Sample dates, oldest first, ending exactly at `now`: daily for one
    /// month, weekly for longer ranges.
    func sampleDates(now: Date = .now, calendar: Calendar = .current) -> [Date] {
        guard let start = calendar.date(byAdding: .month, value: -months, to: now) else { return [now] }
        let stepDays = self == .oneMonth ? 1 : 7
        var dates: [Date] = []
        var date = now
        while date > start {
            dates.append(date)
            guard let previous = calendar.date(byAdding: .day, value: -stepDays, to: date) else { break }
            date = previous
        }
        dates.append(start)
        return dates.reversed()
    }
}

nonisolated enum NetWorthCalculator {
    /// Assets minus liabilities.
    static func netWorth(_ balances: [(balanceCents: Int, isLiability: Bool)]) -> Int {
        balances.reduce(0) { $0 + ($1.isLiability ? -$1.balanceCents : $1.balanceCents) }
    }

    /// Net worth at each date, using each account's latest observation on or
    /// before that date. Accounts with no observation yet are left out.
    static func series(observations: [BalanceObservation], at dates: [Date]) -> [NetWorthPoint] {
        let byAccount = Dictionary(grouping: observations, by: \.accountID)
            .mapValues { $0.sorted { $0.date < $1.date } }

        return dates.map { date in
            var assets = 0
            var liabilities = 0
            for history in byAccount.values {
                guard let latest = lastObservation(in: history, onOrBefore: date) else { continue }
                if latest.isLiability {
                    liabilities += latest.balanceCents
                } else {
                    assets += latest.balanceCents
                }
            }
            return NetWorthPoint(date: date, assetsCents: assets, liabilitiesCents: liabilities)
        }
    }

    /// Balance of one account at each date (`nil` before its first observation).
    static func balanceSeries(observations: [BalanceObservation], at dates: [Date]) -> [(date: Date, balanceCents: Int?)] {
        let history = observations.sorted { $0.date < $1.date }
        return dates.map { ($0, lastObservation(in: history, onOrBefore: $0)?.balanceCents) }
    }

    /// Binary search over observations sorted by date.
    private static func lastObservation(in sorted: [BalanceObservation], onOrBefore date: Date) -> BalanceObservation? {
        var low = 0
        var high = sorted.count
        while low < high {
            let mid = (low + high) / 2
            if sorted[mid].date <= date { low = mid + 1 } else { high = mid }
        }
        return low > 0 ? sorted[low - 1] : nil
    }
}
