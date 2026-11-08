//
//  MerchantNormalizer.swift
//  Haki
//
//  Pure Foundation code (see Money.swift).
//

import Foundation

/// Uppercased alphanumeric tokens, used for keyword matching that respects
/// word boundaries ("SHELL" matches "SHELL OIL 5744" but not "SHELLFISH").
nonisolated enum TextTokens {
    static func tokens(_ text: String) -> [String] {
        text.uppercased()
            .split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map(String.init)
    }

    /// Whether `needle` appears in `haystack` as consecutive tokens.
    static func contains(_ haystack: [String], _ needle: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }
        for start in 0...(haystack.count - needle.count)
        where haystack[start] == needle[0] && Array(haystack[start..<(start + needle.count)]) == needle {
            return true
        }
        return false
    }
}

/// Turns raw bank descriptions into readable merchant names:
///
///     "SQ *BLUE BOTTLE COFFEE  San Francisco CA" → "Blue Bottle Coffee"
///     "AMAZON.COM*2K4AB1C23 AMZN.COM/BILLWA"     → "Amazon"
///     "POS DEBIT 0712 TRADER JOE'S #552"          → "Trader Joe's"
nonisolated enum MerchantNormalizer {
    /// A readable merchant name. Never empty.
    static func displayName(for raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Unknown" }

        let tokens = TextTokens.tokens(trimmed)
        for brand in brands where TextTokens.contains(tokens, brand.tokens) {
            return brand.name
        }

        let cleaned = genericCleanup(trimmed)
        if !cleaned.isEmpty { return cleaned }
        return titleCase(words: trimmed.split(separator: " ").map(String.init))
    }

    /// A stable grouping key for a merchant: lowercase letters and digits only.
    /// Pass either a raw description or a display name; raw descriptions are
    /// normalized first so "SQ *BLUE BOTTLE #12" and "Blue Bottle Coffee" match.
    static func key(for text: String) -> String {
        let name = displayName(for: text)
        return String(name.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
            .map(Character.init))
    }

    // MARK: Generic cleanup

    private static func genericCleanup(_ raw: String) -> String {
        var text = raw.uppercased()

        // Banks pad the merchant name with runs of spaces before the city and
        // state. Keep only the part before the first run.
        if let gap = text.range(of: "  ") {
            let head = String(text[..<gap.lowerBound])
            if head.contains(where: \.isLetter) { text = head }
        }

        // "SQ *MERCHANT", "PAYPAL *MERCHANT", "MERCHANT*REF123"
        if let star = text.firstIndex(of: "*") {
            let left = text[..<star].trimmingCharacters(in: .whitespaces)
            let right = text[text.index(after: star)...].trimmingCharacters(in: .whitespaces)
            let leftTokens = TextTokens.tokens(left)
            if leftTokens.isEmpty || (leftTokens.count == 1 && processorPrefixes.contains(leftTokens[0])) {
                text = right
            } else {
                text = left
            }
        }

        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)

        // Leading noise such as "POS DEBIT" or "DEBIT CARD PURCHASE".
        var removedPrefix = true
        while removedPrefix {
            removedPrefix = false
            let wordTokens = words.map { TextTokens.tokens($0).joined() }
            for phrase in noisePrefixes where wordTokens.starts(with: phrase) && words.count > phrase.count {
                words.removeFirst(phrase.count)
                removedPrefix = true
                break
            }
            if let first = words.first, words.count > 1,
               processorPrefixes.contains(TextTokens.tokens(first).joined()) {
                words.removeFirst()
                removedPrefix = true
            }
        }

        words = words
            .map { $0 == "&" ? $0 : stripDomain(stripEdgePunctuation($0)) }
            .filter { word in
                // Drop store numbers, dates, phone numbers and reference codes.
                word == "&" || (!word.contains(where: \.isNumber) && word.contains(where: \.isLetter))
            }
        // A lone "&" left at either end ("& GRILL #12" after dropping a code) reads oddly.
        while words.first == "&" { words.removeFirst() }
        while words.last == "&" { words.removeLast() }

        while words.count >= 2, let last = words.last,
              usStateCodes.contains(last) || legalSuffixes.contains(last) {
            words.removeLast()
        }

        return titleCase(words: words)
    }

    private static func stripEdgePunctuation(_ word: String) -> String {
        word.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    }

    private static func stripDomain(_ word: String) -> String {
        for suffix in [".COM", ".NET", ".ORG", ".IO", ".CO"] where word.hasSuffix(suffix) && word.count > suffix.count {
            return String(word.dropLast(suffix.count))
        }
        return word
    }

    private static func titleCase(words: [String]) -> String {
        words.map { word in
            let letters = word.filter(\.isLetter)
            let hasVowel = letters.uppercased().contains(where: { "AEIOUY".contains($0) })
            // Acronyms such as "CVS", "BBQ" or "H&M" stay uppercase.
            if word.contains("&") || (!hasVowel && letters.count <= 4) {
                return word.uppercased()
            }
            return word.split(separator: "-", omittingEmptySubsequences: false)
                .map { part in part.prefix(1).uppercased() + part.dropFirst().lowercased() }
                .joined(separator: "-")
        }
        .joined(separator: " ")
    }

    // MARK: Tables

    private struct Brand {
        let tokens: [String]
        let name: String
    }

    private static func brand(_ pattern: String, _ name: String) -> Brand {
        Brand(tokens: TextTokens.tokens(pattern), name: name)
    }

    /// Checked in order, so more specific patterns come first and payment
    /// aggregators (PayPal, Venmo...) come last.
    private static let brands: [Brand] = [
        brand("UBER EATS", "Uber Eats"), brand("UBEREATS", "Uber Eats"),
        brand("UBER", "Uber"), brand("LYFT", "Lyft"),
        brand("AMAZON PRIME", "Amazon Prime"), brand("PRIME VIDEO", "Prime Video"),
        brand("AMAZON FRESH", "Amazon Fresh"),
        brand("AMAZON", "Amazon"), brand("AMZN", "Amazon"),
        brand("WHOLE FOODS", "Whole Foods"), brand("WHOLEFDS", "Whole Foods"),
        brand("TRADER JOE", "Trader Joe's"), brand("TRADER JOES", "Trader Joe's"),
        brand("COSTCO", "Costco"), brand("SAFEWAY", "Safeway"), brand("KROGER", "Kroger"),
        brand("PUBLIX", "Publix"), brand("ALDI", "Aldi"), brand("SPROUTS", "Sprouts"),
        brand("WEGMANS", "Wegmans"), brand("INSTACART", "Instacart"),
        brand("TARGET", "Target"), brand("WALMART", "Walmart"), brand("WAL MART", "Walmart"),
        brand("WM SUPERCENTER", "Walmart"),
        brand("STARBUCKS", "Starbucks"), brand("DUNKIN", "Dunkin'"), brand("PEETS", "Peet's Coffee"),
        brand("PEET S", "Peet's Coffee"), brand("BLUE BOTTLE", "Blue Bottle Coffee"),
        brand("PHILZ", "Philz Coffee"),
        brand("CHIPOTLE", "Chipotle"), brand("MCDONALD", "McDonald's"), brand("MCDONALDS", "McDonald's"),
        brand("SWEETGREEN", "Sweetgreen"), brand("DOORDASH", "DoorDash"), brand("GRUBHUB", "Grubhub"),
        brand("NETFLIX", "Netflix"), brand("SPOTIFY", "Spotify"), brand("HULU", "Hulu"),
        brand("DISNEY PLUS", "Disney+"), brand("DISNEYPLUS", "Disney+"),
        brand("YOUTUBE", "YouTube"), brand("HBO MAX", "Max"), brand("HBOMAX", "Max"),
        brand("AUDIBLE", "Audible"), brand("PATREON", "Patreon"),
        brand("APPLE COM BILL", "Apple Services"), brand("ITUNES", "Apple Services"),
        brand("APPLE STORE", "Apple Store"),
        brand("OPENAI", "OpenAI"), brand("CHATGPT", "OpenAI"), brand("GITHUB", "GitHub"),
        brand("DROPBOX", "Dropbox"), brand("ADOBE", "Adobe"),
        brand("NYTIMES", "The New York Times"), brand("NY TIMES", "The New York Times"),
        brand("PELOTON", "Peloton"), brand("EQUINOX", "Equinox"), brand("PLANET FITNESS", "Planet Fitness"),
        brand("CVS", "CVS Pharmacy"), brand("WALGREENS", "Walgreens"),
        brand("SHELL", "Shell"), brand("CHEVRON", "Chevron"), brand("EXXONMOBIL", "ExxonMobil"),
        brand("EXXON", "ExxonMobil"), brand("ARCO", "ARCO"),
        brand("COMCAST", "Xfinity"), brand("XFINITY", "Xfinity"), brand("VERIZON", "Verizon"),
        brand("AT&T", "AT&T"), brand("T MOBILE", "T-Mobile"), brand("TMOBILE", "T-Mobile"),
        brand("PG&E", "PG&E"), brand("CON ED", "Con Edison"), brand("CONED", "Con Edison"),
        brand("AIRBNB", "Airbnb"), brand("DELTA AIR", "Delta"), brand("UNITED AIRLINES", "United Airlines"),
        brand("JETBLUE", "JetBlue"), brand("MARRIOTT", "Marriott"), brand("HILTON", "Hilton"),
        brand("EXPEDIA", "Expedia"),
        brand("BEST BUY", "Best Buy"), brand("HOME DEPOT", "The Home Depot"),
        brand("LOWES", "Lowe's"), brand("LOWE S", "Lowe's"), brand("IKEA", "IKEA"), brand("ETSY", "Etsy"),
        brand("EBAY", "eBay"), brand("SEPHORA", "Sephora"), brand("ULTA", "Ulta Beauty"),
        brand("NORDSTROM", "Nordstrom"), brand("TJ MAXX", "TJ Maxx"), brand("TJMAXX", "TJ Maxx"),
        brand("7 ELEVEN", "7-Eleven"), brand("7ELEVEN", "7-Eleven"),
        brand("CASH APP", "Cash App"), brand("VENMO", "Venmo"), brand("ZELLE", "Zelle"),
        brand("PAYPAL", "PayPal"),
    ]

    /// Payment processors that prefix the real merchant ("SQ *", "TST* ").
    private static let processorPrefixes: Set<String> = [
        "SQ", "TST", "PAYPAL", "PP", "SP", "GOOGLE", "DD", "IC", "PY", "SQU", "BT", "CKO", "FS",
    ]

    /// Leading phrases banks add, as joined tokens per word.
    private static let noisePrefixes: [[String]] = [
        ["PURCHASE", "AUTHORIZED", "ON"],
        ["DEBIT", "CARD", "PURCHASE"],
        ["DEBIT", "PURCHASE"],
        ["CARD", "PURCHASE"],
        ["POS", "DEBIT"],
        ["POS", "PURCHASE"],
        ["POS"],
        ["CHECKCARD"],
        ["CHECK", "CARD"],
        ["RECURRING", "PAYMENT"],
        ["ACH", "DEBIT"],
        ["ACH", "CREDIT"],
        ["ACH", "DEPOSIT"],
        ["ACH"],
        ["DIRECT", "DEPOSIT"],
        ["DIRECT", "DEP"],
        ["ONLINE", "PAYMENT"],
        ["PREAUTHORIZED", "DEBIT"],
    ]

    private static let legalSuffixes: Set<String> = ["INC", "LLC", "CORP", "CO", "LTD"]

    private static let usStateCodes: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA",
        "KS", "KY", "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT",
        "VA", "WA", "WV", "WI", "WY", "DC",
    ]
}
