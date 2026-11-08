//
//  FoodStore.swift
//  Haki
//
//  Every write to the food log goes through these helpers (see LedgerStore).
//  Screens read with @Query.
//

import Foundation
import SwiftData

enum FoodStore {
    /// Adds an entry and saves.
    @discardableResult
    static func add(
        name: String,
        mealType: MealType,
        macros: Macros,
        eatenAt: Date = .now,
        portion: String = "",
        servings: Double = 1,
        source: FoodEntrySource = .manual,
        placeName: String? = nil,
        confidence: EstimateConfidence? = nil,
        notes: String = "",
        photoData: Data? = nil,
        in context: ModelContext
    ) -> FoodEntry {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = FoodEntry(
            name: trimmed.isEmpty ? mealType.title : trimmed,
            eatenAt: eatenAt,
            mealType: mealType,
            portion: portion,
            servings: servings,
            macros: sanitized(macros),
            source: source,
            placeName: placeName,
            confidence: confidence,
            notes: notes,
            photoData: photoData
        )
        context.insert(entry)
        LedgerStore.save(context)
        return entry
    }

    /// Logs an AI estimate as one entry: the meal's title, every item's
    /// portion listed in `portion`, and the summed macros.
    @discardableResult
    static func add(
        estimate: MealEstimate,
        mealType: MealType,
        eatenAt: Date = .now,
        source: FoodEntrySource,
        photoData: Data? = nil,
        in context: ModelContext
    ) -> FoodEntry {
        let portion = estimate.items
            .map { $0.portion.isEmpty ? $0.name : "\($0.name) (\($0.portion))" }
            .joined(separator: " · ")
        return add(
            name: estimate.title,
            mealType: mealType,
            macros: estimate.total,
            eatenAt: eatenAt,
            portion: portion,
            source: source,
            confidence: estimate.confidence,
            notes: estimate.notes,
            photoData: photoData,
            in: context
        )
    }

    /// Logs `servings` of a dish from a restaurant menu.
    @discardableResult
    static func add(
        dish: MenuDish,
        placeName: String,
        servings: Double = 1,
        mealType: MealType,
        eatenAt: Date = .now,
        in context: ModelContext
    ) -> FoodEntry {
        add(
            name: dish.name,
            mealType: mealType,
            macros: dish.macros.scaled(by: servings),
            eatenAt: eatenAt,
            portion: servings == 1 ? "1 serving" : "\(formatServings(servings)) servings",
            servings: servings,
            source: .menu,
            placeName: placeName,
            confidence: dish.isOfficialNutrition ? .high : .medium,
            in: context
        )
    }

    /// Copies `entry` to a new time and meal ("Log again"). The photo isn't copied.
    @discardableResult
    static func logAgain(_ entry: FoodEntry, eatenAt: Date = .now, mealType: MealType, in context: ModelContext) -> FoodEntry {
        add(
            name: entry.name,
            mealType: mealType,
            macros: entry.macros,
            eatenAt: eatenAt,
            portion: entry.portion,
            servings: entry.servings,
            source: .repeatEntry,
            placeName: entry.placeName,
            confidence: entry.confidence,
            notes: entry.notes,
            in: context
        )
    }

    /// Saves edits made directly on `entry` (with clean numbers).
    static func update(_ entry: FoodEntry, in context: ModelContext) {
        entry.macros = sanitized(entry.macros)
        LedgerStore.save(context)
    }

    static func delete(_ entry: FoodEntry, in context: ModelContext) {
        context.delete(entry)
        LedgerStore.save(context)
    }

    /// Entries eaten on `day`'s calendar date, oldest first.
    static func entries(on day: Date, in context: ModelContext, calendar: Calendar = .current) -> [FoodEntry] {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let descriptor = FetchDescriptor<FoodEntry>(
            predicate: #Predicate { $0.eatenAt >= start && $0.eatenAt < end },
            sortBy: [SortDescriptor(\.eatenAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// The most recent entry for each distinct name (case-insensitive), newest first.
    static func recentDistinct(limit: Int = 20, in context: ModelContext) -> [FoodEntry] {
        var descriptor = FetchDescriptor<FoodEntry>(sortBy: [SortDescriptor(\.eatenAt, order: .reverse)])
        descriptor.fetchLimit = 400
        let all = (try? context.fetch(descriptor)) ?? []
        var seen = Set<String>()
        var result: [FoodEntry] = []
        for entry in all where seen.insert(entry.name.lowercased()).inserted {
            result.append(entry)
            if result.count >= limit { break }
        }
        return result
    }

    static func eraseAll(in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<FoodEntry>())) ?? []
        for entry in all { context.delete(entry) }
        LedgerStore.save(context)
    }

    /// Non-negative, finite numbers with sensible caps.
    static func sanitized(_ macros: Macros) -> Macros {
        func clean(_ value: Double, max upper: Double) -> Double {
            guard value.isFinite, value > 0 else { return 0 }
            return min(value, upper)
        }
        return Macros(
            calories: clean(macros.calories, max: 20_000),
            proteinG: clean(macros.proteinG, max: 2_000),
            carbsG: clean(macros.carbsG, max: 4_000),
            fatG: clean(macros.fatG, max: 2_000),
            fiberG: clean(macros.fiberG, max: 500)
        )
    }

    /// "1.5", "2", "0.25".
    static func formatServings(_ servings: Double) -> String {
        let rounded = (servings * 100).rounded() / 100
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
    }
}
