//
//  WardrobeTypes.swift
//  Haki
//
//  Pure Foundation code (see Money.swift): clothing categories, colors,
//  seasons and styles; outfit completeness; wardrobe stats; and the AI
//  formats the "haki-ai" edge function returns for tagging and outfit ideas.
//

import Foundation

nonisolated enum ClothingCategory: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case top, bottom, dress, outerwear, shoes, accessory, bag, activewear, swimwear, sleepwear, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .top: "Tops"
        case .bottom: "Bottoms"
        case .dress: "Dresses & jumpsuits"
        case .outerwear: "Outerwear"
        case .shoes: "Shoes"
        case .accessory: "Accessories"
        case .bag: "Bags"
        case .activewear: "Activewear"
        case .swimwear: "Swimwear"
        case .sleepwear: "Sleep & lounge"
        case .other: "Other"
        }
    }

    var singularTitle: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        case .dress: "Dress or jumpsuit"
        case .outerwear: "Outerwear"
        case .shoes: "Shoes"
        case .accessory: "Accessory"
        case .bag: "Bag"
        case .activewear: "Activewear"
        case .swimwear: "Swimwear"
        case .sleepwear: "Sleep & lounge"
        case .other: "Other"
        }
    }

    var systemImage: String {
        switch self {
        case .top: "tshirt"
        case .bottom: "figure.walk"
        case .dress: "figure.dress.line.vertical.figure"
        case .outerwear: "cloud.snow"
        case .shoes: "shoe"
        case .accessory: "eyeglasses"
        case .bag: "bag"
        case .activewear: "figure.run"
        case .swimwear: "water.waves"
        case .sleepwear: "moon.zzz"
        case .other: "hanger"
        }
    }

    /// The part of an outfit this fills.
    var slot: OutfitSlot {
        switch self {
        case .top, .activewear, .sleepwear: .top
        case .bottom: .bottom
        case .dress, .swimwear: .onePiece
        case .outerwear: .outer
        case .shoes: .shoes
        case .accessory, .bag, .other: .extra
        }
    }

    /// Lenient mapping from AI or user text ("t-shirt", "jeans", "sneakers").
    static func guess(_ text: String) -> ClothingCategory {
        let t = text.lowercased()
        if let exact = ClothingCategory(rawValue: t) { return exact }
        let table: [(ClothingCategory, [String])] = [
            (.shoes, ["shoe", "sneaker", "boot", "sandal", "heel", "loafer", "trainer", "slipper", "flat"]),
            (.outerwear, ["jacket", "coat", "parka", "blazer", "cardigan", "vest", "puffer", "trench", "outer"]),
            (.dress, ["dress", "jumpsuit", "romper", "overall"]),
            (.bottom, ["pant", "jean", "trouser", "short", "skirt", "legging", "chino", "jogger", "bottom"]),
            (.bag, ["bag", "backpack", "purse", "tote", "clutch", "wallet"]),
            (.swimwear, ["swim", "bikini", "trunk"]),
            (.sleepwear, ["pajama", "pyjama", "robe", "sleep", "lounge"]),
            (.activewear, ["sports bra", "athletic", "gym", "running", "activewear"]),
            (.accessory, ["hat", "cap", "scarf", "belt", "watch", "glasses", "sunglasses", "jewel", "necklace", "earring", "bracelet", "ring", "tie", "glove", "sock", "accessor"]),
            (.top, ["shirt", "tee", "top", "blouse", "sweater", "hoodie", "polo", "tank", "sweatshirt", "jumper", "turtleneck", "camisole", "crop"]),
        ]
        for (category, words) in table where words.contains(where: { t.contains($0) }) {
            return category
        }
        return .other
    }
}

nonisolated enum OutfitSlot: String, CaseIterable, Codable, Sendable {
    case top, bottom, onePiece, outer, shoes, extra

    var title: String {
        switch self {
        case .top: "a top"
        case .bottom: "a bottom"
        case .onePiece: "a dress"
        case .outer: "outerwear"
        case .shoes: "shoes"
        case .extra: "an accessory"
        }
    }
}

nonisolated enum OutfitRules {
    /// What a wearable outfit still needs: a top and a bottom (or a one-piece)
    /// and shoes. Outerwear and accessories are optional.
    static func missing(_ categories: [ClothingCategory]) -> [OutfitSlot] {
        let slots = Set(categories.map(\.slot))
        var missing: [OutfitSlot] = []
        if !slots.contains(.onePiece) {
            if !slots.contains(.top) { missing.append(.top) }
            if !slots.contains(.bottom) { missing.append(.bottom) }
        }
        if !slots.contains(.shoes) { missing.append(.shoes) }
        return missing
    }

    static func isComplete(_ categories: [ClothingCategory]) -> Bool {
        missing(categories).isEmpty
    }

    /// "Add a top and shoes", or nil when complete.
    static func hint(_ categories: [ClothingCategory]) -> String? {
        let gaps = missing(categories).map(\.title)
        guard !gaps.isEmpty else { return nil }
        if gaps.count == 1 { return "Add \(gaps[0])" }
        return "Add " + gaps.dropLast().joined(separator: ", ") + " and " + (gaps.last ?? "")
    }
}

nonisolated enum ClothingSeason: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case spring, summer, fall, winter

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// The season on `date` in the northern (or southern) hemisphere.
    static func current(on date: Date = .now, southernHemisphere: Bool = false, calendar: Calendar = .current) -> ClothingSeason {
        let month = calendar.component(.month, from: date)
        let northern: ClothingSeason
        switch month {
        case 3...5: northern = .spring
        case 6...8: northern = .summer
        case 9...11: northern = .fall
        default: northern = .winter
        }
        guard southernHemisphere else { return northern }
        switch northern {
        case .spring: return .fall
        case .summer: return .winter
        case .fall: return .spring
        case .winter: return .summer
        }
    }
}

nonisolated enum ClothingStyle: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case casual
    case smartCasual = "smart_casual"
    case business, formal, athletic, lounge, party, outdoor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casual: "Casual"
        case .smartCasual: "Smart casual"
        case .business: "Business"
        case .formal: "Formal"
        case .athletic: "Athletic"
        case .lounge: "Lounge"
        case .party: "Going out"
        case .outdoor: "Outdoor"
        }
    }
}

/// A named color with a swatch, for tagging and filtering.
nonisolated enum ClothingColor: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case black, white, gray, navy, blue
    case lightBlue = "light_blue"
    case green, olive, brown, tan, beige, cream, red, burgundy, pink, purple, yellow, orange, gold, silver, denim
    case multicolor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lightBlue: "Light blue"
        case .multicolor: "Multicolor"
        default: rawValue.capitalized
        }
    }

    var hex: String {
        switch self {
        case .black: "#1C1C1E"
        case .white: "#F7F7F5"
        case .gray: "#8E8E93"
        case .navy: "#1F2A44"
        case .blue: "#2F6FDB"
        case .lightBlue: "#9CC3F0"
        case .green: "#2E8B57"
        case .olive: "#6B7035"
        case .brown: "#7B4B2A"
        case .tan: "#C8A27A"
        case .beige: "#D9C7A7"
        case .cream: "#F2E8D5"
        case .red: "#D0312D"
        case .burgundy: "#7A1F2B"
        case .pink: "#F09CB8"
        case .purple: "#7D4FB5"
        case .yellow: "#F2C94C"
        case .orange: "#EE7F2D"
        case .gold: "#C9A44C"
        case .silver: "#C0C0C8"
        case .denim: "#4A6A8F"
        case .multicolor: "#B07CC6"
        }
    }

    /// Neutral colors pair with anything.
    var isNeutral: Bool {
        switch self {
        case .black, .white, .gray, .navy, .brown, .tan, .beige, .cream, .denim: true
        default: false
        }
    }

    /// Lenient mapping from AI or user text ("charcoal", "light blue", "khaki").
    static func guess(_ text: String) -> ClothingColor? {
        let t = text.lowercased().replacingOccurrences(of: "-", with: " ").trimmingCharacters(in: .whitespaces)
        if let exact = ClothingColor(rawValue: t.replacingOccurrences(of: " ", with: "_")) { return exact }
        let synonyms: [String: ClothingColor] = [
            "charcoal": .gray, "grey": .gray, "heather": .gray, "ivory": .cream, "off white": .cream,
            "khaki": .tan, "camel": .tan, "sand": .beige, "taupe": .beige, "nude": .beige,
            "maroon": .burgundy, "wine": .burgundy, "crimson": .red, "scarlet": .red,
            "sky blue": .lightBlue, "baby blue": .lightBlue, "teal": .green, "mint": .green, "forest green": .green,
            "army green": .olive, "khaki green": .olive, "lavender": .purple, "lilac": .purple, "violet": .purple,
            "mustard": .yellow, "rust": .orange, "coral": .orange, "blush": .pink, "rose": .pink,
            "chocolate": .brown, "cognac": .brown, "jeans": .denim, "indigo": .denim,
            "multi": .multicolor, "print": .multicolor, "patterned": .multicolor,
        ]
        if let match = synonyms[t] { return match }
        for color in ClothingColor.allCases where t.contains(color.title.lowercased()) {
            return color
        }
        return nil
    }
}

// MARK: - Stats

nonisolated struct WardrobeWearInfo: Equatable, Sendable {
    let id: String
    let timesWorn: Int
    let lastWornAt: Date?
    let priceCents: Int?
    let addedAt: Date
}

nonisolated enum WardrobeStats {
    /// Price ÷ wears, in cents; nil without a price. Counts at least one wear,
    /// so a piece never worn shows its full price.
    static func costPerWearCents(priceCents: Int?, timesWorn: Int) -> Int? {
        guard let priceCents, priceCents > 0 else { return nil }
        return Int((Double(priceCents) / Double(max(timesWorn, 1))).rounded())
    }

    /// Pieces not worn in `days` days (or never, if added that long ago).
    static func forgotten(_ items: [WardrobeWearInfo], days: Int = 90, now: Date = .now) -> [String] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return items
            .filter { ($0.lastWornAt ?? $0.addedAt) < cutoff }
            .sorted { ($0.lastWornAt ?? $0.addedAt) < ($1.lastWornAt ?? $1.addedAt) }
            .map(\.id)
    }

    /// Most worn first; ties by most recent wear.
    static func mostWorn(_ items: [WardrobeWearInfo], limit: Int = 5) -> [String] {
        items
            .filter { $0.timesWorn > 0 }
            .sorted {
                if $0.timesWorn != $1.timesWorn { return $0.timesWorn > $1.timesWorn }
                return ($0.lastWornAt ?? .distantPast) > ($1.lastWornAt ?? .distantPast)
            }
            .prefix(max(limit, 0))
            .map(\.id)
    }
}

// MARK: - AI formats ("haki-ai" tag_clothing / suggest_outfits)

/// What Claude read from a clothing photo, mapped to Haki's types.
nonisolated struct ClothingTags: Equatable, Codable, Sendable {
    var isClothing: Bool
    var name: String
    var category: ClothingCategory
    var colors: [ClothingColor]
    var pattern: String
    var seasons: [ClothingSeason]
    var styles: [ClothingStyle]
    /// 1 (very casual) ... 5 (black tie).
    var formality: Int
    /// 1 (very light) ... 5 (very warm).
    var warmth: Int

    enum CodingKeys: String, CodingKey {
        case isClothing = "is_clothing"
        case name, category, colors, pattern, seasons, styles, formality, warmth
    }

    init(isClothing: Bool = true, name: String, category: ClothingCategory, colors: [ClothingColor] = [], pattern: String = "", seasons: [ClothingSeason] = [], styles: [ClothingStyle] = [], formality: Int = 2, warmth: Int = 3) {
        self.isClothing = isClothing
        self.name = name
        self.category = category
        self.colors = colors
        self.pattern = pattern
        self.seasons = seasons
        self.styles = styles
        self.formality = min(5, max(1, formality))
        self.warmth = min(5, max(1, warmth))
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isClothing = try container.decodeIfPresent(Bool.self, forKey: .isClothing) ?? true
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        category = ClothingCategory.guess(try container.decodeIfPresent(String.self, forKey: .category) ?? "")
        var seenColors = Set<ClothingColor>()
        colors = (try container.decodeIfPresent([String].self, forKey: .colors) ?? [])
            .compactMap(ClothingColor.guess)
            .filter { seenColors.insert($0).inserted }
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        var seenSeasons = Set<ClothingSeason>()
        seasons = (try container.decodeIfPresent([String].self, forKey: .seasons) ?? [])
            .compactMap { ClothingSeason(rawValue: $0.lowercased() == "autumn" ? "fall" : $0.lowercased()) }
            .filter { seenSeasons.insert($0).inserted }
        var seenStyles = Set<ClothingStyle>()
        styles = (try container.decodeIfPresent([String].self, forKey: .styles) ?? [])
            .compactMap { ClothingStyle(rawValue: $0.lowercased().replacingOccurrences(of: " ", with: "_").replacingOccurrences(of: "-", with: "_")) }
            .filter { seenStyles.insert($0).inserted }
        formality = min(5, max(1, try container.decodeIfPresent(Int.self, forKey: .formality) ?? 2))
        warmth = min(5, max(1, try container.decodeIfPresent(Int.self, forKey: .warmth) ?? 3))
    }
}

/// A piece of clothing as sent to the AI for outfit ideas (no photo).
nonisolated struct WardrobePieceSummary: Equatable, Codable, Sendable {
    var id: String
    var name: String
    var category: String
    var colors: [String]
    var seasons: [String]
    var styles: [String]
    var formality: Int
    var warmth: Int
    var timesWorn: Int

    enum CodingKeys: String, CodingKey {
        case id, name, category, colors, seasons, styles, formality, warmth
        case timesWorn = "times_worn"
    }
}

nonisolated struct OutfitIdea: Equatable, Hashable, Codable, Sendable {
    var name: String
    var itemIDs: [String]
    var reason: String

    enum CodingKeys: String, CodingKey {
        case name, reason
        case itemIDs = "item_ids"
    }
}

nonisolated struct OutfitIdeaReport: Equatable, Codable, Sendable {
    var outfits: [OutfitIdea]
    var notes: String

    init(outfits: [OutfitIdea], notes: String = "") {
        self.outfits = outfits
        self.notes = notes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outfits = try container.decodeIfPresent([OutfitIdea].self, forKey: .outfits) ?? []
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }

    enum CodingKeys: String, CodingKey { case outfits, notes }

    /// Drops ids that aren't in the wardrobe (the AI can misremember) and
    /// ideas left with fewer than two pieces.
    func keepingOnly(knownIDs: Set<String>) -> OutfitIdeaReport {
        let cleaned = outfits.compactMap { idea -> OutfitIdea? in
            var seen = Set<String>()
            let ids = idea.itemIDs.filter { knownIDs.contains($0) && seen.insert($0).inserted }
            guard ids.count >= 2 else { return nil }
            return OutfitIdea(name: idea.name, itemIDs: ids, reason: idea.reason)
        }
        return OutfitIdeaReport(outfits: cleaned, notes: notes)
    }
}
