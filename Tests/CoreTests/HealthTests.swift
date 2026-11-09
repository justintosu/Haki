//
//  HealthTests.swift
//  Haki core tests
//
//  Nutrition, menus, workouts and Hevy JSON. Called from main.swift.
//

import Foundation

private func hday(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 12, minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = dayOfMonth
    components.hour = hour
    components.minute = minute
    return healthCalendar.date(from: components)!
}

private let healthCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2 // Monday
    return calendar
}()

private func approx(_ a: Double?, _ b: Double, tolerance: Double = 0.01) -> Bool {
    guard let a else { return false }
    return abs(a - b) <= tolerance
}

private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}

func runHealthTests() {
    suite("MealType.suggested") {
        expectEqual(MealType.suggested(for: hday(2026, 11, 8, hour: 7), calendar: healthCalendar), .breakfast)
        expectEqual(MealType.suggested(for: hday(2026, 11, 8, hour: 10, minute: 45), calendar: healthCalendar), .snack)
        expectEqual(MealType.suggested(for: hday(2026, 11, 8, hour: 12, minute: 30), calendar: healthCalendar), .lunch)
        expectEqual(MealType.suggested(for: hday(2026, 11, 8, hour: 19), calendar: healthCalendar), .dinner)
        expectEqual(MealType.suggested(for: hday(2026, 11, 8, hour: 23), calendar: healthCalendar), .snack)
        expectEqual(MealType.suggested(for: hday(2026, 11, 8, hour: 2), calendar: healthCalendar), .snack)
    }

    suite("Macros") {
        let a = Macros(calories: 400, proteinG: 30, carbsG: 40, fatG: 10, fiberG: 5)
        let b = Macros(calories: 100, proteinG: 5, carbsG: 10, fatG: 5, fiberG: 1)
        expectEqual(a + b, Macros(calories: 500, proteinG: 35, carbsG: 50, fatG: 15, fiberG: 6))
        expectEqual(Macros.total([a, b, .zero]), a + b)
        expectEqual(a.scaled(by: 0.5), Macros(calories: 200, proteinG: 15, carbsG: 20, fatG: 5, fiberG: 2.5))
        expectEqual(a.scaled(by: -2), .zero, "negative servings count as none")
        expectEqual(a.scaled(by: .nan), .zero)
        expectEqual(a.caloriesFromMacros, 370.0)
        expect(approx(a.proteinShareOfCalories, 0.3))
        expectEqual(Macros.zero.proteinShareOfCalories, nil)
    }

    suite("BodyUnits") {
        expect(approx(BodyUnits.kilograms(fromPounds: 180), 81.65))
        expect(approx(BodyUnits.pounds(fromKilograms: 100), 220.46))
        expect(approx(BodyUnits.centimeters(feet: 5, inches: 10), 177.8))
        let (feet, inches) = BodyUnits.feetAndInches(fromCentimeters: 177.8)
        expectEqual(feet, 5)
        expectEqual(inches, 10)
        let (f2, i2) = BodyUnits.feetAndInches(fromCentimeters: 182.5) // 71.85 in
        expectEqual(f2, 6)
        expectEqual(i2, 0)
    }

    suite("NutritionGoals") {
        let profile = NutritionProfile(weightKg: 80, heightCm: 180, ageYears: 30, sex: .male, activity: .moderate, goal: .maintain)
        // 10*80 + 6.25*180 - 5*30 + 5 = 1780
        expect(approx(NutritionGoals.restingCalories(profile), 1_780))
        expect(approx(NutritionGoals.maintenanceCalories(profile), 2_759))
        let maintain = NutritionGoals.targets(for: profile)
        expectEqual(maintain.calories, 2_760)
        expectEqual(maintain.proteinG, 128) // 1.6 g/kg
        expectEqual(maintain.fatG, 83) // 27% of 2760 / 9
        expectEqual(maintain.fiberG, 39)
        // Carbs fill the rest: (2760 - 128*4 - 82.8*9) / 4
        expectEqual(maintain.carbsG, 376)

        var cut = profile
        cut.goal = .lose
        let lose = NutritionGoals.targets(for: cut)
        expectEqual(lose.calories, 2_260)
        expectEqual(lose.proteinG, 160) // 2.0 g/kg

        var female = profile
        female.sex = .female
        expect(approx(NutritionGoals.restingCalories(female), 1_614))
        var unspecified = profile
        unspecified.sex = .unspecified
        expect(approx(NutritionGoals.restingCalories(unspecified), 1_697))

        // Never below the floor.
        let small = NutritionProfile(weightKg: 45, heightCm: 150, ageYears: 70, sex: .female, activity: .sedentary, goal: .lose)
        expectEqual(NutritionGoals.targets(for: small).calories, NutritionGoals.minimumCalories)
        // Protein capped at 35% of calories for heavy people on a cut.
        let heavy = NutritionProfile(weightKg: 200, heightCm: 170, ageYears: 40, sex: .female, activity: .sedentary, goal: .lose)
        let heavyTargets = NutritionGoals.targets(for: heavy)
        expect(Double(heavyTargets.proteinG * 4) <= Double(heavyTargets.calories) * 0.35 + 4)
        expect(heavyTargets.carbsG >= 0)

        // Implausible numbers fall back to the standard targets.
        let incomplete = NutritionProfile(weightKg: 0, heightCm: 180, ageYears: 30, sex: .male, activity: .moderate, goal: .maintain)
        expect(!incomplete.isComplete)
        expectEqual(NutritionGoals.targets(for: incomplete), .standard)
    }

    suite("NutritionProgress") {
        let targets = NutritionTargets(calories: 2_000, proteinG: 150, carbsG: 200, fatG: 70, fiberG: 30)
        let progress = NutritionProgress(consumed: Macros(calories: 1_250.4, proteinG: 90, carbsG: 100, fatG: 35, fiberG: 12), targets: targets)
        expectEqual(progress.remainingCalories, 750)
        expectEqual(progress.remainingProteinG, 60)
        expect(approx(progress.calorieFraction, 0.625, tolerance: 0.001))
        expect(approx(progress.proteinFraction, 0.6))
        expect(!progress.isOverCalories)
        expect(!progress.hasHitProtein)
        let over = NutritionProgress(consumed: Macros(calories: 2_300, proteinG: 160), targets: targets)
        expectEqual(over.remainingCalories, -300)
        expect(over.isOverCalories)
        expect(over.hasHitProtein)
        expectEqual(over.remainingProteinG, 0)
        let zeroTargets = NutritionProgress(consumed: Macros(calories: 100), targets: NutritionTargets(calories: 0, proteinG: 0, carbsG: 0, fatG: 0, fiberG: 0))
        expectEqual(zeroTargets.calorieFraction, 0)
    }

    suite("NutritionStats") {
        let now = hday(2026, 11, 8, hour: 9)
        let dates = [hday(2026, 11, 8, hour: 8), hday(2026, 11, 7), hday(2026, 11, 7, hour: 19), hday(2026, 11, 6), hday(2026, 11, 4)]
        expectEqual(NutritionStats.loggingStreak(entryDates: dates, now: now, calendar: healthCalendar), 3)
        // Nothing yet today: yesterday's streak still counts.
        expectEqual(NutritionStats.loggingStreak(entryDates: Array(dates.dropFirst()), now: now, calendar: healthCalendar), 2)
        expectEqual(NutritionStats.loggingStreak(entryDates: [hday(2026, 11, 5)], now: now, calendar: healthCalendar), 0)
        expectEqual(NutritionStats.loggingStreak(entryDates: [], now: now, calendar: healthCalendar), 0)

        let average = NutritionStats.averagePerLoggedDay([
            (hday(2026, 11, 7, hour: 8), Macros(calories: 500, proteinG: 30)),
            (hday(2026, 11, 7, hour: 13), Macros(calories: 700, proteinG: 40)),
            (hday(2026, 11, 8, hour: 8), Macros(calories: 1_000, proteinG: 50)),
        ], calendar: healthCalendar)
        expectEqual(average, Macros(calories: 1_100, proteinG: 60))
        expectEqual(NutritionStats.averagePerLoggedDay([], calendar: healthCalendar), nil)
    }

    suite("MealEstimate decoding") {
        let json = """
        {"is_food": true, "title": "Chicken bowl", "confidence": "medium", "notes": "Assumed 1 tbsp oil",
         "items": [
           {"name": "Grilled chicken", "portion": "150 g", "grams": 150, "calories": 248, "protein_g": 46.5, "carbs_g": 0, "fat_g": 5.4, "fiber_g": 0},
           {"name": "Rice", "portion": "1 cup", "grams": 158, "calories": 205, "protein_g": 4.3, "carbs_g": 44.5, "fat_g": 0.4, "fiber_g": 0.6}
         ],
         "total": {"calories": 453, "protein_g": 50.8, "carbs_g": 44.5, "fat_g": 5.8, "fiber_g": 0.6}}
        """
        let estimate = try decode(MealEstimate.self, json)
        expectEqual(estimate.title, "Chicken bowl")
        expectEqual(estimate.items.count, 2)
        expectEqual(estimate.confidence, .medium)
        expect(approx(estimate.total.calories, 453))
        expect(approx(estimate.total.proteinG, 50.8))
        let sparse = try decode(MealEstimate.self, #"{"confidence": "very sure"}"#)
        expect(sparse.isFood)
        expectEqual(sparse.items, [])
        expectEqual(sparse.confidence, .medium, "unknown confidence falls back")
    }

    suite("MenuReport decoding") {
        let json = """
        {"place_name": "Green Bowl", "cuisine": "Salads", "found_menu": true, "currency": "USD",
         "items": [
           {"name": "Chicken Power Bowl", "section": "Bowls", "description": "Chicken, quinoa, greens", "price": 13.95,
            "calories": 620, "protein_g": 48, "carbs_g": 55, "fat_g": 20, "nutrition_source": "official",
            "tags": ["high_protein", "balanced", "something_new", "high_protein"], "health_score": 9},
           {"name": "Mac & Cheese", "section": "Sides", "description": "", "price": null,
            "calories": 540, "protein_g": 18, "carbs_g": 50, "fat_g": 30, "nutrition_source": "estimated",
            "tags": [], "health_score": 14}
         ],
         "notes": "", "sources": [{"title": "Green Bowl menu", "url": "https://example.com/menu"}],
         "generated_at": "2026-11-08T12:00:00.123Z", "cached": true}
        """
        let report = try decode(MenuReport.self, json)
        expectEqual(report.placeName, "Green Bowl")
        expect(report.foundMenu)
        expect(report.cached)
        expectEqual(report.items.count, 2)
        expectEqual(report.items[0].tags, [.highProtein, .balanced], "unknown and repeated tags dropped")
        expect(report.items[0].isOfficialNutrition)
        expectEqual(report.items[0].priceCents, 1_395)
        expectEqual(report.items[1].price, nil)
        expectEqual(report.items[1].healthScore, 10, "clamped to 1...10")
        expectEqual(report.sections, ["Bowls", "Sides"])
        expect(report.generatedDate != nil)
        // Round trip.
        let data = try JSONEncoder().encode(report)
        expectEqual(try JSONDecoder().decode(MenuReport.self, from: data), report)
    }

    suite("MenuRanking") {
        let bowl = MenuDish(name: "Chicken Bowl", section: "Bowls", price: 12, calories: 600, proteinG: 45, tags: [.highProtein], healthScore: 9)
        let salad = MenuDish(name: "Garden Salad", section: "Salads", price: 9, calories: 300, proteinG: 8, tags: [.vegetarian, .lowCalorie], healthScore: 8)
        let burger = MenuDish(name: "Double Burger", section: "Burgers", price: 11, calories: 1_100, proteinG: 55, healthScore: 3)
        let shake = MenuDish(name: "Protein Shake", section: "Drinks", price: nil, calories: 250, proteinG: 30, tags: [.highProtein], healthScore: 7)
        let fries = MenuDish(name: "Fries", section: "Sides", price: 4, calories: 0, proteinG: 4, healthScore: 2)
        let menu = [bowl, salad, burger, shake, fries]

        expectEqual(MenuRanking.apply(menu, sort: .menuOrder).map(\.name), menu.map(\.name))
        expectEqual(MenuRanking.apply(menu, sort: .mostProtein).map(\.name), ["Double Burger", "Chicken Bowl", "Protein Shake", "Garden Salad", "Fries"])
        expectEqual(MenuRanking.apply(menu, sort: .healthiest).first?.name, "Chicken Bowl")
        expectEqual(MenuRanking.apply(menu, sort: .proteinPerCalorie).first?.name, "Protein Shake")
        // Missing values go last: the shake has no price.
        expectEqual(MenuRanking.apply(menu, sort: .lowestPrice).map(\.name), ["Fries", "Garden Salad", "Double Burger", "Chicken Bowl", "Protein Shake"])
        expectEqual(MenuRanking.apply(menu, sort: .proteinPerPrice).last?.name, "Protein Shake")
        expectEqual(MenuRanking.apply(menu, sort: .fewestCalories).map(\.name), ["Protein Shake", "Garden Salad", "Chicken Bowl", "Double Burger", "Fries"])

        var filter = MenuFilter()
        expect(!filter.isActive)
        filter.minProteinG = 30
        filter.maxCalories = 700
        expect(filter.isActive)
        expectEqual(MenuRanking.apply(menu, filter: filter, sort: .menuOrder).map(\.name), ["Chicken Bowl", "Protein Shake"])
        filter.maxPriceCents = 1_500
        expectEqual(MenuRanking.apply(menu, filter: filter, sort: .menuOrder).map(\.name), ["Chicken Bowl"], "no price, no budget match")
        var tagFilter = MenuFilter()
        tagFilter.requiredTags = [.vegetarian]
        expectEqual(MenuRanking.apply(menu, filter: tagFilter, sort: .menuOrder).map(\.name), ["Garden Salad"])
        var query = MenuFilter()
        query.query = "  bowl "
        expectEqual(MenuRanking.apply(menu, filter: query, sort: .menuOrder).map(\.name), ["Chicken Bowl"])
        query.query = "BURGERS"
        expectEqual(MenuRanking.apply(menu, filter: query, sort: .menuOrder).map(\.name), ["Double Burger"], "section matches")

        expectEqual(MenuRanking.healthyPicks(menu).map(\.name), ["Chicken Bowl", "Garden Salad", "Protein Shake"])
        expectEqual(MenuRanking.healthyPicks(menu, remainingCalories: 400).map(\.name), ["Garden Salad", "Protein Shake"])
        expectEqual(MenuRanking.healthyPicks(menu, remainingCalories: 100).map(\.name), ["Chicken Bowl", "Garden Salad", "Protein Shake"], "nothing fits: show the healthiest")
        expectEqual(MenuRanking.healthyPicks(menu, limit: 0), [])
        expect(approx(bowl.proteinPer100Calories, 7.5))
        expect(approx(bowl.proteinPerCurrencyUnit, 3.75))
    }

    suite("ExerciseLibrary") {
        let keys = ExerciseLibrary.all.map(\.key)
        expectEqual(Set(keys).count, keys.count, "keys are unique")
        let names = ExerciseLibrary.all.map(\.name)
        expectEqual(Set(names).count, names.count, "names are unique")
        expectEqual(ExerciseLibrary.exercise(key: "squat_barbell")?.name, "Squat (Barbell)")
        expectEqual(ExerciseLibrary.exercise(key: "nope"), nil)
        expect(ExerciseLibrary.search("bench").allSatisfy { $0.name.lowercased().contains("bench") })
        expect(ExerciseLibrary.search("bench press dumbbell").map(\.key).contains("bench_press_dumbbell"))
        expect(!ExerciseLibrary.search("bench press dumbbell").map(\.key).contains("bench_press_barbell"))
        let biceps = ExerciseLibrary.search("", muscle: .biceps)
        expect(biceps.contains { $0.key == "bicep_curl_barbell" })
        expect(biceps.contains { $0.key == "chin_up" }, "secondary muscle counts")
        expectEqual(ExerciseLibrary.search("quads").first?.primaryMuscle, .quadriceps, "matches muscle titles")
        expectEqual(ExerciseLibrary.normalizedTitle("Bench Press (Barbell)"), "benchpressbarbell")
        let templates: [(id: String, title: String, isCustom: Bool)] = [
            ("C1", "bench press - barbell", true),
            ("79D0BB3A", "Bench Press (Barbell)", false),
            ("X", "Squat (Barbell)", false),
        ]
        expectEqual(ExerciseLibrary.matchingTemplateID(for: "Bench Press (Barbell)", in: templates), "79D0BB3A", "built-in preferred")
        expectEqual(ExerciseLibrary.matchingTemplateID(for: "Leg Press (Machine)", in: templates), nil)
        expectEqual(ExerciseLibrary.matchingTemplateID(for: "", in: templates), nil)
        expectEqual(ExerciseLibrary.builtIn(matchingTitle: "squat - barbell")?.key, "squat_barbell")
        expectEqual(ExerciseLibrary.builtIn(matchingTitle: "Underwater Basket Weaving"), nil)
        expectEqual(ExerciseLibrary.exercise(key: "plank")?.defaultRestSeconds, 60)
        expectEqual(ExerciseLibrary.exercise(key: "squat_barbell")?.defaultRestSeconds, 150)
        expect(ExerciseKind.weightReps.countsWeightForRecords)
        expect(!ExerciseKind.assistedBodyweightReps.countsWeightForRecords)
        expect(ExerciseKind.distanceDuration.logsDistance && ExerciseKind.distanceDuration.logsDuration)
        expect(!ExerciseKind.repsOnly.logsWeight)
    }

    suite("WorkoutMath sets and records") {
        expectEqual(WorkoutMath.estimatedOneRepMax(weightKg: 100, reps: 1), 100)
        expect(approx(WorkoutMath.estimatedOneRepMax(weightKg: 100, reps: 10), 133.33))
        expectEqual(WorkoutMath.estimatedOneRepMax(weightKg: 100, reps: 16), nil)
        expectEqual(WorkoutMath.estimatedOneRepMax(weightKg: 0, reps: 5), nil)
        expectEqual(WorkoutMath.estimatedOneRepMax(weightKg: 50, reps: 0), nil)

        let warmup = SetValues(kind: .warmup, weightKg: 40, reps: 10, isCompleted: true)
        let set1 = SetValues(weightKg: 80, reps: 8, isCompleted: true)
        let set2 = SetValues(weightKg: 85, reps: 5, isCompleted: true)
        let unticked = SetValues(weightKg: 200, reps: 5, isCompleted: false)
        let sets = [warmup, set1, set2, unticked]
        expectEqual(WorkoutMath.workingSets(sets).count, 2)
        expectEqual(WorkoutMath.volumeKg(sets), 1_065.0)
        expectEqual(WorkoutMath.bestSet(sets), set1, "80x8 (e1RM 101.3) beats 85x5 (99.2)")
        expectEqual(WorkoutMath.bestSet([unticked]), nil)

        let history = [
            ExercisePerformance(date: hday(2026, 11, 1), sets: [set1]),
            ExercisePerformance(date: hday(2026, 11, 4), sets: [set2, warmup]),
        ]
        let records = WorkoutMath.records(history)
        expectEqual(records.heaviestWeightKg, 85)
        expect(approx(records.bestOneRepMaxKg, 101.33))
        expectEqual(records.mostReps, 8)
        expectEqual(records.bestSetVolumeKg, 640)
        expectEqual(WorkoutMath.records([]), .none)

        let heavier = SetValues(weightKg: 90, reps: 3, isCompleted: true)
        expectEqual(WorkoutMath.newRecords(for: heavier, previous: records), [.heaviestWeight])
        let big = SetValues(weightKg: 82.5, reps: 10, isCompleted: true)
        expectEqual(WorkoutMath.newRecords(for: big, previous: records), [.bestOneRepMax, .mostReps, .bestSetVolume])
        expectEqual(WorkoutMath.newRecords(for: SetValues(kind: .warmup, weightKg: 200, reps: 20, isCompleted: true), previous: records), [])
        expectEqual(WorkoutMath.newRecords(for: SetValues(weightKg: 200, reps: 20, isCompleted: false), previous: records), [])
        expectEqual(WorkoutMath.newRecords(for: heavier, previous: .none), [], "first time isn't a PR")
        // Assisted / bodyweight: only reps count.
        let assisted = WorkoutMath.records([ExercisePerformance(date: hday(2026, 11, 1), sets: [SetValues(weightKg: 30, reps: 6, isCompleted: true)])], countsWeight: false)
        expectEqual(assisted.heaviestWeightKg, nil)
        expectEqual(assisted.mostReps, 6)
        expectEqual(WorkoutMath.newRecords(for: SetValues(weightKg: 10, reps: 7, isCompleted: true), previous: assisted, countsWeight: false), [.mostReps])
    }

    suite("WorkoutMath streaks and formatting") {
        let now = hday(2026, 11, 11) // Wednesday
        let dates = [hday(2026, 11, 9), hday(2026, 11, 3), hday(2026, 11, 5), hday(2026, 10, 27), hday(2026, 10, 13)]
        expectEqual(WorkoutMath.weekStreak(workoutDates: dates, now: now, calendar: healthCalendar), 3)
        expectEqual(WorkoutMath.weekStreak(workoutDates: Array(dates.dropFirst()), now: now, calendar: healthCalendar), 2, "nothing yet this week")
        expectEqual(WorkoutMath.weekStreak(workoutDates: [], now: now, calendar: healthCalendar), 0)
        let weekly = WorkoutMath.workoutsPerWeek(workoutDates: dates, weeks: 4, now: now, calendar: healthCalendar)
        expectEqual(weekly.map(\.count), [0, 1, 2, 1])
        expectEqual(weekly.last?.weekStart, hday(2026, 11, 9, hour: 0))
        expectEqual(WorkoutMath.workoutsPerWeek(workoutDates: dates, weeks: 0, now: now, calendar: healthCalendar).count, 0)

        let perMuscle = WorkoutMath.setsPerMuscle([
            (.chest, [SetValues(weightKg: 60, reps: 10, isCompleted: true), SetValues(kind: .warmup, weightKg: 20, reps: 10, isCompleted: true)]),
            (.chest, [SetValues(weightKg: 20, reps: 12, isCompleted: true)]),
            (.lats, [SetValues(weightKg: 50, reps: 10, isCompleted: false)]),
        ])
        expectEqual(perMuscle, [.chest: 2])

        expectEqual(WorkoutMath.formatTimer(seconds: 45), "45s")
        expectEqual(WorkoutMath.formatTimer(seconds: 725), "12:05")
        expectEqual(WorkoutMath.formatTimer(seconds: 3_729), "1:02:09")
        expectEqual(WorkoutMath.formatTimer(seconds: -5), "0s")
        expectEqual(WorkoutMath.formatDuration(seconds: 3_120), "52m")
        expectEqual(WorkoutMath.formatDuration(seconds: 3_900), "1h 05m")
        expectEqual(WorkoutMath.formatDuration(seconds: 50), "50s")
        expectEqual(WorkoutMath.formatDuration(seconds: 0), "0s")
        expectEqual(WorkoutMath.formatDuration(seconds: 60), "1m")
    }

    suite("WeightUnit and DistanceUnit") {
        expectEqual(WeightUnit.kilograms.format(kilograms: 62.5), "62.5")
        expectEqual(WeightUnit.kilograms.format(kilograms: 100), "100")
        expectEqual(WeightUnit.pounds.format(kilograms: BodyUnits.kilograms(fromPounds: 135)), "135")
        expect(approx(WeightUnit.pounds.parse("135"), 61.235))
        expect(approx(WeightUnit.kilograms.parse("62,5"), 62.5))
        expectEqual(WeightUnit.kilograms.parse(""), nil)
        expectEqual(WeightUnit.kilograms.parse("-5"), nil)
        expectEqual(WeightUnit.kilograms.parse("abc"), nil)
        expectEqual(WeightUnit.preferred(for: Locale(identifier: "en_US")), .pounds)
        expectEqual(WeightUnit.preferred(for: Locale(identifier: "de_DE")), .kilograms)
        expectEqual(DistanceUnit.miles.format(meters: 1_609.344), "1.00")
        expect(approx(DistanceUnit.kilometers.parse("5"), 5_000))
        expectEqual(DistanceUnit.kilometers.parse("x"), nil)
    }

    suite("Hevy JSON") {
        let page = """
        {"page": 1, "page_count": 3, "workouts": [{
          "id": "b459cba5-cd6d-463c-abd6-54f8eafcadcb", "title": "Morning Workout", "routine_id": null,
          "description": null, "start_time": "2021-09-14T12:00:00Z", "end_time": "2021-09-14T13:00:00.500Z",
          "updated_at": "2021-09-14T13:05:00Z", "created_at": "2021-09-14T13:05:00Z",
          "exercises": [{"index": 0, "title": "Bench Press (Barbell)", "notes": null, "exercise_template_id": "05293BCA",
            "superset_id": null, "sets": [
              {"index": 0, "type": "warmup", "weight_kg": 40, "reps": 10, "distance_meters": null, "duration_seconds": null, "rpe": null, "custom_metric": null},
              {"index": 1, "type": "normal", "weight_kg": 100, "reps": 8, "distance_meters": null, "duration_seconds": null, "rpe": 9.5, "custom_metric": null}
            ]}]
        }]}
        """
        let decoded = try decode(HevyWorkoutPage.self, page)
        expectEqual(decoded.pageCount, 3)
        let workout = decoded.workouts[0]
        expectEqual(workout.exercises.first?.exerciseTemplateID, "05293BCA")
        expectEqual(workout.startDate, hday(2021, 9, 14))
        expect(workout.endDate != nil, "fractional seconds parse")
        let values = workout.exercises[0].sets.map(\.values)
        expectEqual(values[0].kind, .warmup)
        expectEqual(values[1].reps, 8)
        expectEqual(values[1].rpe, 9.5)
        expect(values.allSatisfy(\.isCompleted))

        let events = """
        {"page": 1, "page_count": 1, "events": [
          {"type": "updated", "workout": {"id": "w1", "title": "Legs", "start_time": "2024-08-14T12:00:00Z", "end_time": "2024-08-14T12:30:00Z", "exercises": []}},
          {"type": "deleted", "id": "w2", "deleted_at": "2024-08-15T08:00:00Z"},
          {"type": "something_else"}
        ]}
        """
        let eventPage = try decode(HevyEventPage.self, events)
        expectEqual(eventPage.events.count, 3)
        if case .updated(let updated) = eventPage.events[0] { expectEqual(updated.title, "Legs") } else { expect(false, "first is updated") }
        if case .deleted(let id, let deletedAt) = eventPage.events[1] {
            expectEqual(id, "w2")
            expect(deletedAt != nil)
        } else { expect(false, "second is deleted") }
        expectEqual(eventPage.events[2], .unknown)

        let templates = """
        {"page": 1, "page_count": 1, "exercise_templates": [
          {"id": "05293BCA", "title": "Bench Press (Barbell)", "type": "weight_reps", "primary_muscle_group": "chest",
           "secondary_muscle_groups": ["triceps"], "equipment": "barbell", "is_custom": false, "thumbnail_url": null},
          {"id": "Z1", "title": "Mystery", "type": "teleport", "primary_muscle_group": "aura", "equipment": "wand"}
        ]}
        """
        let templatePage = try decode(HevyTemplatePage.self, templates)
        expectEqual(templatePage.exerciseTemplates[0].muscle, .chest)
        expectEqual(templatePage.exerciseTemplates[0].equipmentValue, .barbell)
        expectEqual(templatePage.exerciseTemplates[1].kind, .weightReps, "unknown kinds fall back")
        expectEqual(templatePage.exerciseTemplates[1].muscle, .other)

        let user = try decode(HevyUserInfoResponse.self, #"{"data": {"id": "u1", "username": "jo", "weight_unit": "lbs", "is_pro": true}}"#)
        expectEqual(user.data.isPro, true)
        expectEqual(try decode(HevyWorkoutCount.self, #"{"workout_count": 42}"#).workoutCount, 42)

        expect(HevyAPI.isPlausibleAPIKey(" 3fa85f64-5717-4562-b3fc-2c963f66afa6 "))
        expect(!HevyAPI.isPlausibleAPIKey("not-a-key"))
        expectEqual(HevyAPI.formatDate(hday(2024, 8, 14)), "2024-08-14T12:00:00Z")
    }

    suite("Hevy new workout encoding") {
        expectEqual(HevyNewWorkout.set(from: SetValues(weightKg: 60, reps: 10, isCompleted: false)), nil)
        let set = HevyNewWorkout.set(from: SetValues(kind: .failure, weightKg: 61.23456, reps: 10, rpe: 8.4, isCompleted: true))
        expectEqual(set?.type, "failure")
        expectEqual(set?.weightKg, 61.235)
        expectEqual(set?.rpe, nil, "8.4 isn't an RPE Hevy accepts")
        expectEqual(HevyNewWorkout.set(from: SetValues(reps: 5, rpe: 7.5, isCompleted: true))?.rpe, 7.5)
        let workout = HevyNewWorkout(
            title: "Push", description: nil, startTime: hday(2024, 8, 14), endTime: hday(2024, 8, 14, hour: 11),
            isPrivate: false,
            exercises: [HevyNewWorkout.ExerciseEntry(exerciseTemplateID: "05293BCA", supersetID: nil, notes: nil, sets: [set].compactMap { $0 })]
        )
        let data = try JSONEncoder().encode(workout)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let inner = object?["workout"] as? [String: Any]
        expectEqual(inner?["title"] as? String, "Push")
        expectEqual(inner?["start_time"] as? String, "2024-08-14T12:00:00Z")
        expectEqual(inner?["end_time"] as? String, "2024-08-14T12:00:00Z", "end never before start")
        expect(inner?["description"] is NSNull, "explicit null")
        let exercises = inner?["exercises"] as? [[String: Any]]
        expectEqual(exercises?.first?["exercise_template_id"] as? String, "05293BCA")
        let sets = exercises?.first?["sets"] as? [[String: Any]]
        expectEqual(sets?.first?["reps"] as? Int, 10)
        expect(sets?.first?["distance_meters"] is NSNull)
    }
}
