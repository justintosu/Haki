//
//  Money.swift
//  Haki
//
//  Pure Foundation code: no SwiftUI or SwiftData. Compiled and unit-tested on
//  Linux by scripts/test-core.sh, so keep it free of Apple-only frameworks.
//

import Foundation

/// Money helpers.
///
/// **Storage.** Every amount in Haki is an `Int` count of hundredths of the
/// currency unit ("cents"). Integers never drift the way `Double` does and are
/// cheap to sum, sort and filter in SwiftData predicates.
///
/// **Sign convention** (the same one Plaid uses, so bank sync can be added
/// later without flipping signs): a **positive** amount is money leaving an
/// account — a purchase or a bill. A **negative** amount is money coming in —
/// a paycheck, a refund, interest.
nonisolated enum Money {
    /// The currency the app formats amounts in. Haki is single-currency for now.
    static let defaultCurrencyCode: String = Locale.current.currency?.identifier ?? "USD"

    // MARK: Conversion

    static func decimal(fromCents cents: Int) -> Decimal {
        Decimal(cents) / 100
    }

    /// Converts a decimal amount to cents, rounding half away from zero.
    static func cents(from decimal: Decimal) -> Int {
        var scaled = decimal * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        return Int(truncating: NSDecimalNumber(decimal: rounded))
    }

    // MARK: Formatting

    /// Formats cents as currency, e.g. `123456` → `"$1,234.56"`.
    /// - Parameters:
    ///   - showsCents: `false` rounds to whole units (`"$1,235"`), useful for big headline numbers.
    ///   - alwaysShowsSign: prefixes positive values with `+`.
    static func format(
        _ cents: Int,
        currencyCode: String = defaultCurrencyCode,
        locale: Locale = .current,
        showsCents: Bool = true,
        alwaysShowsSign: Bool = false
    ) -> String {
        var style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
            .precision(.fractionLength(showsCents ? 2 : 0))
        if alwaysShowsSign {
            style = style.sign(strategy: .always(showZero: false))
        }
        return decimal(fromCents: cents).formatted(style)
    }

    /// Short form for chart axes and tight spaces: `"$950"`, `"$1.2K"`, `"$3.4M"`.
    static func compact(
        _ cents: Int,
        currencyCode: String = defaultCurrencyCode,
        locale: Locale = .current
    ) -> String {
        let value = decimal(fromCents: cents)
        let magnitude = abs(Double(cents) / 100)
        let suffix: String
        let divisor: Decimal
        switch magnitude {
        case 1_000_000_000...:
            suffix = "B"; divisor = 1_000_000_000
        case 1_000_000...:
            suffix = "M"; divisor = 1_000_000
        case 1_000...:
            suffix = "K"; divisor = 1_000
        default:
            return format(cents, currencyCode: currencyCode, locale: locale, showsCents: false)
        }
        let scaled = value / divisor
        let style = Decimal.FormatStyle.Currency(code: currencyCode, locale: locale)
            .precision(.fractionLength(0...1))
        return scaled.formatted(style) + suffix
    }

    // MARK: Parsing

    /// Parses user- or CSV-entered text into cents. Returns `nil` when the text
    /// holds no number.
    ///
    /// Accepts currency symbols and codes, grouping separators, a leading or
    /// trailing minus, and accounting parentheses: `"$1,234.56"`, `"-12"`,
    /// `"(45.00)"`, `"12.00-"`, `"USD 7.5"`.
    /// - Parameter decimalSeparator: the character that separates the
    ///   fraction. Every other non-digit character is ignored, so for `","`
    ///   the text `"1.234,56"` parses as 1234.56.
    static func parseCents(_ text: String, decimalSeparator: Character = ".") -> Int? {
        var working = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return nil }

        var isNegative = false
        if working.hasPrefix("("), working.hasSuffix(")") {
            isNegative = true
            working = String(working.dropFirst().dropLast())
        }

        var digits = ""
        var sawSeparator = false
        for character in working {
            if character.isASCII, character.isNumber {
                digits.append(character)
            } else if character == decimalSeparator {
                guard !sawSeparator else { return nil }
                sawSeparator = true
                digits.append(".")
            } else if character == "-" || character == "\u{2212}" {
                isNegative = true
            }
            // Anything else (currency symbols, grouping, spaces, letters) is ignored.
        }

        guard digits.contains(where: \.isNumber) else { return nil }
        if digits.hasPrefix(".") { digits = "0" + digits }
        guard let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        let cents = cents(from: value)
        return isNegative ? -cents : cents
    }

    /// Text to pre-fill an editable amount field, e.g. `1250` → `"12.50"`.
    static func editableText(fromCents cents: Int, locale: Locale = .current) -> String {
        let style = Decimal.FormatStyle(locale: locale)
            .precision(.fractionLength(2))
            .grouping(.never)
        return decimal(fromCents: cents).formatted(style)
    }
}
