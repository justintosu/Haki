//
//  main.swift
//  Haki core tests
//

import Foundation

// MARK: - Money

suite("Money.parseCents") {
    expectEqual(Money.parseCents("$1,234.56"), 123_456)
    expectEqual(Money.parseCents("-12"), -1_200)
    expectEqual(Money.parseCents("(45.00)"), -4_500)
    expectEqual(Money.parseCents("12.00-"), -1_200)
    expectEqual(Money.parseCents("USD 7.5"), 750)
    expectEqual(Money.parseCents(".5"), 50)
    expectEqual(Money.parseCents("-$0.99"), -99)
    expectEqual(Money.parseCents("$-12.00"), -1_200)
    expectEqual(Money.parseCents("1.234,56", decimalSeparator: ","), 123_456)
    expectEqual(Money.parseCents("0.005"), 1, "rounds half away from zero")
    expectEqual(Money.parseCents(""), nil)
    expectEqual(Money.parseCents("   "), nil)
    expectEqual(Money.parseCents("abc"), nil)
    expectEqual(Money.parseCents("1.2.3"), nil)
    expectEqual(Money.parseCents("$"), nil)
    // Amounts too large to be real would wrap around Int and crash later math.
    expectEqual(Money.parseCents("1000000000000"), 100_000_000_000_000, "the cap itself is accepted")
    expectEqual(Money.parseCents("1000000000000.01"), nil)
    expectEqual(Money.parseCents("99999999999999999"), nil)
    expectEqual(Money.parseCents("92233720368547758.08"), nil)
    expectEqual(Money.parseCents("-92233720368547758.08"), nil)
    expectEqual(Money.parseCents(String(repeating: "9", count: 60)), nil)
}

suite("Money.format") {
    expectEqual(Money.format(123_456, currencyCode: "USD", locale: usLocale), "$1,234.56")
    expectEqual(Money.format(-500, currencyCode: "USD", locale: usLocale), "-$5.00")
    expectEqual(Money.format(0, currencyCode: "USD", locale: usLocale), "$0.00")
    expectEqual(Money.format(123_456, currencyCode: "USD", locale: usLocale, showsCents: false), "$1,235")
    expectEqual(Money.format(1_500, currencyCode: "USD", locale: usLocale, alwaysShowsSign: true), "+$15.00")
    expectEqual(Money.compact(95_000, currencyCode: "USD", locale: usLocale), "$950")
    expectEqual(Money.compact(123_456, currencyCode: "USD", locale: usLocale), "$1.2K")
    expectEqual(Money.compact(100_000, currencyCode: "USD", locale: usLocale), "$1K")
    expectEqual(Money.compact(340_000_000, currencyCode: "USD", locale: usLocale), "$3.4M")
    expectEqual(Money.compact(-250_000, currencyCode: "USD", locale: usLocale), "-$2.5K")
    expectEqual(Money.cents(from: Decimal(string: "10.005")!), 1_001)
    expectEqual(Money.cents(from: Decimal(string: "-10.005")!), -1_001)
    expectEqual(Money.cents(from: Decimal(Int.max) * 1_000), Int.max, "clamped, not wrapped")
    expectEqual(Money.cents(from: Decimal(Int.max) * -1_000), -Int.max, "clamped, not wrapped")
    expectEqual(Money.editableText(fromCents: 1_250, locale: usLocale), "12.50")
    expectEqual(Money.editableText(fromCents: 123_456, locale: usLocale), "1234.56")
    expectEqual(Money.parseCents(Money.editableText(fromCents: -98_765, locale: usLocale)), -98_765, "round trip")
}

// MARK: - Dates

suite("MonthInterval") {
    expectEqual(MonthInterval(year: 2026, month: 13), MonthInterval(year: 2027, month: 1))
    expectEqual(MonthInterval(year: 2026, month: 0), MonthInterval(year: 2025, month: 12))
    expectEqual(MonthInterval(year: 2026, month: -11), MonthInterval(year: 2025, month: 1))
    expectEqual(MonthInterval(year: 2026, month: 11).adding(months: 14), MonthInterval(year: 2028, month: 1))
    expectEqual(MonthInterval(year: 2028, month: 2).numberOfDays(in: testCalendar), 29)
    expectEqual(MonthInterval(year: 2026, month: 2).numberOfDays(in: testCalendar), 28)

    let november = MonthInterval(year: 2026, month: 11)
    expect(november.contains(day(2026, 11, 1), calendar: testCalendar))
    expect(november.contains(day(2026, 11, 30), calendar: testCalendar))
    expect(!november.contains(day(2026, 12, 1), calendar: testCalendar))
    expect(!november.contains(november.end(in: testCalendar), calendar: testCalendar), "end is exclusive")
    expectEqual(MonthInterval(containing: day(2026, 11, 8), calendar: testCalendar), november)

    expectEqual(MonthInterval.trailing(3, endingAt: MonthInterval(year: 2026, month: 1)),
                [MonthInterval(year: 2025, month: 11), MonthInterval(year: 2025, month: 12), MonthInterval(year: 2026, month: 1)])
    expectEqual(MonthInterval.trailing(0, endingAt: november), [])
    expectEqual(november.title(calendar: testCalendar, locale: usLocale), "November 2026")
    expectEqual(november.shortTitle(calendar: testCalendar, locale: usLocale), "Nov")

    let now = day(2026, 11, 8)
    expectEqual(november.elapsedDays(asOf: now, calendar: testCalendar), 8)
    expectEqual(november.previous.elapsedDays(asOf: now, calendar: testCalendar), 31)
    expectEqual(november.next.elapsedDays(asOf: now, calendar: testCalendar), 0)
    expect(MonthInterval(year: 2025, month: 12) < november)
}

suite("Calendar helpers") {
    expectEqual(testCalendar.noon(year: 2026, month: 2, day: 30), nil, "rejects impossible days")
    expectEqual(testCalendar.component(.hour, from: day(2026, 3, 8)), 12, "noon on a DST change day")
    expectEqual(testCalendar.daysBetween(day(2026, 1, 1), day(2026, 3, 1)), 59)
    expectEqual(testCalendar.daysBetween(day(2026, 3, 1), day(2026, 1, 1)), -59)
    expectEqual(testCalendar.noon(on: testCalendar.date(from: DateComponents(year: 2026, month: 5, day: 4, hour: 23, minute: 59))!),
                day(2026, 5, 4))
}

// MARK: - Ledger types

suite("LedgerFlow.resolve") {
    expectEqual(LedgerFlow.resolve(categoryKind: .expense, isExcluded: false, amountCents: -500), .spending, "refunds stay spending")
    expectEqual(LedgerFlow.resolve(categoryKind: .income, isExcluded: false, amountCents: -500), .income)
    expectEqual(LedgerFlow.resolve(categoryKind: .transfer, isExcluded: false, amountCents: 500), .transfer)
    expectEqual(LedgerFlow.resolve(categoryKind: .expense, isExcluded: true, amountCents: 500), .excluded)
    expectEqual(LedgerFlow.resolve(categoryKind: nil, isExcluded: false, amountCents: 500), .spending)
    expectEqual(LedgerFlow.resolve(categoryKind: nil, isExcluded: false, amountCents: -500), .income)
}

suite("AccountKind") {
    expect(AccountKind.creditCard.isLiability)
    expect(AccountKind.loan.isLiability)
    expect(!AccountKind.savings.isLiability)
    for kind in AccountKind.allCases {
        expectEqual(kind.group.isLiability, kind.isLiability, "group and kind agree for \(kind)")
    }
}

suite("RecurrenceFrequency") {
    expectEqual(RecurrenceFrequency.weekly.monthlyCents(1_000), 4_333)
    expectEqual(RecurrenceFrequency.biweekly.monthlyCents(1_200), 2_600)
    expectEqual(RecurrenceFrequency.yearly.monthlyCents(12_000), 1_000)
    expectEqual(RecurrenceFrequency.quarterly.monthlyCents(3_000), 1_000)
    expectEqual(RecurrenceFrequency.monthly.yearlyCents(1_499), 17_988)
}

suite("RecurringSchedule") {
    let endOfMonth = RecurringSchedule(anchor: day(2026, 1, 31), frequency: .monthly)
    expectEqual(endOfMonth.occurrence(1, calendar: testCalendar), day(2026, 2, 28))
    expectEqual(endOfMonth.occurrence(2, calendar: testCalendar), day(2026, 3, 31), "no drift to the 28th")
    expectEqual(endOfMonth.nextOccurrence(onOrAfter: day(2026, 3, 1), calendar: testCalendar), day(2026, 3, 31))
    expectEqual(endOfMonth.nextOccurrence(onOrAfter: day(2025, 6, 1), calendar: testCalendar), day(2026, 1, 31),
                "dates before the anchor return the anchor")
    expectEqual(endOfMonth.nextOccurrence(onOrAfter: day(2026, 1, 31), calendar: testCalendar), day(2026, 1, 31),
                "the due day itself counts")
    expectEqual(endOfMonth.occurrences(in: MonthInterval(year: 2026, month: 3).dateInterval(in: testCalendar), calendar: testCalendar),
                [day(2026, 3, 31)])
    expectEqual(endOfMonth.nextOccurrence(onOrAfter: day(2030, 7, 15), calendar: testCalendar), day(2030, 7, 31))

    let weekly = RecurringSchedule(anchor: day(2026, 11, 2), frequency: .weekly)
    let novemberWeeks = weekly.occurrences(in: MonthInterval(year: 2026, month: 11).dateInterval(in: testCalendar), calendar: testCalendar)
    expectEqual(novemberWeeks, [day(2026, 11, 2), day(2026, 11, 9), day(2026, 11, 16), day(2026, 11, 23), day(2026, 11, 30)])

    let yearly = RecurringSchedule(anchor: day(2024, 2, 29), frequency: .yearly)
    expectEqual(yearly.nextOccurrence(onOrAfter: day(2026, 1, 1), calendar: testCalendar), day(2026, 2, 28))
    expectEqual(yearly.nextOccurrence(onOrAfter: day(2027, 3, 1), calendar: testCalendar), day(2028, 2, 29))
}

// MARK: - Analytics

suite("SpendingAnalytics totals") {
    let november = MonthInterval(year: 2026, month: 11).dateInterval(in: testCalendar)
    let entries = [
        Entry(ledgerDate: day(2026, 11, 1), ledgerAmountCents: 10_000, ledgerCategoryID: "food"),
        Entry(ledgerDate: day(2026, 11, 3), ledgerAmountCents: 2_500, ledgerCategoryID: "food"),
        Entry(ledgerDate: day(2026, 11, 4), ledgerAmountCents: -1_500, ledgerCategoryID: "food"), // refund
        Entry(ledgerDate: day(2026, 11, 5), ledgerAmountCents: 4_000, ledgerCategoryID: "fun"),
        Entry(ledgerDate: day(2026, 11, 6), ledgerAmountCents: 999, ledgerCategoryID: nil),
        Entry(ledgerDate: day(2026, 11, 7), ledgerAmountCents: -300_000, ledgerFlow: .income),
        Entry(ledgerDate: day(2026, 11, 7), ledgerAmountCents: 50_000, ledgerFlow: .transfer),
        Entry(ledgerDate: day(2026, 11, 8), ledgerAmountCents: 7_000, ledgerFlow: .excluded),
        Entry(ledgerDate: day(2026, 10, 31), ledgerAmountCents: 8_000, ledgerCategoryID: "food"),
        Entry(ledgerDate: day(2026, 12, 1), ledgerAmountCents: 8_000, ledgerCategoryID: "food"),
    ]
    expectEqual(SpendingAnalytics.spending(entries, in: november), 10_000 + 2_500 - 1_500 + 4_000 + 999)
    expectEqual(SpendingAnalytics.income(entries, in: november), 300_000)
    expectEqual(SpendingAnalytics.spending(entries, categoryID: "food", in: november), 11_000)
    expectEqual(SpendingAnalytics.spending(entries, categoryID: nil, in: november), 999)

    let byCategory = SpendingAnalytics.spendingByCategory(entries, in: november)
    expectEqual(byCategory, [
        CategoryTotal(categoryID: "food", cents: 11_000),
        CategoryTotal(categoryID: "fun", cents: 4_000),
        CategoryTotal(categoryID: nil, cents: 999),
    ])

    let daily = SpendingAnalytics.cumulativeDailySpending(entries, month: MonthInterval(year: 2026, month: 11), throughDay: 5, calendar: testCalendar)
    expectEqual(daily.map(\.cents), [10_000, 10_000, 12_500, 11_000, 15_000])
    expectEqual(daily.map(\.day), [1, 2, 3, 4, 5])
    expectEqual(SpendingAnalytics.cumulativeDailySpending(entries, month: MonthInterval(year: 2026, month: 11), calendar: testCalendar).count, 30)
    expectEqual(SpendingAnalytics.cumulativeDailySpending(entries, month: MonthInterval(year: 2026, month: 11), throughDay: 0, calendar: testCalendar), [])

    let months = MonthInterval.trailing(3, endingAt: MonthInterval(year: 2026, month: 12))
    expectEqual(SpendingAnalytics.monthlyTotals(entries, months: months, calendar: testCalendar).map(\.cents), [8_000, 15_999, 8_000])
    expectEqual(SpendingAnalytics.monthlyTotals(entries, months: months, flow: .income, calendar: testCalendar).map(\.cents), [0, 300_000, 0])
    expectEqual(SpendingAnalytics.monthlyCategorySpending(entries, months: months, categoryID: "fun", calendar: testCalendar).map(\.cents), [0, 4_000, 0])
    expectEqual(SpendingAnalytics.averageMonthlySpending(entries, months: months, calendar: testCalendar), 10_666)
}

suite("SpendingAnalytics.projectedSpending") {
    // Last month: $2,000 rent on the 1st, then $10 a day.
    var entries: [Entry] = [Entry(ledgerDate: day(2026, 10, 1), ledgerAmountCents: 200_000)]
    for d in 1...31 { entries.append(Entry(ledgerDate: day(2026, 10, d), ledgerAmountCents: 1_000)) }
    // This month so far: rent again, then $20 a day for 8 days.
    entries.append(Entry(ledgerDate: day(2026, 11, 1), ledgerAmountCents: 200_000))
    for d in 1...8 { entries.append(Entry(ledgerDate: day(2026, 11, d), ledgerAmountCents: 2_000)) }
    let november = MonthInterval(year: 2026, month: 11)
    let projected = SpendingAnalytics.projectedSpending(entries, month: november, asOf: day(2026, 11, 8), calendar: testCalendar)
    // Spent 216,000 so far; last month's days 9...31 added 23 × 1,000.
    expectEqual(projected, 216_000 + 23_000, "rent isn't extrapolated")
    expectEqual(SpendingAnalytics.projectedSpending(entries, month: november.previous, asOf: day(2026, 11, 8), calendar: testCalendar),
                231_000, "past months return their total")
    let noHistory = entries.filter { $0.ledgerDate >= day(2026, 11, 1) }
    expectEqual(SpendingAnalytics.projectedSpending(noHistory, month: november, asOf: day(2026, 11, 8), calendar: testCalendar),
                810_000, "falls back to a straight line")
}

suite("BudgetProgress") {
    let progress = BudgetProgress(budgetCents: 30_000, spentCents: 12_000)
    expectEqual(progress.remainingCents, 18_000)
    expect(!progress.isOverBudget)
    expectEqual(progress.fractionUsed, 0.4)
    expectEqual(progress.pace(elapsedDays: 15, daysInMonth: 30), .onTrack)
    expectEqual(progress.pace(elapsedDays: 5, daysInMonth: 30), .onTrack, "under half the budget is never flagged")
    expectEqual(BudgetProgress(budgetCents: 30_000, spentCents: 18_000).pace(elapsedDays: 10, daysInMonth: 30), .aheadOfPace)
    expectEqual(progress.projectedCents(elapsedDays: 10, daysInMonth: 30), 36_000)
    expectEqual(progress.projectedCents(elapsedDays: 0, daysInMonth: 30), 12_000)
    expectEqual(BudgetProgress(budgetCents: 100, spentCents: Int.max / 2).projectedCents(elapsedDays: 1, daysInMonth: 31),
                Int.max, "huge stored spending is clamped instead of trapping")

    let over = BudgetProgress(budgetCents: 10_000, spentCents: 12_500)
    expect(over.isOverBudget)
    expectEqual(over.pace(elapsedDays: 3, daysInMonth: 30), .overBudget)
    expectEqual(over.fractionUsed, 1.25)
    expectEqual(BudgetProgress(budgetCents: 0, spentCents: 100).fractionUsed, 1)
    expectEqual(BudgetProgress(budgetCents: 0, spentCents: 0).fractionUsed, 0)
    expectEqual(BudgetProgress(budgetCents: 10_000, spentCents: -500).fractionUsed, 0, "net refunds don't go negative")
}

// MARK: - Merchants and categories

suite("MerchantNormalizer") {
    let cases: [(String, String)] = [
        ("SQ *BLUE BOTTLE COFFEE  San Francisco CA", "Blue Bottle Coffee"),
        ("AMAZON.COM*2K4AB1C23 AMZN.COM/BILLWA", "Amazon"),
        ("POS DEBIT 0712 TRADER JOE'S #552", "Trader Joe's"),
        ("TST* JOE'S PIZZA", "Joe's Pizza"),
        ("UBER *TRIP HELP.UBER.COM", "Uber"),
        ("UBER *EATS PENDING", "Uber Eats"),
        ("NETFLIX.COM 866-579-7172 CA", "Netflix"),
        ("PAYPAL *SPOTIFY", "Spotify"),
        ("CHECKCARD 0712 SHELL OIL 57444", "Shell"),
        ("DEBIT CARD PURCHASE - KEZAR BAR & GRILL", "Kezar Bar & Grill"),
        ("SQ *TACOLICIOUS TAQUERIA", "Tacolicious Taqueria"),
        ("OAKWOOD APARTMENTS RENT", "Oakwood Apartments Rent"),
        ("BRIGHTWAVE LABS PAYROLL DIRECT DEP", "Brightwave Labs Payroll Direct Dep"),
        ("ACH DEPOSIT BRIGHTWAVE LABS", "Brightwave Labs"),
        ("THE BARBER SHOP", "The Barber Shop"),
        ("CVS/PHARMACY #01234", "CVS Pharmacy"),
        ("KAHN'S BBQ LLC", "Kahn's BBQ"),
        ("SUMMIT CREDIT UNION AUTO PMT", "Summit Credit Union Auto PMT"),
        ("GREEN-LEAF MARKET 22 OAKLAND CA", "Green-Leaf Market Oakland"),
        ("   ", "Unknown"),
        ("12345", "12345"),
    ]
    for (raw, expected) in cases {
        expectEqual(MerchantNormalizer.displayName(for: raw), expected, "displayName(\(raw))")
    }
    // Normalizing a display name again must not change it, because stored
    // merchant keys are computed from display names.
    for (raw, _) in cases {
        let once = MerchantNormalizer.displayName(for: raw)
        expectEqual(MerchantNormalizer.displayName(for: once), once, "idempotent for \(raw)")
    }
    expectEqual(MerchantNormalizer.key(for: "SQ *BLUE BOTTLE COFFEE #12"), "bluebottlecoffee")
    expectEqual(MerchantNormalizer.key(for: "Blue Bottle Coffee"), "bluebottlecoffee")
    expectEqual(MerchantNormalizer.key(for: "PG&E WEB ONLINE"), MerchantNormalizer.key(for: "PG&E"))
}

suite("TextTokens") {
    expect(TextTokens.contains(TextTokens.tokens("SHELL OIL 5744"), ["SHELL"]))
    expect(!TextTokens.contains(TextTokens.tokens("SHELLFISH SHACK"), ["SHELL"]))
    expect(TextTokens.contains(TextTokens.tokens("UBER *EATS"), ["UBER", "EATS"]))
    expect(!TextTokens.contains(TextTokens.tokens("EATS UBER"), ["UBER", "EATS"]))
    expect(!TextTokens.contains([], ["A"]))
    expect(!TextTokens.contains(["A"], []))
}

suite("Categorizer") {
    let cases: [(String, Int, String?)] = [
        ("SQ *BLUE BOTTLE COFFEE", 650, "coffee"),
        ("UBER *EATS PENDING", 2_400, "restaurants"),
        ("UBER *TRIP HELP.UBER.COM", 1_800, "transport"),
        ("TRADER JOE'S #552", 6_400, "groceries"),
        ("NETFLIX.COM 866-579-7172 CA", 1_549, "subscriptions"),
        ("APPLE.COM/BILL 866-712-7753", 299, "subscriptions"),
        ("AMAZON.COM*2K4AB1C23 AMZN.COM/BILLWA", 3_200, "shopping"),
        ("PAYMENT THANK YOU", -120_000, "transfer"),
        ("BRIGHTWAVE LABS PAYROLL DIRECT DEP", -425_000, "income"),
        ("BRIGHTWAVE LABS PAYROLL DIRECT DEP", 425_000, nil),
        ("INTEREST PAYMENT", -6_000, "income"),
        ("OAKWOOD APARTMENTS RENT", 215_000, "housing"),
        ("PG&E WEB ONLINE", 11_500, "utilities"),
        ("SHELLFISH SHACK", 4_500, nil),
        ("KEZAR BAR & GRILL", 5_600, "restaurants"),
        ("VERIZON WIRELESS AUTOPAY", 8_500, "utilities"),
        ("NORTHWIND CARD AUTOPAY", 120_000, "transfer"),
        ("CREDIT CARD PAYMENT", 120_000, "transfer"),
        ("CARD PAYMENT TO TESCO STORES", 1_240, nil),
        ("", 100, nil),
    ]
    for (description, cents, expected) in cases {
        expectEqual(Categorizer.suggestedSeedKey(description: description, amountCents: cents), expected, description)
    }
    expect(Categorizer.ruleMatches(ruleKey: "bluebottle", merchantKey: "bluebottlecoffee"))
    expect(Categorizer.ruleMatches(ruleKey: "uber", merchantKey: "uber"))
    expect(!Categorizer.ruleMatches(ruleKey: "ub", merchantKey: "uber"), "short keys must match exactly")
    expect(!Categorizer.ruleMatches(ruleKey: "", merchantKey: "uber"))

    let keys = DefaultCategories.all.map(\.seedKey)
    expectEqual(Set(keys).count, keys.count, "seed keys are unique")
    expect(DefaultCategories.all.allSatisfy { $0.colorHex.count == 7 && $0.colorHex.hasPrefix("#") }, "hex colors are #RRGGBB")
}

// MARK: - CSV

suite("CSVParser") {
    let text = "\u{FEFF}Date,Description,Amount\r\n2026-07-01,\"Coffee, large\",-4.50\r\n2026-07-02,\"Say \"\"hi\"\"\",1\n\n2026-07-03,\"Line\nbreak\",2\r"
    let rows = CSVParser.rows(from: text)
    expectEqual(rows.count, 4)
    expectEqual(rows[0], ["Date", "Description", "Amount"])
    expectEqual(rows[1], ["2026-07-01", "Coffee, large", "-4.50"])
    expectEqual(rows[2], ["2026-07-02", "Say \"hi\"", "1"])
    expectEqual(rows[3], ["2026-07-03", "Line\nbreak", "2"])
    expectEqual(CSVParser.rows(from: "a;b;c\n1;2;3"), [["a", "b", "c"], ["1", "2", "3"]])
    expectEqual(CSVParser.rows(from: "a\tb\n1\t2"), [["a", "b"], ["1", "2"]])
    expectEqual(CSVParser.rows(from: "a,b\n1,"), [["a", "b"], ["1", ""]])
    expectEqual(CSVParser.rows(from: ""), [])
    expectEqual(CSVParser.detectDelimiter(in: "\"x;y\",b,c\n"), ",")
}

suite("CSVTransactionImporter: bank export") {
    let csv = """
    Posting Date,Description,Amount,Balance
    07/14/2026,SQ *BLUE BOTTLE COFFEE,-5.25,1000.00
    07/15/2026,ACH DEPOSIT BRIGHTWAVE LABS PAYROLL,"2,500.00",3500.00
    07/16/2026,TRADER JOE'S #552,-64.10,3435.90
    not a date,Mystery,-1.00,0
    07/17/2026,,-3.00,0
    07/18/2026,Missing amount,,0
    """
    let result = try CSVTransactionImporter.parse(csv, calendar: testCalendar)
    expectEqual(result.signConvention, .negativeIsMoneyOut, "inferred from mostly negative amounts")
    expectEqual(result.transactions.map(\.amountCents), [525, -250_000, 6_410])
    expectEqual(result.transactions.map(\.merchantName), ["Blue Bottle Coffee", "Brightwave Labs Payroll", "Trader Joe's"])
    expectEqual(result.transactions[0].date, day(2026, 7, 14))
    expectEqual(result.skipped.map(\.line), [5, 6, 7])

    let flipped = try CSVTransactionImporter.parse(csv, signConvention: .positiveIsMoneyOut, calendar: testCalendar)
    expectEqual(flipped.transactions.map(\.amountCents), [-525, 250_000, -6_410])
}

suite("CSVTransactionImporter: Mint-style type column") {
    let csv = """
    Date,Description,Original Description,Amount,Transaction Type,Category,Account Name,Labels,Notes
    7/14/2026,Starbucks,STARBUCKS STORE 05521,5.75,debit,Coffee Shops,Rewards Card,,morning
    7/15/2026,Paycheck,PAYROLL,2500.00,credit,Paycheck,Checking,,
    """
    let result = try CSVTransactionImporter.parse(csv, calendar: testCalendar)
    expectEqual(result.signConvention, nil)
    expectEqual(result.transactions.map(\.amountCents), [575, -250_000])
    expectEqual(result.transactions[0].categoryName, "Coffee Shops")
    expectEqual(result.transactions[0].accountName, "Rewards Card")
    expectEqual(result.transactions[0].notes, "morning")
    expectEqual(result.transactions[1].notes, nil)
}

suite("CSVTransactionImporter: debit and credit columns") {
    let csv = """
    Date;Payee;Money Out;Money In
    14.07.2026;Rewe Markt;23,10;
    15.07.2026;Gehalt;;3000,00
    """
    let result = try CSVTransactionImporter.parse(csv, calendar: testCalendar)
    expectEqual(result.transactions.count, 2)
    expectEqual(result.transactions[0].date, day(2026, 7, 14), "dd.MM.yyyy")
    expectEqual(result.transactions.map(\.amountCents), [2_310, -300_000], "decimal comma")
}

suite("CSVTransactionImporter: decimal separator") {
    let csv = """
    Date;Description;Amount
    2026-11-03;CORNER CAFE;-5,25
    2026-11-04;RENT;-1.250,00
    2026-11-05;REFUND;"12,5"
    """
    let result = try CSVTransactionImporter.parse(csv, calendar: testCalendar)
    expectEqual(result.transactions.map(\.amountCents), [525, 125_000, -1_250])

    expectEqual(CSVTransactionImporter.detectDecimalSeparator(in: ["2,500.00", "-5.25"]), ".")
    expectEqual(CSVTransactionImporter.detectDecimalSeparator(in: ["1.250,00", "(5,25)", "EUR 3,1"]), ",")
    expectEqual(CSVTransactionImporter.detectDecimalSeparator(in: ["1,250", "1.250", "12", ""]), ".", "no votes")
    expectEqual(CSVTransactionImporter.detectDecimalSeparator(in: ["5,25", "3.10"]), ".", "mixed votes keep the default")

    let huge = try CSVTransactionImporter.parse("Date,Description,Amount\n2026-11-03,CAFE,-5.25\n2026-11-04,REF,123456789012345678\n",
                                                calendar: testCalendar)
    expectEqual(huge.transactions.count, 1)
    expectEqual(huge.skipped.map(\.reason), ["Unreadable amount \"123456789012345678\""])
}

suite("CSVTransactionImporter: date order") {
    let dayFirst = """
    Date,Description,Amount
    05/11/2026,TESCO STORES,-12.40
    20/11/2026,TESCO STORES,-8.00
    """
    let uk = try CSVTransactionImporter.parse(dayFirst, locale: usLocale, calendar: testCalendar)
    expectEqual(uk.transactions.map(\.date), [day(2026, 11, 5), day(2026, 11, 20)], "one order for the whole file")
    expectEqual(uk.dateOrder, .dayFirst)
    expect(!uk.dateOrderIsAmbiguous)

    let monthFirst = "Date,Description,Amount\n11/05/2026,CAFE,-1\n11/20/2026,CAFE,-1"
    let us = try CSVTransactionImporter.parse(monthFirst, locale: Locale(identifier: "en_GB"), calendar: testCalendar)
    expectEqual(us.transactions.map(\.date), [day(2026, 11, 5), day(2026, 11, 20)])
    expectEqual(us.dateOrder, .monthFirst)

    // Nothing over 12: the region decides, or the caller.
    let ambiguous = "Date,Description,Amount\n05/11/2026,CAFE,-1\n06/11/2026,CAFE,-1"
    let gb = try CSVTransactionImporter.parse(ambiguous, locale: Locale(identifier: "en_GB"), calendar: testCalendar)
    expectEqual(gb.transactions.first?.date, day(2026, 11, 5))
    expectEqual(gb.dateOrder, .dayFirst)
    expect(gb.dateOrderIsAmbiguous)
    let usGuess = try CSVTransactionImporter.parse(ambiguous, locale: usLocale, calendar: testCalendar)
    expectEqual(usGuess.transactions.first?.date, day(2026, 5, 11))
    expectEqual(usGuess.dateOrder, .monthFirst)
    let chosen = try CSVTransactionImporter.parse(ambiguous, dateOrder: .dayFirst, locale: usLocale, calendar: testCalendar)
    expectEqual(chosen.transactions.first?.date, day(2026, 11, 5))
    expect(chosen.dateOrderIsAmbiguous, "still ambiguous, so the choice stays offered")

    // Dates that contradict each other are each read on their own.
    let mixed = "Date,Description,Amount\n20/11/2026,CAFE,-1\n11/21/2026,CAFE,-1"
    let mixedResult = try CSVTransactionImporter.parse(mixed, locale: usLocale, calendar: testCalendar)
    expectEqual(mixedResult.transactions.map(\.date), [day(2026, 11, 20), day(2026, 11, 21)])
    expectEqual(mixedResult.dateOrder, nil)

    let iso = try CSVTransactionImporter.parse("Date,Description,Amount\n2026-11-05,CAFE,-1", calendar: testCalendar)
    expectEqual(iso.dateOrder, nil, "ISO dates have a fixed order")
    expect(!iso.dateOrderIsAmbiguous)

    expectEqual(CSVDateOrder.preferred(in: usLocale), .monthFirst)
    expectEqual(CSVDateOrder.preferred(in: Locale(identifier: "en_GB")), .dayFirst)
    expectEqual(CSVDateOrder.preferred(in: Locale(identifier: "de_DE")), .dayFirst)
    expectEqual(CSVDateOrder.preferred(in: Locale(identifier: "ja_JP")), .monthFirst)
}

suite("CSVTransactionImporter: errors and dates") {
    do {
        _ = try CSVTransactionImporter.parse("Foo,Bar\n1,2", calendar: testCalendar)
        expect(false, "expected missing columns")
    } catch let error as CSVImportError {
        expectEqual(error, .missingColumns(["Date", "Description", "Amount"]))
    }
    do {
        _ = try CSVTransactionImporter.parse("Date,Description,Amount", calendar: testCalendar)
        expect(false, "expected empty")
    } catch let error as CSVImportError {
        expectEqual(error, .empty)
    }

    let parse = { CSVTransactionImporter.parseDate($0, calendar: testCalendar) }
    expectEqual(parse("2026-07-14"), day(2026, 7, 14))
    expectEqual(parse("2026-07-14T23:30:00Z"), day(2026, 7, 14))
    expectEqual(parse("07/14/2026"), day(2026, 7, 14))
    expectEqual(parse("7/14/26"), day(2026, 7, 14))
    expectEqual(parse("14/07/2026"), day(2026, 7, 14))
    expectEqual(parse("2026/07/14"), day(2026, 7, 14))
    expectEqual(parse("14.07.2026"), day(2026, 7, 14))
    expectEqual(parse("Jul 14, 2026"), day(2026, 7, 14))
    expectEqual(parse("14 Jul 2026"), day(2026, 7, 14))
    expectEqual(parse("07/14/2026 09:30"), day(2026, 7, 14))
    expectEqual(CSVTransactionImporter.parseDate("05/11/2026", calendar: testCalendar, order: .dayFirst), day(2026, 11, 5))
    expectEqual(CSVTransactionImporter.parseDate("05/11/2026", calendar: testCalendar, order: .monthFirst), day(2026, 5, 11))
    expectEqual(CSVTransactionImporter.parseDate("14.07.2026", calendar: testCalendar, order: .monthFirst), day(2026, 7, 14),
                "dotted dates stay day first")
    expectEqual(parse("02/30/2026"), nil)
    expectEqual(parse("yesterday"), nil)
    expectEqual(parse(""), nil)
}

suite("ImportDeduplicator") {
    let coffee = ImportedTransaction(date: day(2026, 7, 14), rawDescription: "SQ *BLUE BOTTLE", merchantName: "Blue Bottle Coffee", amountCents: 500)
    let fingerprint = coffee.fingerprint(calendar: testCalendar)
    expectEqual(fingerprint, "2026-07-14|500|bluebottlecoffee")

    let none = ImportDeduplicator.newTransactions([coffee, coffee], existingFingerprints: [], calendar: testCalendar)
    expectEqual(none.new.count, 2, "two identical coffees in one file are both kept")
    let one = ImportDeduplicator.newTransactions([coffee, coffee], existingFingerprints: [fingerprint], calendar: testCalendar)
    expectEqual(one.new.count, 1)
    expectEqual(one.duplicateCount, 1)
    let both = ImportDeduplicator.newTransactions([coffee, coffee], existingFingerprints: [fingerprint, fingerprint], calendar: testCalendar)
    expectEqual(both.new.count, 0)
}

// MARK: - Net worth

suite("NetWorthCalculator") {
    expectEqual(NetWorthCalculator.netWorth([(10_000, false), (2_500, true), (1_000, false)]), 8_500)

    let observations = [
        BalanceObservation(accountID: "checking", date: day(2026, 1, 1), balanceCents: 100_000, isLiability: false),
        BalanceObservation(accountID: "checking", date: day(2026, 2, 1), balanceCents: 150_000, isLiability: false),
        BalanceObservation(accountID: "card", date: day(2026, 1, 15), balanceCents: 30_000, isLiability: true),
    ]
    let series = NetWorthCalculator.series(observations: observations, at: [day(2025, 12, 31), day(2026, 1, 10), day(2026, 1, 20), day(2026, 2, 1)])
    expectEqual(series.map(\.netCents), [0, 100_000, 70_000, 120_000])
    expectEqual(series.map(\.liabilitiesCents), [0, 0, 30_000, 30_000])

    let checking = NetWorthCalculator.balanceSeries(observations: observations.filter { $0.accountID == "checking" },
                                                    at: [day(2025, 12, 1), day(2026, 1, 5)])
    expectEqual(checking.map(\.balanceCents), [nil, 100_000])

    let now = day(2026, 11, 8)
    let monthDates = ChartRange.oneMonth.sampleDates(now: now, calendar: testCalendar)
    expectEqual(monthDates.last, now)
    expectEqual(monthDates.first, day(2026, 10, 8))
    expectEqual(monthDates.count, 32)
    let yearDates = ChartRange.oneYear.sampleDates(now: now, calendar: testCalendar)
    expectEqual(yearDates.last, now)
    expectEqual(yearDates.first, day(2025, 11, 8))
    expect(zip(yearDates, yearDates.dropFirst()).allSatisfy { $0 < $1 }, "ascending")
}

// MARK: - Recurring

suite("RecurringDetector") {
    let now = day(2026, 11, 8)
    var entries: [Entry] = []
    for month in 6...11 {
        entries.append(Entry(ledgerDate: day(2026, month, 5), ledgerAmountCents: month == 11 ? 1_799 : 1_549, ledgerMerchant: "Netflix"))
    }
    // Weekly groceries with very different amounts: not recurring.
    for week in 0..<20 {
        entries.append(Entry(ledgerDate: testCalendar.date(byAdding: .day, value: -7 * week, to: now)!,
                             ledgerAmountCents: [2_500, 14_000, 6_300, 9_900][week % 4], ledgerMerchant: "Trader Joe's"))
    }
    // A gym that stopped billing in May.
    for month in 1...5 {
        entries.append(Entry(ledgerDate: day(2026, month, 17), ledgerAmountCents: 2_499, ledgerMerchant: "Planet Fitness"))
    }
    // Only two charges: not enough history.
    entries.append(Entry(ledgerDate: day(2026, 9, 20), ledgerAmountCents: 299, ledgerMerchant: "Apple Services"))
    entries.append(Entry(ledgerDate: day(2026, 10, 20), ledgerAmountCents: 299, ledgerMerchant: "Apple Services"))
    // Transfers never count.
    for month in 7...11 {
        entries.append(Entry(ledgerDate: day(2026, month, 2), ledgerAmountCents: 50_000, ledgerFlow: .transfer, ledgerMerchant: "Online Transfer"))
    }

    let candidates = RecurringDetector.candidates(from: entries, now: now, calendar: testCalendar)
    expectEqual(candidates.map(\.displayName), ["Netflix"])
    if let netflix = candidates.first {
        expectEqual(netflix.frequency, .monthly)
        expectEqual(netflix.typicalAmountCents, 1_799, "uses the latest price")
        expectEqual(netflix.nextExpectedDate, day(2026, 12, 5))
        expectEqual(netflix.occurrenceCount, 6)
    }
    expectEqual(RecurringDetector.candidates(from: entries, now: now, calendar: testCalendar, excludingMerchantKeys: ["netflix"]).count, 0)
}

suite("RecurringMatcher") {
    let now = day(2026, 11, 8)
    let entries = [
        Entry(ledgerDate: day(2026, 11, 6), ledgerAmountCents: 1_549, ledgerMerchant: "Netflix"),
        Entry(ledgerDate: day(2026, 11, 1), ledgerAmountCents: 2_000, ledgerMerchant: "Spotify"),
    ]
    expectEqual(RecurringMatcher.status(dueDate: day(2026, 11, 5), merchantKey: "netflix", frequency: .monthly, entries: entries, now: now, calendar: testCalendar),
                .paid(on: day(2026, 11, 6), amountCents: 1_549))
    expectEqual(RecurringMatcher.status(dueDate: day(2026, 11, 20), merchantKey: "netflix", frequency: .monthly, entries: entries, now: now, calendar: testCalendar),
                .upcoming)
    expectEqual(RecurringMatcher.status(dueDate: day(2026, 11, 8), merchantKey: "hulu", frequency: .monthly, entries: entries, now: now, calendar: testCalendar),
                .upcoming, "due today is still upcoming")
    expectEqual(RecurringMatcher.status(dueDate: day(2026, 10, 20), merchantKey: "spotify", frequency: .weekly, entries: entries, now: now, calendar: testCalendar),
                .late)
}

// MARK: - Sample data

suite("SampleLedger") {
    let now = day(2026, 11, 8)
    let ledger = SampleLedger.generate(now: now, calendar: testCalendar)
    expectEqual(ledger, SampleLedger.generate(now: now, calendar: testCalendar), "deterministic")
    expectEqual(ledger.accounts.count, 6)
    expect(ledger.transactions.count > 150, "about four months of activity (\(ledger.transactions.count))")
    expect(ledger.transactions.allSatisfy { $0.date <= now }, "nothing in the future")
    expect(ledger.transactions.allSatisfy { $0.date >= day(2026, 8, 1) }, "starts at the first sample month")
    expect(ledger.transactions.contains { !$0.isReviewed }, "some transactions need review")
    expect(ledger.transactions.contains { $0.isReviewed })

    let accountKeys = Set(ledger.accounts.map(\.key))
    expect(ledger.transactions.allSatisfy { accountKeys.contains($0.accountKey) }, "transactions reference real accounts")
    expect(ledger.balances.allSatisfy { accountKeys.contains($0.accountKey) })
    let seedKeys = Set(DefaultCategories.all.map(\.seedKey))
    expect(ledger.transactions.allSatisfy { $0.categorySeedKey.map(seedKeys.contains) ?? false }, "categories exist")
    let uncategorized = ledger.transactions.filter { $0.categorySeedKey == "general" }.map(\.description)
    expectEqual(Set(uncategorized), [], "the categorizer recognizes every sample merchant")

    for account in ledger.accounts {
        let latest = ledger.balances.filter { $0.accountKey == account.key }.max { $0.date < $1.date }
        expectEqual(latest?.balanceCents, account.balanceCents, "history ends at the current balance for \(account.key)")
    }

    // The recurring detector should suggest the untracked bills, and no
    // everyday merchants.
    struct SampleEntry: LedgerEntry {
        let spec: SampleLedger.TransactionSpec
        var ledgerDate: Date { spec.date }
        var ledgerAmountCents: Int { spec.amountCents }
        var ledgerFlow: LedgerFlow {
            LedgerFlow.resolve(categoryKind: spec.categorySeedKey.flatMap(DefaultCategories.category(seedKey:))?.kind,
                               isExcluded: false, amountCents: spec.amountCents)
        }
        var ledgerCategoryID: String? { spec.categorySeedKey }
        var ledgerMerchant: String { MerchantNormalizer.displayName(for: spec.description) }
        var ledgerMerchantKey: String { MerchantNormalizer.key(for: spec.description) }
    }
    let entries = ledger.transactions.map(SampleEntry.init)
    let tracked = Set(ledger.recurring.map(\.merchantKey))
    let suggestions = RecurringDetector.candidates(from: entries, now: now, calendar: testCalendar, excludingMerchantKeys: tracked)
    let names = Set(suggestions.map(\.displayName))
    expect(names.isSuperset(of: ["The New York Times", "Apple Services", "The Barber Shop"]), "suggests untracked bills: \(names)")
    expect(names.isDisjoint(with: ["Trader Joe's", "Whole Foods", "Starbucks", "Blue Bottle Coffee", "Uber", "Amazon", "Shell"]),
           "no everyday merchants: \(names)")

    // Every tracked bill has a matching charge this month or is still upcoming.
    let thisMonth = MonthInterval(containing: now, calendar: testCalendar).dateInterval(in: testCalendar)
    for bill in ledger.recurring {
        let schedule = RecurringSchedule(anchor: bill.anchor, frequency: bill.frequency)
        for due in schedule.occurrences(in: thisMonth, calendar: testCalendar) {
            let status = RecurringMatcher.status(dueDate: due, merchantKey: bill.merchantKey, frequency: bill.frequency,
                                                 entries: entries, now: now, calendar: testCalendar)
            expect(status != .late, "\(bill.name) due \(due) should not be late")
        }
    }

    let november = MonthInterval(containing: now, calendar: testCalendar)
    let spent = SpendingAnalytics.spending(entries, in: november.previous.dateInterval(in: testCalendar))
    expect(spent > 300_000 && spent < 900_000, "a believable month of spending: \(spent)")
}

// MARK: - Portfolio

suite("PortfolioMath") {
    let holdings = [
        HoldingInput(ticker: "AAPL", name: "Apple", securityType: "equity", quantity: 5, value: 1_000, costBasis: 800),
        HoldingInput(ticker: "aapl", name: "Apple Inc.", securityType: "equity", quantity: 1, value: 200, costBasis: 150),
        HoldingInput(ticker: "VTI", name: "Vanguard Total", securityType: "etf", quantity: 10, value: 2_400, costBasis: nil),
        HoldingInput(ticker: nil, name: "Cash Sweep", securityType: "cash", quantity: 400, value: 400, costBasis: nil),
        HoldingInput(ticker: "DEAD", name: "Delisted", securityType: "equity", quantity: 1, value: 0, costBasis: 10),
    ]
    let positions = PortfolioMath.positions(holdings)
    expectEqual(positions.map(\.symbol), ["VTI", "AAPL", "Cash Sweep"], "merged by symbol, zero-value dropped")
    expectEqual(positions[1].quantity, 6)
    expectEqual(positions[1].value, 1_200)
    expectEqual(positions[1].costBasis, 950)
    expectEqual(positions[1].weightPct, 30)
    expectEqual(positions[0].gainPct, nil, "no cost basis")
    expect(abs((positions[1].gainPct ?? 0) - 26.315789) < 0.0001)
    expect(positions[2].isCash)

    let totals = PortfolioMath.totals(holdings)
    expectEqual(totals.value, 4_000)
    expectEqual(totals.costBasis, 950)
    expectEqual(totals.valueWithCostBasis, 1_200)
    expectEqual(totals.gain, 250)

    let allocation = PortfolioMath.allocation(holdings)
    expectEqual(allocation.map(\.assetClass), [.etfs, .stocks, .cash])
    expectEqual(allocation.map(\.weightPct), [60, 30, 10])

    let shared = PortfolioMath.sharedPortfolio(holdings, limit: 1)
    expectEqual(shared.holdings, [SharedPortfolio.Item(ticker: "VTI", weightPct: 66.7), SharedPortfolio.Item(ticker: "Other", weightPct: 33.3)],
                "cash excluded, rest folded into Other")
    expectEqual(shared.totalGainPct, 26.3)
    expectEqual(PortfolioMath.sharedPortfolio([], limit: 5).holdings, [])

    // Encoded with the database's snake_case keys.
    let json = try JSONEncoder().encode(SharedPortfolio(holdings: [.init(ticker: "VTI", weightPct: 50)], totalGainPct: 1.5))
    let text = String(decoding: json, as: UTF8.self)
    expect(text.contains("\"weight_pct\":50") && text.contains("\"total_gain_pct\":1.5"), text)
    let decoded = try JSONDecoder().decode(SharedPortfolio.self, from: Data(#"{"holdings":[{"ticker":"AAPL","weight_pct":12.5}],"total_gain_pct":null}"#.utf8))
    expectEqual(decoded.holdings.first?.weightPct, 12.5)
    expectEqual(decoded.totalGainPct, nil)

    expectEqual(PortfolioMath.changePct(from: 200, to: 250), 25)
    expectEqual(PortfolioMath.changePct(from: 0, to: 250), nil)
    expectEqual(AssetClass(plaidType: "Mutual Fund"), .funds)
    expectEqual(AssetClass(plaidType: nil), .other)
}

suite("PortfolioMath partial cost basis") {
    // Mixed lots: one with a cost basis, one without, one with a zero basis
    // (which counts as unknown, as in `totals`).
    let mixed = PortfolioMath.positions([
        HoldingInput(ticker: "AAPL", name: "Apple", securityType: "equity", quantity: 10, value: 2_000, costBasis: 1_500),
        HoldingInput(ticker: "AAPL", name: "Apple", securityType: "equity", quantity: 5, value: 1_000, costBasis: nil),
        HoldingInput(ticker: "AAPL", name: "Apple", securityType: "equity", quantity: 2, value: 400, costBasis: 0),
    ])
    expectEqual(mixed.count, 1, "merged into one position")
    if let position = mixed.first {
        expectEqual(position.quantity, 17)
        expectEqual(position.value, 3_400)
        expectEqual(position.costBasis, 1_500)
        expectEqual(position.valueWithCostBasis, 2_000)
        expectEqual(position.quantityWithCostBasis, 10)
        expectEqual(position.gain, 500, "lots without a cost basis aren't counted as gain")
        expect(abs((position.gainPct ?? 0) - 33.333333) < 0.0001, "return on the lots with a cost basis")
        expect(position.isCostBasisPartial)
    }

    // No lot reports a cost basis.
    let unknown = PortfolioMath.positions([
        HoldingInput(ticker: "VTI", name: "Vanguard Total", securityType: "etf", quantity: 3, value: 900, costBasis: nil),
        HoldingInput(ticker: "VTI", name: "Vanguard Total", securityType: "etf", quantity: 1, value: 300, costBasis: 0),
    ])
    expectEqual(unknown.count, 1)
    if let position = unknown.first {
        expectEqual(position.value, 1_200)
        expectEqual(position.costBasis, nil)
        expectEqual(position.valueWithCostBasis, 0)
        expectEqual(position.quantityWithCostBasis, 0)
        expectEqual(position.gain, nil)
        expectEqual(position.gainPct, nil)
        expect(!position.isCostBasisPartial, "nothing to be partial about")
    }

    // Every lot reports a cost basis.
    let known = PortfolioMath.positions([
        HoldingInput(ticker: "MSFT", name: "Microsoft", securityType: "equity", quantity: 1, value: 400, costBasis: 300),
        HoldingInput(ticker: "msft", name: "Microsoft", securityType: "equity", quantity: 2, value: 600, costBasis: 500),
    ])
    expectEqual(known.count, 1)
    if let position = known.first {
        expectEqual(position.quantity, 3)
        expectEqual(position.value, 1_000)
        expectEqual(position.costBasis, 800)
        expectEqual(position.valueWithCostBasis, 1_000)
        expectEqual(position.quantityWithCostBasis, 3)
        expectEqual(position.gain, 200)
        expectEqual(position.gainPct, 25)
        expect(!position.isCostBasisPartial)
    }

    // The position's numbers agree with the totals over the same holdings.
    let totals = PortfolioMath.totals([
        HoldingInput(ticker: "AAPL", name: "Apple", securityType: "equity", quantity: 10, value: 2_000, costBasis: 1_500),
        HoldingInput(ticker: "AAPL", name: "Apple", securityType: "equity", quantity: 5, value: 1_000, costBasis: nil),
    ])
    expectEqual(totals.gain, 500)

    // Built directly (previews): the whole position counts when it has a cost basis.
    let withCost = PortfolioPosition(symbol: "VTI", name: "Vanguard Total", securityType: "etf",
                                     quantity: 110, value: 31_900, costBasis: 26_700, weightPct: 48.6)
    expectEqual(withCost.valueWithCostBasis, 31_900)
    expectEqual(withCost.quantityWithCostBasis, 110)
    expectEqual(withCost.gain, 5_200)
    expect(!withCost.isCostBasisPartial)
    let withoutCost = PortfolioPosition(symbol: "CUR:USD", name: "U.S. Dollar", securityType: "cash",
                                        quantity: 2_500, value: 2_500, costBasis: nil, weightPct: 3.8)
    expectEqual(withoutCost.valueWithCostBasis, 0)
    expectEqual(withoutCost.quantityWithCostBasis, 0)
    expectEqual(withoutCost.gain, nil)
    expect(!withoutCost.isCostBasisPartial)
}

suite("Cashtags") {
    expectEqual(Cashtags.extract(from: "Loading up on $AAPL and $msft, trimming $AAPL."), ["AAPL", "MSFT"])
    expectEqual(Cashtags.extract(from: "Paid $100 for US$5 of $BRK.B."), ["BRK.B"])
    expectEqual(Cashtags.extract(from: "$TSLA"), ["TSLA"])
    expectEqual(Cashtags.extract(from: "no tags $ here $"), [])
    let text = "Buy $NVDA now"
    expectEqual(Cashtags.ranges(in: text).map { String(text[$0]) }, ["$NVDA"])
    expect(Cashtags.isValidTicker("BRK.B"))
    expect(Cashtags.isValidTicker("RDS-A"))
    expect(!Cashtags.isValidTicker("aapl"))
    expect(!Cashtags.isValidTicker("1ABC"))
    expect(!Cashtags.isValidTicker(""))
    expect(!Cashtags.isValidTicker("ABCDEFGHIJK"))
}

suite("UsernameRules") {
    expect(UsernameRules.isValid("alice_a"))
    expect(UsernameRules.isValid("bob.smith"))
    expect(!UsernameRules.isValid("Al"))
    expect(!UsernameRules.isValid("Alice"))
    expect(!UsernameRules.isValid("has space"))
    expect(!UsernameRules.isValid(String(repeating: "a", count: 25)))
    expectEqual(UsernameRules.normalize("Hello World!_99"), "helloworld_99")
    expectEqual(UsernameRules.problem(with: "ab"), "Use at least 3 characters.")
    expectEqual(UsernameRules.problem(with: "Ab3"), "Only a–z, 0–9, underscore and period.")
    expectEqual(UsernameRules.problem(with: "good_name"), nil)
}

// MARK: - Summary

print("\(checkCount) checks, \(failureCount) failures")
exit(failureCount == 0 ? 0 : 1)
