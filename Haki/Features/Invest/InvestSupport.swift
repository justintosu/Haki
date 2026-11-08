//
//  InvestSupport.swift
//  Haki
//
//  Formatting, colors and small views shared by the Invest screens.
//  Brokerage amounts arrive in dollars (fractional shares, sub-cent prices),
//  so they are converted to cents only at the moment they are formatted.
//

import Foundation
import SwiftUI

// MARK: - Formatting

/// Formatting for brokerage data. Pure Foundation, usable from any context.
nonisolated enum InvestFormat {
    /// Dollars → cents for `Money`, safe for non-finite and absurdly large values.
    static func cents(_ dollars: Double) -> Int {
        guard dollars.isFinite else { return 0 }
        let scaled = (dollars * 100).rounded()
        let limit = 9.0e15
        if scaled >= limit { return Int(limit) }
        if scaled <= -limit { return -Int(limit) }
        return Int(scaled)
    }

    /// "$1,234.56" (or "+$1,234.56" with `alwaysShowsSign`).
    static func money(
        _ dollars: Double,
        currency: String = Money.defaultCurrencyCode,
        showsCents: Bool = true,
        alwaysShowsSign: Bool = false
    ) -> String {
        Money.format(cents(dollars), currencyCode: currency, showsCents: showsCents, alwaysShowsSign: alwaysShowsSign)
    }

    /// "$1.2K" for chart axes.
    static func compact(_ dollars: Double, currency: String = Money.defaultCurrencyCode) -> String {
        Money.compact(cents(dollars), currencyCode: currency)
    }

    /// A share price: two decimals, up to four for prices under one unit.
    static func price(_ dollars: Double, currency: String = Money.defaultCurrencyCode) -> String {
        guard dollars.isFinite else { return "—" }
        if abs(dollars) >= 1 || dollars == 0 {
            return money(dollars, currency: currency)
        }
        let style = FloatingPointFormatStyle<Double>.Currency(code: currency)
            .precision(.fractionLength(2...4))
        return dollars.formatted(style)
    }

    /// "12.5", "0.0512" — at most four decimals, never negative.
    static func quantity(_ value: Double) -> String {
        guard value.isFinite else { return "—" }
        return abs(value).formatted(.number.precision(.fractionLength(0...4)))
    }

    /// "25 shares", "1 share", "0.05 BTC".
    static func shares(_ quantity: Double, securityType: String?, symbol: String) -> String {
        let amount = Self.quantity(quantity)
        switch AssetClass(plaidType: securityType) {
        case .crypto:
            return Cashtags.isValidTicker(symbol) ? "\(amount) \(symbol)" : "\(amount) units"
        case .bonds:
            return abs(quantity) == 1 ? "1 unit" : "\(amount) units"
        case .cash:
            return amount
        default:
            return abs(quantity) == 1 ? "1 share" : "\(amount) shares"
        }
    }

    /// "12.3%" (no sign).
    static func percent(_ value: Double, decimals: Int = 1) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(.number.precision(.fractionLength(decimals))) + "%"
    }

    /// "Synced just now", "Synced 2 hours ago", "Not synced yet".
    static func syncedText(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Not synced yet" }
        if abs(now.timeIntervalSince(date)) < 60 { return "Synced just now" }
        return "Synced " + date.formatted(.relative(presentation: .named))
    }

    /// Noon local time on a "yyyy-MM-dd" day (how `date` columns arrive).
    static func day(from string: String) -> Date? {
        let parts = string.prefix(10).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        return Calendar.current.noon(year: year, month: month, day: day)
    }

    /// "Nov 6"
    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// The portfolio's currency: what the brokerage reports, else the device's.
    static func currencyCode(holdings: [BrokerageHolding], accounts: [InvestmentAccount]) -> String {
        let code = holdings.first?.currency ?? accounts.first?.currency ?? ""
        return code.count == 3 ? code.uppercased() : Money.defaultCurrencyCode
    }

    /// Latest successful sync over every connection.
    static func lastSynced(_ connections: [BrokerageConnection]) -> Date? {
        connections.compactMap(\.lastSyncedAt).max()
    }
}

// MARK: - Colors and symbols

enum InvestStyle {
    static func color(for assetClass: AssetClass) -> Color {
        switch assetClass {
        case .stocks: Color(hex: "#4F8EF7")
        case .etfs: Color(hex: "#1FA67A")
        case .funds: Color(hex: "#9B6DF2")
        case .crypto: Color(hex: "#F2994A")
        case .bonds: Color(hex: "#2BB5C9")
        case .cash: Color(hex: "#8E8E93")
        case .other: Color(hex: "#E05FA3")
        }
    }

    static func systemImage(for assetClass: AssetClass) -> String {
        switch assetClass {
        case .stocks: "chart.line.uptrend.xyaxis"
        case .etfs: "square.stack.3d.up"
        case .funds: "building.columns"
        case .crypto: "bitcoinsign.circle"
        case .bonds: "doc.text"
        case .cash: "dollarsign.circle"
        case .other: "circle.grid.2x2"
        }
    }

    /// Green for gains, red for losses, gray for flat or unknown.
    static func gainColor(_ value: Double?) -> Color {
        guard let value, value != 0, value.isFinite else { return .secondary }
        return value > 0 ? .hakiPositive : .hakiNegative
    }

    /// An arrow that carries the direction without relying on color.
    static func gainSystemImage(_ value: Double?) -> String {
        guard let value, value != 0 else { return "minus" }
        return value > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    /// What to call a position in lists: cash shows as "Cash" rather than "CUR:USD".
    static func displaySymbol(for position: PortfolioPosition) -> String {
        position.isCash ? "Cash" : position.symbol
    }

    /// Whether social actions (cashtags, ticker feeds, trade posts) make sense for this symbol.
    static func isShareableTicker(_ position: PortfolioPosition) -> Bool {
        !position.isCash && Cashtags.isValidTicker(position.symbol)
    }
}

// MARK: - Symbol badge

/// A rounded tile with the ticker, tinted by asset class.
struct HoldingSymbolBadge: View {
    let symbol: String
    let name: String
    let assetClass: AssetClass
    var size: CGFloat = 40

    var body: some View {
        let tint = InvestStyle.color(for: assetClass)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(tint.opacity(0.16))
            if assetClass == .cash {
                Image(systemName: "dollarsign")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(tint)
            } else {
                Text(label)
                    .font(.system(size: size * (label.count > 3 ? 0.26 : 0.32), weight: .bold, design: .rounded))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var label: String {
        if Cashtags.isValidTicker(symbol) { return String(symbol.prefix(5)) }
        return AvatarView.initials(for: name)
    }
}

// MARK: - Banner and toast

/// A dismissible warning with a retry action, shown above the cards.
struct InvestErrorBanner: View {
    let message: String
    var retryTitle: String = "Try again"
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.hakiWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Button(retryTitle, action: onRetry)
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hakiWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.hakiWarning.opacity(0.35))
        }
    }
}

/// A short confirmation capsule ("Connected Northwind Investing").
struct InvestToast: View {
    let message: String

    var body: some View {
        Label {
            Text(message)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.hakiPositive)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.08))
        }
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Small building blocks

/// A chart legend entry: a short solid or dashed line and a title, so series
/// can be told apart without color.
struct InvestLegendItem: View {
    let title: String
    let color: Color
    var dashed: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 1, y: 2))
                path.addLine(to: CGPoint(x: 17, y: 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: dashed ? [3, 4] : []))
            .frame(width: 18, height: 4)
            .accessibilityHidden(true)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A caption over a value, for stat grids.
struct InvestStatTile<Value: View>: View {
    let title: String
    let value: Value

    init(_ title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            value
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A gentle inline note inside a card (empty chart, nothing synced yet).
struct InvestInlineNote: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// "+$1,234.56 (+12.3%)" with an arrow, colored by direction.
struct InvestGainLabel: View {
    let gain: Double?
    let gainPct: Double?
    let currency: String
    var font: Font = .subheadline.weight(.semibold)

    var body: some View {
        if let gain {
            HStack(spacing: 4) {
                Image(systemName: InvestStyle.gainSystemImage(gain))
                    .font(.caption.weight(.bold))
                    .accessibilityHidden(true)
                Text(InvestFormat.money(gain, currency: currency, alwaysShowsSign: true))
                    .monospacedDigit()
                if let gainPct {
                    PercentChangeText(percent: gainPct)
                        .padding(.leading, 2)
                }
            }
            .font(font)
            .foregroundStyle(InvestStyle.gainColor(gain))
            .accessibilityElement(children: .combine)
        } else {
            Text("Gain not reported")
                .font(font)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Building blocks") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                HoldingSymbolBadge(symbol: "VTI", name: "Vanguard Total Stock Market ETF", assetClass: .etfs)
                HoldingSymbolBadge(symbol: "AAPL", name: "Apple Inc.", assetClass: .stocks)
                HoldingSymbolBadge(symbol: "BTC", name: "Bitcoin", assetClass: .crypto)
                HoldingSymbolBadge(symbol: "CUR:USD", name: "U.S. Dollar", assetClass: .cash)
                HoldingSymbolBadge(symbol: "Target 2050", name: "Target Retirement 2050", assetClass: .funds)
            }
            InvestGainLabel(gain: 1_234.56, gainPct: 12.3, currency: "USD")
            InvestGainLabel(gain: -88.1, gainPct: -2.4, currency: "USD")
            HStack {
                InvestLegendItem(title: "Value", color: .accentColor)
                InvestLegendItem(title: "Invested", color: .hakiComparison, dashed: true)
            }
            InvestErrorBanner(message: "Couldn't load your investments. Pull to refresh.", onRetry: {}, onDismiss: {})
            InvestInlineNote(systemImage: "chart.xyaxis.line", text: "History builds up as Haki syncs your accounts each day.")
            InvestToast(message: "Connected Northwind Investing")
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
