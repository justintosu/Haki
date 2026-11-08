//
//  Theme.swift
//  Haki
//
//  Colors and card styling shared by every screen. Screens are a ScrollView
//  (or List) on `Color.hakiBackground` with content in `.hakiCard()` blocks.
//

import Foundation
import SwiftUI
import UIKit

extension Color {
    /// `Color(hex: "#3FB97B")`. Falls back to gray for malformed input.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# ")).uppercased()
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// Screen background behind cards (grouped background).
    static let hakiBackground = Color(uiColor: .systemGroupedBackground)
    /// Card surface.
    static let hakiCardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    /// Money coming in. Darker in light mode so small green text stays
    /// readable on white cards (about 5.3:1 there, about 5:1 on dark cards).
    static let hakiPositive = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 31.0 / 255, green: 166.0 / 255, blue: 122.0 / 255, alpha: 1)
            : UIColor(red: 19.0 / 255, green: 122.0 / 255, blue: 87.0 / 255, alpha: 1)
    })
    /// Over budget, late bills, money owed.
    static let hakiNegative = Color(uiColor: .systemRed)
    /// Spending faster than the budget's pace; things that need attention.
    /// A deeper orange in light mode, because system orange is too light for
    /// text on white (about 5.2:1 instead of 2.2:1).
    static let hakiWarning = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.systemOrange.resolvedColor(with: traits)
            : UIColor(red: 178.0 / 255, green: 80.0 / 255, blue: 0, alpha: 1)
    })
    /// Last month / comparison lines in charts.
    static let hakiComparison = Color(uiColor: .systemGray3)
}

/// Colors offered when creating or editing a category, in display order.
enum CategoryPalette {
    static let hexColors: [String] = [
        "#3FB97B", "#1FA67A", "#2BB5C9", "#4F8EF7", "#6C63FF", "#9B6DF2",
        "#E05FA3", "#F78FB3", "#EB5757", "#F2994A", "#E2B93B", "#A0673D",
        "#8D7B68", "#7F8C8D", "#8E8E93", "#34495E",
    ]
}

struct HakiCardModifier: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

extension View {
    /// A rounded card on the grouped background.
    func hakiCard(padding: CGFloat = 16) -> some View {
        modifier(HakiCardModifier(padding: padding))
    }
}

/// A card title row with an optional trailing button ("See all").
struct CardHeader: View {
    let title: String
    var systemImage: String?
    var actionTitle: String?
    var action: (() -> Void)?

    init(_ title: String, systemImage: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            } else {
                Text(title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }
}
