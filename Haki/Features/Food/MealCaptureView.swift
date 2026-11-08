//
//  MealCaptureView.swift
//  Haki
//
//  Snap a meal: take or choose a photo and/or describe it, Haki's AI
//  estimates each item's calories and macros, and the person reviews and
//  adjusts everything before it's logged. "Enter it myself instead" swaps
//  to the manual form.
//

import Foundation
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MealCaptureView: View {
    let mealType: MealType?
    let eatenAt: Date?

    init(mealType: MealType? = nil, eatenAt: Date? = nil) {
        self.mealType = mealType
        self.eatenAt = eatenAt
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(FoodAIService.self) private var foodAI
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var step: MealCaptureStep = .compose
    @State private var isManual = false

    // Step 1
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: MealCapturePhoto?
    @State private var isPreparingPhoto = false
    @State private var photoError: String?
    @State private var isShowingCamera = false
    @State private var descriptionText = ""
    @State private var isEstimating = false
    @State private var estimateTask: Task<Void, Never>?
    @State private var errorMessage: String?

    // Step 2
    @State private var draft = MealReviewDraft()

    private static let descriptionLimit = 600

    var body: some View {
        NavigationStack {
            content
        }
        .interactiveDismissDisabled(isEstimating || (step == .review && !isManual))
        .fullScreenCover(isPresented: $isShowingCamera) {
            MealCameraPicker(
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
        .onChange(of: descriptionText) { _, newValue in
            if newValue.count > Self.descriptionLimit {
                descriptionText = String(newValue.prefix(Self.descriptionLimit))
            }
        }
        .onDisappear {
            estimateTask?.cancel()
        }
    }

    @ViewBuilder
    private var content: some View {
        if isManual {
            FoodEntryForm(
                entry: nil,
                mealType: mealType,
                eatenAt: eatenAt,
                prefillName: manualPrefillName,
                photoData: photo?.thumbnailJPEG
            )
        } else {
            switch step {
            case .compose:
                composeStep
            case .review:
                reviewStep
            }
        }
    }

    // MARK: Step 1: photo and description

    private var composeStep: some View {
        ScrollView {
            VStack(spacing: 16) {
                photoCard
                descriptionCard
                if let errorMessage {
                    errorCard(errorMessage)
                }
                estimateButton
                Button("Enter it myself instead") {
                    switchToManual()
                }
                .font(.subheadline.weight(.medium))
                .padding(.top, 4)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Snap a meal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .overlay {
            if isEstimating {
                MealEstimatingOverlay(image: photo?.image, onCancel: cancelEstimate)
            }
        }
    }

    private var photoCard: some View {
        VStack(spacing: 14) {
            photoPreview
            photoButtons
            if let photoError {
                Label(photoError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Color.hakiWarning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .hakiCard()
    }

    @ViewBuilder
    private var photoPreview: some View {
        if let photo {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .overlay {
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    Button {
                        removePhoto()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(Color.black.opacity(0.55), in: Circle())
                            .padding(8)
                    }
                    .accessibilityLabel("Remove photo")
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Meal photo")
        } else {
            MealPhotoPlaceholder(isPreparing: isPreparingPhoto)
        }
    }

    private var photoButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if MealCameraPicker.isAvailable {
                Button {
                    isShowingCamera = true
                } label: {
                    Label("Take photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(photo == nil ? "Choose photo" : "Choose another", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
        .disabled(isPreparingPhoto || isEstimating)
    }

    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(photo == nil ? "Describe what you ate" : "Add details (optional)")
                .font(.headline)
            TextField("e.g. 2 eggs, toast with butter, black coffee", text: $descriptionText, axis: .vertical)
                .lineLimit(3...6)
                .padding(12)
                .background(Color.hakiBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityLabel("Meal description")
            HStack(alignment: .firstTextBaseline) {
                Text("Sizes, sauces and drinks make the estimate closer.")
                Spacer(minLength: 8)
                Text("\(descriptionText.count)/\(Self.descriptionLimit)")
                    .monospacedDigit()
                    .accessibilityLabel("\(descriptionText.count) of \(Self.descriptionLimit) characters")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .hakiCard()
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.hakiWarning)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") {
                    startEstimate()
                }
                .font(.subheadline.weight(.semibold))
                .disabled(!canEstimate)
            }
            Spacer(minLength: 0)
        }
        .hakiCard()
    }

    private var estimateButton: some View {
        VStack(spacing: 8) {
            Button {
                startEstimate()
            } label: {
                Label("Estimate calories & protein", systemImage: "sparkles")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canEstimate)
            if !hasInput {
                Text("Add a photo or a description to get an estimate.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: Step 2: review

    @ViewBuilder
    private var reviewStep: some View {
        if draft.isFood {
            MealReviewForm(
                draft: $draft,
                image: photo?.image,
                onBack: { withAnimation(.snappy) { step = .compose } },
                onSave: save,
                onManual: switchToManual
            )
        } else {
            MealNotFoodView(
                notes: draft.notes,
                onRetake: retake,
                onManual: switchToManual,
                onCancel: { dismiss() }
            )
        }
    }

    // MARK: Derived values

    private var trimmedDescription: String {
        descriptionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasInput: Bool {
        photo != nil || !trimmedDescription.isEmpty
    }

    private var canEstimate: Bool {
        hasInput && !isPreparingPhoto && !isEstimating
    }

    /// A starting name for the manual form: the estimate's name when coming
    /// from the review, otherwise what was typed.
    private var manualPrefillName: String {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if step == .review, draft.isFood, !title.isEmpty {
            return title
        }
        let text = trimmedDescription
        guard !text.isEmpty else { return "" }
        return String(text.prefix(80))
    }

    // MARK: Photos

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        photoError = nil
        isPreparingPhoto = true
        defer { isPreparingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                photoError = "Couldn't read that photo. Try another one."
                return
            }
            let prepared = await MealCapturePhoto.make(from: data)
            // Replaced or removed while it was being prepared.
            guard photoItem == item else { return }
            guard let prepared else {
                photoError = "That file isn't a photo Haki can use."
                return
            }
            withAnimation(.snappy) { photo = prepared }
            errorMessage = nil
        } catch {
            if !Backend.isCancellation(error) {
                photoError = "Couldn't load that photo. Try another one."
            }
        }
    }

    private func useCameraImage(_ image: UIImage) {
        photoItem = nil
        photoError = nil
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            photoError = "Couldn't use that photo. Try again."
            return
        }
        isPreparingPhoto = true
        Task {
            let prepared = await MealCapturePhoto.make(from: data)
            isPreparingPhoto = false
            // A photo chosen from the library in the meantime wins.
            guard photoItem == nil else { return }
            guard let prepared else {
                photoError = "Couldn't use that photo. Try again."
                return
            }
            withAnimation(.snappy) { photo = prepared }
            errorMessage = nil
        }
    }

    private func removePhoto() {
        withAnimation(.snappy) {
            photo = nil
            photoItem = nil
        }
        photoError = nil
    }

    // MARK: Estimate

    private func startEstimate() {
        guard canEstimate else { return }
        estimateTask?.cancel()
        errorMessage = nil
        isEstimating = true
        let photoJPEG = photo?.uploadJPEG
        let note: String? = trimmedDescription.isEmpty ? nil : trimmedDescription
        UIAccessibility.post(notification: .announcement, argument: "Looking at your meal")
        estimateTask = Task {
            do {
                let estimate = try await foodAI.analyzeMeal(photoJPEG: photoJPEG, description: note)
                guard !Task.isCancelled else { return }
                isEstimating = false
                showReview(estimate)
            } catch {
                guard !Task.isCancelled else { return }
                isEstimating = false
                if !Backend.isCancellation(error) {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func cancelEstimate() {
        estimateTask?.cancel()
        estimateTask = nil
        isEstimating = false
    }

    private func showReview(_ estimate: MealEstimate) {
        let time = eatenAt ?? .now
        draft = MealReviewDraft(
            estimate: estimate,
            mealType: mealType ?? MealType.suggested(for: time),
            eatenAt: time
        )
        withAnimation(.snappy) { step = .review }
    }

    private func retake() {
        removePhoto()
        withAnimation(.snappy) { step = .compose }
    }

    private func switchToManual() {
        cancelEstimate()
        withAnimation(.snappy) { isManual = true }
    }

    private func save() {
        let estimate = draft.makeEstimate()
        guard !estimate.items.isEmpty else { return }
        FoodStore.add(
            estimate: estimate,
            mealType: draft.mealType,
            eatenAt: draft.eatenAt,
            source: photo == nil ? .aiText : .aiPhoto,
            photoData: photo?.thumbnailJPEG,
            in: modelContext
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Model

private enum MealCaptureStep {
    case compose
    case review
}

/// A picked or taken photo, prepared twice: for the AI (≤ 1280 px) and for
/// the food log (≤ 600 px). Neither keeps the original's metadata.
private struct MealCapturePhoto {
    let uploadJPEG: Data
    let thumbnailJPEG: Data
    let image: UIImage

    static func make(from data: Data) async -> MealCapturePhoto? {
        guard let upload = await ImageUpload.makeJPEG(from: data, maxDimension: 1280, quality: 0.75) else { return nil }
        guard let thumbnail = await ImageUpload.makeJPEG(from: upload, maxDimension: 600, quality: 0.7) else { return nil }
        guard let image = UIImage(data: upload) else { return nil }
        return MealCapturePhoto(uploadJPEG: upload, thumbnailJPEG: thumbnail, image: image)
    }
}

/// One item of the estimate being reviewed. A class, so rows bind to it
/// directly and removing an item never leaves a row bound to a stale index.
@Observable
private final class MealDraftItem: Identifiable {
    let id = UUID()
    var name: String
    var portion: String
    var caloriesText: String
    var proteinText: String
    var carbsText: String
    var fatText: String
    /// Kept from the estimate (not edited here).
    let grams: Double
    let fiberG: Double

    init(name: String = "", portion: String = "", calories: String = "", protein: String = "", carbs: String = "", fat: String = "", grams: Double = 0, fiberG: Double = 0) {
        self.name = name
        self.portion = portion
        self.caloriesText = calories
        self.proteinText = protein
        self.carbsText = carbs
        self.fatText = fat
        self.grams = grams
        self.fiberG = fiberG
    }

    convenience init(item: MealEstimateItem) {
        self.init(
            name: item.name,
            portion: item.portion,
            calories: FoodFormat.fieldText(item.calories),
            protein: FoodFormat.fieldText(item.proteinG),
            carbs: FoodFormat.fieldText(item.carbsG),
            fat: FoodFormat.fieldText(item.fatG),
            grams: item.grams,
            fiberG: item.fiberG
        )
    }

    var macros: Macros {
        Macros(
            calories: FoodFormat.parse(caloriesText) ?? 0,
            proteinG: FoodFormat.parse(proteinText) ?? 0,
            carbsG: FoodFormat.parse(carbsText) ?? 0,
            fatG: FoodFormat.parse(fatText) ?? 0,
            fiberG: fiberG
        )
    }

    /// Nil for an untouched blank item.
    var estimateItem: MealEstimateItem? {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = macros
        guard !cleanName.isEmpty || values.calories > 0 else { return nil }
        return MealEstimateItem(
            name: cleanName.isEmpty ? "Item" : cleanName,
            portion: portion.trimmingCharacters(in: .whitespacesAndNewlines),
            grams: grams,
            calories: values.calories,
            proteinG: values.proteinG,
            carbsG: values.carbsG,
            fatG: values.fatG,
            fiberG: values.fiberG
        )
    }
}

/// The estimate as the person edits it.
private struct MealReviewDraft {
    var isFood = true
    var title = ""
    var items: [MealDraftItem] = []
    var confidence: EstimateConfidence = .medium
    var notes = ""
    var mealType: MealType = .snack
    var eatenAt = Date.now

    init() {}

    init(estimate: MealEstimate, mealType: MealType, eatenAt: Date) {
        isFood = estimate.isFood
        title = estimate.title
        items = estimate.items.map { MealDraftItem(item: $0) }
        confidence = estimate.confidence
        notes = estimate.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        self.mealType = mealType
        self.eatenAt = eatenAt
    }

    var totals: Macros {
        Macros.total(items.map(\.macros))
    }

    func makeEstimate() -> MealEstimate {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return MealEstimate(
            isFood: true,
            title: cleanTitle.isEmpty ? "Meal" : cleanTitle,
            items: items.compactMap { $0.estimateItem },
            confidence: confidence,
            notes: notes
        )
    }
}

private enum MealReviewFocus: Hashable {
    case title
    case name(UUID)
    case portion(UUID)
    case calories(UUID)
    case protein(UUID)
    case carbs(UUID)
    case fat(UUID)
}

// MARK: - Step 1 pieces

private struct MealPhotoPlaceholder: View {
    let isPreparing: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64

    var body: some View {
        VStack(spacing: 10) {
            if isPreparing {
                ProgressView()
                    .controlSize(.large)
                    .frame(width: iconSize, height: iconSize)
                Text("Preparing photo…")
                    .font(.headline)
            } else {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: iconSize * 0.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: iconSize, height: iconSize)
                    .background(Color.accentColor.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)
                Text("Snap your meal")
                    .font(.headline)
                Text("Haki's AI estimates calories and protein from a photo, a description, or both.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .accessibilityElement(children: .combine)
    }
}

/// Covers the first step while the AI works, with a way to stop it.
private struct MealEstimatingOverlay: View {
    let image: UIImage?
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
            VStack(spacing: 16) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityHidden(true)
                }
                ProgressView()
                    .controlSize(.large)
                Text("Looking at your meal…")
                    .font(.headline)
                Text("This usually takes 5 to 30 seconds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .padding(.top, 4)
            }
            .padding(24)
        }
        .transition(.opacity)
    }
}

// MARK: - Step 2 pieces

/// The editable estimate: name, items with their numbers, live totals,
/// confidence, notes, meal and time.
private struct MealReviewForm: View {
    @Binding var draft: MealReviewDraft
    let image: UIImage?
    let onBack: () -> Void
    let onSave: () -> Void
    let onManual: () -> Void

    @FocusState private var focus: MealReviewFocus?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Form {
            summarySection
            itemsSection
            if !draft.notes.isEmpty {
                Section("Notes from Haki") {
                    Text(draft.notes)
                        .font(.subheadline)
                }
            }
            whenSection
            Section {
                Button("Enter it myself instead") {
                    onManual()
                }
            } footer: {
                Text("Estimates from Haki's AI. Adjust anything that looks off.")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    // MARK: Sections

    private var summarySection: some View {
        Section {
            HStack(alignment: .center, spacing: 14) {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Meal name", text: $draft.title)
                        .font(.headline)
                        .focused($focus, equals: .title)
                        .accessibilityLabel("Meal name")
                    Label(draft.confidence.title, systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.purple)
                        .accessibilityLabel("Confidence: \(draft.confidence.title)")
                }
            }
            MealTotalsRow(totals: draft.totals)
        }
    }

    private var itemsSection: some View {
        Section {
            ForEach(draft.items) { item in
                MealItemEditorRow(
                    item: item,
                    focus: $focus,
                    stacksFields: dynamicTypeSize.isAccessibilitySize,
                    onRemove: { remove(item) }
                )
            }
            .onDelete { offsets in
                withAnimation(.snappy) { draft.items.remove(atOffsets: offsets) }
            }
            Button {
                addItem()
            } label: {
                Label("Add an item", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("What's in it")
        } footer: {
            if draft.items.isEmpty {
                Text("Add at least one item to save.")
            } else {
                Text("Swipe left on an item to remove it.")
            }
        }
    }

    private var whenSection: some View {
        Section("When") {
            Picker("Meal", selection: $draft.mealType) {
                ForEach(MealType.allCases) { meal in
                    Label(meal.title, systemImage: meal.systemImage)
                        .tag(meal)
                }
            }
            DatePicker("Time", selection: $draft.eatenAt, displayedComponents: [.date, .hourAndMinute])
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                onBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .labelStyle(.titleAndIcon)
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                onSave()
            }
            .disabled(!canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    private var canSave: Bool {
        draft.items.contains { $0.estimateItem != nil }
    }

    private func remove(_ item: MealDraftItem) {
        withAnimation(.snappy) {
            draft.items.removeAll { $0.id == item.id }
        }
    }

    private func addItem() {
        let item = MealDraftItem()
        let id = item.id
        withAnimation(.snappy) { draft.items.append(item) }
        // Focus once the new row exists.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            focus = .name(id)
        }
    }
}

/// Live totals of the items: calories, protein, carbs and fat.
private struct MealTotalsRow: View {
    let totals: Macros

    var body: some View {
        HStack(spacing: 8) {
            stat("Calories", value: FoodFormat.whole(totals.calories), unit: "kcal", tint: NutritionPalette.calories)
            stat("Protein", value: FoodFormat.grams(totals.proteinG), unit: "g", tint: NutritionPalette.protein)
            stat("Carbs", value: FoodFormat.grams(totals.carbsG), unit: "g", tint: NutritionPalette.carbs)
            stat("Fat", value: FoodFormat.grams(totals.fatG), unit: "g", tint: NutritionPalette.fat)
        }
        .padding(.vertical, 4)
        .animation(.snappy, value: totals)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Total")
        .accessibilityValue(spokenTotals)
    }

    private var spokenTotals: String {
        let calories = FoodFormat.whole(totals.calories)
        let protein = FoodFormat.grams(totals.proteinG)
        let carbs = FoodFormat.grams(totals.carbsG)
        let fat = FoodFormat.grams(totals.fatG)
        return "\(calories) kilocalories, \(protein) grams protein, \(carbs) grams carbs, \(fat) grams fat"
    }

    private func stat(_ title: String, value: String, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// One estimated item: name, portion, and its four numbers.
private struct MealItemEditorRow: View {
    @Bindable var item: MealDraftItem
    var focus: FocusState<MealReviewFocus?>.Binding
    let stacksFields: Bool
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("Item, e.g. Rice", text: $item.name)
                    .font(.body.weight(.semibold))
                    .focused(focus, equals: .name(item.id))
                    .accessibilityLabel("Item name")
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.hakiNegative)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(removeLabel)
            }
            TextField("Portion, e.g. 1 cup", text: $item.portion)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .focused(focus, equals: .portion(item.id))
                .accessibilityLabel("Portion")
            numberFields
        }
        .padding(.vertical, 4)
    }

    private var removeLabel: String {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Remove item" : "Remove \(name)"
    }

    @ViewBuilder
    private var numberFields: some View {
        if stacksFields {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    caloriesField
                    proteinField
                }
                HStack(spacing: 8) {
                    carbsField
                    fatField
                }
            }
        } else {
            HStack(spacing: 8) {
                caloriesField
                proteinField
                carbsField
                fatField
            }
        }
    }

    private var caloriesField: some View {
        MealNumberField(title: "kcal", spokenTitle: "Calories", text: $item.caloriesText, focus: focus, field: .calories(item.id))
    }

    private var proteinField: some View {
        MealNumberField(title: "Protein g", spokenTitle: "Protein in grams", text: $item.proteinText, focus: focus, field: .protein(item.id))
    }

    private var carbsField: some View {
        MealNumberField(title: "Carbs g", spokenTitle: "Carbs in grams", text: $item.carbsText, focus: focus, field: .carbs(item.id))
    }

    private var fatField: some View {
        MealNumberField(title: "Fat g", spokenTitle: "Fat in grams", text: $item.fatText, focus: focus, field: .fat(item.id))
    }
}

/// A small labeled decimal field.
private struct MealNumberField: View {
    let title: String
    let spokenTitle: String
    @Binding var text: String
    var focus: FocusState<MealReviewFocus?>.Binding
    let field: MealReviewFocus

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityHidden(true)
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .monospacedDigit()
                .focused(focus, equals: field)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.hakiBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel(spokenTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The AI didn't see food: say so, with its notes, and offer a retake.
private struct MealNotFoodView: View {
    let notes: String
    let onRetake: () -> Void
    let onManual: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("That doesn't look like food", systemImage: "questionmark.circle")
        } description: {
            Text(notes.isEmpty ? "Haki couldn't find a meal in that photo. Try another photo, or describe what you ate." : notes)
        } actions: {
            Button {
                onRetake()
            } label: {
                Label("Try another photo", systemImage: "camera")
            }
            .buttonStyle(.borderedProminent)
            Button("Enter it myself instead") {
                onManual()
            }
            .buttonStyle(.bordered)
        }
        .background(Color.hakiBackground)
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { onCancel() }
            }
        }
    }
}

#Preview {
    MealCaptureView()
        .previewEnvironment()
}

#Preview("For dinner yesterday") {
    MealCaptureView(mealType: .dinner, eatenAt: Date.now.addingTimeInterval(-86_400))
        .previewEnvironment()
}
