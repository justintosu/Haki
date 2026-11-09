//
//  WardrobeView.swift
//  Haki
//
//  The wardrobe: every piece of clothing (filter by type, search, sort by
//  recent or by wears) and every outfit (new outfit from chosen pieces, AI
//  outfit ideas), with a stats row on top: pieces, outfits, the most worn
//  piece and the ones not worn in 90 days. Pushed from the You tab.
//

import Foundation
import SwiftData
import SwiftUI

struct WardrobeView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\ClothingItem.createdAt, order: .reverse)])
    private var items: [ClothingItem]

    @Query(sort: [SortDescriptor(\Outfit.createdAt, order: .reverse)])
    private var outfits: [Outfit]

    @AppStorage("wardrobe.section") private var sectionRaw = WardrobeSection.pieces.rawValue
    @AppStorage("wardrobe.sort") private var sortRaw = WardrobeSort.recent.rawValue

    @State private var categoryFilter: ClothingCategory?
    @State private var showsForgottenOnly = false
    @State private var searchText = ""
    @State private var activeSheet: WardrobeSheet?
    /// Made in the "New outfit" sheet; opened once the sheet has closed.
    @State private var pendingOutfit: Outfit?
    @State private var openedOutfit: Outfit?
    @State private var wornFeedback = 0

    @ScaledMetric(relativeTo: .body) private var cardMinWidth: CGFloat = 150

    init() {}

    var body: some View {
        let overview = WardrobeOverview(items: items)
        ScrollView {
            VStack(spacing: 16) {
                sectionPicker
                statsGrid(overview)
                switch section {
                case .pieces:
                    piecesSection(overview)
                case .outfits:
                    outfitsSection
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .animation(.snappy, value: section)
        }
        .background(Color.hakiBackground)
        .navigationTitle("Wardrobe")
        .searchable(text: $searchText, prompt: Text(section == .pieces ? "Search pieces" : "Search outfits"))
        .toolbar { toolbarContent }
        .sheet(item: $activeSheet, onDismiss: openPendingOutfit) { sheet in
            sheetContent(sheet)
        }
        .navigationDestination(item: $openedOutfit) { outfit in
            OutfitBoardView(outfit: outfit)
        }
        .sensoryFeedback(.success, trigger: wornFeedback)
    }

    private var section: WardrobeSection {
        WardrobeSection(rawValue: sectionRaw) ?? .pieces
    }

    private var sort: WardrobeSort {
        WardrobeSort(rawValue: sortRaw) ?? .recent
    }

    private var sectionBinding: Binding<WardrobeSection> {
        Binding(
            get: { WardrobeSection(rawValue: sectionRaw) ?? .pieces },
            set: { sectionRaw = $0.rawValue }
        )
    }

    private var sortBinding: Binding<WardrobeSort> {
        Binding(
            get: { WardrobeSort(rawValue: sortRaw) ?? .recent },
            set: { sortRaw = $0.rawValue }
        )
    }

    private var sectionPicker: some View {
        Picker("Show", selection: sectionBinding) {
            ForEach(WardrobeSection.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 4)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if section == .pieces {
                Menu {
                    Picker("Sort by", selection: sortBinding) {
                        ForEach(WardrobeSort.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Sort pieces")
                Button {
                    activeSheet = .addPiece
                } label: {
                    Label("Add piece", systemImage: "plus")
                }
                .accessibilityLabel("Add piece")
            } else {
                Button {
                    activeSheet = .newOutfit
                } label: {
                    Label("New outfit", systemImage: "plus")
                }
                .accessibilityLabel("New outfit")
                .disabled(items.isEmpty)
            }
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: WardrobeSheet) -> some View {
        switch sheet {
        case .addPiece:
            ClothingItemEditorView(item: nil)
        case .edit(let item):
            ClothingItemEditorView(item: item)
        case .newOutfit:
            OutfitPiecePickerView(title: "New outfit", confirmTitle: "Create", showsNameField: true) { picked, name in
                pendingOutfit = WardrobeStore.createOutfit(name: name, items: picked, in: modelContext)
            }
        case .ideas:
            OutfitIdeasView()
        }
    }

    private func openPendingOutfit() {
        guard let outfit = pendingOutfit else { return }
        pendingOutfit = nil
        openedOutfit = outfit
    }

    // MARK: Stats

    private func statsGrid(_ overview: WardrobeOverview) -> some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                Button {
                    sectionRaw = WardrobeSection.pieces.rawValue
                } label: {
                    WardrobeStatTile(title: "Pieces", value: "\(items.count)", systemImage: "tshirt", tint: .teal)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows your pieces")
                Button {
                    sectionRaw = WardrobeSection.outfits.rawValue
                } label: {
                    WardrobeStatTile(title: "Outfits", value: "\(outfits.count)", systemImage: "square.grid.2x2", tint: .indigo)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows your outfits")
            }
            GridRow {
                mostWornTile(overview.mostWorn)
                forgottenTile(count: overview.forgottenIDs.count)
            }
        }
    }

    @ViewBuilder
    private func mostWornTile(_ item: ClothingItem?) -> some View {
        if let item {
            NavigationLink {
                ClothingItemDetailView(item: item)
            } label: {
                WardrobeStatTile(title: "Most worn", value: item.name, detail: WardrobeFormat.wears(item.timesWorn), systemImage: "flame", tint: .orange)
            }
            .buttonStyle(.plain)
        } else {
            WardrobeStatTile(title: "Most worn", value: "None yet", detail: "Tap “Wore it today” on a piece", systemImage: "flame", tint: .orange)
        }
    }

    private func forgottenTile(count: Int) -> some View {
        Button {
            sectionRaw = WardrobeSection.pieces.rawValue
            withAnimation(.snappy) {
                showsForgottenOnly = count > 0 ? !showsForgottenOnly : false
                categoryFilter = nil
            }
        } label: {
            WardrobeStatTile(
                title: "Forgotten",
                value: "\(count)",
                detail: "Haven't worn in 90 days",
                systemImage: "clock.arrow.circlepath",
                tint: .pink
            )
            .overlay {
                if showsForgottenOnly {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
        .accessibilityHint(showsForgottenOnly ? "Shows all pieces again" : "Shows only these pieces")
        .accessibilityAddTraits(showsForgottenOnly ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    // MARK: Pieces

    @ViewBuilder
    private func piecesSection(_ overview: WardrobeOverview) -> some View {
        if items.isEmpty {
            emptyWardrobe
        } else {
            let shown = visibleItems(forgottenIDs: overview.forgottenIDs)
            VStack(alignment: .leading, spacing: 12) {
                categoryChips(overview)
                if shown.isEmpty {
                    noMatches
                } else {
                    piecesGrid(shown)
                }
            }
        }
    }

    private var emptyWardrobe: some View {
        ContentUnavailableView {
            Label("Your wardrobe is empty", systemImage: "hanger")
        } description: {
            Text("Photograph a piece of clothing. Haki removes the background on your iPhone and fills in the details for you.")
        } actions: {
            Button {
                activeSheet = .addPiece
            } label: {
                Label("Add a piece", systemImage: "camera.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 24)
    }

    private var noMatches: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No pieces match")
                .font(.headline)
            Button("Clear filters") {
                withAnimation(.snappy) {
                    categoryFilter = nil
                    showsForgottenOnly = false
                    searchText = ""
                }
            }
            .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func categoryChips(_ overview: WardrobeOverview) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                WardrobeChip("All", isSelected: categoryFilter == nil && !showsForgottenOnly) {
                    withAnimation(.snappy) {
                        categoryFilter = nil
                        showsForgottenOnly = false
                    }
                }
                if !overview.forgottenIDs.isEmpty {
                    WardrobeChip("Not worn lately", systemImage: "clock.arrow.circlepath", isSelected: showsForgottenOnly) {
                        withAnimation(.snappy) { showsForgottenOnly.toggle() }
                    }
                }
                ForEach(presentCategories) { category in
                    WardrobeChip(category.title, systemImage: category.systemImage, isSelected: categoryFilter == category) {
                        withAnimation(.snappy) {
                            categoryFilter = categoryFilter == category ? nil : category
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func piecesGrid(_ shown: [ClothingItem]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cardMinWidth), spacing: 12)], spacing: 12) {
            ForEach(shown) { item in
                NavigationLink {
                    ClothingItemDetailView(item: item)
                } label: {
                    WardrobeItemCard(item: item)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        WardrobeStore.markWorn(item, in: modelContext)
                        wornFeedback += 1
                    } label: {
                        Label("Wore it today", systemImage: "hanger")
                    }
                    .disabled(WardrobeFormat.isToday(item.lastWornAt))
                    Button {
                        activeSheet = .edit(item)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                }
            }
        }
    }

    private var presentCategories: [ClothingCategory] {
        let present = Set(items.map(\.category))
        return ClothingCategory.allCases.filter { present.contains($0) }
    }

    private func visibleItems(forgottenIDs: Set<String>) -> [ClothingItem] {
        var result = items
        if let categoryFilter {
            result = result.filter { $0.category == categoryFilter }
        }
        if showsForgottenOnly {
            result = result.filter { forgottenIDs.contains($0.id.uuidString) }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                item.name.lowercased().contains(query)
                    || item.brand.lowercased().contains(query)
                    || item.category.title.lowercased().contains(query)
                    || item.colors.contains { $0.title.lowercased().contains(query) }
                    || item.styles.contains { $0.title.lowercased().contains(query) }
            }
        }
        switch sort {
        case .recent:
            return result
        case .mostWorn:
            return result.sorted { lhs, rhs in
                if lhs.timesWorn != rhs.timesWorn { return lhs.timesWorn > rhs.timesWorn }
                return (lhs.lastWornAt ?? .distantPast) > (rhs.lastWornAt ?? .distantPast)
            }
        case .leastWorn:
            return result.sorted { lhs, rhs in
                if lhs.timesWorn != rhs.timesWorn { return lhs.timesWorn < rhs.timesWorn }
                return (lhs.lastWornAt ?? .distantPast) < (rhs.lastWornAt ?? .distantPast)
            }
        }
    }

    // MARK: Outfits

    private var outfitsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            outfitActions
            if outfits.isEmpty {
                emptyOutfits
            } else {
                let shown = visibleOutfits
                if shown.isEmpty {
                    Text("No outfits match “\(searchText)”.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    outfitsGrid(shown)
                }
            }
        }
    }

    private var outfitActions: some View {
        HStack(spacing: 10) {
            Button {
                activeSheet = .newOutfit
            } label: {
                WardrobeActionTile(title: "New outfit", systemImage: "square.on.square", tint: .indigo)
            }
            .buttonStyle(.plain)
            .disabled(items.isEmpty)
            .accessibilityHint("Choose pieces and arrange them on a board")
            Button {
                activeSheet = .ideas
            } label: {
                WardrobeActionTile(title: "Outfit ideas", systemImage: "sparkles", tint: .accentColor)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Haki's AI suggests outfits from your pieces")
        }
    }

    private var emptyOutfits: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No outfits yet")
                .font(.headline)
            Text(items.isEmpty
                 ? "Add a few pieces first, then put them together here."
                 : "Put pieces together on a board, or ask Haki for ideas.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
    }

    private func outfitsGrid(_ shown: [Outfit]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: cardMinWidth), spacing: 12)], spacing: 12) {
            ForEach(shown) { outfit in
                NavigationLink {
                    OutfitBoardView(outfit: outfit)
                } label: {
                    WardrobeOutfitCard(outfit: outfit)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        WardrobeStore.markWorn(outfit, in: modelContext)
                        wornFeedback += 1
                    } label: {
                        Label("Wore it today", systemImage: "hanger")
                    }
                    .disabled(WardrobeFormat.isToday(outfit.lastWornAt))
                }
            }
        }
    }

    private var visibleOutfits: [Outfit] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return outfits }
        return outfits.filter { outfit in
            outfit.name.lowercased().contains(query)
                || outfit.occasion.lowercased().contains(query)
                || outfit.items.contains { $0.name.lowercased().contains(query) }
        }
    }
}

// MARK: - Model

private enum WardrobeSection: String, CaseIterable, Identifiable {
    case pieces
    case outfits

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pieces: "Pieces"
        case .outfits: "Outfits"
        }
    }
}

private enum WardrobeSort: String, CaseIterable, Identifiable {
    case recent
    case mostWorn
    case leastWorn

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recently added"
        case .mostWorn: "Most worn"
        case .leastWorn: "Least worn"
        }
    }

    var systemImage: String {
        switch self {
        case .recent: "clock"
        case .mostWorn: "flame"
        case .leastWorn: "moon.zzz"
        }
    }
}

private enum WardrobeSheet: Identifiable {
    case addPiece
    case edit(ClothingItem)
    case newOutfit
    case ideas

    var id: String {
        switch self {
        case .addPiece: "addPiece"
        case .edit(let item): "edit-\(item.id.uuidString)"
        case .newOutfit: "newOutfit"
        case .ideas: "ideas"
        }
    }
}

/// Counts worked out once per redraw.
private struct WardrobeOverview {
    let mostWorn: ClothingItem?
    let forgottenIDs: Set<String>

    init(items: [ClothingItem]) {
        let infos = items.map(\.wearInfo)
        let topID = WardrobeStats.mostWorn(infos, limit: 1).first
        mostWorn = topID.flatMap { id in items.first { $0.id.uuidString == id } }
        forgottenIDs = Set(WardrobeStats.forgotten(infos))
    }
}

/// A shortcut with a tinted icon (same shape as the Health tab's).
private struct WardrobeActionTile: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: iconSize, height: iconSize)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

#Preview {
    NavigationStack {
        WardrobeView()
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        WardrobeView()
    }
    .previewEnvironment(empty: true)
}
