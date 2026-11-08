//
//  PortfolioMath.swift
//  Haki
//
//  Pure Foundation code (see Money.swift).
//

import Foundation

/// One brokerage holding, as the portfolio math needs it. Values are in the
/// account currency (dollars, not cents: brokerage data has fractional shares
/// and sub-cent prices).
nonisolated struct HoldingInput: Hashable {
    var ticker: String?
    var name: String
    /// Plaid security type, e.g. "equity", "etf", "mutual fund", "cash", "cryptocurrency".
    var securityType: String?
    var quantity: Double
    var value: Double
    var costBasis: Double?
}

/// A position across all accounts: holdings of the same security are merged.
nonisolated struct PortfolioPosition: Hashable, Identifiable {
    /// Ticker if known, else the security name.
    let symbol: String
    let name: String
    let securityType: String?
    let quantity: Double
    let value: Double
    /// `nil` when no holding of this security reported a cost basis.
    let costBasis: Double?
    /// Share of the whole portfolio, 0...100.
    let weightPct: Double

    var id: String { symbol }

    var gain: Double? { costBasis.map { value - $0 } }

    /// Return on cost, in percent. `nil` without a positive cost basis.
    var gainPct: Double? {
        guard let costBasis, costBasis > 0 else { return nil }
        return (value - costBasis) / costBasis * 100
    }

    var isCash: Bool { securityType?.lowercased() == "cash" }
}

/// Allocation by asset class.
nonisolated struct AllocationSlice: Hashable, Identifiable {
    let assetClass: AssetClass
    let value: Double
    let weightPct: Double

    var id: AssetClass { assetClass }
}

nonisolated enum AssetClass: String, CaseIterable, Hashable, Identifiable {
    case stocks, etfs, funds, crypto, bonds, cash, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .stocks: "Stocks"
        case .etfs: "ETFs"
        case .funds: "Funds"
        case .crypto: "Crypto"
        case .bonds: "Bonds"
        case .cash: "Cash"
        case .other: "Other"
        }
    }

    init(plaidType: String?) {
        switch plaidType?.lowercased() {
        case "equity": self = .stocks
        case "etf": self = .etfs
        case "mutual fund": self = .funds
        case "cryptocurrency": self = .crypto
        case "fixed income": self = .bonds
        case "cash": self = .cash
        default: self = .other
        }
    }
}

/// Holdings shared on a post or profile: percentages only, never amounts.
nonisolated struct SharedPortfolio: Codable, Hashable {
    nonisolated struct Item: Codable, Hashable {
        let ticker: String
        let weightPct: Double

        enum CodingKeys: String, CodingKey {
            case ticker
            case weightPct = "weight_pct"
        }
    }

    let holdings: [Item]
    /// Whole-portfolio return on cost, in percent.
    let totalGainPct: Double?

    enum CodingKeys: String, CodingKey {
        case holdings
        case totalGainPct = "total_gain_pct"
    }
}

nonisolated struct PortfolioTotals: Hashable {
    let value: Double
    /// Cost basis of the holdings that report one.
    let costBasis: Double
    /// Value of the holdings that report a cost basis (for an apples-to-apples gain).
    let valueWithCostBasis: Double

    var gain: Double { valueWithCostBasis - costBasis }
    var gainPct: Double? { costBasis > 0 ? gain / costBasis * 100 : nil }
}

nonisolated enum PortfolioMath {
    /// Merges holdings by symbol and computes weights. Largest first; holdings
    /// worth nothing are dropped.
    static func positions(_ holdings: [HoldingInput]) -> [PortfolioPosition] {
        struct Accumulator {
            var name: String
            var securityType: String?
            var quantity = 0.0
            var value = 0.0
            var costBasis: Double?
        }
        var bySymbol: [String: Accumulator] = [:]
        var order: [String] = []
        for holding in holdings where holding.value > 0 {
            let symbol = symbol(for: holding)
            var item: Accumulator
            if let existing = bySymbol[symbol] {
                item = existing
            } else {
                item = Accumulator(name: holding.name, securityType: holding.securityType)
                order.append(symbol)
            }
            item.quantity += holding.quantity
            item.value += holding.value
            if let cost = holding.costBasis {
                item.costBasis = (item.costBasis ?? 0) + cost
            }
            bySymbol[symbol] = item
        }
        let total = bySymbol.values.reduce(0) { $0 + $1.value }
        return order.compactMap { symbol -> PortfolioPosition? in
            guard let item = bySymbol[symbol] else { return nil }
            return PortfolioPosition(
                symbol: symbol,
                name: item.name,
                securityType: item.securityType,
                quantity: item.quantity,
                value: item.value,
                costBasis: item.costBasis,
                weightPct: total > 0 ? item.value / total * 100 : 0
            )
        }
        .sorted { $0.value != $1.value ? $0.value > $1.value : $0.symbol < $1.symbol }
    }

    static func totals(_ holdings: [HoldingInput]) -> PortfolioTotals {
        var value = 0.0
        var cost = 0.0
        var valueWithCost = 0.0
        for holding in holdings where holding.value > 0 {
            value += holding.value
            if let basis = holding.costBasis, basis > 0 {
                cost += basis
                valueWithCost += holding.value
            }
        }
        return PortfolioTotals(value: value, costBasis: cost, valueWithCostBasis: valueWithCost)
    }

    /// Allocation by asset class, largest first.
    static func allocation(_ holdings: [HoldingInput]) -> [AllocationSlice] {
        var byClass: [AssetClass: Double] = [:]
        for holding in holdings where holding.value > 0 {
            byClass[AssetClass(plaidType: holding.securityType), default: 0] += holding.value
        }
        let total = byClass.values.reduce(0, +)
        return byClass
            .map { AllocationSlice(assetClass: $0.key, value: $0.value, weightPct: total > 0 ? $0.value / total * 100 : 0) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.assetClass.rawValue < $1.assetClass.rawValue }
    }

    /// A shareable snapshot: the top `limit` positions by weight (cash
    /// excluded), the rest folded into "Other", weights rounded to one decimal.
    static func sharedPortfolio(_ holdings: [HoldingInput], limit: Int = 5) -> SharedPortfolio {
        let invested = positions(holdings).filter { !$0.isCash }
        let investedTotal = invested.reduce(0) { $0 + $1.value }
        guard investedTotal > 0 else { return SharedPortfolio(holdings: [], totalGainPct: totals(holdings).gainPct.map(round1)) }

        var items = invested.prefix(max(0, limit)).map {
            SharedPortfolio.Item(ticker: $0.symbol, weightPct: round1($0.value / investedTotal * 100))
        }
        let rest = invested.dropFirst(max(0, limit)).reduce(0) { $0 + $1.value }
        if rest > 0 {
            items.append(SharedPortfolio.Item(ticker: "Other", weightPct: round1(rest / investedTotal * 100)))
        }
        return SharedPortfolio(holdings: items, totalGainPct: totals(holdings).gainPct.map(round1))
    }

    /// Change between the first and last value of a series, in percent.
    static func changePct(from start: Double, to end: Double) -> Double? {
        guard start != 0 else { return nil }
        return (end - start) / abs(start) * 100
    }

    private static func symbol(for holding: HoldingInput) -> String {
        if let ticker = holding.ticker?.trimmingCharacters(in: .whitespaces), !ticker.isEmpty {
            return ticker.uppercased()
        }
        return holding.name
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}

// MARK: - Cashtags and usernames

nonisolated enum Cashtags {
    /// Ticker symbols mentioned as cashtags ("$AAPL", "$brk.b"), uppercased, in
    /// order of first appearance. A cashtag starts with a letter, so "$100"
    /// isn't one.
    static func extract(from text: String) -> [String] {
        ranges(in: text).map { String(text[$0].dropFirst()).uppercased() }
            .reduce(into: [String]()) { result, ticker in
                if !result.contains(ticker) { result.append(ticker) }
            }
    }

    /// Ranges of cashtags in `text`, including the "$".
    static func ranges(in text: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "$" else {
                index = text.index(after: index)
                continue
            }
            // Must not be glued to a preceding word ("US$5" isn't a cashtag).
            if index > text.startIndex {
                let previous = text[text.index(before: index)]
                if previous.isLetter || previous.isNumber || previous == "$" {
                    index = text.index(after: index)
                    continue
                }
            }
            let start = index
            var end = text.index(after: index)
            guard end < text.endIndex, text[end].isASCII, text[end].isLetter else {
                index = end
                continue
            }
            var length = 0
            while end < text.endIndex, length < 10,
                  text[end].isASCII, text[end].isLetter || text[end].isNumber || text[end] == "." {
                end = text.index(after: end)
                length += 1
            }
            // Don't swallow a trailing period that ends a sentence.
            while text[text.index(before: end)] == "." { end = text.index(before: end) }
            result.append(start..<end)
            index = end
        }
        return result
    }

    /// Whether `ticker` is a valid symbol for a post (mirrors the database check).
    static func isValidTicker(_ ticker: String) -> Bool {
        guard let first = ticker.first, first.isASCII, first.isUppercase, ticker.count <= 10 else { return false }
        return ticker.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber || $0 == "." || $0 == "-") }
    }
}

nonisolated enum UsernameRules {
    static let allowedCharacters = "a–z, 0–9, underscore and period"
    static let lengthRange = 3...24

    /// Lowercases and drops characters usernames can't contain.
    static func normalize(_ text: String) -> String {
        String(text.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
            .prefix(lengthRange.upperBound))
    }

    /// Mirrors the database constraint `^[a-z0-9_.]{3,24}$`.
    static func isValid(_ username: String) -> Bool {
        lengthRange.contains(username.count) && normalize(username) == username
    }

    /// A short explanation of what's wrong, or `nil` if valid.
    static func problem(with username: String) -> String? {
        if username.count < lengthRange.lowerBound { return "Use at least \(lengthRange.lowerBound) characters." }
        if username.count > lengthRange.upperBound { return "Use at most \(lengthRange.upperBound) characters." }
        if normalize(username) != username { return "Only \(allowedCharacters)." }
        return nil
    }
}
