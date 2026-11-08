//
//  MenuRanking.swift
//  Haki
//
//  Pure Foundation code (see Money.swift): restaurant menus researched by the
//  "food-ai" edge function, and the filters, sorts and "healthiest picks"
//  the menu screen offers.
//

import Foundation

// MARK: - Menu format ("food-ai" menu)

nonisolated enum MenuTag: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case highProtein = "high_protein"
    case lowCalorie = "low_calorie"
    case lowCarb = "low_carb"
    case highFiber = "high_fiber"
    case vegetarian
    case vegan
    case glutenFree = "gluten_free"
    case balanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highProtein: "High protein"
        case .lowCalorie: "Lower calorie"
        case .lowCarb: "Low carb"
        case .highFiber: "High fiber"
        case .vegetarian: "Vegetarian"
        case .vegan: "Vegan"
        case .glutenFree: "Gluten-free"
        case .balanced: "Balanced"
        }
    }

    var systemImage: String {
        switch self {
        case .highProtein: "bolt.fill"
        case .lowCalorie: "flame"
        case .lowCarb: "leaf"
        case .highFiber: "laurel.leading"
        case .vegetarian, .vegan: "carrot.fill"
        case .glutenFree: "checkmark.seal"
        case .balanced: "scalemass"
        }
    }
}

nonisolated struct MenuDish: Equatable, Hashable, Codable, Identifiable, Sendable {
    var name: String
    var section: String
    var description: String
    /// In the menu's currency; nil when no price was found.
    var price: Double?
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    /// Published by the business (true) or estimated by Haki's AI (false).
    var isOfficialNutrition: Bool
    var tags: [MenuTag]
    /// 1 (least healthy) to 10 (healthiest).
    var healthScore: Int

    var id: String { "\(section)|\(name)" }

    var macros: Macros { Macros(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG) }

    /// Price in cents (minor units), or nil.
    var priceCents: Int? {
        guard let price, price.isFinite, price > 0 else { return nil }
        return Int((price * 100).rounded())
    }

    /// Grams of protein per 100 kcal, or nil without calories.
    var proteinPer100Calories: Double? {
        guard calories > 0 else { return nil }
        return proteinG / calories * 100
    }

    /// Grams of protein per whole unit of currency, or nil without a price.
    var proteinPerCurrencyUnit: Double? {
        guard let price, price > 0, proteinG > 0 else { return nil }
        return proteinG / price
    }

    enum CodingKeys: String, CodingKey {
        case name, section, description, price, calories, tags
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case nutritionSource = "nutrition_source"
        case healthScore = "health_score"
    }

    init(
        name: String, section: String = "Menu", description: String = "", price: Double? = nil,
        calories: Double, proteinG: Double, carbsG: Double = 0, fatG: Double = 0,
        isOfficialNutrition: Bool = false, tags: [MenuTag] = [], healthScore: Int = 5
    ) {
        self.name = name
        self.section = section
        self.description = description
        self.price = price
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.isOfficialNutrition = isOfficialNutrition
        self.tags = tags
        self.healthScore = min(10, max(1, healthScore))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        section = try container.decodeIfPresent(String.self, forKey: .section) ?? "Menu"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        calories = try container.decodeIfPresent(Double.self, forKey: .calories) ?? 0
        proteinG = try container.decodeIfPresent(Double.self, forKey: .proteinG) ?? 0
        carbsG = try container.decodeIfPresent(Double.self, forKey: .carbsG) ?? 0
        fatG = try container.decodeIfPresent(Double.self, forKey: .fatG) ?? 0
        isOfficialNutrition = (try container.decodeIfPresent(String.self, forKey: .nutritionSource)) == "official"
        // Unknown tags (from a newer server) are dropped rather than failing the menu.
        let rawTags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        var seen = Set<MenuTag>()
        tags = rawTags.compactMap(MenuTag.init(rawValue:)).filter { seen.insert($0).inserted }
        healthScore = min(10, max(1, try container.decodeIfPresent(Int.self, forKey: .healthScore) ?? 5))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(section, forKey: .section)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(price, forKey: .price)
        try container.encode(calories, forKey: .calories)
        try container.encode(proteinG, forKey: .proteinG)
        try container.encode(carbsG, forKey: .carbsG)
        try container.encode(fatG, forKey: .fatG)
        try container.encode(isOfficialNutrition ? "official" : "estimated", forKey: .nutritionSource)
        try container.encode(tags, forKey: .tags)
        try container.encode(healthScore, forKey: .healthScore)
    }
}

nonisolated struct MenuSource: Equatable, Hashable, Codable, Sendable {
    var title: String
    var url: String
}

nonisolated struct MenuReport: Equatable, Codable, Sendable {
    var placeName: String
    var cuisine: String
    var foundMenu: Bool
    /// ISO 4217, e.g. "USD".
    var currency: String
    var items: [MenuDish]
    var notes: String
    var sources: [MenuSource]
    /// ISO 8601 timestamp from the server.
    var generatedAt: String
    var cached: Bool

    enum CodingKeys: String, CodingKey {
        case placeName = "place_name"
        case foundMenu = "found_menu"
        case generatedAt = "generated_at"
        case cuisine, currency, items, notes, sources, cached
    }

    init(
        placeName: String, cuisine: String = "", foundMenu: Bool = true, currency: String = "USD",
        items: [MenuDish], notes: String = "", sources: [MenuSource] = [], generatedAt: String = "", cached: Bool = false
    ) {
        self.placeName = placeName
        self.cuisine = cuisine
        self.foundMenu = foundMenu
        self.currency = currency
        self.items = items
        self.notes = notes
        self.sources = sources
        self.generatedAt = generatedAt
        self.cached = cached
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        placeName = try container.decodeIfPresent(String.self, forKey: .placeName) ?? ""
        cuisine = try container.decodeIfPresent(String.self, forKey: .cuisine) ?? ""
        foundMenu = try container.decodeIfPresent(Bool.self, forKey: .foundMenu) ?? false
        currency = try container.decodeIfPresent(String.self, forKey: .currency) ?? "USD"
        items = try container.decodeIfPresent([MenuDish].self, forKey: .items) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        sources = try container.decodeIfPresent([MenuSource].self, forKey: .sources) ?? []
        generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt) ?? ""
        cached = try container.decodeIfPresent(Bool.self, forKey: .cached) ?? false
    }

    /// Item sections in menu order (first appearance).
    var sections: [String] {
        var seen = Set<String>()
        return items.map(\.section).filter { seen.insert($0).inserted }
    }

    var generatedDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: generatedAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: generatedAt)
    }
}

// MARK: - Filtering and sorting

nonisolated enum MenuSort: String, CaseIterable, Identifiable, Sendable {
    case healthiest, mostProtein, proteinPerCalorie, proteinPerPrice, fewestCalories, lowestPrice, menuOrder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .healthiest: "Healthiest"
        case .mostProtein: "Most protein"
        case .proteinPerCalorie: "Protein per calorie"
        case .proteinPerPrice: "Protein per dollar"
        case .fewestCalories: "Fewest calories"
        case .lowestPrice: "Lowest price"
        case .menuOrder: "Menu order"
        }
    }
}

nonisolated struct MenuFilter: Equatable, Sendable {
    var query: String = ""
    var maxCalories: Int?
    var minProteinG: Int?
    var maxPriceCents: Int?
    /// Every tag here must be on the dish.
    var requiredTags: Set<MenuTag> = []

    static let none = MenuFilter()

    var isActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || maxCalories != nil || minProteinG != nil || maxPriceCents != nil || !requiredTags.isEmpty
    }

    func matches(_ dish: MenuDish) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !needle.isEmpty {
            let haystack = "\(dish.name) \(dish.section) \(dish.description)"
            guard haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { return false }
        }
        if let maxCalories, dish.calories > Double(maxCalories) { return false }
        if let minProteinG, dish.proteinG < Double(minProteinG) { return false }
        if let maxPriceCents {
            // A dish without a price can't be shown to fit a budget.
            guard let cents = dish.priceCents, cents <= maxPriceCents else { return false }
        }
        if !requiredTags.isSubset(of: Set(dish.tags)) { return false }
        return true
    }
}

nonisolated enum MenuRanking {
    /// The dishes that pass `filter`, ordered by `sort`. Ties, and dishes
    /// missing what the sort needs (a price, calories), keep menu order;
    /// dishes missing the value go last.
    static func apply(_ dishes: [MenuDish], filter: MenuFilter = .none, sort: MenuSort) -> [MenuDish] {
        let kept = dishes.enumerated().filter { filter.matches($0.element) }
        guard sort != .menuOrder else { return kept.map(\.element) }
        let sorted = kept.sorted { lhs, rhs in
            let a = key(lhs.element, sort)
            let b = key(rhs.element, sort)
            switch (a, b) {
            case let (a?, b?):
                if a != b { return a > b }
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case (nil, nil):
                break
            }
            return lhs.offset < rhs.offset
        }
        return sorted.map(\.element)
    }

    /// Higher is better for every sort (costs are negated).
    private static func key(_ dish: MenuDish, _ sort: MenuSort) -> Double? {
        switch sort {
        case .healthiest: healthiness(dish)
        case .mostProtein: dish.proteinG
        case .proteinPerCalorie: dish.proteinPer100Calories
        case .proteinPerPrice: dish.proteinPerCurrencyUnit
        case .fewestCalories: dish.calories > 0 ? -dish.calories : nil
        case .lowestPrice: dish.priceCents.map { -Double($0) }
        case .menuOrder: nil
        }
    }

    /// The AI's health score, nudged by protein density so two "8"s with
    /// very different protein don't tie.
    static func healthiness(_ dish: MenuDish) -> Double {
        let density = min(dish.proteinPer100Calories ?? 0, 15) / 15 // 0...1
        return Double(dish.healthScore) + density
    }

    /// Up to `limit` standout dishes for someone who has `remainingCalories`
    /// left today (nil = unknown): healthy, protein-dense mains that fit.
    /// When nothing fits the remaining calories, falls back to the healthiest.
    static func healthyPicks(_ dishes: [MenuDish], remainingCalories: Int? = nil, limit: Int = 3) -> [MenuDish] {
        guard limit > 0 else { return [] }
        let candidates = dishes.filter { $0.calories >= 150 && $0.healthScore >= 6 }
        let fitting: [MenuDish]
        if let remainingCalories, remainingCalories > 0 {
            let fit = candidates.filter { $0.calories <= Double(remainingCalories) }
            fitting = fit.isEmpty ? candidates : fit
        } else {
            fitting = candidates
        }
        let ranked = apply(fitting, sort: .healthiest)
        return Array(ranked.prefix(limit))
    }
}
