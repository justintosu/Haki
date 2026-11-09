//
//  WardrobeSummaryCard.swift
//  Haki
//
//  The You tab's wardrobe card: how many pieces and outfits there are, the
//  four newest pieces, "Add piece" (opens the photo flow) and a link to the
//  whole wardrobe.
//

import Foundation
import SwiftData
import SwiftUI

struct WardrobeSummaryCard: View {
    @Query(sort: [SortDescriptor(\ClothingItem.createdAt, order: .reverse)])
    private var items: [ClothingItem]

    @Query(sort: [SortDescriptor(\Outfit.createdAt, order: .reverse)])
    private var outfits: [Outfit]

    @State private var showsAddPiece = false

    init() {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink {
                WardrobeView()
            } label: {
                WardrobeSummaryCardContent(
                    recent: Array(items.prefix(4)),
                    pieceCount: items.count,
                    outfitCount: outfits.count
                )
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your wardrobe and outfits")

            Button {
                showsAddPiece = true
            } label: {
                Label("Add piece", systemImage: "camera.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityHint("Take or choose a photo of a piece of clothing")
        }
        .hakiCard()
        .sheet(isPresented: $showsAddPiece) {
            ClothingItemEditorView(item: nil)
        }
    }
}

/// The linked part of the card: header, counts and the newest pieces.
private struct WardrobeSummaryCardContent: View {
    let recent: [ClothingItem]
    let pieceCount: Int
    let outfitCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if pieceCount == 0 {
                Text("Photograph your clothes and Haki removes the background and tags them. Then build outfits, get ideas and see what you actually wear.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                counts
                thumbnails
            }
        }
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label("Wardrobe", systemImage: "hanger")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var counts: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            count(pieceCount, singular: "piece", plural: "pieces")
            count(outfitCount, singular: "outfit", plural: "outfits")
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func count(_ value: Int, singular: String, plural: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(value)")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.primary)
            Text(value == 1 ? singular : plural)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var thumbnails: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { index in
                if index < recent.count {
                    WardrobeItemTile(item: recent[index], cornerRadius: 12)
                        .aspectRatio(1, contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.secondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(thumbnailsLabel)
    }

    private var thumbnailsLabel: String {
        let names = recent.map(\.name)
        return names.isEmpty ? "" : "Newest: " + names.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            WardrobeSummaryCard()
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        ScrollView {
            WardrobeSummaryCard()
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment(empty: true)
}
