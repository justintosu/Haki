//
//  Categorizer.swift
//  Haki
//
//  Pure Foundation code (see Money.swift).
//

import Foundation

/// A built-in category. `seedKey` identifies it permanently, even if the
/// user renames the category.
nonisolated struct DefaultCategory: Hashable, Identifiable {
    let seedKey: String
    let name: String
    let emoji: String
    let colorHex: String
    let kind: CategoryKind
    /// Used only when loading sample data; new users start with no budgets.
    let suggestedBudgetCents: Int?

    var id: String { seedKey }
}

nonisolated enum DefaultCategories {
    static let all: [DefaultCategory] = [
        DefaultCategory(seedKey: "groceries", name: "Groceries", emoji: "🛒", colorHex: "#3FB97B", kind: .expense, suggestedBudgetCents: 60_000),
        DefaultCategory(seedKey: "restaurants", name: "Restaurants", emoji: "🍽️", colorHex: "#F2994A", kind: .expense, suggestedBudgetCents: 35_000),
        DefaultCategory(seedKey: "coffee", name: "Coffee", emoji: "☕️", colorHex: "#A0673D", kind: .expense, suggestedBudgetCents: 6_000),
        DefaultCategory(seedKey: "shopping", name: "Shopping", emoji: "🛍️", colorHex: "#E05FA3", kind: .expense, suggestedBudgetCents: 30_000),
        DefaultCategory(seedKey: "transport", name: "Transport", emoji: "🚗", colorHex: "#4F8EF7", kind: .expense, suggestedBudgetCents: 20_000),
        DefaultCategory(seedKey: "travel", name: "Travel", emoji: "✈️", colorHex: "#2BB5C9", kind: .expense, suggestedBudgetCents: 25_000),
        DefaultCategory(seedKey: "entertainment", name: "Entertainment", emoji: "🎬", colorHex: "#9B6DF2", kind: .expense, suggestedBudgetCents: 10_000),
        DefaultCategory(seedKey: "subscriptions", name: "Subscriptions", emoji: "📺", colorHex: "#6C63FF", kind: .expense, suggestedBudgetCents: 6_000),
        DefaultCategory(seedKey: "utilities", name: "Utilities", emoji: "💡", colorHex: "#E2B93B", kind: .expense, suggestedBudgetCents: 25_000),
        DefaultCategory(seedKey: "housing", name: "Housing", emoji: "🏠", colorHex: "#8D7B68", kind: .expense, suggestedBudgetCents: 220_000),
        DefaultCategory(seedKey: "health", name: "Health & Fitness", emoji: "💪", colorHex: "#EB5757", kind: .expense, suggestedBudgetCents: 12_000),
        DefaultCategory(seedKey: "personalCare", name: "Personal Care", emoji: "💇", colorHex: "#F78FB3", kind: .expense, suggestedBudgetCents: 6_000),
        DefaultCategory(seedKey: "general", name: "Other", emoji: "📦", colorHex: "#8E8E93", kind: .expense, suggestedBudgetCents: 10_000),
        DefaultCategory(seedKey: "income", name: "Income", emoji: "💰", colorHex: "#27AE60", kind: .income, suggestedBudgetCents: nil),
        DefaultCategory(seedKey: "transfer", name: "Transfers", emoji: "🔄", colorHex: "#7F8C8D", kind: .transfer, suggestedBudgetCents: nil),
    ]

    static func category(seedKey: String) -> DefaultCategory? {
        all.first { $0.seedKey == seedKey }
    }
}

/// Suggests a category for a transaction from its description.
nonisolated enum Categorizer {
    /// The `seedKey` of the built-in category that best fits, or `nil`.
    /// - Parameters:
    ///   - description: the raw bank description (preferred) or merchant name.
    ///   - amountCents: Plaid sign convention. Income keywords only apply to money in.
    static func suggestedSeedKey(description: String, amountCents: Int) -> String? {
        let tokens = TextTokens.tokens(description)
        guard !tokens.isEmpty else { return nil }
        for rule in keywordRules {
            if rule.seedKey == "income", amountCents >= 0 { continue }
            if rule.patterns.contains(where: { TextTokens.contains(tokens, $0) }) {
                return rule.seedKey
            }
        }
        return nil
    }

    /// Whether a user's merchant rule (stored as a merchant key, see
    /// `MerchantNormalizer.key(for:)`) applies to a transaction's merchant key.
    static func ruleMatches(ruleKey: String, merchantKey: String) -> Bool {
        guard !ruleKey.isEmpty, !merchantKey.isEmpty else { return false }
        if ruleKey == merchantKey { return true }
        // Allow "bluebottle" to match "bluebottlecoffee", but don't let very
        // short keys match everything.
        return ruleKey.count >= 4 && merchantKey.contains(ruleKey)
    }

    // MARK: Keyword table

    private struct KeywordRule {
        let seedKey: String
        let patterns: [[String]]
    }

    private static func rule(_ seedKey: String, _ patterns: [String]) -> KeywordRule {
        KeywordRule(seedKey: seedKey, patterns: patterns.map(TextTokens.tokens))
    }

    /// Checked in order: the first rule with a matching pattern wins.
    private static let keywordRules: [KeywordRule] = [
        rule("transfer", [
            "PAYMENT THANK YOU", "AUTOPAY", "AUTO PAY", "AUTOMATIC PAYMENT", "ONLINE TRANSFER",
            "TRANSFER", "XFER", "ZELLE", "VENMO", "CASH APP", "CREDIT CARD PAYMENT", "CARD PAYMENT",
        ]),
        rule("income", [
            "PAYROLL", "DIRECT DEP", "DIRECT DEPOSIT", "SALARY", "DIVIDEND", "INTEREST PAYMENT",
            "INTEREST PAID", "INTEREST EARNED", "TAX REFUND", "IRS TREAS",
        ]),
        rule("subscriptions", [
            "NETFLIX", "SPOTIFY", "HULU", "DISNEY PLUS", "DISNEYPLUS", "YOUTUBE PREMIUM", "YOUTUBE TV",
            "APPLE COM BILL", "ITUNES", "HBO MAX", "HBOMAX", "AUDIBLE", "PATREON", "ICLOUD", "OPENAI",
            "CHATGPT", "ADOBE", "DROPBOX", "NYTIMES", "NY TIMES", "AMAZON PRIME", "PRIME VIDEO",
            "GITHUB", "SUBSCRIPTION",
        ]),
        rule("coffee", [
            "STARBUCKS", "BLUE BOTTLE", "PEETS", "PEET S", "DUNKIN", "PHILZ", "COFFEE", "CAFE", "ESPRESSO",
        ]),
        rule("restaurants", [
            "UBER EATS", "UBEREATS", "DOORDASH", "GRUBHUB", "CHIPOTLE", "MCDONALD", "MCDONALDS", "SWEETGREEN",
            "RESTAURANT", "PIZZA", "PIZZERIA", "BURGER", "TACO", "TAQUERIA", "SUSHI", "GRILL", "KITCHEN",
            "DINER", "BBQ", "RAMEN", "BISTRO", "TST", "BAR", "BREWERY", "BAKERY",
        ]),
        rule("groceries", [
            "WHOLE FOODS", "WHOLEFDS", "TRADER JOE", "TRADER JOES", "SAFEWAY", "KROGER", "COSTCO", "ALDI",
            "PUBLIX", "SPROUTS", "WEGMANS", "INSTACART", "AMAZON FRESH", "GROCERY", "GROCERIES", "SUPERMARKET",
        ]),
        rule("transport", [
            "UBER", "LYFT", "SHELL", "CHEVRON", "EXXON", "EXXONMOBIL", "MOBIL", "ARCO", "GAS STATION", "FUEL",
            "PARKING", "METRO", "TRANSIT", "CLIPPER", "MTA", "TOLL", "FASTRAK", "CALTRAIN", "BART",
        ]),
        rule("travel", [
            "AIRLINES", "AIRWAYS", "AIRLINE", "DELTA AIR", "UNITED AIRLINES", "JETBLUE", "AIRBNB", "MARRIOTT",
            "HILTON", "HYATT", "HOTEL", "EXPEDIA", "BOOKING COM", "AMTRAK",
        ]),
        rule("utilities", [
            "PG&E", "PGE", "CON ED", "CONED", "COMCAST", "XFINITY", "VERIZON", "AT&T", "T MOBILE", "TMOBILE",
            "SPECTRUM", "ELECTRIC", "WATER", "UTILITY", "UTILITIES", "INTERNET",
        ]),
        rule("housing", [
            "RENT", "MORTGAGE", "APARTMENTS", "PROPERTY MGMT", "PROPERTY MANAGEMENT", "HOA",
        ]),
        rule("health", [
            "CVS", "WALGREENS", "PHARMACY", "RITE AID", "DENTAL", "DENTIST", "MEDICAL", "CLINIC", "HOSPITAL",
            "KAISER", "EQUINOX", "PLANET FITNESS", "PELOTON", "GYM", "FITNESS", "YOGA",
        ]),
        rule("personalCare", [
            "SALON", "BARBER", "SPA", "SEPHORA", "ULTA",
        ]),
        rule("entertainment", [
            "AMC", "CINEMA", "THEATER", "THEATRE", "TICKETMASTER", "STUBHUB", "STEAM", "PLAYSTATION", "XBOX",
            "NINTENDO", "CONCERT", "MUSEUM",
        ]),
        rule("shopping", [
            "AMAZON", "AMZN", "TARGET", "WALMART", "WAL MART", "BEST BUY", "APPLE STORE", "IKEA", "ETSY",
            "EBAY", "NORDSTROM", "ZARA", "UNIQLO", "NIKE", "HOME DEPOT", "LOWES", "TJ MAXX", "TJMAXX",
        ]),
    ]
}
