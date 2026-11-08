//
//  SampleLedger.swift
//  Haki
//
//  Pure Foundation code (see Money.swift).
//

import Foundation

/// Realistic, deterministic demo data: accounts, a few months of
/// transactions, tracked recurring bills and a year of balance history.
///
/// Used for "Load sample data", for SwiftUI previews and in unit tests.
/// All institutions and employers are fictional.
nonisolated struct SampleLedger: Hashable {
    struct AccountSpec: Hashable {
        let key: String
        let name: String
        let institution: String
        let kind: AccountKind
        /// Current balance (amount owed for liabilities).
        let balanceCents: Int
        let mask: String
    }

    struct TransactionSpec: Hashable {
        let date: Date
        let description: String
        /// Haki sign convention: positive = money out.
        let amountCents: Int
        let categorySeedKey: String?
        let accountKey: String
        let isReviewed: Bool
    }

    struct RecurringSpec: Hashable {
        let name: String
        let merchantKey: String
        let amountCents: Int
        let frequency: RecurrenceFrequency
        let anchor: Date
        let categorySeedKey: String?
    }

    struct BalanceSpec: Hashable {
        let accountKey: String
        let date: Date
        let balanceCents: Int
    }

    var accounts: [AccountSpec]
    var transactions: [TransactionSpec]
    var recurring: [RecurringSpec]
    var balances: [BalanceSpec]

    /// The demo accounts. Their (fictional) institutions mark them as sample data.
    static let accountSpecs = [
        AccountSpec(key: "checking", name: "Everyday Checking", institution: "Harborline Bank", kind: .checking, balanceCents: 4_812_37, mask: "4821"),
        AccountSpec(key: "savings", name: "High-Yield Savings", institution: "Harborline Bank", kind: .savings, balanceCents: 18_250_00, mask: "7730"),
        AccountSpec(key: "card", name: "Everyday Rewards Card", institution: "Northwind Card", kind: .creditCard, balanceCents: 1_243_88, mask: "1009"),
        AccountSpec(key: "brokerage", name: "Brokerage", institution: "Tidewater Invest", kind: .investment, balanceCents: 42_380_15, mask: "5512"),
        AccountSpec(key: "retirement", name: "401(k)", institution: "Tidewater Invest", kind: .investment, balanceCents: 61_904_62, mask: "0042"),
        AccountSpec(key: "auto", name: "Auto Loan", institution: "Summit Credit Union", kind: .loan, balanceCents: 9_420_00, mask: "3318"),
    ]

    /// Institutions of the demo accounts.
    static var institutions: Set<String> { Set(accountSpecs.map(\.institution)) }

    // MARK: Generation

    /// - Parameters:
    ///   - months: calendar months of transactions, including the current one.
    static func generate(now: Date = .now, months: Int = 4, calendar: Calendar = .current, seed: UInt64 = 7) -> SampleLedger {
        var rng = SeededGenerator(seed: seed)
        let today = calendar.noon(on: now)
        let firstMonth = MonthInterval(containing: now, calendar: calendar).adding(months: -(max(1, months) - 1))
        let start = calendar.noon(on: firstMonth.start(in: calendar))

        let accounts = accountSpecs

        var transactions: [TransactionSpec] = []
        func add(_ date: Date, _ description: String, _ cents: Int, account: String, category: String? = nil) {
            guard date >= start, date <= today else { return }
            let seedKey = category ?? Categorizer.suggestedSeedKey(description: description, amountCents: cents) ?? "general"
            transactions.append(TransactionSpec(
                date: date,
                description: description,
                amountCents: cents,
                categorySeedKey: seedKey,
                accountKey: account,
                isReviewed: calendar.daysBetween(date, today) > 6
            ))
        }
        func random(_ range: ClosedRange<Int>) -> Int { Int.random(in: range, using: &rng) }
        func chance(_ percent: Int) -> Bool { random(1...100) <= percent }

        // Fixed monthly bills, anchored to a day of the month.
        struct MonthlyBill {
            let day: Int
            let description: String
            let cents: ClosedRange<Int>
            let account: String
        }
        let monthlyBills = [
            MonthlyBill(day: 1, description: "OAKWOOD APARTMENTS RENT", cents: 2_150_00...2_150_00, account: "checking"),
            MonthlyBill(day: 3, description: "NYTIMES DIGITAL", cents: 4_00...4_00, account: "card"),
            MonthlyBill(day: 5, description: "NETFLIX.COM 866-579-7172 CA", cents: 15_49...15_49, account: "card"),
            MonthlyBill(day: 9, description: "COMCAST XFINITY INTERNET", cents: 79_99...79_99, account: "checking"),
            MonthlyBill(day: 12, description: "SPOTIFY USA", cents: 11_99...11_99, account: "card"),
            MonthlyBill(day: 15, description: "SUMMIT CREDIT UNION AUTO PMT", cents: 385_00...385_00, account: "checking"),
            MonthlyBill(day: 17, description: "PLANET FITNESS CLUB FEES", cents: 24_99...24_99, account: "card"),
            MonthlyBill(day: 18, description: "PG&E WEB ONLINE", cents: 92_00...138_00, account: "checking"),
            MonthlyBill(day: 20, description: "APPLE.COM/BILL 866-712-7753", cents: 2_99...2_99, account: "card"),
            MonthlyBill(day: 22, description: "VERIZON WIRELESS PAYMENTS", cents: 85_00...85_00, account: "checking"),
            MonthlyBill(day: 26, description: "THE BARBER SHOP", cents: 35_00...35_00, account: "card"),
        ]

        var month = firstMonth
        let currentMonth = MonthInterval(containing: now, calendar: calendar)
        while month <= currentMonth {
            let days = month.numberOfDays(in: calendar)
            for bill in monthlyBills {
                if let date = calendar.noon(year: month.year, month: month.month, day: min(bill.day, days)) {
                    add(date, bill.description, random(bill.cents), account: bill.account,
                        category: bill.description.contains("AUTO PMT") ? "transfer" : nil)
                }
            }
            // Savings transfer, interest and the card payment.
            if let date = calendar.noon(year: month.year, month: month.month, day: 2) {
                add(date, "ONLINE TRANSFER TO SAVINGS", 500_00, account: "checking")
                add(date, "ONLINE TRANSFER FROM CHECKING", -500_00, account: "savings")
            }
            if let date = calendar.noon(year: month.year, month: month.month, day: min(28, days)) {
                add(date, "INTEREST PAYMENT", -random(58_00...64_00), account: "savings")
            }
            if let date = calendar.noon(year: month.year, month: month.month, day: 24) {
                let payment = random(1_150_00...1_650_00)
                add(date, "NORTHWIND CARD AUTOPAY", payment, account: "checking")
                add(date, "PAYMENT THANK YOU", -payment, account: "card")
            }
            month = month.next
        }

        // Paychecks every other Friday.
        var payday = start
        while calendar.component(.weekday, from: payday) != 6 {
            payday = calendar.date(byAdding: .day, value: 1, to: payday) ?? payday
        }
        while payday <= today {
            add(payday, "BRIGHTWAVE LABS PAYROLL DIRECT DEP", -4_250_00, account: "checking")
            payday = calendar.date(byAdding: .day, value: 14, to: payday) ?? today.addingTimeInterval(1)
        }

        // Day-to-day spending.
        let groceries = ["TRADER JOE'S #552", "WHOLEFDS MKT 10234", "SAFEWAY #1711"]
        let coffee = ["SQ *BLUE BOTTLE COFFEE", "STARBUCKS STORE 05521", "PHILZ COFFEE"]
        let restaurants = ["TST* JOE'S PIZZA", "SQ *TACOLICIOUS TAQUERIA", "DOORDASH*SWEETGREEN", "CHIPOTLE 1234", "UBER *EATS PENDING", "RAMEN NOJO"]
        let shopping = ["AMAZON.COM*2K4AB1C23 AMZN.COM/BILLWA", "TARGET 00012345", "AMZN MKTP US*1A2B3C"]

        var day = start
        var nextGas = calendar.date(byAdding: .day, value: random(2...6), to: start) ?? start
        while day <= today {
            let weekday = calendar.component(.weekday, from: day)
            let isWeekend = weekday == 1 || weekday == 7

            if chance(isWeekend ? 35 : 55) {
                add(day, coffee[random(0...(coffee.count - 1))], random(4_50...7_25), account: "card")
            }
            if chance(isWeekend ? 45 : 14) {
                add(day, groceries[random(0...(groceries.count - 1))], random(28_00...165_00), account: "card")
            }
            if chance(isWeekend ? 50 : 22) {
                add(day, restaurants[random(0...(restaurants.count - 1))], random(14_00...78_00), account: "card")
            }
            if chance(12) {
                add(day, "UBER *TRIP HELP.UBER.COM", random(11_00...36_00), account: "card")
            }
            if chance(9) {
                add(day, shopping[random(0...(shopping.count - 1))], random(12_00...140_00), account: "card")
            }
            if chance(4) {
                add(day, "AMC THEATRES 1029", random(18_00...42_00), account: "card")
            }
            if day >= nextGas {
                add(day, "SHELL OIL 57444", random(42_00...68_00), account: "card")
                nextGas = calendar.date(byAdding: .day, value: random(8...12), to: day) ?? today
            }
            day = calendar.date(byAdding: .day, value: 1, to: day) ?? today.addingTimeInterval(1)
        }

        // One refund and one trip, so those cases show up in the UI.
        if let refundDay = calendar.date(byAdding: .day, value: -9, to: today) {
            add(refundDay, "AMAZON.COM REFUND", -34_99, account: "card", category: "shopping")
        }
        if let tripDay = calendar.date(byAdding: .day, value: -40, to: today) {
            add(tripDay, "UNITED AIRLINES 0162345", 412_80, account: "card")
            if let hotelDay = calendar.date(byAdding: .day, value: 6, to: tripDay) {
                add(hotelDay, "MARRIOTT DOWNTOWN", 538_20, account: "card")
            }
        }

        transactions.sort { $0.date != $1.date ? $0.date > $1.date : $0.description < $1.description }

        // Bills the user tracks. NYTimes, Apple and the barber are left
        // untracked so the recurring screen has suggestions.
        func anchor(day: Int) -> Date {
            calendar.noon(year: firstMonth.year, month: firstMonth.month, day: day) ?? start
        }
        let recurring = [
            RecurringSpec(name: "Rent", merchantKey: MerchantNormalizer.key(for: "OAKWOOD APARTMENTS RENT"), amountCents: 2_150_00, frequency: .monthly, anchor: anchor(day: 1), categorySeedKey: "housing"),
            RecurringSpec(name: "Netflix", merchantKey: MerchantNormalizer.key(for: "Netflix"), amountCents: 15_49, frequency: .monthly, anchor: anchor(day: 5), categorySeedKey: "subscriptions"),
            RecurringSpec(name: "Xfinity Internet", merchantKey: MerchantNormalizer.key(for: "Xfinity"), amountCents: 79_99, frequency: .monthly, anchor: anchor(day: 9), categorySeedKey: "utilities"),
            RecurringSpec(name: "Spotify", merchantKey: MerchantNormalizer.key(for: "Spotify"), amountCents: 11_99, frequency: .monthly, anchor: anchor(day: 12), categorySeedKey: "subscriptions"),
            RecurringSpec(name: "Planet Fitness", merchantKey: MerchantNormalizer.key(for: "Planet Fitness"), amountCents: 24_99, frequency: .monthly, anchor: anchor(day: 17), categorySeedKey: "health"),
            RecurringSpec(name: "PG&E", merchantKey: MerchantNormalizer.key(for: "PG&E"), amountCents: 115_00, frequency: .monthly, anchor: anchor(day: 18), categorySeedKey: "utilities"),
            RecurringSpec(name: "Verizon", merchantKey: MerchantNormalizer.key(for: "Verizon"), amountCents: 85_00, frequency: .monthly, anchor: anchor(day: 22), categorySeedKey: "utilities"),
        ]

        // Weekly balance history for the past year, ending at today's balance.
        var balances: [BalanceSpec] = []
        let trends: [String: (weekly: Int, noise: Int)] = [
            "checking": (0, 900_00), "savings": (115_00, 0), "card": (0, 400_00),
            "brokerage": (95_00, 1_400_00), "retirement": (210_00, 1_100_00), "auto": (-88_00, 0),
        ]
        for account in accounts {
            let trend = trends[account.key] ?? (0, 0)
            for weeksAgo in stride(from: 52, through: 0, by: -1) {
                // Dated from `now`, not noon, so the newest snapshot is never in the future.
                guard let date = calendar.date(byAdding: .day, value: -7 * weeksAgo, to: now) else { continue }
                let noise = trend.noise == 0 || weeksAgo == 0 ? 0 : random(-trend.noise...trend.noise)
                let value = max(0, account.balanceCents - trend.weekly * weeksAgo + noise)
                balances.append(BalanceSpec(accountKey: account.key, date: date, balanceCents: value))
            }
        }

        return SampleLedger(accounts: accounts, transactions: transactions, recurring: recurring, balances: balances)
    }
}

/// SplitMix64: a tiny deterministic random number generator, so sample data
/// is the same on every run and platform.
nonisolated struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
