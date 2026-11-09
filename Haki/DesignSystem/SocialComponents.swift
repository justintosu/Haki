//
//  SocialComponents.swift
//  Haki
//
//  Small views shared by the social, profile, auth and invest features.
//

import Foundation
import SwiftUI

/// A round profile photo with an initials fallback.
struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08)))
        .accessibilityHidden(true)
    }

    private var initials: some View {
        ZStack {
            Circle().fill(Color.accentColor.opacity(0.2))
            Text(Self.initials(for: name))
                .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.accentColor)
        }
    }

    static func initials(for name: String) -> String {
        let words = name.split(whereSeparator: { $0 == " " || $0 == "." || $0 == "_" })
        let letters = words.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return letters.isEmpty ? "?" : letters.joined()
    }
}

/// A percentage with sign and color: "+12.3%" in green, "−4.0%" in red.
struct PercentChangeText: View {
    let percent: Double?
    var decimals: Int = 1

    var body: some View {
        Text(Self.format(percent, decimals: decimals))
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private var color: Color {
        guard let percent, percent != 0 else { return .secondary }
        return percent > 0 ? .hakiPositive : .hakiNegative
    }

    static func format(_ percent: Double?, decimals: Int = 1) -> String {
        guard let percent else { return "—" }
        let style = FloatingPointFormatStyle<Double>.number
            .precision(.fractionLength(decimals))
            .sign(strategy: .always(includingZero: false))
        return percent.formatted(style) + "%"
    }
}

/// "$AAPL" as a tappable-looking capsule, with a "Holds" badge when the
/// post's author holds that stock.
struct TickerChip: View {
    let ticker: String
    var isVerifiedHolder: Bool = false

    var body: some View {
        HStack(spacing: 7) {
            Text("$\(ticker)")
                .font(.subheadline.weight(.semibold))
            if isVerifiedHolder {
                // Spelled out, not just a seal, and the seal hugs "Holds" so the
                // pair reads as one badge rather than a "verified ticker" mark.
                Label("Holds", systemImage: "checkmark.seal.fill")
                    .labelStyle(CompactLabelStyle(spacing: 2))
                    .font(.caption.weight(.semibold))
                    .imageScale(.small)
                    .accessibilityLabel("Author holds this stock")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .foregroundStyle(Color.accentColor)
        .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}
