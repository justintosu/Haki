//
//  ClothingItemEditorView.swift
//  Haki
//
//  Adds a piece of clothing (take or choose a photo; Haki removes the
//  background on the device and, with "Auto-fill with AI", fills in the
//  details from the photo) or edits one. Every field stays editable before
//  saving. Editing also offers "Delete piece".
//

import Foundation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct ClothingItemEditorView: View {
    /// `nil` adds a new piece.
    let item: ClothingItem?
    /// When set, deleting calls this instead of deleting right away (the
    /// presenting screen deletes the piece once it has gone).
    private let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(HakiAIService.self) private var hakiAI

    @State private var draft: ClothingEditorDraft
    @State private var existingImage: UIImage?

    // Photo
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: ClothingEditorPhoto?
    @State private var photoToken = UUID()
    @State private var usesOriginalPhoto = false
    @State private var isPreparingPhoto = false
    @State private var photoError: String?
    @State private var isShowingCamera = false

    // AI
    @State private var autoFill: Bool
    @State private var tagStatus: ClothingTagStatus = .idle
    @State private var tagTask: Task<Void, Never>?

    @State private var showsDeleteConfirmation = false
    @State private var didDelete = false
    @FocusState private var focusedField: ClothingEditorField?

    @ScaledMetric(relativeTo: .caption) private var swatchMinWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .subheadline) private var chipMinWidth: CGFloat = 104

    init(item: ClothingItem?, onDelete: (() -> Void)? = nil) {
        self.item = item
        self.onDelete = onDelete
        let source: ClothingItem? = Self.isLive(item) ? item : nil
        _draft = State(initialValue: ClothingEditorDraft(item: source))
        _autoFill = State(initialValue: item == nil)
    }

    var body: some View {
        NavigationStack {
            Group {
                if didDelete {
                    Color.clear
                } else {
                    form
                }
            }
            .navigationTitle(item == nil ? "Add piece" : "Edit piece")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .confirmationDialog(deleteTitle, isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete piece", role: .destructive) {
                    deletePiece()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It's removed from your wardrobe and from any outfits it's in. This can't be undone.")
            }
        }
        .interactiveDismissDisabled(isPreparingPhoto || (item == nil && photo != nil))
        .fullScreenCover(isPresented: $isShowingCamera) {
            ClothingCameraPicker(
                onImage: { image in
                    isShowingCamera = false
                    useCameraImage(image)
                },
                onCancel: {
                    isShowingCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPickedPhoto(newItem) }
        }
        .onChange(of: autoFill) { _, isOn in
            if isOn {
                if photo != nil, tagStatus != .filled { startTagging() }
            } else {
                cancelTagging()
            }
        }
        .onAppear(perform: loadExistingImage)
        .onDisappear {
            tagTask?.cancel()
        }
    }

    private var form: some View {
        Form {
            photoSection
            if item == nil || photo != nil {
                autoFillSection
            }
            detailsSection
            colorsSection
            seasonsSection
            stylesSection
            feelSection
            priceAndNotesSection
            if item != nil {
                deleteSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(item == nil ? "Add" : "Save") { save() }
                .disabled(!canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
        }
    }

    // MARK: Photo

    private var photoSection: some View {
        Section {
            ClothingEditorPhotoPreview(
                image: previewImage,
                isCutout: previewIsCutout,
                category: draft.category,
                colors: draft.colors,
                isWorking: isPreparingPhoto
            )
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            if ClothingCameraPicker.isAvailable {
                Button {
                    isShowingCamera = true
                } label: {
                    Label(hasAnyPhoto ? "Take another photo" : "Take photo", systemImage: "camera")
                }
                .disabled(isPreparingPhoto)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(hasAnyPhoto ? "Choose another photo" : "Choose photo", systemImage: "photo.on.rectangle")
            }
            .disabled(isPreparingPhoto)

            if photo?.cutoutImage != nil {
                Toggle("Use original photo", isOn: $usesOriginalPhoto.animation(.snappy))
            }
            if let photoError {
                Label(photoError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.hakiWarning)
            }
        } footer: {
            Text(photoFooter)
        }
    }

    private var hasAnyPhoto: Bool {
        photo != nil || existingImage != nil
    }

    private var previewImage: UIImage? {
        if let photo {
            if !usesOriginalPhoto, let cutout = photo.cutoutImage { return cutout }
            return photo.originalImage
        }
        return existingImage
    }

    private var previewIsCutout: Bool {
        if let photo { return !usesOriginalPhoto && photo.cutoutImage != nil }
        return draft.existingIsCutout
    }

    private var photoFooter: String {
        if isPreparingPhoto {
            return "Removing the background on your iPhone…"
        }
        if let photo {
            if photo.cutoutImage == nil {
                return "Haki couldn't separate the piece from its background, so it'll use the photo as taken. A plain, well-lit background helps."
            }
            return usesOriginalPhoto
                ? "Using the photo as taken."
                : "Background removed on your iPhone."
        }
        if existingImage != nil {
            return "Choose a new photo to replace this one."
        }
        return "Lay the piece flat or hang it against a plain background. Haki removes the background on your iPhone."
    }

    // MARK: Auto-fill

    private var autoFillSection: some View {
        Section {
            Toggle(isOn: $autoFill) {
                Label("Auto-fill with AI", systemImage: "sparkles")
            }
            autoFillStatus
        } footer: {
            Text("Haki's AI looks at the photo and fills in the name, type, colors, seasons and style. Check them before saving.")
        }
    }

    @ViewBuilder
    private var autoFillStatus: some View {
        switch tagStatus {
        case .idle:
            // With no photo yet the section footer already explains
            // auto-fill, so only offer the manual button once there's a photo.
            if photo != nil {
                Button {
                    startTagging()
                } label: {
                    Label("Fill in from the photo", systemImage: "wand.and.stars")
                }
            }
        case .working:
            HStack(spacing: 10) {
                ProgressView()
                Text("Reading your photo…")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Stop") {
                    cancelTagging()
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Stop reading the photo")
            }
        case .filled:
            Label("Filled in by Haki's AI. Check the details below.", systemImage: "checkmark.circle.fill")
                .font(.subheadline)
                .foregroundStyle(Color.hakiPositive)
            Button {
                startTagging()
            } label: {
                Label("Fill in again", systemImage: "arrow.clockwise")
            }
        case .notClothing:
            Label("This doesn't look like clothing. Fill in the details yourself, or try another photo.", systemImage: "questionmark.circle")
                .font(.subheadline)
                .foregroundStyle(Color.hakiWarning)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline)
                .foregroundStyle(Color.hakiWarning)
            Button {
                startTagging()
            } label: {
                Label("Try again", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: Details

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name, e.g. Navy crew-neck sweater", text: $draft.name)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .brand }
            Picker("Type", selection: $draft.category) {
                ForEach(ClothingCategory.allCases) { category in
                    Label(category.singularTitle, systemImage: category.systemImage)
                        .tag(category)
                }
            }
            TextField("Brand (optional)", text: $draft.brand)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focusedField, equals: .brand)
                .onSubmit { focusedField = .pattern }
            TextField("Pattern, e.g. solid, striped, plaid", text: $draft.pattern)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused($focusedField, equals: .pattern)
        }
    }

    private var colorsSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: swatchMinWidth), spacing: 6)], spacing: 12) {
                ForEach(ClothingColor.allCases) { color in
                    ClothingColorSwatch(color: color, isSelected: draft.colors.contains(color)) {
                        draft.toggle(color)
                    }
                }
            }
            .padding(.vertical, 6)
        } header: {
            Text("Colors")
        } footer: {
            Text(colorsFooter)
        }
    }

    private var colorsFooter: String {
        if draft.colors.isEmpty {
            return "Pick every color you see, main color first."
        }
        return "Main color first: \(WardrobeFormat.colors(draft.colors))."
    }

    private var chipColumns: [GridItem] {
        [GridItem(.adaptive(minimum: chipMinWidth), spacing: 8)]
    }

    private var seasonsSection: some View {
        Section {
            LazyVGrid(columns: chipColumns, spacing: 8) {
                ForEach(ClothingSeason.allCases) { season in
                    WardrobeChip(season.title, isSelected: draft.seasons.contains(season), fillsWidth: true) {
                        draft.toggle(season)
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Seasons")
        } footer: {
            Text("Leave them all off if it works any time of year.")
        }
    }

    private var stylesSection: some View {
        Section("Style") {
            LazyVGrid(columns: chipColumns, spacing: 8) {
                ForEach(ClothingStyle.allCases) { style in
                    WardrobeChip(style.title, isSelected: draft.styles.contains(style), fillsWidth: true) {
                        draft.toggle(style)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var feelSection: some View {
        Section {
            ClothingLevelStepper(title: "Formality", value: $draft.formality) { level in
                WardrobeFormat.formality(level)
            }
            ClothingLevelStepper(title: "Warmth", value: $draft.warmth) { level in
                WardrobeFormat.warmth(level)
            }
        } header: {
            Text("Formality and warmth")
        } footer: {
            Text("Outfit ideas use these to match the occasion and the weather.")
        }
    }

    private var priceAndNotesSection: some View {
        Section {
            HStack(spacing: 12) {
                Text("Price")
                Spacer(minLength: 12)
                TextField(Money.format(0), text: $draft.priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focusedField, equals: .price)
                    .accessibilityLabel("Price")
            }
            TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                .lineLimit(2...6)
                .focused($focusedField, equals: .notes)
        } header: {
            Text("Price and notes")
        } footer: {
            if draft.isPriceValid {
                Text("Optional. With a price, Haki works out what each wear costs you.")
            } else {
                Text("Enter a price greater than zero, like \(Money.format(4_999)).")
                    .foregroundStyle(Color.hakiNegative)
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("Delete piece", systemImage: "trash")
            }
        }
    }

    private var deleteTitle: String {
        let name = draft.trimmedName
        return name.isEmpty ? "Delete this piece?" : "Delete “\(name)”?"
    }

    // MARK: Loading photos

    private func loadExistingImage() {
        guard existingImage == nil, let item, Self.isLive(item) else { return }
        existingImage = WardrobeImageCache.fullImage(for: item)
    }

    private func loadPickedPhoto(_ pickerItem: PhotosPickerItem) async {
        let token = beginPhotoLoad()
        do {
            let data = try await pickerItem.loadTransferable(type: Data.self)
            await finishPhotoLoad(data, token: token)
        } catch {
            guard token == photoToken else { return }
            isPreparingPhoto = false
            if !Backend.isCancellation(error) {
                photoError = "Couldn't load that photo. Try another one."
            }
        }
    }

    private func useCameraImage(_ image: UIImage) {
        photoItem = nil
        let token = beginPhotoLoad()
        Task {
            // A full-resolution camera photo takes a moment to encode; keep it off the main thread.
            let data = await Task.detached(priority: .userInitiated) {
                image.jpegData(compressionQuality: 0.9)
            }.value
            await finishPhotoLoad(data, token: token)
        }
    }

    /// Starts preparing a new photo; the returned token tells a stale load
    /// (replaced by a newer photo) to stop.
    private func beginPhotoLoad() -> UUID {
        let token = UUID()
        photoToken = token
        photoError = nil
        isPreparingPhoto = true
        cancelTagging()
        return token
    }

    private func finishPhotoLoad(_ data: Data?, token: UUID) async {
        guard token == photoToken else { return }
        guard let data else {
            isPreparingPhoto = false
            photoError = "Couldn't read that photo. Try another one."
            return
        }
        let prepared = await WardrobePhotoProcessor.prepare(data)
        guard token == photoToken else { return }
        isPreparingPhoto = false
        guard let prepared, let editorPhoto = ClothingEditorPhoto(prepared: prepared) else {
            photoError = "That file isn't a photo Haki can use."
            return
        }
        withAnimation(.snappy) {
            photo = editorPhoto
            usesOriginalPhoto = false
        }
        UIAccessibility.post(
            notification: .announcement,
            argument: editorPhoto.cutoutImage == nil ? "Photo added" : "Photo added, background removed"
        )
        if autoFill {
            startTagging()
        } else {
            tagStatus = .idle
        }
    }

    // MARK: Auto-fill

    private func startTagging() {
        guard let jpeg = photo?.prepared.taggingJPEG else { return }
        tagTask?.cancel()
        tagStatus = .working
        tagTask = Task {
            do {
                let tags = try await hakiAI.tagClothing(photoJPEG: jpeg)
                guard !Task.isCancelled else { return }
                applyTags(tags)
            } catch {
                guard !Task.isCancelled else { return }
                if Backend.isCancellation(error) {
                    tagStatus = .idle
                } else {
                    tagStatus = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func cancelTagging() {
        tagTask?.cancel()
        tagTask = nil
        if tagStatus == .working {
            tagStatus = .idle
        }
    }

    private func applyTags(_ tags: ClothingTags) {
        guard tags.isClothing else {
            tagStatus = .notClothing
            return
        }
        withAnimation(.snappy) {
            draft.apply(tags)
        }
        tagStatus = .filled
        UIAccessibility.post(notification: .announcement, argument: "Details filled in. Check them before saving.")
    }

    // MARK: Saving

    private var canSave: Bool {
        guard !didDelete, !isPreparingPhoto, draft.isPriceValid else { return false }
        if item == nil {
            return photo != nil || !draft.trimmedName.isEmpty
        }
        return true
    }

    /// The image to store: the cut-out unless "Use original photo" is on.
    private var chosenPhoto: ClothingEditorPhotoChoice? {
        guard let prepared = photo?.prepared else { return nil }
        if !usesOriginalPhoto, let cutout = prepared.cutoutPNG, let thumbnail = prepared.cutoutThumbnailPNG {
            return ClothingEditorPhotoChoice(imageData: cutout, thumbnailData: thumbnail, isCutout: true)
        }
        return ClothingEditorPhotoChoice(
            imageData: prepared.originalJPEG,
            thumbnailData: prepared.originalThumbnailJPEG,
            isCutout: false
        )
    }

    private func save() {
        guard canSave else { return }
        tagTask?.cancel()
        let choice = chosenPhoto
        let values = draft
        if let item {
            guard Self.isLive(item) else {
                dismiss()
                return
            }
            values.write(to: item)
            if let choice {
                Self.clearOutfitSnapshots(showing: item)
                item.imageData = choice.imageData
                item.thumbnailData = choice.thumbnailData
                item.isCutout = choice.isCutout
            }
            WardrobeStore.save(in: modelContext)
        } else {
            let newItem = WardrobeStore.addItem(
                name: values.trimmedName,
                category: values.category,
                colors: values.colors,
                pattern: values.trimmedPattern,
                seasons: values.orderedSeasons,
                styles: values.orderedStyles,
                formality: values.formality,
                warmth: values.warmth,
                brand: values.trimmedBrand,
                priceCents: values.priceCents,
                imageData: choice?.imageData,
                thumbnailData: choice?.thumbnailData,
                isCutout: choice?.isCutout ?? false,
                in: modelContext
            )
            let notes = values.trimmedNotes
            if !notes.isEmpty {
                newItem.notes = notes
                WardrobeStore.save(in: modelContext)
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func deletePiece() {
        guard let item else { return }
        tagTask?.cancel()
        didDelete = true
        if let onDelete {
            onDelete()
        } else if Self.isLive(item) {
            Self.clearOutfitSnapshots(showing: item)
            WardrobeStore.deleteItem(item, in: modelContext)
        }
        dismiss()
    }

    /// Outfit pictures that show this piece are redrawn when their boards are
    /// next opened (until then the outfit shows a collage of its pieces).
    private static func clearOutfitSnapshots(showing item: ClothingItem) {
        for piece in item.pieces where !piece.isDeleted {
            piece.outfit?.previewData = nil
        }
    }

    /// Whether an item can still be read (it exists and hasn't been deleted).
    private static func isLive(_ item: ClothingItem?) -> Bool {
        guard let item else { return false }
        return !item.isDeleted && item.modelContext != nil
    }
}

// MARK: - Model

private enum ClothingEditorField: Hashable {
    case name
    case brand
    case pattern
    case price
    case notes
}

private enum ClothingTagStatus: Equatable {
    case idle
    case working
    case filled
    case notClothing
    case failed(String)
}

private struct ClothingEditorPhotoChoice {
    let imageData: Data
    let thumbnailData: Data
    let isCutout: Bool
}

/// A prepared photo plus its decoded images (decoded once, not per redraw).
private struct ClothingEditorPhoto {
    let prepared: WardrobePreparedPhoto
    let originalImage: UIImage
    let cutoutImage: UIImage?

    init?(prepared: WardrobePreparedPhoto) {
        guard let original = UIImage(data: prepared.originalJPEG) else { return nil }
        self.prepared = prepared
        self.originalImage = original
        if let cutoutData = prepared.cutoutPNG {
            self.cutoutImage = UIImage(data: cutoutData)
        } else {
            self.cutoutImage = nil
        }
    }
}

/// The form's values, kept apart from the model until "Save".
private struct ClothingEditorDraft {
    var name = ""
    var category: ClothingCategory = .top
    /// In the order picked (main color first).
    var colors: [ClothingColor] = []
    var pattern = ""
    var seasons: [ClothingSeason] = []
    var styles: [ClothingStyle] = []
    var formality = 2
    var warmth = 3
    var brand = ""
    var priceText = ""
    var notes = ""
    /// Whether the saved photo (if any) is a cut-out.
    var existingIsCutout = false
    /// The last name the AI filled in, so a second fill can replace it but
    /// never a name the person typed.
    var lastSuggestedName = ""

    init(item: ClothingItem?) {
        guard let item else { return }
        name = item.name
        category = item.category
        colors = item.colors
        pattern = item.pattern
        seasons = item.seasons
        styles = item.styles
        formality = min(5, max(1, item.formality))
        warmth = min(5, max(1, item.warmth))
        brand = item.brand
        priceText = item.priceCents.map { Money.editableText(fromCents: $0) } ?? ""
        notes = item.notes
        existingIsCutout = item.isCutout
    }

    var trimmedName: String { Self.trim(name) }
    var trimmedPattern: String { Self.trim(pattern) }
    var trimmedBrand: String { Self.trim(brand) }
    var trimmedNotes: String { Self.trim(notes) }

    var orderedSeasons: [ClothingSeason] {
        ClothingSeason.allCases.filter { seasons.contains($0) }
    }

    var orderedStyles: [ClothingStyle] {
        ClothingStyle.allCases.filter { styles.contains($0) }
    }

    var priceCents: Int? {
        let separator = Character(Locale.current.decimalSeparator ?? ".")
        guard let cents = Money.parseCents(priceText, decimalSeparator: separator), cents > 0 else { return nil }
        return cents
    }

    var isPriceValid: Bool {
        Self.trim(priceText).isEmpty || priceCents != nil
    }

    mutating func toggle(_ color: ClothingColor) {
        if let index = colors.firstIndex(of: color) {
            colors.remove(at: index)
        } else {
            colors.append(color)
        }
    }

    mutating func toggle(_ season: ClothingSeason) {
        if let index = seasons.firstIndex(of: season) {
            seasons.remove(at: index)
        } else {
            seasons.append(season)
        }
    }

    mutating func toggle(_ style: ClothingStyle) {
        if let index = styles.firstIndex(of: style) {
            styles.remove(at: index)
        } else {
            styles.append(style)
        }
    }

    /// Fills the form from AI tags, the way `WardrobeStore.apply` does, but
    /// keeps a name the person typed.
    mutating func apply(_ tags: ClothingTags) {
        let suggestedName = Self.trim(tags.name)
        if !suggestedName.isEmpty && (trimmedName.isEmpty || name == lastSuggestedName) {
            name = suggestedName
            lastSuggestedName = suggestedName
        }
        if tags.category != .other { category = tags.category }
        if !tags.colors.isEmpty { colors = tags.colors }
        if !tags.pattern.isEmpty { pattern = tags.pattern }
        if !tags.seasons.isEmpty { seasons = tags.seasons }
        if !tags.styles.isEmpty { styles = tags.styles }
        formality = min(5, max(1, tags.formality))
        warmth = min(5, max(1, tags.warmth))
    }

    /// Writes the fields to an existing item (the photo is handled separately).
    func write(to item: ClothingItem) {
        item.name = trimmedName.isEmpty ? category.singularTitle : trimmedName
        item.category = category
        item.colors = colors
        item.pattern = trimmedPattern
        item.seasons = orderedSeasons
        item.styles = orderedStyles
        item.formality = formality
        item.warmth = warmth
        item.brand = trimmedBrand
        item.priceCents = priceCents
        item.notes = trimmedNotes
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Subviews

/// The photo (or the category icon) on the studio backdrop.
private struct ClothingEditorPhotoPreview: View {
    let image: UIImage?
    let isCutout: Bool
    let category: ClothingCategory
    let colors: [ClothingColor]
    let isWorking: Bool

    var body: some View {
        WardrobePalette.studio
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .overlay { artwork }
            .overlay { progress }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var artwork: some View {
        if let image {
            if isCutout {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(16)
                    .shadow(color: Color.black.opacity(0.16), radius: 8, x: 0, y: 5)
            } else {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        } else {
            VStack(spacing: 10) {
                WardrobeCategoryIcon(category: category, colors: colors)
                    .frame(width: 72, height: 72)
                Text("No photo yet")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var progress: some View {
        if isWorking {
            ZStack {
                Color.black.opacity(0.25)
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.white)
                    Text("Removing the background…")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                }
                .padding()
            }
        }
    }

    private var accessibilityText: String {
        if isWorking { return "Preparing the photo" }
        guard image != nil else { return "No photo yet" }
        return isCutout ? "Photo of the piece, background removed" : "Photo of the piece"
    }
}

/// A color to tap on or off, with its name under it.
private struct ClothingColorSwatch: View {
    let color: ClothingColor
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                swatch
                    .frame(width: 34, height: 34)
                    .padding(3)
                    .overlay {
                        if isSelected {
                            Circle()
                                .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        }
                    }
                Text(color.title)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(color.title)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    @ViewBuilder
    private var swatch: some View {
        ZStack {
            if color == .multicolor {
                Circle()
                    .fill(AngularGradient(gradient: Gradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .red]), center: .center))
            } else {
                Circle()
                    .fill(Color(hex: color.hex))
            }
            Circle()
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(WardrobePalette.paleColors.contains(color) ? Color.black : Color.white)
                    .accessibilityHidden(true)
            }
        }
    }
}

/// A 1–5 stepper with dots and a word for the level.
private struct ClothingLevelStepper: View {
    let title: String
    @Binding var value: Int
    let describe: (Int) -> String

    init(title: String, value: Binding<Int>, describe: @escaping (Int) -> String) {
        self.title = title
        self._value = value
        self.describe = describe
    }

    var body: some View {
        Stepper(value: $value, in: 1...5) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                HStack(spacing: 8) {
                    dots
                    Text(describe(value))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityValue("\(describe(value)), \(value) of 5")
    }

    private var dots: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { level in
                Circle()
                    .fill(level <= value ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview("Add") {
    ClothingItemEditorView(item: nil)
        .previewEnvironment()
}

#Preview("Edit") {
    ClothingItemEditorView(item: PreviewData.sampleClothingItem)
        .previewEnvironment()
}
