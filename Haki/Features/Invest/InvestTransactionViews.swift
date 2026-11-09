//
//  InvestTransactionViews.swift
//  Haki
//
//  Investment transactions (buys, sells, dividends, fees, transfers) as rows,
//  and the "Recent activity" card on the Invest tab.
//
//  Amounts follow the app's sign convention (the same one Plaid uses):
//  positive = cash leaving the account (a buy, a fee), negative = cash coming
//  in (a sale, a dividend). Money in shows as "+$X" in green.
//

import Foundation
import SwiftUI

// MARK: - Kind

/// What a Plaid investment transaction is, for icons and filtering.
enum InvestTransactionKind: String, CaseIterable, Hashable {
    case buy, sell, dividend, interest, fee, deposit, withdrawal, transfer, canceled, other

    init(type: String, subtype: String?) {
        let subtype = (subtype ?? "").lowercased()
        switch type.lowercased() {
        case "buy":
            self = .buy
        case "sell":
            self = .sell
        case "cancel":
            self = .canceled
        case "fee":
            self = .fee
        case "transfer":
            self = Self.movement(subtype) ?? .transfer
        case "cash":
            if subtype.contains("dividend") || subtype.contains("gain") || subtype.contains("distribution") {
                self = .dividend
            } else if subtype.contains("interest") {
                self = .interest
            } else if subtype.contains("fee") || subtype.contains("expense") || subtype.contains("tax") {
                self = .fee
            } else {
                self = Self.movement(subtype) ?? .transfer
            }
        default:
            self = .other
        }
    }

    private static func movement(_ subtype: String) -> InvestTransactionKind? {
        if subtype.contains("deposit") || subtype.contains("contribution") { return .deposit }
        if subtype.contains("withdrawal") { return .withdrawal }
        return nil
    }

    var title: String {
        switch self {
        case .buy: "Buy"
        case .sell: "Sell"
        case .dividend: "Dividend"
        case .interest: "Interest"
        case .fee: "Fee"
        case .deposit: "Deposit"
        case .withdrawal: "Withdrawal"
        case .transfer: "Transfer"
        case .canceled: "Canceled"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .buy: "plus.circle.fill"
        case .sell: "minus.circle.fill"
        case .dividend: "dollarsign.circle.fill"
        case .interest: "percent"
        case .fee: "tag.fill"
        case .deposit: "arrow.down.circle.fill"
        case .withdrawal: "arrow.up.circle.fill"
        case .transfer: "arrow.left.arrow.right.circle.fill"
        case .canceled: "xmark.circle.fill"
        case .other: "circle.dashed"
        }
    }

    var tint: Color {
        switch self {
        case .buy: .accentColor
        case .sell: .hakiWarning
        case .dividend, .interest: .hakiPositive
        case .fee: .hakiNegative
        case .deposit, .withdrawal, .transfer: Color(hex: "#4F8EF7")
        case .canceled, .other: .gray
        }
    }

    /// Whether "quantity × price" means something for this kind.
    var tradesShares: Bool { self == .buy || self == .sell }
}

// MARK: - Row

/// Icon, name, kind (unless the name already says it), ticker,
/// "quantity × price", account, amount and date.
struct InvestTransactionRow: View {
    let transaction: InvestmentTransaction
    var accountName: String? = nil
    var currency: String = Money.defaultCurrencyCode
    var showsDate: Bool = true

    var body: some View {
        let kind = InvestTransactionKind(type: transaction.type, subtype: transaction.subtype)
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(kind.tint.opacity(0.16))
                Image(systemName: kind.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(kind.tint)
            }
            .frame(width: 36, height: 36)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title(kind))
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                Text(subtitle(kind))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                if let amount = transaction.amount, amount.isFinite {
                    Text(amountText(amount))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(amount < 0 ? Color.hakiPositive : Color.primary)
                }
                if showsDate, let day = transaction.day {
                    Text(InvestFormat.shortDay(day))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private func title(_ kind: InvestTransactionKind) -> String {
        let name = transaction.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if let security = transaction.securityName, !security.isEmpty { return "\(kind.title): \(security)" }
        if let ticker = transaction.ticker, !ticker.isEmpty { return "\(kind.title) \(ticker)" }
        return kind.title
    }

    private func subtitle(_ kind: InvestTransactionKind) -> String {
        // The title often already names the kind ("Buy Vanguard…", "Dividend: Apple Inc.",
        // "Account maintenance fee"); don't spend the line repeating it. Whole words only,
        // so "Coffee Holdings" doesn't count as naming "Fee".
        let titleWords = title(kind).lowercased().split(whereSeparator: { !$0.isLetter })
        let kindWord = kind.title.lowercased()
        let titleNamesKind = titleWords.contains { $0 == kindWord }
        var parts: [String] = titleNamesKind ? [] : [kind.title]
        if let ticker = transaction.ticker, Cashtags.isValidTicker(ticker) {
            parts.append(ticker)
        }
        if kind.tradesShares,
           let quantity = transaction.quantity, quantity != 0, quantity.isFinite,
           let price = transaction.price, price.isFinite {
            parts.append("\(InvestFormat.quantity(quantity)) × \(InvestFormat.price(price, currency: transactionCurrency))")
        }
        if let accountName, !accountName.isEmpty {
            parts.append(accountName)
        }
        return parts.isEmpty ? kind.title : parts.joined(separator: " · ")
    }

    /// Money in as "+$X", money out as "$X".
    private func amountText(_ amount: Double) -> String {
        if amount < 0 {
            return InvestFormat.money(-amount, currency: transactionCurrency, alwaysShowsSign: true)
        }
        return InvestFormat.money(amount, currency: transactionCurrency)
    }

    private var transactionCurrency: String {
        transaction.currency.count == 3 ? transaction.currency.uppercased() : currency
    }
}

// MARK: - Recent activity card

/// The first few transactions on the Invest tab, with "See all".
struct InvestRecentActivityCard: View {
    let transactions: [InvestmentTransaction]
    let totalCount: Int
    let accountNames: [UUID: String]
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recent activity", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if totalCount > 0 {
                    NavigationLink {
                        InvestActivityView()
                    } label: {
                        Text("See all")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("See all investment activity")
                }
            }
            if transactions.isEmpty {
                InvestInlineNote(
                    systemImage: "clock",
                    text: "Buys, sells, dividends and transfers from the last 90 days show up here."
                )
                .padding(.top, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(transactions.enumerated()), id: \.element.id) { index, transaction in
                        if index > 0 {
                            Divider().padding(.leading, 48)
                        }
                        InvestTransactionRow(
                            transaction: transaction,
                            accountName: accountNames[transaction.accountID],
                            currency: currency
                        )
                    }
                }
            }
        }
        .hakiCard()
    }
}

#Preview {
    let portfolio = PortfolioService.preview
    NavigationStack {
        ScrollView {
            InvestRecentActivityCard(
                transactions: Array(portfolio.transactions.prefix(5)),
                totalCount: portfolio.transactions.count,
                accountNames: Dictionary(portfolio.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first }),
                currency: "USD"
            )
            .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
