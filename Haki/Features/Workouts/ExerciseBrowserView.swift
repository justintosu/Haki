//
//  ExerciseBrowserView.swift
//  Haki
//
//  The exercise library, pushed from Workouts: built-in and custom
//  exercises, searchable and filterable by muscle. Each opens its history
//  and records. Custom exercises can be created here and swiped away.
//

import Foundation
import SwiftData
import SwiftUI

struct ExerciseBrowserView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \CustomExerciseRecord.name) private var customExercises: [CustomExerciseRecord]

    @State private var exercises: [ExerciseDefinition] = []
    @State private var searchText = ""
    @State private var muscle: MuscleGroup?
    @State private var isCreatingCustom = false

    var body: some View {
        list
            .navigationTitle("Exercises")
            .searchable(text: $searchText, prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isCreatingCustom = true
                    } label: {
                        Label("Create custom exercise", systemImage: "plus")
                    }
                    .accessibilityLabel("Create custom exercise")
                }
            }
            .task(id: customExercises.count) {
                exercises = WorkoutStore.allExercises(in: modelContext)
            }
            .sheet(isPresented: $isCreatingCustom) {
                ExerciseCustomEditor(initialName: searchText, onCreate: { _ in })
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
            if results.isEmpty {
                Section {
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
            } else {
                Section {
                    ForEach(results) { definition in
                        row(for: definition)
                    }
                } header: {
                    Text(verbatim: WorkoutsFormat.exerciseCount(results.count))
                } footer: {
                    Text("Tap an exercise to see your records and every session you've logged it.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.immediately)
    }

    private func row(for definition: ExerciseDefinition) -> some View {
        NavigationLink {
            ExerciseHistoryView(exerciseKey: definition.key, name: definition.name)
        } label: {
            ExerciseDefinitionRow(definition: definition)
        }
        .swipeActions(edge: .trailing) {
            if let custom = customRecord(for: definition) {
                Button(role: .destructive) {
                    WorkoutStore.deleteCustomExercise(custom, in: modelContext)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private func customRecord(for definition: ExerciseDefinition) -> CustomExerciseRecord? {
        guard definition.key.hasPrefix("custom:") else { return nil }
        return customExercises.first { $0.exerciseKey == definition.key }
    }
}

#Preview {
    NavigationStack {
        ExerciseBrowserView()
    }
    .previewEnvironment()
}
