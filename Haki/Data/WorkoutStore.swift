//
//  WorkoutStore.swift
//  Haki
//
//  Every write to workouts, routines and custom exercises goes through these
//  helpers (see LedgerStore): they insert models before relating them and
//  keep `order` values contiguous. Screens read with @Query.
//

import Foundation
import SwiftData
import SwiftUI // MutableCollection.move(fromOffsets:toOffset:)

enum WorkoutStore {
    // MARK: Exercises available to log

    /// Built-in exercises plus the person's custom ones, sorted by name.
    static func allExercises(in context: ModelContext) -> [ExerciseDefinition] {
        let custom = ((try? context.fetch(FetchDescriptor<CustomExerciseRecord>())) ?? []).map(\.definition)
        return (ExerciseLibrary.all + custom).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func definition(forKey key: String, in context: ModelContext) -> ExerciseDefinition? {
        if let builtIn = ExerciseLibrary.exercise(key: key) { return builtIn }
        let custom = (try? context.fetch(FetchDescriptor<CustomExerciseRecord>())) ?? []
        return custom.first { $0.exerciseKey == key }?.definition
    }

    @discardableResult
    static func createCustomExercise(name: String, primaryMuscle: MuscleGroup, equipment: Equipment, kind: ExerciseKind, in context: ModelContext) -> CustomExerciseRecord {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = CustomExerciseRecord(name: trimmed.isEmpty ? "Custom exercise" : trimmed, primaryMuscle: primaryMuscle, equipment: equipment, kind: kind)
        context.insert(record)
        LedgerStore.save(context)
        return record
    }

    static func deleteCustomExercise(_ record: CustomExerciseRecord, in context: ModelContext) {
        // Logged workouts keep their own copy of the name, so history stays.
        context.delete(record)
        LedgerStore.save(context)
    }

    // MARK: Active workout

    /// The Haki workout currently being logged, if any (the newest one).
    static func activeWorkout(in context: ModelContext) -> WorkoutRecord? {
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.endedAt == nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Starts a workout, empty or from `routine` (its exercises with their
    /// target number of sets, filled in with what was lifted last time).
    @discardableResult
    static func startWorkout(title: String? = nil, routine: RoutineRecord? = nil, now: Date = .now, in context: ModelContext) -> WorkoutRecord {
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let workout = WorkoutRecord(
            title: (name?.isEmpty == false ? name : nil) ?? routine?.name ?? defaultTitle(for: now),
            startedAt: now,
            routineID: routine?.id
        )
        context.insert(workout)
        if let routine {
            routine.lastUsedAt = now
            for (index, planned) in routine.orderedExercises.enumerated() {
                let exercise = WorkoutExerciseRecord(
                    order: index, exerciseKey: planned.exerciseKey, name: planned.name,
                    primaryMuscle: planned.primaryMuscle, equipment: planned.equipment,
                    kind: planned.kind, restSeconds: planned.restSeconds
                )
                context.insert(exercise)
                exercise.hevyTemplateID = planned.hevyTemplateID
                exercise.workout = workout
                let previous = previousSets(exerciseKey: planned.exerciseKey, before: now, in: context)
                for setIndex in 0..<max(planned.targetSets, 1) {
                    let template = setIndex < previous.count ? previous[setIndex] : previous.last
                    let set = WorkoutSetRecord(
                        order: setIndex,
                        kind: template?.kind == .warmup ? .warmup : .normal,
                        weightKg: template?.weightKg,
                        reps: template?.reps ?? planned.targetRepsHigh,
                        durationSeconds: template?.durationSeconds,
                        distanceMeters: template?.distanceMeters
                    )
                    context.insert(set)
                    set.exercise = exercise
                }
            }
        }
        LedgerStore.save(context)
        return workout
    }

    /// "Morning workout", "Afternoon workout", "Evening workout".
    static func defaultTitle(for date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 4..<12: return "Morning workout"
        case 12..<17: return "Afternoon workout"
        default: return "Evening workout"
        }
    }

    /// Adds `definition` at the end of `workout` with as many sets as last
    /// time (at least one), prefilled with last time's numbers.
    @discardableResult
    static func addExercise(_ definition: ExerciseDefinition, to workout: WorkoutRecord, in context: ModelContext) -> WorkoutExerciseRecord {
        let exercise = WorkoutExerciseRecord(
            order: (workout.exercises.map(\.order).max() ?? -1) + 1,
            exerciseKey: definition.key, name: definition.name,
            primaryMuscle: definition.primaryMuscle, equipment: definition.equipment,
            kind: definition.kind, restSeconds: definition.defaultRestSeconds
        )
        context.insert(exercise)
        exercise.workout = workout
        let previous = previousSets(exerciseKey: definition.key, before: workout.startedAt, in: context)
        let templates: [SetValues?] = previous.isEmpty ? [nil] : previous.map { Optional($0) }
        for (index, template) in templates.enumerated() {
            let set = WorkoutSetRecord(
                order: index,
                kind: template?.kind ?? .normal,
                weightKg: template?.weightKg,
                reps: template?.reps,
                durationSeconds: template?.durationSeconds,
                distanceMeters: template?.distanceMeters
            )
            context.insert(set)
            set.exercise = exercise
        }
        LedgerStore.save(context)
        return exercise
    }

    /// Adds a set copying the last set's numbers (not its completion).
    @discardableResult
    static func addSet(to exercise: WorkoutExerciseRecord, in context: ModelContext) -> WorkoutSetRecord {
        let last = exercise.orderedSets.last
        let set = WorkoutSetRecord(
            order: (last?.order ?? -1) + 1,
            kind: last?.kind == .warmup ? .normal : (last?.kind ?? .normal),
            weightKg: last?.weightKg,
            reps: last?.reps,
            durationSeconds: last?.durationSeconds,
            distanceMeters: last?.distanceMeters
        )
        context.insert(set)
        set.exercise = exercise
        LedgerStore.save(context)
        return set
    }

    static func removeSet(_ set: WorkoutSetRecord, in context: ModelContext) {
        let exercise = set.exercise
        let removedID = set.id
        context.delete(set)
        if let exercise {
            for (index, remaining) in exercise.orderedSets.filter({ $0.id != removedID }).enumerated() {
                remaining.order = index
            }
        }
        LedgerStore.save(context)
    }

    static func removeExercise(_ exercise: WorkoutExerciseRecord, in context: ModelContext) {
        let workout = exercise.workout
        let removedID = exercise.id
        context.delete(exercise)
        if let workout {
            for (index, remaining) in workout.orderedExercises.filter({ $0.id != removedID }).enumerated() {
                remaining.order = index
            }
        }
        LedgerStore.save(context)
    }

    /// Reorders like `List.onMove`.
    static func moveExercises(in workout: WorkoutRecord, from source: IndexSet, to destination: Int, in context: ModelContext) {
        var ordered = workout.orderedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, exercise) in ordered.enumerated() { exercise.order = index }
        LedgerStore.save(context)
    }

    /// Ticks or unticks a set. Returns true when it is now completed.
    @discardableResult
    static func toggleCompleted(_ set: WorkoutSetRecord, now: Date = .now, in context: ModelContext) -> Bool {
        set.isCompleted.toggle()
        set.completedAt = set.isCompleted ? now : nil
        LedgerStore.save(context)
        return set.isCompleted
    }

    /// Saves edits made directly on a set, exercise or workout.
    static func save(in context: ModelContext) {
        LedgerStore.save(context)
    }

    /// Finishes `workout`: drops unticked sets and exercises left with no
    /// sets, then stamps the end time. Returns false (and changes nothing)
    /// when no set was completed; offer to discard instead.
    @discardableResult
    static func finishWorkout(_ workout: WorkoutRecord, now: Date = .now, in context: ModelContext) -> Bool {
        guard workout.exercises.contains(where: { $0.sets.contains(where: \.isCompleted) }) else { return false }
        for exercise in workout.exercises {
            for set in exercise.sets where !set.isCompleted { context.delete(set) }
        }
        let kept = workout.orderedExercises.filter { $0.sets.contains(where: \.isCompleted) }
        for exercise in workout.exercises where !kept.contains(where: { $0.id == exercise.id }) {
            context.delete(exercise)
        }
        for (index, exercise) in kept.enumerated() {
            exercise.order = index
            for (setIndex, set) in exercise.orderedSets.filter(\.isCompleted).enumerated() { set.order = setIndex }
        }
        workout.endedAt = max(now, workout.startedAt)
        LedgerStore.save(context)
        return true
    }

    static func deleteWorkout(_ workout: WorkoutRecord, in context: ModelContext) {
        context.delete(workout)
        LedgerStore.save(context)
    }

    // MARK: History

    /// Finished workouts' sets for `exerciseKey`, newest first, each with its date.
    static func performances(exerciseKey: String, in context: ModelContext) -> [ExercisePerformance] {
        let key = exerciseKey
        let descriptor = FetchDescriptor<WorkoutExerciseRecord>(predicate: #Predicate { $0.exerciseKey == key })
        let logged = (try? context.fetch(descriptor)) ?? []
        return logged
            .compactMap { exercise -> ExercisePerformance? in
                guard let workout = exercise.workout, workout.endedAt != nil else { return nil }
                return ExercisePerformance(date: workout.startedAt, sets: exercise.setValues)
            }
            .sorted { $0.date > $1.date }
    }

    /// The sets from the most recent finished workout before `date` that
    /// included `exerciseKey` (the "previous" column), or [].
    static func previousSets(exerciseKey: String, before date: Date, in context: ModelContext) -> [SetValues] {
        performances(exerciseKey: exerciseKey, in: context).first { $0.date < date }?.sets ?? []
    }

    /// Records from finished workouts before `date` (so the workout being
    /// logged doesn't count against itself).
    static func records(exerciseKey: String, kind: ExerciseKind, before date: Date, in context: ModelContext) -> PersonalRecords {
        let earlier = performances(exerciseKey: exerciseKey, in: context).filter { $0.date < date }
        return WorkoutMath.records(earlier, countsWeight: kind.countsWeightForRecords)
    }

    // MARK: Routines

    @discardableResult
    static func createRoutine(name: String, exercises: [ExerciseDefinition] = [], in context: ModelContext) -> RoutineRecord {
        let existing = (try? context.fetchCount(FetchDescriptor<RoutineRecord>())) ?? 0
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let routine = RoutineRecord(name: trimmed.isEmpty ? "New routine" : trimmed, sortOrder: existing)
        context.insert(routine)
        for definition in exercises {
            addExercise(definition, to: routine, saving: false, in: context)
        }
        LedgerStore.save(context)
        return routine
    }

    /// A routine with `workout`'s exercises, set counts and rep ranges.
    @discardableResult
    static func saveAsRoutine(_ workout: WorkoutRecord, name: String, in context: ModelContext) -> RoutineRecord {
        let routine = createRoutine(name: name, in: context)
        for (index, exercise) in workout.orderedExercises.enumerated() {
            let reps = exercise.orderedSets.compactMap(\.reps)
            let planned = RoutineExerciseRecord(
                order: index, exerciseKey: exercise.exerciseKey, name: exercise.name,
                primaryMuscle: exercise.primaryMuscle, equipment: exercise.equipment, kind: exercise.kind,
                targetSets: max(exercise.sets.filter { $0.kind != .warmup }.count, 1),
                targetRepsLow: reps.min(), targetRepsHigh: reps.max(),
                restSeconds: exercise.restSeconds
            )
            context.insert(planned)
            planned.hevyTemplateID = exercise.hevyTemplateID
            planned.routine = routine
        }
        LedgerStore.save(context)
        return routine
    }

    @discardableResult
    static func addExercise(_ definition: ExerciseDefinition, to routine: RoutineRecord, saving: Bool = true, in context: ModelContext) -> RoutineExerciseRecord {
        let timed = definition.kind.logsDuration && !definition.kind.logsReps
        let planned = RoutineExerciseRecord(
            order: (routine.exercises.map(\.order).max() ?? -1) + 1,
            exerciseKey: definition.key, name: definition.name,
            primaryMuscle: definition.primaryMuscle, equipment: definition.equipment, kind: definition.kind,
            targetSets: 3,
            targetRepsLow: timed ? nil : 8,
            targetRepsHigh: timed ? nil : 12,
            restSeconds: definition.defaultRestSeconds
        )
        context.insert(planned)
        planned.routine = routine
        if saving { LedgerStore.save(context) }
        return planned
    }

    static func removeExercise(_ planned: RoutineExerciseRecord, in context: ModelContext) {
        let routine = planned.routine
        let removedID = planned.id
        context.delete(planned)
        if let routine {
            for (index, remaining) in routine.orderedExercises.filter({ $0.id != removedID }).enumerated() {
                remaining.order = index
            }
        }
        LedgerStore.save(context)
    }

    static func moveExercises(in routine: RoutineRecord, from source: IndexSet, to destination: Int, in context: ModelContext) {
        var ordered = routine.orderedExercises
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, planned) in ordered.enumerated() { planned.order = index }
        LedgerStore.save(context)
    }

    static func deleteRoutine(_ routine: RoutineRecord, in context: ModelContext) {
        context.delete(routine)
        LedgerStore.save(context)
    }

    // MARK: Hevy

    /// The workout copied from (or uploaded to) Hevy with this id.
    static func workout(hevyID: String, in context: ModelContext) -> WorkoutRecord? {
        let target: String? = hevyID
        var descriptor = FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.hevyID == target })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Inserts or replaces the local copy of a Hevy workout. A Haki workout
    /// that was uploaded to Hevy is left alone (Haki's copy is the original).
    /// `templates` maps Hevy template ids to templates, for muscle and kind.
    /// Returns true when something changed. Doesn't save; call `save(in:)`
    /// after a batch.
    @discardableResult
    static func upsertHevyWorkout(_ remote: HevyWorkout, templates: [String: HevyExerciseTemplate], in context: ModelContext) -> Bool {
        guard let start = remote.startDate else { return false }
        let updated = remote.updatedDate
        let target: WorkoutRecord
        if let existing = Self.workout(hevyID: remote.id, in: context) {
            guard existing.source == .hevy else { return false }
            if let updated, let known = existing.hevyUpdatedAt, updated <= known { return false }
            for exercise in existing.exercises { context.delete(exercise) }
            target = existing
        } else {
            target = WorkoutRecord(title: remote.title, startedAt: start, source: .hevy)
            context.insert(target)
            target.hevyID = remote.id
        }
        target.title = remote.title
        target.startedAt = start
        target.endedAt = max(remote.endDate ?? start, start)
        target.notes = remote.description ?? ""
        target.hevyUpdatedAt = updated

        let sortedExercises = remote.exercises.enumerated().sorted { ($0.element.index ?? $0.offset) < ($1.element.index ?? $1.offset) }
        for (order, item) in sortedExercises.enumerated() {
            let remoteExercise = item.element
            let template = remoteExercise.exerciseTemplateID.flatMap { templates[$0] }
            let builtIn = ExerciseLibrary.builtIn(matchingTitle: template?.title ?? remoteExercise.title)
            let exercise = WorkoutExerciseRecord(
                order: order,
                // Use the built-in key when the title matches one, so history and
                // records line up with workouts logged in Haki.
                exerciseKey: builtIn?.key ?? "hevy:\(remoteExercise.exerciseTemplateID ?? remoteExercise.title)",
                name: remoteExercise.title,
                primaryMuscle: template?.muscle ?? builtIn?.primaryMuscle ?? .other,
                equipment: template?.equipmentValue ?? builtIn?.equipment ?? .other,
                kind: template?.kind ?? builtIn?.kind ?? inferredKind(remoteExercise.sets),
                restSeconds: builtIn?.defaultRestSeconds ?? 90
            )
            context.insert(exercise)
            exercise.notes = remoteExercise.notes ?? ""
            exercise.supersetGroup = remoteExercise.supersetID
            exercise.hevyTemplateID = remoteExercise.exerciseTemplateID
            exercise.workout = target
            let sortedSets = remoteExercise.sets.enumerated().sorted { ($0.element.index ?? $0.offset) < ($1.element.index ?? $1.offset) }
            for (setOrder, setItem) in sortedSets.enumerated() {
                let values = setItem.element.values
                let set = WorkoutSetRecord(
                    order: setOrder, kind: values.kind, weightKg: values.weightKg, reps: values.reps,
                    durationSeconds: values.durationSeconds, distanceMeters: values.distanceMeters
                )
                context.insert(set)
                set.rpe = values.rpe
                set.isCompleted = true
                set.completedAt = target.endedAt
                set.exercise = exercise
            }
        }
        return true
    }

    /// What a Hevy exercise without a known template logs, from its sets.
    private static func inferredKind(_ sets: [HevySet]) -> ExerciseKind {
        let hasWeight = sets.contains { ($0.weightKg ?? 0) > 0 }
        let hasReps = sets.contains { ($0.reps ?? 0) > 0 }
        let hasDistance = sets.contains { ($0.distanceMeters ?? 0) > 0 }
        let hasDuration = sets.contains { ($0.durationSeconds ?? 0) > 0 }
        if hasDistance { return .distanceDuration }
        if hasWeight && hasReps { return .weightReps }
        if hasReps { return .repsOnly }
        if hasDuration { return hasWeight ? .weightDuration : .duration }
        return .weightReps
    }

    /// Removes the local copy of a workout deleted in Hevy (only copies; a
    /// Haki workout that was uploaded keeps existing and just forgets the link).
    static func removeHevyWorkout(hevyID: String, in context: ModelContext) {
        guard let workout = Self.workout(hevyID: hevyID, in: context) else { return }
        if workout.source == .hevy {
            context.delete(workout)
        } else {
            workout.hevyID = nil
        }
    }

    /// Remembers that a Haki workout now exists in Hevy too.
    static func markUploaded(_ workout: WorkoutRecord, hevyID: String, updatedAt: Date?, in context: ModelContext) {
        workout.hevyID = hevyID
        workout.hevyUpdatedAt = updatedAt
        LedgerStore.save(context)
    }

    /// Removes every workout copied from Hevy (when disconnecting).
    static func removeAllHevyCopies(in context: ModelContext) {
        let hevy = WorkoutSource.hevy.rawValue
        let copies = (try? context.fetch(FetchDescriptor<WorkoutRecord>(predicate: #Predicate { $0.sourceRaw == hevy }))) ?? []
        for workout in copies { context.delete(workout) }
        LedgerStore.save(context)
    }

    static func eraseAll(in context: ModelContext) {
        for workout in (try? context.fetch(FetchDescriptor<WorkoutRecord>())) ?? [] { context.delete(workout) }
        for routine in (try? context.fetch(FetchDescriptor<RoutineRecord>())) ?? [] { context.delete(routine) }
        for custom in (try? context.fetch(FetchDescriptor<CustomExerciseRecord>())) ?? [] { context.delete(custom) }
        LedgerStore.save(context)
    }
}
