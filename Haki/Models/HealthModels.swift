//
//  HealthModels.swift
//  Haki
//
//  SwiftData models for food logging and workouts. Same conventions as
//  Models.swift: enums stored as raw strings with typed accessors, a default
//  for every stored property, no unique attributes, and relationships set
//  only through the `FoodStore` / `WorkoutStore` helpers.
//
//  Everything here stays on the device. Weights are kilograms.
//

import Foundation
import SwiftData

// MARK: - Food

nonisolated enum FoodEntrySource: String, CaseIterable, Codable, Sendable {
    /// Typed in by hand.
    case manual
    /// Estimated by Haki's AI from a photo (maybe with a description).
    case aiPhoto
    /// Estimated by Haki's AI from a description only.
    case aiText
    /// Picked from a restaurant menu Haki looked up.
    case menu
    /// A copy of an earlier entry ("Log again").
    case repeatEntry

    var isAIEstimate: Bool {
        switch self {
        case .aiPhoto, .aiText, .menu: true
        case .manual, .repeatEntry: false
        }
    }
}

@Model
final class FoodEntry {
    var id: UUID = UUID()
    /// When it was eaten.
    var eatenAt: Date = Date()
    var mealTypeRaw: String = MealType.snack.rawValue
    var name: String = ""
    /// Everyday amount, e.g. "1 bowl" or "2 slices". May be empty.
    var portion: String = ""
    /// How many of `portion` were eaten; the macros below are already multiplied.
    var servings: Double = 1
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fiberG: Double = 0
    var sourceRaw: String = FoodEntrySource.manual.rawValue
    /// Restaurant or store, for menu items.
    var placeName: String?
    /// `EstimateConfidence` raw value for AI estimates.
    var confidenceRaw: String?
    var notes: String = ""
    /// A small JPEG (about 600 px) of the meal photo, if there was one.
    @Attribute(.externalStorage) var photoData: Data?
    var createdAt: Date = Date()

    init(
        name: String,
        eatenAt: Date = .now,
        mealType: MealType,
        portion: String = "",
        servings: Double = 1,
        macros: Macros,
        source: FoodEntrySource = .manual,
        placeName: String? = nil,
        confidence: EstimateConfidence? = nil,
        notes: String = "",
        photoData: Data? = nil
    ) {
        self.name = name
        self.eatenAt = eatenAt
        self.mealTypeRaw = mealType.rawValue
        self.portion = portion
        self.servings = servings
        self.calories = macros.calories
        self.proteinG = macros.proteinG
        self.carbsG = macros.carbsG
        self.fatG = macros.fatG
        self.fiberG = macros.fiberG
        self.sourceRaw = source.rawValue
        self.placeName = placeName
        self.confidenceRaw = confidence?.rawValue
        self.notes = notes
        self.photoData = photoData
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }

    var source: FoodEntrySource {
        get { FoodEntrySource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var confidence: EstimateConfidence? {
        get { confidenceRaw.flatMap(EstimateConfidence.init(rawValue:)) }
        set { confidenceRaw = newValue?.rawValue }
    }

    var macros: Macros {
        get { Macros(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG) }
        set {
            calories = newValue.calories
            proteinG = newValue.proteinG
            carbsG = newValue.carbsG
            fatG = newValue.fatG
            fiberG = newValue.fiberG
        }
    }
}

// MARK: - Workouts

nonisolated enum WorkoutSource: String, Codable, Sendable {
    /// Logged in Haki.
    case haki
    /// Copied from the person's Hevy account.
    case hevy
}

@Model
final class WorkoutRecord {
    var id: UUID = UUID()
    var title: String = ""
    var startedAt: Date = Date()
    /// Nil while the workout is still being logged.
    var endedAt: Date?
    var notes: String = ""
    var sourceRaw: String = WorkoutSource.haki.rawValue
    /// Hevy's workout id: set for workouts copied from Hevy and for Haki
    /// workouts that were uploaded to Hevy.
    var hevyID: String?
    /// Hevy's `updated_at`, to skip unchanged workouts when syncing.
    var hevyUpdatedAt: Date?
    /// The routine it was started from, if any.
    var routineID: UUID?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \WorkoutExerciseRecord.workout)
    var exercises: [WorkoutExerciseRecord] = []

    init(title: String, startedAt: Date = .now, source: WorkoutSource = .haki, routineID: UUID? = nil) {
        self.title = title
        self.startedAt = startedAt
        self.sourceRaw = source.rawValue
        self.routineID = routineID
    }

    var source: WorkoutSource {
        get { WorkoutSource(rawValue: sourceRaw) ?? .haki }
        set { sourceRaw = newValue.rawValue }
    }

    var isInProgress: Bool { endedAt == nil }

    /// Exercises in the order they were added.
    var orderedExercises: [WorkoutExerciseRecord] {
        exercises.sorted { $0.order < $1.order }
    }

    var durationSeconds: Int {
        Int(max(0, (endedAt ?? .now).timeIntervalSince(startedAt)))
    }

    /// Completed working sets across every exercise.
    var completedSetCount: Int {
        exercises.reduce(0) { $0 + WorkoutMath.workingSets($1.setValues).count }
    }

    /// Weight × reps over completed working sets of weighted exercises.
    var volumeKg: Double {
        exercises.reduce(0) { total, exercise in
            exercise.kind.countsWeightForRecords ? total + WorkoutMath.volumeKg(exercise.setValues) : total
        }
    }
}

@Model
final class WorkoutExerciseRecord {
    var id: UUID = UUID()
    var order: Int = 0
    /// `ExerciseLibrary` key, "custom:<uuid>" for a custom exercise, or
    /// "hevy:<template id>" for an exercise copied from Hevy.
    var exerciseKey: String = ""
    var name: String = ""
    var primaryMuscleRaw: String = MuscleGroup.other.rawValue
    var equipmentRaw: String = Equipment.other.rawValue
    var kindRaw: String = ExerciseKind.weightReps.rawValue
    var notes: String = ""
    var restSeconds: Int = 90
    /// Exercises with the same number are done back to back.
    var supersetGroup: Int?
    /// Hevy's template id, when known (needed to upload to Hevy).
    var hevyTemplateID: String?
    var workout: WorkoutRecord?

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSetRecord.exercise)
    var sets: [WorkoutSetRecord] = []

    init(order: Int, exerciseKey: String, name: String, primaryMuscle: MuscleGroup, equipment: Equipment, kind: ExerciseKind, restSeconds: Int) {
        self.order = order
        self.exerciseKey = exerciseKey
        self.name = name
        self.primaryMuscleRaw = primaryMuscle.rawValue
        self.equipmentRaw = equipment.rawValue
        self.kindRaw = kind.rawValue
        self.restSeconds = restSeconds
    }

    var primaryMuscle: MuscleGroup {
        get { MuscleGroup(rawValue: primaryMuscleRaw) ?? .other }
        set { primaryMuscleRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var kind: ExerciseKind {
        get { ExerciseKind(rawValue: kindRaw) ?? .weightReps }
        set { kindRaw = newValue.rawValue }
    }

    var orderedSets: [WorkoutSetRecord] {
        sets.sorted { $0.order < $1.order }
    }

    var setValues: [SetValues] { orderedSets.map(\.values) }
}

@Model
final class WorkoutSetRecord {
    var id: UUID = UUID()
    var order: Int = 0
    var kindRaw: String = SetKind.normal.rawValue
    var weightKg: Double?
    var reps: Int?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var rpe: Double?
    var isCompleted: Bool = false
    var completedAt: Date?
    var exercise: WorkoutExerciseRecord?

    init(order: Int, kind: SetKind = .normal, weightKg: Double? = nil, reps: Int? = nil, durationSeconds: Int? = nil, distanceMeters: Double? = nil) {
        self.order = order
        self.kindRaw = kind.rawValue
        self.weightKg = weightKg
        self.reps = reps
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
    }

    var kind: SetKind {
        get { SetKind(rawValue: kindRaw) ?? .normal }
        set { kindRaw = newValue.rawValue }
    }

    var values: SetValues {
        SetValues(
            kind: kind, weightKg: weightKg, reps: reps, durationSeconds: durationSeconds,
            distanceMeters: distanceMeters, rpe: rpe, isCompleted: isCompleted
        )
    }
}

// MARK: - Routines and custom exercises

@Model
final class RoutineRecord {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var lastUsedAt: Date?
    var sortOrder: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \RoutineExerciseRecord.routine)
    var exercises: [RoutineExerciseRecord] = []

    init(name: String, notes: String = "", sortOrder: Int = 0) {
        self.name = name
        self.notes = notes
        self.sortOrder = sortOrder
    }

    var orderedExercises: [RoutineExerciseRecord] {
        exercises.sorted { $0.order < $1.order }
    }
}

@Model
final class RoutineExerciseRecord {
    var id: UUID = UUID()
    var order: Int = 0
    var exerciseKey: String = ""
    var name: String = ""
    var primaryMuscleRaw: String = MuscleGroup.other.rawValue
    var equipmentRaw: String = Equipment.other.rawValue
    var kindRaw: String = ExerciseKind.weightReps.rawValue
    var targetSets: Int = 3
    /// Rep range shown as a hint, e.g. 8–12. Nil for timed exercises.
    var targetRepsLow: Int?
    var targetRepsHigh: Int?
    var restSeconds: Int = 90
    var hevyTemplateID: String?
    var routine: RoutineRecord?

    init(order: Int, exerciseKey: String, name: String, primaryMuscle: MuscleGroup, equipment: Equipment, kind: ExerciseKind, targetSets: Int = 3, targetRepsLow: Int? = 8, targetRepsHigh: Int? = 12, restSeconds: Int = 90) {
        self.order = order
        self.exerciseKey = exerciseKey
        self.name = name
        self.primaryMuscleRaw = primaryMuscle.rawValue
        self.equipmentRaw = equipment.rawValue
        self.kindRaw = kind.rawValue
        self.targetSets = targetSets
        self.targetRepsLow = targetRepsLow
        self.targetRepsHigh = targetRepsHigh
        self.restSeconds = restSeconds
    }

    var primaryMuscle: MuscleGroup {
        get { MuscleGroup(rawValue: primaryMuscleRaw) ?? .other }
        set { primaryMuscleRaw = newValue.rawValue }
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var kind: ExerciseKind {
        get { ExerciseKind(rawValue: kindRaw) ?? .weightReps }
        set { kindRaw = newValue.rawValue }
    }
}

@Model
final class CustomExerciseRecord {
    var id: UUID = UUID()
    var name: String = ""
    var primaryMuscleRaw: String = MuscleGroup.other.rawValue
    var equipmentRaw: String = Equipment.other.rawValue
    var kindRaw: String = ExerciseKind.weightReps.rawValue
    var createdAt: Date = Date()

    init(name: String, primaryMuscle: MuscleGroup, equipment: Equipment, kind: ExerciseKind) {
        self.name = name
        self.primaryMuscleRaw = primaryMuscle.rawValue
        self.equipmentRaw = equipment.rawValue
        self.kindRaw = kind.rawValue
    }

    /// The key logged exercises store for this custom exercise.
    var exerciseKey: String { "custom:\(id.uuidString)" }

    var definition: ExerciseDefinition {
        ExerciseDefinition(
            exerciseKey, name,
            MuscleGroup(rawValue: primaryMuscleRaw) ?? .other, [],
            Equipment(rawValue: equipmentRaw) ?? .other,
            ExerciseKind(rawValue: kindRaw) ?? .weightReps
        )
    }
}
