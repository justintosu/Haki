//
//  RoutineEditorView.swift
//  Haki
//
//  A sheet for creating or editing a routine: name, notes and its exercises,
//  each with a target number of sets, a rep range and rest time. Exercise
//  changes save as they're made; the name and notes save with Save / Done.
//  A new routine is created on its first exercise (or on Save), and Cancel
//  removes a routine created here.
//

import Foundation
import SwiftData
import SwiftUI

struct RoutineEditorView: View {
    let routine: RoutineRecord?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// `routine`, or the one created here when the first exercise is added.
    @State private var workingRoutine: RoutineRecord?
    @State private var createdHere = false
    @State private var name = ""
    @State private var notes = ""
    @State private var hasLoaded = false
    @State private var isPicking = false
    @State private var editMode: EditMode = .inactive
    @State private var showsDiscardConfirmation = false
    @State private var showsDeleteConfirmation = false
    /// Set right before deleting, so the body never reads a deleted model.
    @State private var isDeleted = false
    @State private var savedFeedback = 0
    @FocusState private var focusedField: RoutineEditorField?

    private var current: RoutineRecord? {
        guard !isDeleted else { return nil }
        guard let candidate = workingRoutine ?? routine else { return nil }
        return candidate.isDeleted || candidate.modelContext == nil ? nil : candidate
    }

    private var isNew: Bool { routine == nil }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isDeleted {
                    Color.hakiBackground
                } else {
                    form
                }
            }
            .navigationTitle(isNew ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $isPicking) {
                ExercisePickerView(onPick: { definition in add(definition) })
            }
            .confirmationDialog("Discard this routine?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard routine", role: .destructive) { deleteAndClose() }
                Button("Keep editing", role: .cancel) {}
            } message: {
                Text("The exercises you added will be removed too.")
            }
            .confirmationDialog("Delete this routine?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete routine", role: .destructive) { deleteAndClose() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Workouts you logged from it stay.")
            }
            .onAppear { load() }
        }
        .interactiveDismissDisabled(createdHere || hasTextChanges)
        .sensoryFeedback(.success, trigger: savedFeedback)
    }

    private var hasTextChanges: Bool {
        guard let routine, !routine.isDeleted, routine.modelContext != nil else {
            return !trimmedName.isEmpty || !notes.isEmpty
        }
        return trimmedName != routine.name || notes != routine.notes
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                TextField("Routine name", text: $name)
                    .font(.headline)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .notes }
                    .textInputAutocapitalization(.words)
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focusedField, equals: .notes)
            }
            exercisesSection
            if !isNew {
                Section {
                    Button(role: .destructive) {
                        focusedField = nil
                        showsDeleteConfirmation = true
                    } label: {
                        Label("Delete routine", systemImage: "trash")
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .scrollDismissesKeyboard(.interactively)
    }

    private var exercisesSection: some View {
        let planned = current?.orderedExercises ?? []
        return Section {
            ForEach(planned) { item in
                RoutineExerciseEditorRow(planned: item, onSave: { WorkoutStore.save(in: modelContext) })
            }
            .onMove { source, destination in move(from: source, to: destination) }
            .onDelete { offsets in remove(at: offsets) }

            Button {
                focusedField = nil
                isPicking = true
            } label: {
                Label("Add exercise", systemImage: "plus.circle.fill")
            }
        } header: {
            exercisesHeader(count: planned.count)
        } footer: {
            Text(planned.isEmpty
                 ? "Add the exercises you do in this routine. Starting it fills in what you lifted last time."
                 : "Swipe left on an exercise to remove it.")
        }
    }

    private func exercisesHeader(count: Int) -> some View {
        HStack {
            Text(verbatim: count == 0 ? "Exercises" : "Exercises · \(count)")
            Spacer()
            if count > 1 {
                Button(editMode == .active ? "Done" : "Reorder") {
                    withAnimation(.snappy) {
                        editMode = editMode == .active ? .inactive : .active
                    }
                }
                .font(.footnote.weight(.semibold))
                .textCase(nil)
                .accessibilityHint(editMode == .active ? "Stops reordering" : "Drag exercises into a new order")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { cancel() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(isNew ? "Save" : "Done") { save() }
                .fontWeight(.semibold)
                .disabled(trimmedName.isEmpty)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
        }
    }

    // MARK: Actions

    private func load() {
        guard !hasLoaded else { return }
        hasLoaded = true
        workingRoutine = routine
        if let routine, !routine.isDeleted, routine.modelContext != nil {
            name = routine.name
            notes = routine.notes
        } else {
            focusedField = .name
        }
    }

    private func add(_ definition: ExerciseDefinition) {
        let target: RoutineRecord
        if let existing = current {
            target = existing
        } else {
            target = WorkoutStore.createRoutine(name: trimmedName, in: modelContext)
            workingRoutine = target
            createdHere = true
        }
        withAnimation(.snappy) {
            _ = WorkoutStore.addExercise(definition, to: target, in: modelContext)
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let target = current else { return }
        WorkoutStore.moveExercises(in: target, from: source, to: destination, in: modelContext)
    }

    private func remove(at offsets: IndexSet) {
        guard let target = current else { return }
        let planned = target.orderedExercises
        var doomed: [RoutineExerciseRecord] = []
        for index in offsets where index < planned.count {
            doomed.append(planned[index])
        }
        withAnimation(.snappy) {
            for item in doomed {
                WorkoutStore.removeExercise(item, in: modelContext)
            }
        }
    }

    private func save() {
        focusedField = nil
        guard !trimmedName.isEmpty else { return }
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = current {
            existing.name = trimmedName
            existing.notes = cleanNotes
            WorkoutStore.save(in: modelContext)
        } else {
            let created = WorkoutStore.createRoutine(name: trimmedName, in: modelContext)
            created.notes = cleanNotes
            WorkoutStore.save(in: modelContext)
        }
        savedFeedback += 1
        dismiss()
    }

    private func cancel() {
        focusedField = nil
        guard createdHere, let created = current else {
            dismiss()
            return
        }
        if created.exercises.isEmpty {
            deleteAndClose()
        } else {
            showsDiscardConfirmation = true
        }
    }

    /// Deletes the routine (created here, or being edited) and closes.
    private func deleteAndClose() {
        guard let target = current else {
            dismiss()
            return
        }
        isDeleted = true
        WorkoutStore.deleteRoutine(target, in: modelContext)
        dismiss()
    }
}

private enum RoutineEditorField: Hashable {
    case name
    case notes
}

// MARK: - Exercise row

/// One planned exercise: target sets, rep range (for exercises with reps)
/// and rest time. Each change is written and saved right away.
private struct RoutineExerciseEditorRow: View {
    let planned: RoutineExerciseRecord
    let onSave: () -> Void

    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 32

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Stepper(value: setsBinding, in: 1...12) {
                Text(verbatim: WorkoutsFormat.setCount(planned.targetSets))
                    .monospacedDigit()
            }
            if planned.kind.logsReps {
                Stepper(value: lowBinding, in: 1...50) {
                    Text("Reps from \(lowBinding.wrappedValue)")
                        .monospacedDigit()
                }
                Stepper(value: highBinding, in: 1...50) {
                    Text("Reps up to \(highBinding.wrappedValue)")
                        .monospacedDigit()
                }
            }
            Picker("Rest timer", selection: restBinding) {
                ForEach(WorkoutsFormat.restChoices(including: planned.restSeconds), id: \.self) { seconds in
                    Text(WorkoutsFormat.restTitle(seconds)).tag(seconds)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: WorkoutsFormat.symbol(for: planned.kind))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: iconSize, height: iconSize)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(planned.name)
                    .font(.body.weight(.semibold))
                Text("\(planned.primaryMuscle.title) · \(planned.equipment.title)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var setsBinding: Binding<Int> {
        Binding(
            get: { planned.targetSets },
            set: { newValue in
                planned.targetSets = newValue
                onSave()
            }
        )
    }

    private var lowBinding: Binding<Int> {
        Binding(
            get: { planned.targetRepsLow ?? planned.targetRepsHigh ?? 8 },
            set: { newValue in
                planned.targetRepsLow = newValue
                planned.targetRepsHigh = max(planned.targetRepsHigh ?? newValue, newValue)
                onSave()
            }
        )
    }

    private var highBinding: Binding<Int> {
        Binding(
            get: { planned.targetRepsHigh ?? planned.targetRepsLow ?? 12 },
            set: { newValue in
                planned.targetRepsHigh = newValue
                planned.targetRepsLow = min(planned.targetRepsLow ?? newValue, newValue)
                onSave()
            }
        )
    }

    private var restBinding: Binding<Int> {
        Binding(
            get: { planned.restSeconds },
            set: { newValue in
                planned.restSeconds = newValue
                onSave()
            }
        )
    }
}

// MARK: - Previews

#Preview("Edit") {
    RoutineEditorView(routine: PreviewData.sampleRoutine)
        .previewEnvironment()
}

#Preview("New") {
    RoutineEditorView(routine: nil)
        .previewEnvironment()
}
