//
//  PlacesComponents.swift
//  Haki
//
//  Small views shared by the places and menu screens: toggle chips, the
//  tinted category icon and the map pin.
//

import Foundation
import SwiftUI

/// A capsule toggle used for search shortcuts and menu filters. Selection is
/// shown with a fill and a checkmark, and reported to VoiceOver.
struct PlacesChipButton: View {
    let title: String
    var systemImage: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .animation(.snappy, value: isSelected)
    }
}

/// A rounded square with a tinted SF Symbol, sized with Dynamic Type.
struct PlacesCategoryIcon: View {
    let systemImage: String
    var tint: Color
    @ScaledMetric private var size: CGFloat
    private let usesLargeSymbol: Bool

    init(systemImage: String, tint: Color = .orange, size: CGFloat = 40) {
        self.systemImage = systemImage
        self.tint = tint
        self.usesLargeSymbol = size > 44
        _size = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(usesLargeSymbol ? Font.title3.weight(.semibold) : Font.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: size * 0.27, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A tappable pin for a place on the map.
struct PlacesMapPin: View {
    let name: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.callout.weight(.bold))
                .foregroundStyle(Color.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(isSelected ? Color.accentColor : Color.orange))
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(color: Color.black.opacity(0.25), radius: 3, y: 1)
                .scaleEffect(isSelected ? 1.2 : 1)
                .animation(.snappy, value: isSelected)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        HStack {
            PlacesChipButton(title: "Healthy", systemImage: "leaf.fill", isSelected: true) {}
            PlacesChipButton(title: "Coffee", systemImage: "cup.and.saucer.fill", isSelected: false) {}
        }
        HStack(spacing: 12) {
            PlacesCategoryIcon(systemImage: "fork.knife")
            PlacesCategoryIcon(systemImage: "cart.fill", tint: .green, size: 52)
            PlacesMapPin(name: "Green Fork Kitchen", systemImage: "fork.knife", isSelected: false) {}
            PlacesMapPin(name: "Corner Café", systemImage: "cup.and.saucer.fill", isSelected: true) {}
        }
    }
    .padding()
    .previewEnvironment()
}
