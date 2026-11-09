//
//  OutfitBoardView.swift
//  Haki
//
//  An outfit as a board of its pieces: drag to move, pinch to resize, twist
//  to rotate, tap to select (which brings the piece to the front and shows
//  its remove button). Positions are stored as fractions of the board, so
//  the board looks the same at any size. Leaving the board renders a
//  snapshot for the outfit grids. Pushed from the wardrobe.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct OutfitBoardView: View {
    let outfit: Outfit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPieceID: UUID?
    @State private var showsAddPieces = false
    @State private var showsRename = false
    @State private var showsOccasion = false
    @State private var showsDeleteConfirmation = false
    @State private var nameDraft = ""
    @State private var occasionDraft = ""
    /// Set by "Delete outfit". The outfit is deleted once this screen has gone.
    @State private var deletionRequested = false
    /// The board changed, so its snapshot needs redrawing.
    @State private var hasEdits = false
    @State private var wornFeedback = 0

    /// Width ÷ height of the board.
    static let boardAspectRatio: CGFloat = 3.0 / 4.0

    init(outfit: Outfit) {
        self.outfit = outfit
    }

    var body: some View {
        if isOutfitGone {
            ContentUnavailableView(
                "Outfit Deleted",
                systemImage: "hanger",
                description: Text("This outfit is no longer in your wardrobe.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.hakiBackground)
        } else {
            screen
        }
    }

    private var isOutfitGone: Bool {
        outfit.isDeleted || outfit.modelContext == nil
    }

    private var screen: some View {
        screenWithDialogs
            .sensoryFeedback(.success, trigger: wornFeedback)
            .onDisappear {
                finishOnLeave()
            }
    }

    private var layout: some View {
        VStack(spacing: 12) {
            summaryRow
            if !outfitNotes.isEmpty {
                Text(outfitNotes)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let hint = completenessHint {
                hintBanner(hint)
            }
            board
            bottomBar
        }
        .padding(.horizontal)
        .padding(.bottom, 12)
        .padding(.top, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hakiBackground)
    }

    private var navigatedLayout: some View {
        layout
            .navigationTitle(outfit.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showsAddPieces) {
                OutfitPiecePickerView(
                    title: "Add pieces",
                    confirmTitle: "Add",
                    excludedIDs: Set(outfit.items.map(\.id))
                ) { picked, _ in
                    addPieces(picked)
                }
            }
    }

    private var screenWithDialogs: some View {
        navigatedLayout
            .alert("Rename outfit", isPresented: $showsRename) {
                TextField("Name", text: $nameDraft)
                Button("Save") { rename() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Occasion", isPresented: $showsOccasion) {
                TextField("e.g. Work, Dinner, Weekend", text: $occasionDraft)
                Button("Save") { saveOccasion() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Where or when you'd wear it.")
            }
            .confirmationDialog("Delete this outfit?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete outfit", role: .destructive) {
                    requestDelete()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Its pieces stay in your wardrobe.")
            }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    nameDraft = outfit.name
                    showsRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    occasionDraft = outfit.occasion
                    showsOccasion = true
                } label: {
                    Label("Set occasion", systemImage: "tag")
                }
                Button {
                    markWorn()
                } label: {
                    Label("Wore it today", systemImage: "hanger")
                }
                .disabled(isWornToday)
                Divider()
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete outfit", systemImage: "trash")
                }
            } label: {
                Label("Outfit options", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: Header

    private var isWornToday: Bool {
        WardrobeFormat.isToday(outfit.lastWornAt)
    }

    private var summaryRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if outfit.isAISuggested {
                        Image(systemName: "sparkles")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Suggested by Haki")
                    }
                    Text(occasionText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                Text(wearText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 8)
            Button {
                markWorn()
            } label: {
                Label(isWornToday ? "Worn today" : "Wore it today", systemImage: isWornToday ? "checkmark.circle.fill" : "hanger")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .disabled(isWornToday)
            .accessibilityHint(isWornToday ? "Already counted today" : "Counts a wear of the outfit and every piece in it")
        }
    }

    /// Notes on the outfit (for saved ideas, why the AI put it together).
    private var outfitNotes: String {
        outfit.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var occasionText: String {
        let occasion = outfit.occasion.trimmingCharacters(in: .whitespacesAndNewlines)
        return occasion.isEmpty ? "No occasion set" : occasion
    }

    private var wearText: String {
        let pieces = WardrobeFormat.pieces(visiblePieces.count)
        let worn = WardrobeFormat.timesWorn(outfit.timesWorn)
        guard outfit.lastWornAt != nil else { return "\(pieces) · \(worn)" }
        return "\(pieces) · \(worn) · \(WardrobeFormat.lastWorn(outfit.lastWornAt))"
    }

    private var completenessHint: String? {
        guard !visiblePieces.isEmpty else { return nil }
        let categories = visiblePieces.compactMap { $0.item?.category }
        return OutfitRules.hint(categories)
    }

    private func hintBanner(_ hint: String) -> some View {
        Label("\(hint) to finish the look.", systemImage: "lightbulb")
            .font(.subheadline)
            .foregroundStyle(Color.hakiWarning)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.hakiWarning.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Board

    /// Pieces back to front, without any whose clothing was deleted.
    private var visiblePieces: [OutfitPiece] {
        outfit.orderedPieces.filter { !$0.isDeleted && $0.item != nil }
    }

    private var selectedPiece: OutfitPiece? {
        guard let selectedPieceID else { return nil }
        return visiblePieces.first { $0.id == selectedPieceID }
    }

    private var board: some View {
        GeometryReader { proxy in
            boardContent(size: proxy.size)
        }
        .aspectRatio(Self.boardAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func boardContent(size: CGSize) -> some View {
        ZStack {
            WardrobePalette.board
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) { selectedPieceID = nil }
                }
                .accessibilityHidden(true)
            ForEach(visiblePieces) { piece in
                if let item = piece.item {
                    OutfitBoardPieceView(
                        piece: piece,
                        item: item,
                        boardSize: size,
                        isSelected: selectedPieceID == piece.id,
                        onTap: { tap(piece) },
                        onDragStart: { selectedPieceID = piece.id },
                        onCommit: { commitEdit() },
                        onRemove: { remove(piece) }
                    )
                    .zIndex(Double(piece.zIndex))
                }
            }
            if visiblePieces.isEmpty {
                emptyBoard
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(WardrobePalette.boardEdge, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Outfit board")
    }

    private var emptyBoard: some View {
        VStack(spacing: 12) {
            Image(systemName: "hanger")
                .font(.largeTitle)
                .foregroundStyle(WardrobePalette.boardIcon)
                .accessibilityHidden(true)
            Text("Add pieces from your wardrobe to build this outfit.")
                .font(.subheadline)
                .foregroundStyle(WardrobePalette.boardIcon)
                .multilineTextAlignment(.center)
            Button {
                showsAddPieces = true
            } label: {
                Label("Add pieces", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
    }

    // MARK: Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        if let piece = selectedPiece, let item = piece.item {
            HStack(spacing: 10) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    remove(piece)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                Button("Done") {
                    withAnimation(.snappy) { selectedPieceID = nil }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(12)
            .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            VStack(spacing: 6) {
                Button {
                    showsAddPieces = true
                } label: {
                    Label("Add pieces", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                if !visiblePieces.isEmpty {
                    Text("Drag to move · Pinch to resize · Twist to rotate · Tap to bring forward")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: Actions

    private func tap(_ piece: OutfitPiece) {
        withAnimation(.snappy) {
            selectedPieceID = piece.id
        }
        let top = outfit.pieces.map(\.zIndex).max() ?? 0
        let sharesTop = outfit.pieces.filter { $0.zIndex == top }.count > 1
        if piece.zIndex < top || sharesTop {
            WardrobeStore.bringToFront(piece, in: modelContext)
            hasEdits = true
        }
    }

    private func commitEdit() {
        WardrobeStore.save(in: modelContext)
        hasEdits = true
    }

    private func remove(_ piece: OutfitPiece) {
        if selectedPieceID == piece.id {
            selectedPieceID = nil
        }
        withAnimation(.snappy) {
            WardrobeStore.removePiece(piece, in: modelContext)
        }
        hasEdits = true
    }

    private func addPieces(_ items: [ClothingItem]) {
        guard !items.isEmpty else { return }
        withAnimation(.snappy) {
            for item in items {
                WardrobeStore.addPiece(item, to: outfit, in: modelContext)
            }
        }
        hasEdits = true
    }

    private func markWorn() {
        WardrobeStore.markWorn(outfit, in: modelContext)
        wornFeedback += 1
    }

    private func rename() {
        let trimmed = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        outfit.name = trimmed
        WardrobeStore.save(in: modelContext)
    }

    private func saveOccasion() {
        outfit.occasion = occasionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        WardrobeStore.save(in: modelContext)
    }

    private func requestDelete() {
        deletionRequested = true
        dismiss()
    }

    // MARK: Leaving

    private func finishOnLeave() {
        if deletionRequested {
            deletionRequested = false
            guard !isOutfitGone else { return }
            WardrobeStore.deleteOutfit(outfit, in: modelContext)
            return
        }
        guard !isOutfitGone else { return }
        let pieces = visiblePieces
        if pieces.isEmpty {
            if outfit.previewData != nil {
                outfit.previewData = nil
                WardrobeStore.save(in: modelContext)
            }
        } else if hasEdits || outfit.previewData == nil {
            renderSnapshot(pieces)
        }
        hasEdits = false
    }

    /// Draws the board at 300 × 400 pt, scale 2 (600 × 800 px), for grids.
    private func renderSnapshot(_ pieces: [OutfitPiece]) {
        let size = CGSize(width: 300, height: 300 / Self.boardAspectRatio)
        let renderer = ImageRenderer(content: OutfitBoardSnapshot(pieces: pieces, size: size))
        renderer.scale = 2
        guard let image = renderer.uiImage, let data = image.jpegData(compressionQuality: 0.82) else { return }
        outfit.previewData = data
        WardrobeStore.save(in: modelContext)
    }
}

// MARK: - Pieces

/// One piece on the board, with its own live gesture state. The new
/// position, size or angle is written to the piece when a gesture ends.
private struct OutfitBoardPieceView: View {
    let piece: OutfitPiece
    let item: ClothingItem
    let boardSize: CGSize
    let isSelected: Bool
    let onTap: () -> Void
    let onDragStart: () -> Void
    let onCommit: () -> Void
    let onRemove: () -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var pinchScale: CGFloat = 1
    @State private var twistDegrees: Double = 0
    @State private var isDragging = false

    private static let minWidthFraction = 0.12
    private static let maxWidthFraction = 1.0

    var body: some View {
        accessibleArtwork
            .position(livePosition)
    }

    /// The piece as drawn: sized, outlined when selected, rotated.
    private var styledArtwork: some View {
        OutfitPieceArtwork(item: item)
            .frame(width: displayWidth)
            .padding(6)
            .overlay { selectionOutline }
            .overlay(alignment: .topTrailing) { removeButton }
            .contentShape(Rectangle())
            .rotationEffect(Angle(degrees: piece.rotationDegrees + twistDegrees))
            .scaleEffect(isDragging ? 1.03 : 1)
    }

    private var interactiveArtwork: some View {
        styledArtwork
            .onTapGesture { onTap() }
            .gesture(moveGesture)
            .simultaneousGesture(resizeGesture)
            .simultaneousGesture(rotateGesture)
    }

    /// VoiceOver: one element with actions to move, resize and remove it.
    private var accessibleArtwork: some View {
        interactiveArtwork
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityValue(isSelected ? "Selected" : "")
            .accessibilityHint("Drag to move, pinch to resize. Actions move, resize or remove it.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onTap() }
            .accessibilityAction(named: "Move up") { nudge(dx: 0, dy: -0.05) }
            .accessibilityAction(named: "Move down") { nudge(dx: 0, dy: 0.05) }
            .accessibilityAction(named: "Move left") { nudge(dx: -0.05, dy: 0) }
            .accessibilityAction(named: "Move right") { nudge(dx: 0.05, dy: 0) }
            .accessibilityAction(named: "Make bigger") { resize(by: 1.15) }
            .accessibilityAction(named: "Make smaller") { resize(by: 1 / 1.15) }
            .accessibilityAction(named: "Remove") { onRemove() }
    }

    // MARK: Layout

    private var displayWidth: CGFloat {
        let fraction = min(max(piece.widthFraction * Double(pinchScale), Self.minWidthFraction), Self.maxWidthFraction)
        return max(28, CGFloat(fraction) * boardSize.width)
    }

    private var livePosition: CGPoint {
        let x = CGFloat(piece.centerX) * boardSize.width + dragOffset.width
        let y = CGFloat(piece.centerY) * boardSize.height + dragOffset.height
        return CGPoint(
            x: min(max(x, 0), boardSize.width),
            y: min(max(y, 0), boardSize.height)
        )
    }

    @ViewBuilder
    private var selectionOutline: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
        }
    }

    @ViewBuilder
    private var removeButton: some View {
        if isSelected {
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Color.white, Color.black.opacity(0.75))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 16, y: -16)
            .accessibilityLabel("Remove \(item.name)")
        }
    }

    // MARK: Gestures

    private var moveGesture: some Gesture {
        // Global space: the translation doesn't depend on the piece's own
        // rotation or scale (the board itself is never transformed).
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    onDragStart()
                }
                dragOffset = value.translation
            }
            .onEnded { value in
                commitMove(value.translation)
            }
    }

    private var resizeGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                pinchScale = value.magnification
            }
            .onEnded { value in
                commitResize(value.magnification)
            }
    }

    private var rotateGesture: some Gesture {
        RotateGesture()
            .onChanged { value in
                twistDegrees = value.rotation.degrees
            }
            .onEnded { value in
                commitRotation(value.rotation.degrees)
            }
    }

    // MARK: Writing

    private func commitMove(_ translation: CGSize) {
        isDragging = false
        defer { dragOffset = .zero }
        guard boardSize.width > 0, boardSize.height > 0 else { return }
        let x = piece.centerX + Double(translation.width / boardSize.width)
        let y = piece.centerY + Double(translation.height / boardSize.height)
        piece.centerX = Self.clampCenter(x)
        piece.centerY = Self.clampCenter(y)
        onCommit()
    }

    private func commitResize(_ magnification: CGFloat) {
        defer { pinchScale = 1 }
        let width = piece.widthFraction * Double(magnification)
        piece.widthFraction = min(max(width, Self.minWidthFraction), Self.maxWidthFraction)
        onCommit()
    }

    private func commitRotation(_ degrees: Double) {
        defer { twistDegrees = 0 }
        var angle = (piece.rotationDegrees + degrees).truncatingRemainder(dividingBy: 360)
        if angle > 180 { angle -= 360 }
        if angle < -180 { angle += 360 }
        piece.rotationDegrees = angle
        onCommit()
    }

    private func nudge(dx: Double, dy: Double) {
        piece.centerX = Self.clampCenter(piece.centerX + dx)
        piece.centerY = Self.clampCenter(piece.centerY + dy)
        onCommit()
    }

    private func resize(by factor: Double) {
        piece.widthFraction = min(max(piece.widthFraction * factor, Self.minWidthFraction), Self.maxWidthFraction)
        onCommit()
    }

    private static func clampCenter(_ value: Double) -> Double {
        min(max(value, 0.02), 0.98)
    }
}

// MARK: - Snapshot

/// The board drawn without controls, for `ImageRenderer`.
private struct OutfitBoardSnapshot: View {
    let pieces: [OutfitPiece]
    let size: CGSize

    var body: some View {
        ZStack {
            WardrobePalette.board
            ForEach(pieces) { piece in
                if let item = piece.item {
                    OutfitPieceArtwork(item: item)
                        .frame(width: max(20, CGFloat(piece.widthFraction) * size.width))
                        .padding(6)
                        .rotationEffect(Angle(degrees: piece.rotationDegrees))
                        .position(x: CGFloat(piece.centerX) * size.width, y: CGFloat(piece.centerY) * size.height)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, .light)
    }
}

#Preview {
    NavigationStack {
        OutfitBoardView(outfit: PreviewData.sampleOutfit)
    }
    .previewEnvironment()
}
