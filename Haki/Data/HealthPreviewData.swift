//
//  HealthPreviewData.swift
//  Haki
//
//  Sample meals, workouts and a routine for previews (added to
//  `PreviewData.container`), plus accessors for model-taking previews.
//

import Foundation
import SwiftData

extension PreviewData {
    /// A meal logged today.
    static var sampleFoodEntry: FoodEntry {
        let descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.eatenAt, order: .reverse)])
        if let entry = try? context.fetch(descriptor).first { return entry }
        return FoodStore.add(name: "Greek yogurt bowl", mealType: .breakfast, macros: Macros(calories: 320, proteinG: 24, carbsG: 38, fatG: 8, fiberG: 4), in: context)
    }

    /// A finished workout.
    static var sampleWorkout: WorkoutRecord {
        let descriptor = FetchDescriptor<WorkoutRecord>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        if let workout = try? context.fetch(descriptor).first(where: { !$0.isInProgress }) { return workout }
        let workout = WorkoutStore.startWorkout(title: "Push day", in: context)
        return workout
    }

    /// A routine with a few exercises.
    static var sampleRoutine: RoutineRecord {
        if let routine = try? context.fetch(FetchDescriptor<RoutineRecord>()).first { return routine }
        return WorkoutStore.createRoutine(name: "Push day", in: context)
    }

    /// Adds a day of meals and two weeks of workouts.
    static func loadHealthSamples(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0, daysAgo: Int = 0) -> Date {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
        }

        let meals: [(String, MealType, Macros, FoodEntrySource, Int, Int)] = [
            ("Greek yogurt bowl", .breakfast, Macros(calories: 320, proteinG: 24, carbsG: 38, fatG: 8, fiberG: 4), .manual, 8, 0),
            ("Chicken burrito bowl", .lunch, FoodAIPreviewSamples.meal.total, .aiPhoto, 12, 0),
            ("Protein shake", .snack, Macros(calories: 160, proteinG: 30, carbsG: 4, fatG: 2, fiberG: 1), .manual, 16, 0),
            ("Salmon rice bowl", .dinner, Macros(calories: 720, proteinG: 38, carbsG: 68, fatG: 30, fiberG: 5), .menu, 19, 1),
            ("Oatmeal with berries", .breakfast, Macros(calories: 350, proteinG: 12, carbsG: 60, fatG: 7, fiberG: 9), .manual, 8, 1),
        ]
        for (name, mealType, macros, source, hour, daysAgo) in meals {
            let entry = FoodEntry(
                name: name, eatenAt: at(hour, daysAgo: daysAgo), mealType: mealType, macros: macros, source: source,
                placeName: source == .menu ? "Green Fork Kitchen" : nil,
                confidence: source.isAIEstimate ? .medium : nil
            )
            context.insert(entry)
        }

        let plans: [(title: String, daysAgo: Int, exercises: [(key: String, sets: [(Double, Int)])])] = [
            ("Push day", 1, [("bench_press_barbell", [(60, 8), (60, 8), (62.5, 6)]), ("shoulder_press_dumbbell", [(20, 10), (20, 9)]), ("triceps_pushdown_cable", [(25, 12), (25, 12)])]),
            ("Leg day", 3, [("squat_barbell", [(80, 5), (80, 5), (80, 5)]), ("romanian_deadlift_barbell", [(70, 8), (70, 8)]), ("standing_calf_raise_machine", [(50, 12), (50, 12)])]),
            ("Pull day", 5, [("lat_pulldown_cable", [(55, 10), (55, 10), (60, 8)]), ("dumbbell_row", [(26, 10), (26, 10)]), ("bicep_curl_dumbbell", [(12, 12), (12, 10)])]),
            ("Push day", 8, [("bench_press_barbell", [(57.5, 8), (57.5, 8), (60, 6)]), ("shoulder_press_dumbbell", [(18, 10), (18, 10)])]),
            ("Leg day", 10, [("squat_barbell", [(77.5, 5), (77.5, 5), (77.5, 5)])]),
        ]
        for plan in plans {
            let start = at(18, daysAgo: plan.daysAgo)
            let workout = WorkoutRecord(title: plan.title, startedAt: start)
            context.insert(workout)
            workout.endedAt = start.addingTimeInterval(55 * 60)
            for (order, item) in plan.exercises.enumerated() {
                guard let definition = ExerciseLibrary.exercise(key: item.key) else { continue }
                let exercise = WorkoutExerciseRecord(
                    order: order, exerciseKey: definition.key, name: definition.name,
                    primaryMuscle: definition.primaryMuscle, equipment: definition.equipment,
                    kind: definition.kind, restSeconds: definition.defaultRestSeconds
                )
                context.insert(exercise)
                exercise.workout = workout
                for (setOrder, values) in item.sets.enumerated() {
                    let set = WorkoutSetRecord(order: setOrder, weightKg: values.0, reps: values.1)
                    context.insert(set)
                    set.isCompleted = true
                    set.completedAt = workout.endedAt
                    set.exercise = exercise
                }
            }
        }

        let routine = WorkoutStore.createRoutine(
            name: "Push day",
            exercises: ["bench_press_barbell", "shoulder_press_dumbbell", "triceps_pushdown_cable"].compactMap(ExerciseLibrary.exercise(key:)),
            in: context
        )
        routine.notes = "Chest, shoulders and triceps"
        LedgerStore.save(context)
    }
}
