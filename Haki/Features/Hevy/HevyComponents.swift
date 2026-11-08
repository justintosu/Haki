//
//  HevyComponents.swift
//  Haki
//
//  Small pieces shared by the Hevy screens: the sync icon tile, an
//  explanatory row, and status wording.
//

import Foundation
import SwiftUI

enum HevyStyle {
    /// Haki's own color for the Hevy connection (not Hevy's branding).
    static let tint = Color.indigo
    static let symbol = "arrow.triangle.2.circlepath"
}

nonisolated enum HevyFormat {
    /// "Synced just now", "Synced 5 minutes ago", "Not synced yet".
    static func syncedText(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Not synced yet" }
        if abs(now.timeIntervalSince(date)) < 60 { return "Synced just now" }
        return "Synced " + date.formatted(.relative(presentation: .named))
    }

    /// "Just now", "5 minutes ago", "Not yet".
    static func lastSyncText(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Not yet" }
        if abs(now.timeIntervalSince(date)) < 60 { return "Just now" }
        return date.formatted(.relative(presentation: .named))
    }

    /// "1 workout", "12 workouts".
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        let number = value.formatted()
        return value == 1 ? "\(number) \(singular)" : "\(number) \(plural)"
    }
}

/// An SF Symbol on a rounded square: a tinted symbol on a light tint (like
/// the Health tab's rows), or white on the color (`solid`, like Settings).
struct HevyIconTile: View {
    var systemImage: String = HevyStyle.symbol
    var tint: Color = HevyStyle.tint
    var size: CGFloat = 36
    var font: Font = .body.weight(.semibold)
    var solid = false

    var body: some View {
        Image(systemName: systemImage)
            .font(font)
            .foregroundStyle(solid ? Color.white : tint)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }

    private var fill: AnyShapeStyle {
        solid ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.15))
    }
}

/// An icon with a title and a short explanation, for informational rows.
struct HevyFeatureRow: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 28

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            HevyIconTile(
                systemImage: systemImage,
                tint: tint,
                size: iconSize,
                font: .system(size: iconSize * 0.5, weight: .semibold),
                solid: true
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    List {
        HevyFeatureRow(
            systemImage: "arrow.down.circle.fill",
            tint: HevyStyle.tint,
            title: "From Hevy to Haki",
            message: "Workouts you log in Hevy are copied into Haki."
        )
        HStack(spacing: 12) {
            HevyIconTile()
            HevyIconTile(size: 52, font: .title2.weight(.semibold))
            Text(HevyFormat.syncedText(Date.now.addingTimeInterval(-300)))
        }
    }
    .previewEnvironment()
}
