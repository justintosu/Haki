//
//  OutfitPiecePickerView.swift
//  Haki
//
//  Picks several pieces from the wardrobe (for a new outfit, or to add to an
//  outfit's board): a searchable grid with type filters, tap to select, and
//  a bar that says what the outfit still needs. Presented as a sheet.
//

import Foundation
import SwiftData
import SwiftUI

struct OutfitPiecePickerView: View {
    let title: String
    let confirmTitle: String
    /// Pieces already on the board (left out of the grid).
    let excludedIDs: Set<UUID>
    /// Ask for the new outfit's name too.
    let showsNameField: Bool
    /// Called with the chosen pieces (in the order picked) and the name typed.
    let onDone: ([ClothingItem], String) -> Void

    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\ClothingItem.createdAt, order: .reverse)])
    private var items: [ClothingItem]

    @State private var selectedIDs: [UUID] = []
    @State private var categoryFilter: ClothingCategory?
    @State private var searchText = ""
    @State private var name = ""
    @State private var selectionFeedback = 0

    @ScaledMetric(relativeTo: .body) private var cardMinWidth: CGFloat = 104

    init(
        title: String,
        confirmTitle: String,
        excludedIDs: Set<UUID> = [],
        showsNameField: Bool = false,
        onDone: @escaping ([ClothingItem], String) -> Void
    ) {
        self.title = title
        self.confirmTitle = confirmTitle
        self.excludedIDs = excludedIDs
        self.showsNameField = showsNameField
        self.onDone = onDone
    }

    var body: some View {
        NavigationStack {
            content
                .background(Color.hakiBackground)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, prompt: Text("Search your pieces"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(confirmTitle) { finish() }
                            .disabled(selectedIDs.isEmpty)
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if !availableItems.isEmpty {
                        selectionBar
                    }
                }
                .sensoryFeedback(.selection, trigger: selectionFeedback)
        }
    }

    @ViewBuilder
    private var content: some View {
        if availableItems.isEmpty {
            ContentUnavailableView {
                Label(items.isEmpty ? "No pieces yet" : "Nothing left to add", systemImage: "hanger")
            } description: {
                Text(items.isEmpty
                     ? "Add clothes to your wardrobe first, then build outfits from them."
                     : "Every piece in your wardrobe is already on this board.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if showsNameField {
                        nameField
                    }
                    filterChips
                    grid
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Name")
                .font(.subheadline.weight(.semibold))
            TextField("e.g. Friday dinner", text: $name)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .padding(12)
                .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Outfit name")
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                WardrobeChip("All", isSelected: categoryFilter == nil) {
                    categoryFilter = nil
                }
                ForEach(presentCategories) { category in
                    WardrobeChip(category.title, systemImage: category.systemImage, isSelected: categoryFilter == category) {
                        categoryFilter = categoryFilter == category ? nil : category
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var grid: some View {
        let shown = filteredItems
        if shown.isEmpty {
            Text("No pieces match.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: cardMinWidth), spacing: 12)], spacing: 12) {
                ForEach(shown) { item in
                    pickerCell(item)
                }
            }
        }
    }

    private func pickerCell(_ item: ClothingItem) -> some View {
        let order = selectedIDs.firstIndex(of: item.id)
        let isSelected = order != nil
        return Button {
            toggle(item)
        } label: {
            WardrobeItemCard(item: item)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                }
                .overlay(alignment: .topLeading) {
                    OutfitPickerBadge(number: order.map { $0 + 1 })
                        .padding(14)
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectionTitle)
                    .font(.subheadline.weight(.semibold))
                if let hint = selectionHint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button(confirmTitle) {
                finish()
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    // MARK: Derived values

    private var selectionTitle: String {
        selectedIDs.isEmpty ? "Tap pieces to choose them" : "\(WardrobeFormat.pieces(selectedIDs.count)) chosen"
    }

    private var availableItems: [ClothingItem] {
        items.filter { !excludedIDs.contains($0.id) }
    }

    private var presentCategories: [ClothingCategory] {
        let present = Set(availableItems.map(\.category))
        return ClothingCategory.allCases.filter { present.contains($0) }
    }

    private var filteredItems: [ClothingItem] {
        var result = availableItems
        if let categoryFilter {
            result = result.filter { $0.category == categoryFilter }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                item.name.lowercased().contains(query)
                    || item.brand.lowercased().contains(query)
                    || item.category.title.lowercased().contains(query)
                    || item.colors.contains { $0.title.lowercased().contains(query) }
            }
        }
        return result
    }

    private var selectedItems: [ClothingItem] {
        let byID = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return selectedIDs.compactMap { byID[$0] }
    }

    /// What the outfit (with what's already on the board) still needs.
    private var selectionHint: String? {
        guard !selectedIDs.isEmpty || !excludedIDs.isEmpty else { return nil }
        let onBoard = items.filter { excludedIDs.contains($0.id) }.map(\.category)
        let categories = onBoard + selectedItems.map(\.category)
        return OutfitRules.hint(categories) ?? "That's a complete outfit."
    }

    // MARK: Actions

    private func toggle(_ item: ClothingItem) {
        if let index = selectedIDs.firstIndex(of: item.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(item.id)
        }
        selectionFeedback += 1
    }

    private func finish() {
        let chosen = selectedItems
        guard !chosen.isEmpty else { return }
        onDone(chosen, name.trimmingCharacters(in: .whitespacesAndNewlines))
        dismiss()
    }
}

/// A numbered check on a chosen piece, or an empty ring.
private struct OutfitPickerBadge: View {
    let number: Int?

    var body: some View {
        ZStack {
            if let number {
                Circle()
                    .fill(Color.accentColor)
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Color.white)
            } else {
                Circle()
                    .fill(Color.black.opacity(0.12))
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
            }
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true)
    }
}

#Preview("New outfit") {
    OutfitPiecePickerView(title: "New outfit", confirmTitle: "Create", showsNameField: true) { _, _ in }
        .previewEnvironment()
}
