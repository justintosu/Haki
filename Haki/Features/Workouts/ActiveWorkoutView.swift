//
//  ActiveWorkoutView.swift
//  Haki
//
//  The workout being logged, full screen in its own NavigationStack: name,
//  elapsed time, volume and sets so far, then a section per exercise with
//  its set table (see WorkoutSetTable.swift). Ticking a set starts the rest
//  timer and checks for personal records. Finish saves it (and posts it to
//  Hevy when that's turned on) and shows a short summary; Discard deletes
//  it; the chevron just minimizes, and the Health tab can resume it.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct ActiveWorkoutView: View {
    let workout: WorkoutRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HevySyncService.self) private var hevy

    @AppStorage(HealthSettings.weightUnitKey) private var weightUnitRaw = ""
    @AppStorage(HealthSettings.distanceUnitKey) private var distanceUnitRaw = ""
    @AppStorage(HealthSettings.restTimerEnabledKey) private var restTimerEnabled = true

    @FocusState private var focusedField: WorkoutSetFocus?

    /// Last time's sets per logged exercise (by exercise id), loaded once.
    @State private var previousSets: [UUID: [SetValues]] = [:]
    /// Records from before this workout per logged exercise, loaded when needed.
    @State private var historyRecords: [UUID: PersonalRecords] = [:]
    /// Records each ticked set beat, by set id.
    @State private var recordSets: [UUID: Set<RecordKind>] = [:]

    @State private var restEndsAt: Date?
    @State private var restTotalSeconds = 0

    @State private var isPickingExercise = false
    @State private var historyTarget: WorkoutHistoryTarget?
    @State private var showsFinishConfirmation = false
    @State private var showsDiscardConfirmation = false
    @State private var showsNoSetsAlert = false

    @State private var finishSummary: WorkoutFinishSummary?
    @State private var isPostingToHevy = false
    @State private var hevyPostFailed = false
    /// Set when discarding: the screen shows nothing while it closes, and the
    /// workout is deleted once it's gone, so nothing reads a deleted model.
    @State private var isClosing = false
    @State private var deletesWhenClosed = false

    @State private var recordFeedback = 0
    @State private var restDoneFeedback = 0
    @State private var finishFeedback = 0

    private var weightUnit: WeightUnit { HealthSettings.weightUnit(from: weightUnitRaw) }
    private var distanceUnit: DistanceUnit { HealthSettings.distanceUnit(from: distanceUnitRaw) }

    var body: some View {
        NavigationStack {
            content
        }
        .sensoryFeedback(.impact(weight: .light), trigger: recordFeedback)
        .sensoryFeedback(.success, trigger: restDoneFeedback)
        .sensoryFeedback(.success, trigger: finishFeedback)
        .onAppear { restoreRest() }
        .onChange(of: restEndsAt) { _, end in rememberRest(endingAt: end) }
        .onDisappear { closeUp() }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if isClosing {
            Color.hakiBackground
                .ignoresSafeArea()
        } else if let finishSummary {
            WorkoutFinishedView(
                summary: finishSummary,
                weightUnit: weightUnit,
                hevyStatus: hevyStatus,
                onDone: { dismiss() }
            )
        } else if isGone {
            endedElsewhere
        } else {
            workoutScreen
        }
    }

    /// Deleted or finished somewhere else (e.g. "Erase all data") while open.
    private var isGone: Bool {
        workout.isDeleted || workout.modelContext == nil || workout.endedAt != nil
    }

    private var endedElsewhere: some View {
        ContentUnavailableView(
            "Workout ended",
            systemImage: "checkmark.circle",
            description: Text("This workout is no longer in progress.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hakiBackground)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Close") { dismiss() }
            }
        }
    }

    /// "Posting to Hevy…" / "Also posted to Hevy" / a failure on the summary.
    private var hevyStatus: String? {
        if isPostingToHevy { return "Posting to Hevy…" }
        guard !workout.isDeleted, workout.modelContext != nil else { return nil }
        if workout.hevyID != nil && workout.source == .haki { return "Also posted to Hevy" }
        if hevyPostFailed { return "Couldn't post to Hevy. Try again from this workout in your history." }
        return nil
    }

    // MARK: Workout screen

    // The modifiers are split over three properties so no single expression
    // gets long enough to strain the type checker.

    private var workoutScreen: some View {
        workoutListWithSheets
            .confirmationDialog("Discard this workout?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
                Button("Discard workout", role: .destructive) { discard() }
                Button("Keep workout", role: .cancel) {}
            } message: {
                Text("Everything logged in this workout will be deleted.")
            }
            .alert("No completed sets", isPresented: $showsNoSetsAlert) {
                Button("Discard workout", role: .destructive) { discard() }
                Button("Keep logging", role: .cancel) {}
            } message: {
                Text("Tick the sets you did to save this workout, or discard it.")
            }
    }

    private var workoutListWithSheets: some View {
        workoutList
            .safeAreaInset(edge: .bottom) { restBar }
            .sheet(isPresented: $isPickingExercise) {
                ExercisePickerView(onPick: { definition in add(definition) })
            }
            .navigationDestination(item: $historyTarget) { target in
                ExerciseHistoryView(exerciseKey: target.key, name: target.name)
            }
            .onAppear { loadCaches() }
            .onChange(of: workout.exercises.count) { _, _ in loadCaches() }
            .onChange(of: focusedField) { oldValue, _ in
                if oldValue != nil { WorkoutStore.save(in: modelContext) }
            }
            .task(id: restEndsAt) { await runRestTimer() }
    }

    private var workoutList: some View {
        let exercises = workout.orderedExercises
        return List {
            Section {
                WorkoutActiveHeader(workout: workout, weightUnit: weightUnit, focus: $focusedField)
            }
            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                exerciseSection(exercise, position: index, count: exercises.count)
            }
            addExerciseSection(isEmpty: exercises.isEmpty)
            Section {
                Button(role: .destructive) {
                    focusedField = nil
                    showsDiscardConfirmation = true
                } label: {
                    Label("Discard workout", systemImage: "trash")
                        .foregroundStyle(Color.hakiNegative)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
    }

    private func exerciseSection(_ exercise: WorkoutExerciseRecord, position: Int, count: Int) -> some View {
        WorkoutExerciseSection(
            exercise: exercise,
            position: position,
            exerciseCount: count,
            previous: previousSets[exercise.id] ?? [],
            recordSets: recordSets,
            weightUnit: weightUnit,
            distanceUnit: distanceUnit,
            focus: $focusedField,
            onOpenHistory: { openHistory(exercise) },
            onToggleSet: { setRecord in toggle(setRecord, in: exercise) },
            onRemoveSet: { setRecord in removeSet(setRecord) },
            onMove: { offset in move(exercise, by: offset) },
            onRemove: { remove(exercise) }
        )
    }

    private func addExerciseSection(isEmpty: Bool) -> some View {
        Section {
            Button {
                focusedField = nil
                isPickingExercise = true
            } label: {
                Label("Add exercise", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
        } footer: {
            if isEmpty {
                Text("Add your first exercise, then log each set as you go. Tick a set when it's done to start the rest timer.")
            }
        }
    }

    @ViewBuilder
    private var restBar: some View {
        if let restEndsAt {
            WorkoutRestTimerBar(
                endsAt: restEndsAt,
                totalSeconds: restTotalSeconds,
                onAdjust: { delta in adjustRest(by: delta) },
                onSkip: { skipRest() }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                minimize()
            } label: {
                Image(systemName: "chevron.down")
                    .fontWeight(.semibold)
            }
            .accessibilityLabel("Minimize")
            .accessibilityHint("Keeps the workout going. Resume it from the Health tab.")
        }
        ToolbarItem(placement: .principal) {
            WorkoutElapsedText(startedAt: workout.startedAt)
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button("Finish") { requestFinish() }
                .fontWeight(.semibold)
                // Attached here so the popover points at the Finish button.
                .confirmationDialog("Finish workout?", isPresented: $showsFinishConfirmation, titleVisibility: .visible) {
                    Button("Finish workout") { finish() }
                    Button("Keep going", role: .cancel) {}
                } message: {
                    Text(finishMessage)
                }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { focusedField = nil }
        }
    }

    private var finishMessage: String {
        let stats = WorkoutsFormat.statsLine(
            durationSeconds: workout.durationSeconds,
            sets: workout.completedSetCount,
            volumeKg: workout.volumeKg,
            unit: weightUnit
        )
        let hasUnticked = workout.exercises.contains { exercise in exercise.sets.contains { !$0.isCompleted } }
        return hasUnticked ? "\(stats)\n\nSets you haven't ticked will be removed." : stats
    }

    // MARK: Caches

    /// Loads last time's sets for exercises that don't have them yet, and
    /// the records already set by sets ticked before the screen opened.
    private func loadCaches() {
        guard !isGone else { return }
        var previous = previousSets
        var history = historyRecords
        var beaten = recordSets
        var changed = false
        for exercise in workout.exercises {
            if previous[exercise.id] == nil {
                previous[exercise.id] = WorkoutStore.previousSets(exerciseKey: exercise.exerciseKey, before: workout.startedAt, in: modelContext)
                changed = true
            }
            if history[exercise.id] == nil, exercise.sets.contains(where: { $0.isCompleted }) {
                let records = WorkoutStore.records(exerciseKey: exercise.exerciseKey, kind: exercise.kind, before: workout.startedAt, in: modelContext)
                history[exercise.id] = records
                let found = WorkoutsRecordMath.recordSets(exercise.orderedSets, kind: exercise.kind, history: records, date: workout.startedAt)
                for (id, kinds) in found { beaten[id] = kinds }
                changed = true
            }
        }
        guard changed else { return }
        previousSets = previous
        historyRecords = history
        recordSets = beaten
    }

    private func historyRecord(for exercise: WorkoutExerciseRecord) -> PersonalRecords {
        if let cached = historyRecords[exercise.id] { return cached }
        let records = WorkoutStore.records(exerciseKey: exercise.exerciseKey, kind: exercise.kind, before: workout.startedAt, in: modelContext)
        historyRecords[exercise.id] = records
        return records
    }

    // MARK: Sets

    private func toggle(_ setRecord: WorkoutSetRecord, in exercise: WorkoutExerciseRecord) {
        guard !setRecord.isDeleted, setRecord.modelContext != nil else { return }
        focusedField = nil
        let isDone = WorkoutStore.toggleCompleted(setRecord, in: modelContext)
        guard isDone else {
            recordSets[setRecord.id] = nil
            return
        }
        let beaten = newRecords(for: setRecord, in: exercise)
        if beaten.isEmpty {
            recordSets[setRecord.id] = nil
        } else {
            recordSets[setRecord.id] = beaten
            recordFeedback += 1
            UIAccessibility.post(notification: .announcement, argument: "New personal record")
        }
        startRest(for: exercise)
    }

    /// Records this set beats: earlier workouts plus the other sets already
    /// ticked today, so only the best set of the day wears the medal.
    private func newRecords(for setRecord: WorkoutSetRecord, in exercise: WorkoutExerciseRecord) -> Set<RecordKind> {
        let countsWeight = exercise.kind.countsWeightForRecords
        let others = exercise.orderedSets
            .filter { $0.id != setRecord.id && $0.isCompleted }
            .map(\.values)
        let session = WorkoutMath.records([ExercisePerformance(date: workout.startedAt, sets: others)], countsWeight: countsWeight)
        let baseline = WorkoutsRecordMath.merged(history: historyRecord(for: exercise), session: session)
        return WorkoutMath.newRecords(for: setRecord.values, previous: baseline, countsWeight: countsWeight)
    }

    private func removeSet(_ setRecord: WorkoutSetRecord) {
        focusedField = nil
        recordSets[setRecord.id] = nil
        withAnimation(.snappy) {
            WorkoutStore.removeSet(setRecord, in: modelContext)
        }
    }

    // MARK: Exercises

    private func add(_ definition: ExerciseDefinition) {
        withAnimation(.snappy) {
            _ = WorkoutStore.addExercise(definition, to: workout, in: modelContext)
        }
        loadCaches()
    }

    private func openHistory(_ exercise: WorkoutExerciseRecord) {
        focusedField = nil
        historyTarget = WorkoutHistoryTarget(key: exercise.exerciseKey, name: exercise.name)
    }

    private func move(_ exercise: WorkoutExerciseRecord, by offset: Int) {
        let ordered = workout.orderedExercises
        guard let index = ordered.firstIndex(where: { $0.id == exercise.id }) else { return }
        let target = index + offset
        guard target >= 0, target < ordered.count else { return }
        // `move(fromOffsets:toOffset:)` counts the destination before removal.
        let destination = offset > 0 ? target + 1 : target
        withAnimation(.snappy) {
            WorkoutStore.moveExercises(in: workout, from: IndexSet(integer: index), to: destination, in: modelContext)
        }
    }

    private func remove(_ exercise: WorkoutExerciseRecord) {
        focusedField = nil
        for setRecord in exercise.sets {
            recordSets[setRecord.id] = nil
        }
        previousSets[exercise.id] = nil
        historyRecords[exercise.id] = nil
        withAnimation(.snappy) {
            WorkoutStore.removeExercise(exercise, in: modelContext)
        }
    }

    // MARK: Rest timer

    private func startRest(for exercise: WorkoutExerciseRecord) {
        guard restTimerEnabled, exercise.restSeconds > 0 else { return }
        restTotalSeconds = exercise.restSeconds
        withAnimation(.snappy) {
            restEndsAt = Date.now.addingTimeInterval(TimeInterval(exercise.restSeconds))
        }
    }

    private func adjustRest(by delta: Int) {
        guard let end = restEndsAt else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(delta))
        guard newEnd.timeIntervalSinceNow > 0.5 else {
            skipRest()
            return
        }
        if delta > 0 { restTotalSeconds += delta }
        restEndsAt = newEnd
    }

    private func skipRest() {
        withAnimation(.snappy) {
            restEndsAt = nil
        }
    }

    /// Keeps the running rest outside the screen, so minimizing and resuming
    /// the workout shows it again; cleared when the rest ends or is skipped.
    private func rememberRest(endingAt end: Date?) {
        if let end, !isGone {
            WorkoutRestCountdown.current = WorkoutRestCountdown(workoutID: workout.id, endsAt: end, totalSeconds: restTotalSeconds)
        } else {
            WorkoutRestCountdown.current = nil
        }
    }

    /// Picks up the rest that was running when this workout was minimized.
    private func restoreRest() {
        guard restEndsAt == nil, !isGone, let saved = WorkoutRestCountdown.current,
              saved.workoutID == workout.id, saved.endsAt.timeIntervalSinceNow > 0.5 else { return }
        restTotalSeconds = saved.totalSeconds
        restEndsAt = saved.endsAt
    }

    /// Waits for the current rest to end (restarted whenever the end moves).
    private func runRestTimer() async {
        guard let end = restEndsAt else { return }
        let wait = end.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait))
        }
        guard !Task.isCancelled, restEndsAt == end else { return }
        restDoneFeedback += 1
        UIAccessibility.post(notification: .announcement, argument: "Rest is over")
        withAnimation(.snappy) {
            restEndsAt = nil
        }
    }

    // MARK: Finish, discard, minimize

    private var hasCompletedSet: Bool {
        workout.exercises.contains { exercise in exercise.sets.contains { $0.isCompleted } }
    }

    private func requestFinish() {
        focusedField = nil
        WorkoutStore.save(in: modelContext)
        if hasCompletedSet {
            showsFinishConfirmation = true
        } else {
            showsNoSetsAlert = true
        }
    }

    private func finish() {
        focusedField = nil
        if workout.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            workout.title = WorkoutStore.defaultTitle(for: workout.startedAt)
        }
        let completedIDs = Set(workout.exercises.flatMap { exercise in exercise.sets.filter { $0.isCompleted }.map(\.id) })
        let summary = WorkoutFinishSummary(
            title: workout.title,
            durationSeconds: workout.durationSeconds,
            volumeKg: workout.volumeKg,
            setCount: workout.completedSetCount,
            exerciseCount: workout.exercises.filter { exercise in exercise.sets.contains { $0.isCompleted } }.count,
            recordCount: recordSets.keys.filter { completedIDs.contains($0) }.count
        )
        guard WorkoutStore.finishWorkout(workout, in: modelContext) else {
            showsNoSetsAlert = true
            return
        }
        restEndsAt = nil
        finishFeedback += 1
        withAnimation(.snappy) {
            finishSummary = summary
        }
        postToHevy()
    }

    /// Posts the finished workout to Hevy when that's turned on (the service
    /// checks); the summary shows progress meanwhile.
    private func postToHevy() {
        let finished = workout
        let context = modelContext
        let shouldPost = hevy.isConnected && hevy.uploadEnabled
        isPostingToHevy = shouldPost
        hevyPostFailed = false
        Task {
            await hevy.uploadIfEnabled(finished, in: context)
            isPostingToHevy = false
            // `uploadIfEnabled` never throws; a workout still without a Hevy
            // id afterwards wasn't posted (the reason is in `hevy.lastError`).
            if shouldPost, !finished.isDeleted, finished.modelContext != nil, finished.hevyID == nil {
                hevyPostFailed = true
            }
        }
    }

    private func discard() {
        focusedField = nil
        restEndsAt = nil
        deletesWhenClosed = true
        isClosing = true
        dismiss()
    }

    private func minimize() {
        focusedField = nil
        if !isGone { WorkoutStore.save(in: modelContext) }
        dismiss()
    }

    /// Runs once the screen is gone: deletes a discarded workout, or saves.
    private func closeUp() {
        if deletesWhenClosed {
            deletesWhenClosed = false
            guard !workout.isDeleted, workout.modelContext != nil else { return }
            WorkoutStore.deleteWorkout(workout, in: modelContext)
        } else if !workout.isDeleted, workout.modelContext != nil {
            WorkoutStore.save(in: modelContext)
        }
    }
}

// MARK: - Header

/// The editable name and the totals so far.
private struct WorkoutActiveHeader: View {
    @Bindable var workout: WorkoutRecord
    let weightUnit: WeightUnit
    let focus: FocusState<WorkoutSetFocus?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Workout name", text: $workout.title)
                .font(.title2.weight(.bold))
                .submitLabel(.done)
                .focused(focus, equals: .title)
                .accessibilityLabel("Workout name")
            HStack(spacing: 12) {
                WorkoutsStatTile(title: "Volume", value: WorkoutsFormat.volume(workout.volumeKg, unit: weightUnit))
                WorkoutsStatTile(title: "Sets done", value: "\(workout.completedSetCount)")
                WorkoutsStatTile(title: "Exercises", value: "\(workout.exercises.count)")
            }
        }
        .padding(.vertical, 4)
    }
}

/// The elapsed time in the navigation bar, ticking every second.
private struct WorkoutElapsedText: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let seconds = Int(max(0, context.date.timeIntervalSince(startedAt)))
            Label(WorkoutMath.formatTimer(seconds: seconds), systemImage: "stopwatch")
                .labelStyle(.titleAndIcon)
                .font(.headline)
                .monospacedDigit()
                .accessibilityLabel("Elapsed time, \(WorkoutMath.formatTimer(seconds: seconds))")
        }
    }
}

/// An exercise whose history is pushed from the workout.
private struct WorkoutHistoryTarget: Hashable {
    let key: String
    let name: String
}

/// The rest countdown of the workout being logged, kept while the screen is
/// minimized so resuming shows it again.
private struct WorkoutRestCountdown {
    var workoutID: UUID
    var endsAt: Date
    var totalSeconds: Int
    static var current: WorkoutRestCountdown?
}

// MARK: - Finished

/// What the summary after finishing shows. Captured before the workout is
/// finished, since finishing drops unticked sets.
struct WorkoutFinishSummary: Equatable {
    let title: String
    let durationSeconds: Int
    let volumeKg: Double
    let setCount: Int
    let exerciseCount: Int
    let recordCount: Int
}

/// "Workout saved": duration, volume, sets and records.
private struct WorkoutFinishedView: View {
    let summary: WorkoutFinishSummary
    let weightUnit: WeightUnit
    let hevyStatus: String?
    let onDone: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var iconSize: CGFloat = 64

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                hero
                stats
                if summary.recordCount > 0 {
                    recordsLine
                }
                if let hevyStatus {
                    Label(hevyStatus, systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal)
            .padding(.top, 32)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .safeAreaInset(edge: .bottom) {
            Button(action: onDone) {
                Text("Done")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .navigationTitle("Workout saved")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: iconSize))
                .foregroundStyle(Color.hakiPositive)
                .accessibilityHidden(true)
            Text("Nice work!")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
            Text(summary.title)
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    private var stats: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                WorkoutsStatTile(title: "Duration", value: WorkoutMath.formatDuration(seconds: summary.durationSeconds))
                WorkoutsStatTile(title: "Volume", value: WorkoutsFormat.volume(summary.volumeKg, unit: weightUnit))
            }
            HStack(spacing: 16) {
                WorkoutsStatTile(title: "Sets", value: "\(summary.setCount)")
                WorkoutsStatTile(title: "Exercises", value: "\(summary.exerciseCount)")
            }
        }
        .hakiCard()
    }

    private var recordsText: String {
        summary.recordCount == 1 ? "1 personal record" : "\(summary.recordCount) personal records"
    }

    private var recordsLine: some View {
        Label(recordsText, systemImage: "trophy.fill")
        .font(.headline)
        .foregroundStyle(Color.hakiWarning)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.14), in: Capsule())
    }
}

// MARK: - Previews

#Preview {
    ActiveWorkoutView(workout: ActiveWorkoutPreviewSupport.workout())
        .previewEnvironment()
}

#Preview("Finished") {
    NavigationStack {
        WorkoutFinishedView(
            summary: WorkoutFinishSummary(title: "Push day", durationSeconds: 3_300, volumeKg: 4_250, setCount: 12, exerciseCount: 3, recordCount: 2),
            weightUnit: .kilograms,
            hevyStatus: "Also posted to Hevy",
            onDone: {}
        )
    }
    .previewEnvironment()
}

private enum ActiveWorkoutPreviewSupport {
    /// A workout in progress, started from the sample routine.
    static func workout() -> WorkoutRecord {
        if let active = WorkoutStore.activeWorkout(in: PreviewData.context) { return active }
        return WorkoutStore.startWorkout(routine: PreviewData.sampleRoutine, in: PreviewData.context)
    }
}
