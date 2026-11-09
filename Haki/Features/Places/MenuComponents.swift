//
//  MenuComponents.swift
//  Haki
//
//  Pieces of the menu screen: number and price formatting, the dish row,
//  tag chips, the health score capsule and the official/estimated marker.
//

import Foundation
import SwiftUI

/// Formatting for menus (prices in the menu's own currency).
enum MenuFormat {
    /// A usable ISO 4217 code ("USD" when the menu's is missing or malformed).
    static func currencyCode(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count == 3, trimmed.allSatisfy({ $0.isASCII && $0.isLetter }) else { return "USD" }
        return trimmed
    }

    /// "$13.95" in the report's currency.
    static func price(_ value: Double, currency: String) -> String {
        value.formatted(.currency(code: currency))
    }

    /// "$15" — whole units, for filter labels.
    static func wholePrice(_ value: Double, currency: String) -> String {
        value.formatted(.currency(code: currency).precision(.fractionLength(0)))
    }

    /// "$", "€", "£"... for the currency code, as the person's locale writes it.
    static func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let symbol: String? = formatter.currencySymbol
        guard let symbol, !symbol.isEmpty else { return code }
        return symbol
    }

    /// "610"
    static func whole(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    /// "3.4"
    static func oneDecimal(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        return value.formatted(.number.precision(.fractionLength(1)))
    }

    static func kcal(_ value: Double) -> String { "\(whole(value)) kcal" }

    static func grams(_ value: Double) -> String { "\(whole(value)) g" }

    /// "610 kcal · 48 g protein"
    static func macrosLine(_ dish: MenuDish) -> String {
        "\(kcal(dish.calories)) · \(grams(dish.proteinG)) protein"
    }

    /// "7.9 g protein per 100 kcal · 3.4 g protein per $", or nil.
    static func proteinValueLine(_ dish: MenuDish, currency: String) -> String? {
        var parts: [String] = []
        if let perCalories = dish.proteinPer100Calories {
            parts.append("\(oneDecimal(perCalories)) g protein per 100 kcal")
        }
        // Dropped when it rounds to 0.0 (yen, won and other small units).
        if let perPrice = dish.proteinPerCurrencyUnit, perPrice >= 0.05 {
            parts.append("\(oneDecimal(perPrice)) g protein per \(currencySymbol(for: currency))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Health score 8 out of 10, very healthy", for VoiceOver.
    static func scoreDescription(_ score: Int) -> String {
        let word: String
        switch score {
        case 8...: word = "very healthy"
        case 6..<8: word = "healthy"
        case 4..<6: word = "okay"
        default: word = "less healthy"
        }
        return "Health score \(score) out of 10, \(word)"
    }
}

/// One dish in the menu list. The whole row is the tap target (it opens
/// the dish sheet), so it reads as one element for VoiceOver.
struct MenuDishRow: View {
    let dish: MenuDish
    let currency: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(dish.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(MenuFormat.macrosLine(dish))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if let value = MenuFormat.proteinValueLine(dish, currency: currency) {
                    Text(value)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if !dish.tags.isEmpty {
                    MenuTagRow(tags: dish.tags)
                }
                MenuNutritionMarker(isOfficial: dish.isOfficialNutrition)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                MenuScoreBadge(score: dish.healthScore)
                if let price = dish.price, price > 0 {
                    Text(MenuFormat.price(price, currency: currency))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows details and lets you log it")
    }
}

/// A small capsule for a dish tag ("High protein").
struct MenuTagChip: View {
    let menuTag: MenuTag

    var body: some View {
        Label(menuTag.title, systemImage: menuTag.systemImage)
            .labelStyle(MenuCompactLabelStyle())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    private var tint: Color {
        switch menuTag {
        case .highProtein: .purple
        case .lowCalorie, .lowCarb: .blue
        case .highFiber, .balanced: .teal
        case .vegetarian, .vegan: .hakiPositive
        case .glutenFree: .brown
        }
    }
}

/// As many tag chips as fit on one line, then "+N".
struct MenuTagRow: View {
    let tags: [MenuTag]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            chips(showing: tags.count)
            chips(showing: min(3, tags.count))
            chips(showing: min(2, tags.count))
            chips(showing: min(1, tags.count))
        }
    }

    private func chips(showing count: Int) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(tags.prefix(count).enumerated()), id: \.offset) { _, menuTag in
                MenuTagChip(menuTag: menuTag)
            }
            if count < tags.count {
                Text("+\(tags.count - count)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("and \(tags.count - count) more")
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// "9/10" in a capsule; the number carries the meaning, the color only helps.
struct MenuScoreBadge: View {
    let score: Int

    var body: some View {
        Text("\(score)/10")
            .font(.caption.weight(.bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityLabel(MenuFormat.scoreDescription(score))
    }

    private var tint: Color {
        if score >= 8 { return .hakiPositive }
        if score >= 5 { return .secondary }
        return .hakiWarning
    }
}

/// Whether the nutrition was published by the business or estimated by Haki's AI.
struct MenuNutritionMarker: View {
    let isOfficial: Bool

    var body: some View {
        Label(
            isOfficial ? "Official nutrition" : "Estimated nutrition",
            systemImage: isOfficial ? "checkmark.seal.fill" : "sparkles"
        )
        .labelStyle(MenuCompactLabelStyle())
        .font(.caption2)
        .foregroundStyle(isOfficial ? Color.hakiPositive : Color.secondary)
    }
}

/// Icon and title close together, for small captions.
struct MenuCompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon
                .accessibilityHidden(true)
            configuration.title
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(Array(FoodAIPreviewSamples.menu.items.enumerated()), id: \.offset) { index, dish in
                if index > 0 { Divider() }
                MenuDishRow(dish: dish, currency: "USD")
            }
        }
        .hakiCard()
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
