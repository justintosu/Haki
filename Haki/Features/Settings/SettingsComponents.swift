//
//  SettingsComponents.swift
//  Haki
//
//  Small pieces shared by the Settings screens and CSV import: rounded,
//  tinted icon tiles (like the system Settings app), labels built on them
//  and a pluralizing count formatter.
//

import Foundation
import SwiftUI

// MARK: - Formatting

nonisolated enum SettingsFormat {
    /// "1 transaction", "1,204 transactions".
    static func count(_ value: Int, _ singular: String, _ plural: String) -> String {
        let number = value.formatted()
        return value == 1 ? "\(number) \(singular)" : "\(number) \(plural)"
    }
}

// MARK: - Icon tile

/// An SF Symbol in white on a rounded, tinted square. Scales with Dynamic Type.
struct SettingsIconTile: View {
    let systemImage: String
    let tint: Color
    @ScaledMetric private var size: CGFloat

    init(systemImage: String, tint: Color, size: CGFloat = 28) {
        self.systemImage = systemImage
        self.tint = tint
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

// MARK: - Row label

/// A list row label: icon tile and title. The title stays in the primary color
/// even inside a `Button`, unless a color is given (e.g. red for destructive rows).
struct SettingsIconLabel: View {
    let title: String
    let systemImage: String
    let tint: Color
    let titleColor: Color

    init(_ title: String, systemImage: String, tint: Color = .accentColor, titleColor: Color = .primary) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.titleColor = titleColor
    }

    var body: some View {
        Label {
            Text(title)
                .foregroundStyle(titleColor)
        } icon: {
            SettingsIconTile(systemImage: systemImage, tint: tint)
        }
    }
}

// MARK: - Note row

/// An icon tile with a title and a short explanation, for informational rows.
struct SettingsNoteRow: View {
    let title: String
    let message: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SettingsIconTile(systemImage: systemImage, tint: tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body)
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
        Section {
            SettingsIconLabel("Import from CSV", systemImage: "tray.and.arrow.down.fill")
            SettingsIconLabel("Erase all data", systemImage: "trash.fill", tint: .red, titleColor: .hakiNegative)
            SettingsNoteRow(
                title: "Private by design",
                message: "Everything you add to Haki is stored only on this device.",
                systemImage: "lock.fill",
                tint: .blue
            )
        }
        Section {
            Text(SettingsFormat.count(1, "transaction", "transactions"))
            Text(SettingsFormat.count(1204, "transaction", "transactions"))
        }
    }
    .previewEnvironment()
}
