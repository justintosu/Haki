//
//  FoodAIService.swift
//  Haki
//
//  Talks to the "food-ai" edge function (supabase/functions/food-ai), which
//  asks Claude to estimate a meal's nutrition from a photo or description
//  and to research a restaurant's menu. Every result is an estimate and the
//  screens say so.
//
//  Injected at the root: `.environment(FoodAIService.live)`; read with
//  `@Environment(FoodAIService.self) private var foodAI`. The preview
//  instance answers with sample data and never touches the network.
//

import Foundation
import Observation
import Supabase

/// A place whose menu to look up. Built from a map search result.
struct FoodPlaceQuery: Encodable, Hashable, Sendable {
    var placeName: String
    var address: String?
    var city: String?
    var region: String?
    /// ISO 3166-1 alpha-2, e.g. "US".
    var country: String?
    var latitude: Double?
    var longitude: Double?
    var website: String?

    enum CodingKeys: String, CodingKey {
        case placeName = "place_name"
        case address, city, region, country, latitude, longitude, website
    }

    /// Same business at about the same spot (≈100 m) — matches the server's cache key.
    var cacheKey: String {
        let name = placeName.lowercased().filter { $0.isLetter || $0.isNumber }
        if let latitude, let longitude {
            return "\(name)|\(String(format: "%.3f", latitude)),\(String(format: "%.3f", longitude))"
        }
        return "\(name)|\((address ?? city ?? "").lowercased())"
    }
}

@MainActor
@Observable
final class FoodAIService {
    private let client: SupabaseClient?
    /// Menus fetched this session, so going back and forth doesn't ask again.
    private var menuCache: [String: MenuReport] = [:]

    init(client: SupabaseClient?) {
        self.client = client
    }

    /// Answers with sample data after a short pause; no network.
    static let preview = FoodAIService(client: nil)
    /// Uses `Backend.client`.
    static let live = FoodAIService(client: Backend.client)

    var isPreview: Bool { client == nil }

    // MARK: Meals

    /// Estimates the nutrition of a meal from a JPEG photo, a description,
    /// or both (at least one is required). Takes 5–30 seconds.
    func analyzeMeal(photoJPEG: Data?, description: String?) async throws -> MealEstimate {
        let text = description?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (text?.isEmpty ?? true) ? nil : text
        guard photoJPEG != nil || note != nil else {
            throw BackendError(code: "bad_request", message: "Add a photo or describe what you ate.")
        }
        guard let client else {
            try await Task.sleep(for: .seconds(1.5))
            return FoodAIPreviewSamples.meal
        }
        let request = FoodAIMealRequest(
            action: "analyze_meal",
            imageBase64: photoJPEG?.base64EncodedString(),
            mediaType: photoJPEG == nil ? nil : "image/jpeg",
            description: note.map { String($0.prefix(600)) }
        )
        do {
            return try await client.functions.invoke(
                "food-ai",
                options: FunctionInvokeOptions(body: request, timeoutInterval: 90),
                decoder: JSONDecoder()
            )
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't estimate that meal. Try again.")
        }
    }

    // MARK: Menus

    /// A menu already fetched this session, if any.
    func cachedMenu(for place: FoodPlaceQuery) -> MenuReport? {
        menuCache[place.cacheKey]
    }

    /// Looks up a place's menu with prices, calories and protein. The first
    /// lookup of a place can take up to two minutes (the server searches the
    /// web); later ones come from a cache. `refresh` asks for a new search.
    func menu(for place: FoodPlaceQuery, refresh: Bool = false) async throws -> MenuReport {
        if !refresh, let cached = menuCache[place.cacheKey] { return cached }
        guard let client else {
            try await Task.sleep(for: .seconds(2))
            var sample = FoodAIPreviewSamples.menu
            sample.placeName = place.placeName
            menuCache[place.cacheKey] = sample
            return sample
        }
        let request = FoodAIMenuRequest(action: "menu", place: place, refresh: refresh)
        do {
            let report: MenuReport = try await client.functions.invoke(
                "food-ai",
                options: FunctionInvokeOptions(body: request, timeoutInterval: 160),
                decoder: JSONDecoder()
            )
            if report.foundMenu { menuCache[place.cacheKey] = report }
            return report
        } catch {
            throw Backend.userFacingError(error, fallback: "Couldn't look up that menu. Try again.")
        }
    }

    /// Forgets menus fetched this session (e.g. on sign-out).
    func reset() {
        menuCache = [:]
    }
}

// MARK: - Requests

private struct FoodAIMealRequest: Encodable {
    var action: String
    var imageBase64: String?
    var mediaType: String?
    var description: String?

    enum CodingKeys: String, CodingKey {
        case action, description
        case imageBase64 = "image_base64"
        case mediaType = "media_type"
    }
}

private struct FoodAIMenuRequest: Encodable {
    var action: String
    var place: FoodPlaceQuery
    var refresh: Bool

    enum CodingKeys: String, CodingKey {
        case action, refresh
    }

    /// Flattens the place's fields into the top-level object the function expects.
    func encode(to encoder: any Encoder) throws {
        try place.encode(to: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(action, forKey: .action)
        try container.encode(refresh, forKey: .refresh)
    }
}

// MARK: - Preview samples

enum FoodAIPreviewSamples {
    static let meal = MealEstimate(
        isFood: true,
        title: "Chicken burrito bowl",
        items: [
            MealEstimateItem(name: "Grilled chicken", portion: "4 oz", grams: 113, calories: 185, proteinG: 35, carbsG: 0, fatG: 4.5, fiberG: 0),
            MealEstimateItem(name: "Cilantro-lime rice", portion: "½ cup", grams: 100, calories: 210, proteinG: 4, carbsG: 40, fatG: 4, fiberG: 1),
            MealEstimateItem(name: "Black beans", portion: "½ cup", grams: 120, calories: 130, proteinG: 8, carbsG: 22, fatG: 1, fiberG: 7),
            MealEstimateItem(name: "Salsa and lettuce", portion: "½ cup", grams: 90, calories: 30, proteinG: 1, carbsG: 6, fatG: 0, fiberG: 2),
        ],
        confidence: .medium,
        notes: "Assumed no sour cream or cheese."
    )

    static let menu = MenuReport(
        placeName: "Green Fork Kitchen",
        cuisine: "Bowls and salads",
        foundMenu: true,
        currency: "USD",
        items: [
            MenuDish(name: "Chicken Power Bowl", section: "Bowls", description: "Chicken, quinoa, kale, roasted vegetables", price: 13.95, calories: 610, proteinG: 48, carbsG: 52, fatG: 21, isOfficialNutrition: true, tags: [.highProtein, .balanced, .highFiber], healthScore: 9),
            MenuDish(name: "Salmon Rice Bowl", section: "Bowls", description: "Salmon, brown rice, cucumber, avocado", price: 15.5, calories: 720, proteinG: 38, carbsG: 68, fatG: 30, isOfficialNutrition: true, tags: [.highProtein, .balanced], healthScore: 8),
            MenuDish(name: "Tofu Greens Bowl", section: "Bowls", description: "Crispy tofu, greens, sesame dressing", price: 12.5, calories: 480, proteinG: 24, carbsG: 38, fatG: 24, tags: [.vegan, .lowCalorie], healthScore: 8),
            MenuDish(name: "Steak Cobb Salad", section: "Salads", description: "Steak, egg, bacon, blue cheese", price: 16.25, calories: 830, proteinG: 55, carbsG: 14, fatG: 60, tags: [.highProtein, .lowCarb], healthScore: 6),
            MenuDish(name: "Grilled Chicken Wrap", section: "Wraps", description: "Chicken, romaine, parmesan, wheat wrap", price: 11.75, calories: 560, proteinG: 39, carbsG: 45, fatG: 22, tags: [.highProtein], healthScore: 7),
            MenuDish(name: "Mac and Cheese", section: "Sides", description: "Three-cheese baked pasta", price: 5.5, calories: 540, proteinG: 18, carbsG: 50, fatG: 30, healthScore: 3),
        ],
        notes: "Prices from the online ordering page; some nutrition is estimated.",
        sources: [MenuSource(title: "Green Fork Kitchen menu", url: "https://example.com/menu")],
        generatedAt: "2026-11-08T12:00:00Z",
        cached: false
    )
}
