//
//  WorkoutDetailView.swift
//  Haki
//
//  A finished workout: when, how long, volume, sets and the records it set,
//  then each exercise with its sets (best set marked). The menu saves it as
//  a routine, repeats it, posts it to Hevy or deletes it.
//

import Foundation
import SwiftData
import SwiftUI

struct WorkoutDetailView: View {
    let workout: WorkoutRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HevySyncService.self) private var hevy

    @AppStorage(HealthSettings.weightUnitKey) private var weightUnitRaw = ""
    @AppStorage(HealthSettings.distanceUnitKey) private var distanceUnitRaw = ""

    @Query(filter: #Predicate<WorkoutRecord> { $0.endedAt == nil }, sort: [SortDescriptor(\WorkoutRecord.startedAt, order: .reverse)])
    private var activeWorkouts: [WorkoutRecord]

    /// Records each set beat, by set id, against earlier workouts.
    @State private var recordSets: [UUID: Set<RecordKind>] = [:]
    @State private var showsSaveRoutine = false
    @State private var routineName = ""
    @State private var showsDeleteConfirmation = false
    /// Set right before deleting, so the body never reads a deleted model.
    @State private var isDeleted = false
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var presentedWorkout: WorkoutRecord?
    @State private var notice: String?
    @State private var successFeedback = 0

    private var weightUnit: WeightUnit { HealthSettings.weightUnit(from: weightUnitRaw) }
    private var distanceUnit: DistanceUnit { HealthSettings.distanceUnit(from: distanceUnitRaw) }

    var body: some View {
        Group {
            if isDeleted {
                // Deleted here: the screen is closing.
                Color.hakiBackground
            } else if isGone {
                ContentUnavailableView(
                    "Workout deleted",
                    systemImage: "trash",
                    description: Text("This workout is no longer in Haki.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.hakiBackground)
            } else {
                screen
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: successFeedback)
    }

    /// Deleted here or elsewhere (e.g. removed by a Hevy sync). Checked
    /// before reading any of its values.
    private var isGone: Bool {
        isDeleted || workout.isDeleted || workout.modelContext == nil
    }

    // MARK: Screen

    private var screen: some View {
        scrollContent
            .navigationTitle(workout.title.isEmpty ? "Workout" : workout.title)
            .toolbar { toolbarContent }
            .task { loadRecords() }
            .overlay(alignment: .bottom) { noticeOverlay }
            .task(id: notice) { await hideNoticeLater() }
            .fullScreenCover(item: $presentedWorkout) { active in
                ActiveWorkoutView(workout: active)
            }
            .alert("Save as routine", isPresented: $showsSaveRoutine) {
                TextField("Routine name", text: $routineName)
                Button("Save") { saveRoutine() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Start this workout again any time from Workouts.")
            }
            .confirmationDialog("Delete this workout?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete workout", role: .destructive) { delete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
            .alert("Couldn't post to Hevy", isPresented: showsUploadError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(uploadError ?? "")
            }
    }

    private var scrollContent: some View {
        let exercises = workout.orderedExercises
        return ScrollView {
            VStack(spacing: 16) {
                WorkoutDetailSummaryCard(
                    workout: workout,
                    recordCount: recordSets.count,
                    weightUnit: weightUnit,
                    canUpload: canUpload,
                    isUploading: isUploading,
                    onUpload: { upload() }
                )
                ForEach(exercises) { exercise in
                    WorkoutDetailExerciseCard(
                        exercise: exercise,
                        recordSets: recordSets,
                        weightUnit: weightUnit,
                        distanceUnit: distanceUnit
                    )
                }
                if !workout.notes.isEmpty {
                    notesCard
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader("Notes", systemImage: "note.text")
            Text(workout.notes)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .hakiCard()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    routineName = workout.title
                    showsSaveRoutine = true
                } label: {
                    Label("Save as routine", systemImage: "list.bullet.rectangle")
                }
                Button {
                    repeatWorkout()
                } label: {
                    if activeWorkouts.isEmpty {
                        Label("Repeat workout", systemImage: "arrow.clockwise")
                    } else {
                        Label("Resume current workout", systemImage: "figure.strengthtraining.traditional")
                    }
                }
                if canUpload {
                    Button {
                        upload()
                    } label: {
                        Label("Upload to Hevy", systemImage: "arrow.up.circle")
                    }
                    .disabled(isUploading)
                }
                Divider()
                Button(role: .destructive) {
                    showsDeleteConfirmation = true
                } label: {
                    Label("Delete workout", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Workout options")
        }
    }

    @ViewBuilder
    private var noticeOverlay: some View {
        if let notice {
            Label(notice, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
        }
    }

    private func hideNoticeLater() async {
        guard notice != nil else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) { notice = nil }
    }

    // MARK: Hevy

    /// A finished Haki workout that isn't in Hevy yet, while Hevy is connected.
    private var canUpload: Bool {
        workout.source == .haki && workout.hevyID == nil && workout.endedAt != nil && hevy.isConnected
    }

    private var showsUploadError: Binding<Bool> {
        Binding(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        )
    }

    private func upload() {
        guard canUpload, !isUploading else { return }
        isUploading = true
        uploadError = nil
        let target = workout
        let context = modelContext
        Task {
            do {
                try await hevy.upload(target, in: context)
                successFeedback += 1
                withAnimation(.snappy) { notice = "Posted to Hevy" }
            } catch {
                if !Backend.isCancellation(error) {
                    uploadError = error.localizedDescription
                }
            }
            isUploading = false
        }
    }

    // MARK: Actions

    private func loadRecords() {
        guard !isGone else { return }
        var found: [UUID: Set<RecordKind>] = [:]
        for exercise in workout.exercises {
            let history = WorkoutStore.records(exerciseKey: exercise.exerciseKey, kind: exercise.kind, before: workout.startedAt, in: modelContext)
            let beaten = WorkoutsRecordMath.recordSets(exercise.orderedSets, kind: exercise.kind, history: history, date: workout.startedAt)
            for (id, kinds) in beaten { found[id] = kinds }
        }
        recordSets = found
    }

    private func saveRoutine() {
        let trimmed = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        let routine = WorkoutStore.saveAsRoutine(workout, name: trimmed.isEmpty ? workout.title : trimmed, in: modelContext)
        successFeedback += 1
        withAnimation(.snappy) { notice = "Saved routine “\(routine.name)”" }
    }

    /// Starts a new workout with the same exercises (prefilled with what was
    /// lifted last time). With a workout already going, opens that instead.
    private func repeatWorkout() {
        if let active = activeWorkouts.first {
            presentedWorkout = active
            return
        }
        let fresh = WorkoutStore.startWorkout(title: workout.title, in: modelContext)
        for exercise in workout.orderedExercises {
            let definition = WorkoutStore.definition(forKey: exercise.exerciseKey, in: modelContext)
                ?? ExerciseDefinition(exercise.exerciseKey, exercise.name, exercise.primaryMuscle, [], exercise.equipment, exercise.kind)
            let added = WorkoutStore.addExercise(definition, to: fresh, in: modelContext)
            added.hevyTemplateID = exercise.hevyTemplateID
            added.restSeconds = exercise.restSeconds
        }
        WorkoutStore.save(in: modelContext)
        presentedWorkout = fresh
    }

    private var deleteMessage: String {
        switch workout.source {
        case .hevy:
            return "This removes Haki's copy. The workout stays in your Hevy account."
        case .haki:
            return workout.hevyID == nil
                ? "This can't be undone."
                : "This removes it from Haki. The copy in your Hevy account stays."
        }
    }

    private func delete() {
        isDeleted = true
        WorkoutStore.deleteWorkout(workout, in: modelContext)
        dismiss()
    }
}

// MARK: - Summary

/// Title, badge, date and time, and the totals.
private struct WorkoutDetailSummaryCard: View {
    let workout: WorkoutRecord
    let recordCount: Int
    let weightUnit: WeightUnit
    let canUpload: Bool
    let isUploading: Bool
    let onUpload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(workout.title.isEmpty ? "Workout" : workout.title)
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    WorkoutsSourceBadge(source: workout.source, hevyID: workout.hevyID)
                }
                Text(dateLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                WorkoutsStatTile(title: "Duration", value: WorkoutMath.formatDuration(seconds: workout.durationSeconds))
                WorkoutsStatTile(title: "Volume", value: WorkoutsFormat.volume(workout.volumeKg, unit: weightUnit))
            }
            HStack(spacing: 12) {
                WorkoutsStatTile(title: "Sets", value: "\(workout.completedSetCount)")
                WorkoutsStatTile(title: "Exercises", value: "\(workout.exercises.count)")
            }
            if recordCount > 0 {
                Label(recordsText, systemImage: "trophy.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.hakiWarning)
            }
            if canUpload || isUploading {
                uploadButton
            }
        }
        .hakiCard()
    }

    private var recordsText: String {
        recordCount == 1 ? "1 personal record in this workout" : "\(recordCount) personal records in this workout"
    }

    private var uploadButton: some View {
        Button(action: onUpload) {
            HStack(spacing: 8) {
                if isUploading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .accessibilityHidden(true)
                }
                Text(isUploading ? "Posting to Hevy…" : "Upload to Hevy")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .disabled(isUploading)
        .accessibilityHint("Posts this workout to your Hevy account")
    }

    /// "Monday, November 3 · 6:00 – 6:55 PM"
    private var dateLine: String {
        let day = workout.startedAt.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let start = workout.startedAt.formatted(date: .omitted, time: .shortened)
        guard let end = workout.endedAt else { return "\(day) · \(start)" }
        return "\(day) · \(start) – \(end.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Exercise

/// An exercise with its sets: the best set and record sets are marked.
private struct WorkoutDetailExerciseCard: View {
    let exercise: WorkoutExerciseRecord
    let recordSets: [UUID: Set<RecordKind>]
    let weightUnit: WeightUnit
    let distanceUnit: DistanceUnit

    var body: some View {
        let sets = exercise.orderedSets
        let labels = WorkoutExerciseSection.setLabels(sets)
        let bestID = Self.bestSetID(sets)

        VStack(alignment: .leading, spacing: 10) {
            header
            if !exercise.notes.isEmpty {
                Text(exercise.notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(sets) { setRecord in
                setLine(
                    setRecord,
                    label: labels[setRecord.id] ?? "",
                    isBest: setRecord.id == bestID,
                    records: recordSets[setRecord.id] ?? []
                )
            }
        }
        .hakiCard()
    }

    private var header: some View {
        NavigationLink {
            ExerciseHistoryView(exerciseKey: exercise.exerciseKey, name: exercise.name)
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text("\(exercise.primaryMuscle.title) · \(exercise.equipment.title)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows your history and records for this exercise")
    }

    private func setLine(_ setRecord: WorkoutSetRecord, label: String, isBest: Bool, records: Set<RecordKind>) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(setRecord.kind == .warmup ? Color.hakiWarning : Color.secondary)
                .frame(minWidth: 22, alignment: .leading)
            Text(WorkoutsFormat.setSummary(setRecord.values, kind: exercise.kind, weightUnit: weightUnit, distanceUnit: distanceUnit))
                .font(.subheadline)
                .monospacedDigit()
            Spacer(minLength: 8)
            if !records.isEmpty {
                WorkoutsRecordBadge(compact: true)
            }
            if isBest {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Best set")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(recordsDescription(records))
    }

    private func recordsDescription(_ records: Set<RecordKind>) -> String {
        guard !records.isEmpty else { return "" }
        let titles = RecordKind.allCases.filter { records.contains($0) }.map(\.title)
        return "New record: " + titles.joined(separator: ", ")
    }

    /// The completed working set with the best estimated 1RM.
    static func bestSetID(_ sets: [WorkoutSetRecord]) -> UUID? {
        guard let best = WorkoutMath.bestSet(sets.map(\.values)) else { return nil }
        return sets.first { $0.values == best }?.id
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        WorkoutDetailView(workout: PreviewData.sampleWorkout)
    }
    .previewEnvironment()
}
