//
//  ExercisePickerView.swift
//  Haki
//
//  A sheet for choosing an exercise: Haki's built-in library plus the
//  person's custom exercises, searchable and filterable by muscle, with a
//  way to create a custom exercise. Tapping one hands it to `onPick` and
//  closes the sheet.
//

import Foundation
import SwiftData
import SwiftUI

struct ExercisePickerView: View {
    let onPick: (ExerciseDefinition) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \CustomExerciseRecord.name) private var customExercises: [CustomExerciseRecord]

    @State private var exercises: [ExerciseDefinition] = []
    @State private var searchText = ""
    @State private var muscle: MuscleGroup?
    @State private var isCreatingCustom = false
    /// A custom exercise just created in the editor, picked once it closes.
    @State private var createdExercise: ExerciseDefinition?

    var body: some View {
        NavigationStack {
            list
                .navigationTitle("Add exercise")
                .navigationBarTitleDisplayMode(.inline)
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
                .task(id: customExercises.count) {
                    exercises = WorkoutStore.allExercises(in: modelContext)
                }
                .sheet(isPresented: $isCreatingCustom, onDismiss: { pickCreated() }) {
                    ExerciseCustomEditor(initialName: searchText, onCreate: { definition in
                        createdExercise = definition
                    })
                }
        }
    }

    private var list: some View {
        // The built-in library until the custom exercises have loaded.
        let source = exercises.isEmpty ? ExerciseLibrary.all : exercises
        let results = ExerciseLibrary.search(searchText, muscle: muscle, in: source)
        return List {
            Section {
                ExerciseMuscleChips(selection: $muscle)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            Section {
                Button {
                    isCreatingCustom = true
                } label: {
                    Label("Create custom exercise", systemImage: "plus.circle")
                }
            }
            if results.isEmpty {
                Section {
                    noResults
                }
            } else {
                Section {
                    ForEach(results) { definition in
                        Button {
                            pick(definition)
                        } label: {
                            ExerciseDefinitionRow(definition: definition)
                        }
                        .accessibilityHint("Adds this exercise")
                    }
                } header: {
                    Text(resultsTitle(count: results.count))
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    private var noResults: some View {
        ContentUnavailableView {
            Label("No matching exercises", systemImage: "magnifyingglass")
        } description: {
            Text("Try another word or muscle, or create your own exercise.")
        } actions: {
            Button("Create custom exercise") {
                isCreatingCustom = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func resultsTitle(count: Int) -> String {
        let noun = count == 1 ? "exercise" : "exercises"
        if let muscle { return "\(muscle.title) · \(count) \(noun)" }
        return "\(count) \(noun)"
    }

    private func pick(_ definition: ExerciseDefinition) {
        onPick(definition)
        dismiss()
    }

    private func pickCreated() {
        guard let created = createdExercise else { return }
        createdExercise = nil
        pick(created)
    }
}

// MARK: - Custom exercise editor

/// A sheet for creating a custom exercise: name, main muscle, equipment and
/// what each set logs.
struct ExerciseCustomEditor: View {
    var initialName: String = ""
    let onCreate: (ExerciseDefinition) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var muscle: MuscleGroup = .chest
    @State private var equipment: Equipment = .barbell
    @State private var kind: ExerciseKind = .weightReps
    @State private var hasLoaded = false
    @FocusState private var isNameFocused: Bool

    var body: some View {
        NavigationStack {
            form
                .navigationTitle("Custom exercise")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .disabled(trimmedName.isEmpty)
                    }
                }
                .onAppear {
                    guard !hasLoaded else { return }
                    hasLoaded = true
                    name = initialName.trimmingCharacters(in: .whitespacesAndNewlines)
                    isNameFocused = true
                }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Exercise name", text: $name)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.words)
            } footer: {
                Text("For example \"Cable Fly (Machine)\". Naming the equipment in brackets helps Haki match the same exercise in Hevy.")
            }
            Section {
                Picker("Main muscle", selection: $muscle) {
                    ForEach(MuscleGroup.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("Equipment", selection: $equipment) {
                    ForEach(Equipment.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                Picker("Each set logs", selection: $kind) {
                    ForEach(ExerciseKind.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
            } footer: {
                Text(kindFooter)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var kindFooter: String {
        var fields: [String] = []
        if kind.logsWeight { fields.append(kind == .assistedBodyweightReps ? "assistance weight" : (kind == .bodyweightReps ? "extra weight" : "weight")) }
        if kind.logsReps { fields.append("reps") }
        if kind.logsDistance { fields.append("distance") }
        if kind.logsDuration { fields.append("time") }
        let joined: String
        if fields.count > 1, let last = fields.last {
            joined = fields.dropLast().joined(separator: ", ") + " and " + last
        } else {
            joined = fields.first ?? "nothing"
        }
        return "Each set records \(joined)."
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        let record = WorkoutStore.createCustomExercise(
            name: trimmedName,
            primaryMuscle: muscle,
            equipment: equipment,
            kind: kind,
            in: modelContext
        )
        onCreate(record.definition)
        dismiss()
    }
}

// MARK: - Previews

#Preview {
    ExercisePickerView(onPick: { _ in })
        .previewEnvironment()
}

#Preview("Custom exercise") {
    ExerciseCustomEditor(initialName: "Cable fly", onCreate: { _ in })
        .previewEnvironment()
}
