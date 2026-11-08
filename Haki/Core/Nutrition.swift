//
//  Nutrition.swift
//  Haki
//
//  Pure Foundation code (see Money.swift): meals, macros, daily targets and
//  the AI meal-estimate format the "food-ai" edge function returns.
//

import Foundation

// MARK: - Meals and macros

nonisolated enum MealType: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Breakfast"
        case .lunch: "Lunch"
        case .dinner: "Dinner"
        case .snack: "Snack"
        }
    }

    var systemImage: String {
        switch self {
        case .breakfast: "sunrise"
        case .lunch: "sun.max"
        case .dinner: "moon.stars"
        case .snack: "carrot"
        }
    }

    /// The meal people usually eat at `date`'s local time of day.
    static func suggested(for date: Date, calendar: Calendar = .current) -> MealType {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (components.hour ?? 12) * 60 + (components.minute ?? 0)
        switch minutes {
        case 300..<630: return .breakfast // 5:00–10:29
        case 660..<900: return .lunch // 11:00–14:59
        case 1020..<1290: return .dinner // 17:00–21:29
        default: return .snack
        }
    }
}

/// Energy and macronutrients. Calories are kcal; the rest are grams.
nonisolated struct Macros: Equatable, Hashable, Codable, Sendable {
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double

    init(calories: Double = 0, proteinG: Double = 0, carbsG: Double = 0, fatG: Double = 0, fiberG: Double = 0) {
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
    }

    static let zero = Macros()

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(
            calories: lhs.calories + rhs.calories,
            proteinG: lhs.proteinG + rhs.proteinG,
            carbsG: lhs.carbsG + rhs.carbsG,
            fatG: lhs.fatG + rhs.fatG,
            fiberG: lhs.fiberG + rhs.fiberG
        )
    }

    static func += (lhs: inout Macros, rhs: Macros) { lhs = lhs + rhs }

    /// Every value multiplied by `factor` (for "1.5 servings"). Negative factors count as 0.
    func scaled(by factor: Double) -> Macros {
        let f = factor.isFinite ? max(factor, 0) : 0
        return Macros(calories: calories * f, proteinG: proteinG * f, carbsG: carbsG * f, fatG: fatG * f, fiberG: fiberG * f)
    }

    /// Calories implied by the macros (4 kcal/g protein and carbs, 9 kcal/g fat).
    var caloriesFromMacros: Double { proteinG * 4 + carbsG * 4 + fatG * 9 }

    /// Share of calories from protein, 0...1, or nil when there are no calories.
    var proteinShareOfCalories: Double? {
        guard calories > 0 else { return nil }
        return min(proteinG * 4 / calories, 1)
    }

    static func total<S: Sequence>(_ items: S) -> Macros where S.Element == Macros {
        items.reduce(.zero, +)
    }
}

// MARK: - Units

nonisolated enum BodyUnits {
    static let poundsPerKilogram = 2.204_622_621_8
    static let centimetersPerInch = 2.54

    static func kilograms(fromPounds pounds: Double) -> Double { pounds / poundsPerKilogram }
    static func pounds(fromKilograms kilograms: Double) -> Double { kilograms * poundsPerKilogram }

    static func centimeters(feet: Int, inches: Double) -> Double {
        (Double(feet) * 12 + inches) * centimetersPerInch
    }

    /// Whole feet and the remaining inches (rounded to the nearest inch).
    static func feetAndInches(fromCentimeters centimeters: Double) -> (feet: Int, inches: Int) {
        let totalInches = Int((max(centimeters, 0) / centimetersPerInch).rounded())
        return (totalInches / 12, totalInches % 12)
    }
}

// MARK: - Targets

nonisolated enum BodySex: String, CaseIterable, Codable, Identifiable, Sendable {
    case female, male, unspecified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .female: "Female"
        case .male: "Male"
        case .unspecified: "Prefer not to say"
        }
    }
}

nonisolated enum ActivityLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case sedentary, light, moderate, active, veryActive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sedentary: "Mostly sitting"
        case .light: "Lightly active"
        case .moderate: "Moderately active"
        case .active: "Very active"
        case .veryActive: "Athlete"
        }
    }

    var detail: String {
        switch self {
        case .sedentary: "Desk job, little exercise"
        case .light: "Exercise 1–3 days a week"
        case .moderate: "Exercise 3–5 days a week"
        case .active: "Hard exercise 6–7 days a week"
        case .veryActive: "Physical job plus daily training"
        }
    }

    /// Multiplier applied to resting energy to estimate daily energy use.
    var multiplier: Double {
        switch self {
        case .sedentary: 1.2
        case .light: 1.375
        case .moderate: 1.55
        case .active: 1.725
        case .veryActive: 1.9
        }
    }
}

nonisolated enum WeightGoal: String, CaseIterable, Codable, Identifiable, Sendable {
    case lose, maintain, gain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lose: "Lose weight"
        case .maintain: "Maintain"
        case .gain: "Build muscle"
        }
    }

    /// Daily calories added to (or taken from) maintenance.
    var calorieAdjustment: Double {
        switch self {
        case .lose: -500
        case .maintain: 0
        case .gain: 300
        }
    }

    /// Protein per kilogram of body weight.
    var proteinPerKilogram: Double {
        switch self {
        case .lose: 2.0
        case .maintain: 1.6
        case .gain: 1.8
        }
    }
}

nonisolated struct NutritionProfile: Equatable, Codable, Sendable {
    var weightKg: Double
    var heightCm: Double
    var ageYears: Int
    var sex: BodySex
    var activity: ActivityLevel
    var goal: WeightGoal

    /// Whether the numbers are plausible for an adult; targets need this.
    var isComplete: Bool {
        (30...350).contains(weightKg) && (120...230).contains(heightCm) && (13...100).contains(ageYears)
    }
}

nonisolated struct NutritionTargets: Equatable, Codable, Sendable {
    var calories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    var fiberG: Int

    /// Used until the person sets their own.
    static let standard = NutritionTargets(calories: 2_000, proteinG: 120, carbsG: 220, fatG: 67, fiberG: 28)
}

nonisolated enum NutritionGoals {
    /// The lowest daily target Haki suggests; going lower needs a professional.
    static let minimumCalories = 1_200

    /// Resting energy (kcal/day), Mifflin–St Jeor. `unspecified` uses the
    /// midpoint of the female and male constants.
    static func restingCalories(_ profile: NutritionProfile) -> Double {
        let base = 10 * profile.weightKg + 6.25 * profile.heightCm - 5 * Double(profile.ageYears)
        switch profile.sex {
        case .male: return base + 5
        case .female: return base - 161
        case .unspecified: return base - 78
        }
    }

    /// Estimated calories burned per day.
    static func maintenanceCalories(_ profile: NutritionProfile) -> Double {
        restingCalories(profile) * profile.activity.multiplier
    }

    /// Daily targets for `profile`: calories from maintenance and the goal
    /// (never below `minimumCalories`), protein by body weight, fat at 27%
    /// of calories, carbs from what's left, and 14 g fiber per 1,000 kcal.
    static func targets(for profile: NutritionProfile) -> NutritionTargets {
        guard profile.isComplete else { return .standard }
        let calories = max(Double(minimumCalories), maintenanceCalories(profile) + profile.goal.calorieAdjustment)
        let roundedCalories = (calories / 10).rounded() * 10
        // Protein no higher than 35% of calories, so carbs and fat stay sensible.
        let protein = min(profile.weightKg * profile.goal.proteinPerKilogram, roundedCalories * 0.35 / 4)
        let fat = roundedCalories * 0.27 / 9
        let carbs = max(0, (roundedCalories - protein * 4 - fat * 9) / 4)
        return NutritionTargets(
            calories: Int(roundedCalories),
            proteinG: Int(protein.rounded()),
            carbsG: Int(carbs.rounded()),
            fatG: Int(fat.rounded()),
            fiberG: Int((roundedCalories / 1_000 * 14).rounded())
        )
    }
}

// MARK: - Daily progress

nonisolated struct NutritionProgress: Equatable, Sendable {
    let consumed: Macros
    let targets: NutritionTargets

    var remainingCalories: Int { targets.calories - Int(consumed.calories.rounded()) }
    var remainingProteinG: Int { max(0, targets.proteinG - Int(consumed.proteinG.rounded())) }

    /// 0... (can pass 1 when over).
    var calorieFraction: Double { fraction(consumed.calories, of: targets.calories) }
    var proteinFraction: Double { fraction(consumed.proteinG, of: targets.proteinG) }
    var carbsFraction: Double { fraction(consumed.carbsG, of: targets.carbsG) }
    var fatFraction: Double { fraction(consumed.fatG, of: targets.fatG) }
    var fiberFraction: Double { fraction(consumed.fiberG, of: targets.fiberG) }

    var isOverCalories: Bool { remainingCalories < 0 }
    var hasHitProtein: Bool { targets.proteinG > 0 && consumed.proteinG >= Double(targets.proteinG) }

    private func fraction(_ value: Double, of target: Int) -> Double {
        guard target > 0, value.isFinite else { return 0 }
        return max(value, 0) / Double(target)
    }
}

nonisolated enum NutritionStats {
    /// Consecutive days with at least one logged entry, ending today — or
    /// yesterday when nothing is logged yet today, so the streak isn't lost
    /// before breakfast.
    static func loggingStreak(entryDates: [Date], now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = Set(entryDates.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// Average daily totals over the days in `entries` that have any (days
    /// with nothing logged aren't counted as zero).
    static func averagePerLoggedDay(_ entries: [(date: Date, macros: Macros)], calendar: Calendar = .current) -> Macros? {
        guard !entries.isEmpty else { return nil }
        var byDay: [Date: Macros] = [:]
        for entry in entries {
            byDay[calendar.startOfDay(for: entry.date), default: .zero] += entry.macros
        }
        return Macros.total(byDay.values).scaled(by: 1 / Double(byDay.count))
    }
}

// MARK: - AI meal estimates ("food-ai" analyze_meal)

nonisolated enum EstimateConfidence: String, Codable, Sendable {
    case low, medium, high

    var title: String {
        switch self {
        case .low: "Rough estimate"
        case .medium: "Good estimate"
        case .high: "Close estimate"
        }
    }
}

nonisolated struct MealEstimateItem: Equatable, Hashable, Codable, Sendable {
    var name: String
    var portion: String
    var grams: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double

    var macros: Macros {
        Macros(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG, fiberG: fiberG)
    }

    enum CodingKeys: String, CodingKey {
        case name, portion, grams, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
    }
}

nonisolated struct MealEstimate: Equatable, Codable, Sendable {
    var isFood: Bool
    var title: String
    var items: [MealEstimateItem]
    var confidence: EstimateConfidence
    var notes: String

    var total: Macros { Macros.total(items.map(\.macros)) }

    enum CodingKeys: String, CodingKey {
        case isFood = "is_food"
        case title, items, confidence, notes
    }

    init(isFood: Bool, title: String, items: [MealEstimateItem], confidence: EstimateConfidence, notes: String) {
        self.isFood = isFood
        self.title = title
        self.items = items
        self.confidence = confidence
        self.notes = notes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isFood = try container.decodeIfPresent(Bool.self, forKey: .isFood) ?? true
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Meal"
        items = try container.decodeIfPresent([MealEstimateItem].self, forKey: .items) ?? []
        confidence = (try? container.decode(EstimateConfidence.self, forKey: .confidence)) ?? .medium
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}
