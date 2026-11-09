//
//  ClothingItemDetailView.swift
//  Haki
//
//  One piece of clothing: its photo, "Wore it today", how often and how
//  recently it's been worn, what each wear has cost, its details and the
//  outfits it's in (plus "Add to outfit"). Pushed from the wardrobe.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct ClothingItemDetailView: View {
    let item: ClothingItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showsEditor = false
    @State private var showsAddToOutfit = false
    /// Set when the person deletes the piece from the editor. It's deleted
    /// only once this screen has gone, so nothing reads a deleted model.
    @State private var deletionRequested = false
    @State private var wornFeedback = 0
    @State private var pendingOutfit: Outfit?
    @State private var openedOutfit: Outfit?

    init(item: ClothingItem) {
        self.item = item
    }

    var body: some View {
        if isItemGone {
            ContentUnavailableView(
                "Piece deleted",
                systemImage: "hanger",
                description: Text("This piece is no longer in your wardrobe.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hakiBackground)
        } else {
            detail
        }
    }

    private var isItemGone: Bool {
        item.isDeleted || item.modelContext == nil
    }

    private var detail: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                wearCard
                detailsCard
                outfitsCard
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $showsEditor, onDismiss: editorDismissed) {
            ClothingItemEditorView(item: item, onDelete: { deletionRequested = true })
        }
        .sheet(isPresented: $showsAddToOutfit, onDismiss: openPendingOutfit) {
            ClothingAddToOutfitSheet(item: item) { outfit in
                pendingOutfit = outfit
            }
        }
        .navigationDestination(item: $openedOutfit) { outfit in
            OutfitBoardView(outfit: outfit)
        }
        .sensoryFeedback(.success, trigger: wornFeedback)
        .onDisappear {
            deleteIfRequested()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                item.isFavorite.toggle()
                WardrobeStore.save(in: modelContext)
            } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
            }
            .accessibilityLabel(item.isFavorite ? "Remove from favorites" : "Add to favorites")
            Button("Edit") {
                showsEditor = true
            }
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(spacing: 14) {
            ClothingDetailImage(item: item)
            VStack(spacing: 4) {
                Text(item.name)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(heroSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            if !item.colors.isEmpty {
                colorDots
            }
        }
        .hakiCard()
    }

    private var heroSubtitle: String {
        var parts = [item.category.singularTitle]
        let brand = item.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !brand.isEmpty { parts.append(brand) }
        if item.isFavorite { parts.append("Favorite") }
        return parts.joined(separator: " · ")
    }

    private var colorDots: some View {
        HStack(spacing: 6) {
            ForEach(item.colors) { color in
                Circle()
                    .fill(Color(hex: color.hex))
                    .overlay {
                        Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    }
                    .frame(width: 16, height: 16)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Colors: \(WardrobeFormat.colors(item.colors))")
    }

    // MARK: Wear

    private var isWornToday: Bool {
        WardrobeFormat.isToday(item.lastWornAt)
    }

    private var wearCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            CardHeader("Wear", systemImage: "calendar")
            wearStats
            Button {
                markWorn()
            } label: {
                Label(isWornToday ? "Worn today" : "Wore it today", systemImage: isWornToday ? "checkmark.circle.fill" : "hanger")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWornToday)
            .accessibilityHint(isWornToday ? "Already counted today" : "Counts one wear today")
        }
        .hakiCard()
    }

    private var wearStats: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        return layout {
            ClothingDetailStat(title: "Times worn", value: "\(item.timesWorn)")
            ClothingDetailStat(title: "Last worn", value: WardrobeFormat.lastWorn(item.lastWornAt))
            ClothingDetailStat(title: "Cost per wear", value: costPerWearText)
        }
    }

    private var costPerWearText: String {
        guard let cents = WardrobeStats.costPerWearCents(priceCents: item.priceCents, timesWorn: item.timesWorn) else {
            return "Add a price"
        }
        return Money.format(cents)
    }

    private func markWorn() {
        withAnimation(.snappy) {
            WardrobeStore.markWorn(item, in: modelContext)
        }
        wornFeedback += 1
    }

    // MARK: Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Details", systemImage: "tag")
            VStack(spacing: 0) {
                ForEach(Array(detailRows.enumerated()), id: \.offset) { index, row in
                    if index > 0 {
                        Divider()
                    }
                    ClothingDetailRow(title: row.title, value: row.value)
                }
            }
            if !item.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(item.notes)
                        .font(.body)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .hakiCard()
    }

    private var detailRows: [ClothingDetailRowData] {
        var rows: [ClothingDetailRowData] = [
            ClothingDetailRowData(title: "Type", value: item.category.singularTitle),
            ClothingDetailRowData(title: "Colors", value: WardrobeFormat.colors(item.colors)),
        ]
        let pattern = item.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if !pattern.isEmpty {
            rows.append(ClothingDetailRowData(title: "Pattern", value: pattern.capitalized))
        }
        rows.append(ClothingDetailRowData(title: "Seasons", value: WardrobeFormat.seasons(item.seasons)))
        rows.append(ClothingDetailRowData(title: "Style", value: WardrobeFormat.styles(item.styles)))
        rows.append(ClothingDetailRowData(title: "Formality", value: "\(WardrobeFormat.formality(item.formality)) (\(item.formality) of 5)"))
        rows.append(ClothingDetailRowData(title: "Warmth", value: "\(WardrobeFormat.warmth(item.warmth)) (\(item.warmth) of 5)"))
        let brand = item.brand.trimmingCharacters(in: .whitespacesAndNewlines)
        if !brand.isEmpty {
            rows.append(ClothingDetailRowData(title: "Brand", value: brand))
        }
        if let price = item.priceCents {
            rows.append(ClothingDetailRowData(title: "Price", value: Money.format(price)))
        }
        rows.append(ClothingDetailRowData(title: "Added", value: item.createdAt.formatted(date: .abbreviated, time: .omitted)))
        return rows
    }

    // MARK: Outfits

    private var containingOutfits: [Outfit] {
        var seen = Set<UUID>()
        return item.pieces
            .filter { !$0.isDeleted }
            .compactMap { $0.outfit }
            .filter { !$0.isDeleted && seen.insert($0.id).inserted }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var outfitsCard: some View {
        let outfits = containingOutfits
        return VStack(alignment: .leading, spacing: 12) {
            CardHeader("Outfits", systemImage: "square.grid.2x2")
            if outfits.isEmpty {
                Text("Not in any outfit yet. Put it on a board with other pieces to plan a look.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 10) {
                    // Opened through `openedOutfit`, not a link: removing this
                    // piece on the board takes the outfit out of this list,
                    // and a removed link would close the board.
                    ForEach(outfits) { outfit in
                        Button {
                            openedOutfit = outfit
                        } label: {
                            HStack {
                                WardrobeOutfitRow(outfit: outfit)
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button {
                showsAddToOutfit = true
            } label: {
                Label("Add to outfit", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .hakiCard()
    }

    private func openPendingOutfit() {
        guard let outfit = pendingOutfit else { return }
        pendingOutfit = nil
        openedOutfit = outfit
    }

    // MARK: Deleting

    private func editorDismissed() {
        guard deletionRequested else { return }
        // Back to the wardrobe; the piece is deleted in `onDisappear`.
        dismiss()
    }

    private func deleteIfRequested() {
        guard deletionRequested else { return }
        deletionRequested = false
        guard !isItemGone else { return }
        // Outfit pictures showing this piece are redrawn on their next visit.
        for piece in item.pieces where !piece.isDeleted {
            piece.outfit?.previewData = nil
        }
        // Not animated: grids animating the card away would keep drawing the deleted model.
        WardrobeStore.deleteItem(item, in: modelContext)
    }
}

// MARK: - Subviews

private struct ClothingDetailRowData {
    let title: String
    let value: String
}

/// The big photo (or icon) on the studio backdrop.
private struct ClothingDetailImage: View {
    let item: ClothingItem

    var body: some View {
        WardrobePalette.studio
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .overlay { artwork }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isImage)
    }

    private var accessibilityText: String {
        WardrobeImageCache.fullImage(for: item) == nil ? "No photo" : "Photo of \(item.name)"
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = WardrobeImageCache.fullImage(for: item) {
            if item.isCutout {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .shadow(color: Color.black.opacity(0.16), radius: 10, x: 0, y: 6)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            WardrobeCategoryIcon(category: item.category, colors: item.colors)
                .frame(width: 96, height: 96)
        }
    }
}

private struct ClothingDetailStat: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct ClothingDetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Picks an outfit to add the piece to, or starts a new one with it.
private struct ClothingAddToOutfitSheet: View {
    let item: ClothingItem
    /// Called with the outfit the piece was added to (opened once the sheet closes).
    let onAdded: (Outfit) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\Outfit.createdAt, order: .reverse)])
    private var outfits: [Outfit]

    init(item: ClothingItem, onAdded: @escaping (Outfit) -> Void) {
        self.item = item
        self.onAdded = onAdded
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        createOutfit()
                    } label: {
                        Label("New outfit with this piece", systemImage: "plus.square.on.square")
                    }
                }
                Section("Your outfits") {
                    if availableOutfits.isEmpty {
                        Text(outfits.isEmpty ? "You haven't made any outfits yet." : "This piece is already in all your outfits.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableOutfits) { outfit in
                            Button {
                                add(to: outfit)
                            } label: {
                                WardrobeOutfitRow(outfit: outfit)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Adds the piece to this outfit and opens it")
                        }
                    }
                }
            }
            .navigationTitle("Add to outfit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var availableOutfits: [Outfit] {
        let itemID = item.id
        return outfits.filter { outfit in
            !outfit.pieces.contains { $0.item?.id == itemID }
        }
    }

    private func add(to outfit: Outfit) {
        WardrobeStore.addPiece(item, to: outfit, in: modelContext)
        // The board's snapshot is redrawn when it's next opened and closed.
        outfit.previewData = nil
        WardrobeStore.save(in: modelContext)
        onAdded(outfit)
        dismiss()
    }

    private func createOutfit() {
        let name = "\(item.name) outfit"
        let outfit = WardrobeStore.createOutfit(name: name, items: [item], in: modelContext)
        onAdded(outfit)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        ClothingItemDetailView(item: PreviewData.sampleClothingItem)
    }
    .previewEnvironment()
}
