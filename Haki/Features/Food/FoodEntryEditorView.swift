//
//  FoodEntryEditorView.swift
//  Haki
//
//  Adds a food by hand or edits a logged one: name, meal, time, portion,
//  servings, calories and macros, notes. `FoodEntryForm` is the form on its
//  own, so the meal capture sheet can swap to it ("Enter it myself instead").
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct FoodEntryEditorView: View {
    let entry: FoodEntry?
    let mealType: MealType?
    let eatenAt: Date?

    /// `entry: nil` creates a new entry, for `mealType` at `eatenAt` (defaults:
    /// the meal usually eaten now, and now).
    init(entry: FoodEntry?, mealType: MealType? = nil, eatenAt: Date? = nil) {
        self.entry = entry
        self.mealType = mealType
        self.eatenAt = eatenAt
    }

    var body: some View {
        NavigationStack {
            FoodEntryForm(entry: entry, mealType: mealType, eatenAt: eatenAt)
        }
    }
}

// MARK: - Form

private enum FoodEntryField: Hashable {
    case name, portion, calories, protein, carbs, fat, fiber, notes
}

/// The editor's form, without a NavigationStack of its own. Saving or
/// deleting dismisses the presenting sheet.
struct FoodEntryForm: View {
    let entry: FoodEntry?
    private let photoData: Data?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var meal: MealType
    @State private var time: Date
    @State private var portion = ""
    @State private var servings: Double = 1
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var fiberText = ""
    @State private var notes = ""
    /// The photo shown at the top: the entry's, or the one passed in for a new entry.
    @State private var photo: UIImage?
    @State private var removesPhoto = false
    /// "Estimated by Haki's AI · Good estimate" for AI entries being edited.
    @State private var sourceNote: String?
    @State private var didLoad = false
    @State private var isConfirmingDelete = false
    @FocusState private var focus: FoodEntryField?

    /// For a new entry, `mealType`, `eatenAt`, `prefillName` and `photoData`
    /// fill in the form. For an existing entry they're ignored; its values
    /// load when the form appears (never in `init`, so a re-created form
    /// doesn't read a model that was just deleted).
    init(entry: FoodEntry?, mealType: MealType? = nil, eatenAt: Date? = nil, prefillName: String = "", photoData: Data? = nil) {
        self.entry = entry
        self.photoData = entry == nil ? photoData : nil
        let date = eatenAt ?? .now
        _time = State(initialValue: date)
        _meal = State(initialValue: mealType ?? MealType.suggested(for: date))
        _name = State(initialValue: prefillName)
    }

    var body: some View {
        Form {
            if let photo, !removesPhoto {
                photoSection(photo)
            }
            foodSection
            whenSection
            nutritionSection
            notesSection
            if entry != nil {
                deleteSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(entry == nil ? "Add food" : "Edit food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear(perform: loadIfNeeded)
        .confirmationDialog("Delete this entry?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It's removed from your food log and today's totals.")
        }
    }

    // MARK: Sections

    private func photoSection(_ image: UIImage) -> some View {
        Section {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 180)
                .overlay {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityElement()
                .accessibilityLabel("Meal photo")
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            Button(role: .destructive) {
                withAnimation(.snappy) { removesPhoto = true }
            } label: {
                Label("Remove photo", systemImage: "trash")
            }
        }
    }

    private var foodSection: some View {
        Section {
            TextField("Name, e.g. Chicken salad", text: $name)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.next)
                .focused($focus, equals: .name)
                .onSubmit { focus = .portion }
            TextField("Portion, e.g. 1 bowl", text: $portion)
                .submitLabel(.done)
                .focused($focus, equals: .portion)
            Stepper(value: servingsBinding, in: 0.5...50, step: 0.5) {
                HStack {
                    Text("Servings")
                    Spacer(minLength: 8)
                    Text(FoodStore.formatServings(servings))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityValue("\(FoodStore.formatServings(servings)) servings")
        } header: {
            Text("Food")
        } footer: {
            Text("Changing servings scales the numbers below.")
        }
    }

    private var whenSection: some View {
        Section("When") {
            Picker("Meal", selection: $meal) {
                ForEach(MealType.allCases) { meal in
                    Label(meal.title, systemImage: meal.systemImage)
                        .tag(meal)
                }
            }
            DatePicker("Time", selection: $time, displayedComponents: [.date, .hourAndMinute])
        }
    }

    private var nutritionSection: some View {
        Section {
            numberRow("Calories", unit: "kcal", spokenUnit: "kilocalories", text: $caloriesText, field: .calories)
            numberRow("Protein", unit: "g", spokenUnit: "grams", text: $proteinText, field: .protein)
            numberRow("Carbs", unit: "g", spokenUnit: "grams", text: $carbsText, field: .carbs)
            numberRow("Fat", unit: "g", spokenUnit: "grams", text: $fatText, field: .fat)
            numberRow("Fiber", unit: "g", spokenUnit: "grams", text: $fiberText, field: .fiber)
            if let suggested = caloriesFromMacros {
                Button {
                    caloriesText = FoodFormat.fieldText(suggested)
                } label: {
                    Label("Use \(FoodFormat.kcal(suggested)) from protein, carbs and fat", systemImage: "wand.and.stars")
                        .font(.subheadline)
                }
            }
        } header: {
            Text("Nutrition")
        } footer: {
            Text(nutritionFooter)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .focused($focus, equals: .notes)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                isConfirmingDelete = true
            } label: {
                Label("Delete entry", systemImage: "trash")
            }
        }
    }

    private func numberRow(_ title: String, unit: String, spokenUnit: String, text: Binding<String>, field: FoodEntryField) -> some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 12)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused($focus, equals: field)
                .frame(maxWidth: 120)
                .accessibilityLabel("\(title) in \(spokenUnit)")
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(minWidth: 32, alignment: .leading)
                .accessibilityHidden(true)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }
                .disabled(!canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focus = nil }
        }
    }

    // MARK: Derived values

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && FoodFormat.parse(caloriesText) != nil
    }

    private var enteredMacros: Macros {
        Macros(
            calories: FoodFormat.parse(caloriesText) ?? 0,
            proteinG: FoodFormat.parse(proteinText) ?? 0,
            carbsG: FoodFormat.parse(carbsText) ?? 0,
            fatG: FoodFormat.parse(fatText) ?? 0,
            fiberG: FoodFormat.parse(fiberText) ?? 0
        )
    }

    /// Calories implied by the macros, offered while the calories field is empty.
    private var caloriesFromMacros: Double? {
        guard FoodFormat.parse(caloriesText) == nil else { return nil }
        let fromMacros = enteredMacros.caloriesFromMacros
        return fromMacros > 0 ? fromMacros.rounded() : nil
    }

    private var nutritionFooter: String {
        var lines = ["Totals for everything you ate, all servings included."]
        if let sourceNote {
            lines.append(sourceNote)
        }
        if trimmedName.isEmpty || FoodFormat.parse(caloriesText) == nil {
            lines.append("A name and calories are needed to save.")
        }
        return lines.joined(separator: " ")
    }

    /// Changing servings scales every number already entered.
    private var servingsBinding: Binding<Double> {
        Binding(
            get: { servings },
            set: { newValue in
                let old = servings
                servings = newValue
                scaleNumbers(by: old > 0 ? newValue / old : 1)
            }
        )
    }

    private func scaleNumbers(by factor: Double) {
        guard factor.isFinite, factor > 0, factor != 1 else { return }
        caloriesText = scaled(caloriesText, by: factor)
        proteinText = scaled(proteinText, by: factor)
        carbsText = scaled(carbsText, by: factor)
        fatText = scaled(fatText, by: factor)
        fiberText = scaled(fiberText, by: factor)
    }

    private func scaled(_ text: String, by factor: Double) -> String {
        guard let value = FoodFormat.parse(text) else { return text }
        return FoodFormat.fieldText(value * factor)
    }

    // MARK: Actions

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        guard let entry else {
            if let photoData {
                photo = UIImage(data: photoData)
            }
            focus = trimmedName.isEmpty ? .name : .calories
            return
        }
        name = entry.name
        meal = entry.mealType
        time = entry.eatenAt
        portion = entry.portion
        servings = entry.servings.isFinite && entry.servings > 0 && entry.servings <= 1_000 ? entry.servings : 1
        caloriesText = FoodFormat.fieldText(entry.calories)
        proteinText = FoodFormat.fieldText(entry.proteinG)
        carbsText = FoodFormat.fieldText(entry.carbsG)
        fatText = FoodFormat.fieldText(entry.fatG)
        fiberText = FoodFormat.fieldText(entry.fiberG)
        notes = entry.notes
        if let data = entry.photoData {
            photo = UIImage(data: data)
        }
        sourceNote = Self.sourceNote(for: entry)
    }

    private static func sourceNote(for entry: FoodEntry) -> String? {
        let confidence = entry.confidence.map { " (\($0.title.lowercased()))" } ?? ""
        switch entry.source {
        case .aiPhoto, .aiText:
            return "Estimated by Haki's AI\(confidence)."
        case .menu:
            if let place = entry.placeName, !place.isEmpty {
                return "From the menu at \(place)\(confidence)."
            }
            return "From a restaurant menu\(confidence)."
        case .manual, .repeatEntry:
            return nil
        }
    }

    private func save() {
        guard canSave else { return }
        let macros = enteredMacros
        let cleanPortion = portion.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let entry {
            entry.name = trimmedName
            entry.mealType = meal
            entry.eatenAt = time
            entry.portion = cleanPortion
            entry.servings = servings
            entry.macros = macros
            entry.notes = cleanNotes
            if removesPhoto {
                entry.photoData = nil
            }
            FoodStore.update(entry, in: modelContext)
        } else {
            FoodStore.add(
                name: trimmedName,
                mealType: meal,
                macros: macros,
                eatenAt: time,
                portion: cleanPortion,
                servings: servings,
                source: .manual,
                notes: cleanNotes,
                photoData: removesPhoto ? nil : photoData,
                in: modelContext
            )
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    private func delete() {
        guard let entry else { return }
        FoodStore.delete(entry, in: modelContext)
        dismiss()
    }
}

#Preview("Edit") {
    FoodEntryEditorView(entry: PreviewData.sampleFoodEntry)
        .previewEnvironment()
}

#Preview("New") {
    FoodEntryEditorView(entry: nil, mealType: .lunch)
        .previewEnvironment()
}
