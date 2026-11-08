//
//  FoodComponents.swift
//  Haki
//
//  Small pieces shared by the food screens: number formatting and parsing,
//  the calorie ring, macro bars, a day's summary, and the food log row.
//

import Foundation
import SwiftUI
import UIKit

// MARK: - Formatting

/// Formats and parses the numbers on the food screens.
enum FoodFormat {
    /// Whole number with grouping: "1,240". Non-finite or absurd values read as "0".
    static func whole(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1_000_000_000 else { return "0" }
        return Int(value.rounded()).formatted()
    }

    /// Grams: one decimal under 10 ("4.5"), whole numbers above ("38").
    static func grams(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1_000_000_000 else { return "0" }
        if abs(value) < 10 {
            return value.formatted(FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...1)))
        }
        return Int(value.rounded()).formatted()
    }

    /// "520 kcal".
    static func kcal(_ value: Double) -> String {
        "\(whole(value)) kcal"
    }

    /// "520 kcal · 38 g protein".
    static func macroLine(_ macros: Macros) -> String {
        "\(kcal(macros.calories)) · \(grams(macros.proteinG)) g protein"
    }

    /// The text an editable number field starts with: "12.5", "185", "0".
    /// No grouping separators, so `parse` reads it back unchanged.
    static func fieldText(_ value: Double) -> String {
        guard value.isFinite, value > 0, value < 1_000_000 else { return "0" }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(rounded)
    }

    /// Reads what someone typed ("12,5" or "12.5"). Nil for empty text,
    /// nonsense, negative or absurdly large numbers.
    static func parse(_ text: String) -> Double? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0, value < 100_000 else {
            return nil
        }
        return value
    }

    /// "Today", "Yesterday" or "Monday, Nov 3".
    static func dayTitle(_ day: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

/// Colors for each nutrient. Always shown next to a text label, never alone.
enum NutritionPalette {
    static let calories = Color.accentColor
    static let protein = Color.pink
    static let carbs = Color.blue
    static let fat = Color.orange
    static let fiber = Color.green
}

// MARK: - Bars and ring

/// A rounded progress bar, 0...1 (anything above 1 shows full).
struct NutritionProgressBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(clamped))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private var clamped: Double {
        guard fraction.isFinite else { return 0 }
        return min(max(fraction, 0), 1)
    }
}

/// Calories left (or over) inside a ring that fills as the day's calories add up.
struct NutritionCalorieRing: View {
    let progress: NutritionProgress
    var lineWidth: CGFloat = 12
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 116

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: trimEnd)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(FoodFormat.whole(Double(abs(progress.remainingCalories))))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(progress.isOverCalories ? "kcal over" : "kcal left")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(progress.isOverCalories ? Color.hakiWarning : Color.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(lineWidth + 6)
        }
        .frame(width: size, height: size)
        .animation(.snappy, value: progress.calorieFraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories")
        .accessibilityValue(accessibilityText)
    }

    private var trimEnd: CGFloat {
        let fraction = progress.calorieFraction
        guard fraction.isFinite else { return 0 }
        return CGFloat(min(max(fraction, 0), 1))
    }

    private var ringColor: Color {
        progress.isOverCalories ? Color.hakiWarning : NutritionPalette.calories
    }

    private var accessibilityText: String {
        let eaten = FoodFormat.whole(progress.consumed.calories)
        let goal = FoodFormat.whole(Double(progress.targets.calories))
        let remaining = FoodFormat.whole(Double(abs(progress.remainingCalories)))
        let state = progress.isOverCalories ? "\(remaining) over" : "\(remaining) left"
        return "\(eaten) of \(goal) kilocalories eaten, \(state)"
    }
}

/// Protein toward its target, shown large: "82 of 140 g protein".
struct NutritionProteinBar: View {
    let progress: NutritionProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(FoodFormat.grams(progress.consumed.proteinG))
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("of \(progress.targets.proteinG) g protein")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            NutritionProgressBar(fraction: progress.proteinFraction, tint: NutritionPalette.protein, height: 10)
            statusLabel
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein")
        .accessibilityValue(accessibilityText)
    }

    @ViewBuilder
    private var statusLabel: some View {
        if progress.hasHitProtein {
            Label("Protein goal reached", systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.hakiPositive)
        } else {
            Text("\(progress.remainingProteinG) g to go")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var accessibilityText: String {
        let eaten = FoodFormat.grams(progress.consumed.proteinG)
        if progress.hasHitProtein {
            return "\(eaten) of \(progress.targets.proteinG) grams, goal reached"
        }
        return "\(eaten) of \(progress.targets.proteinG) grams, \(progress.remainingProteinG) to go"
    }
}

/// A small labeled bar: "Carbs", "120 / 220 g".
struct NutritionMiniBar: View {
    let title: String
    let consumed: Double
    let target: Int
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Text("\(FoodFormat.grams(consumed)) / \(target) g")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            NutritionProgressBar(fraction: fraction, tint: tint, height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(FoodFormat.grams(consumed)) of \(target) grams")
    }
}

/// A day's calories (ring), protein (large bar) and carbs, fat and fiber (small bars).
struct NutritionDaySummary: View {
    let progress: NutritionProgress
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) {
                    NutritionCalorieRing(progress: progress)
                    headline
                }
                VStack(alignment: .leading, spacing: 12) {
                    minorBars
                }
            } else {
                HStack(alignment: .center, spacing: 18) {
                    NutritionCalorieRing(progress: progress)
                    headline
                }
                HStack(alignment: .top, spacing: 14) {
                    minorBars
                }
            }
        }
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(FoodFormat.whole(progress.consumed.calories)) of \(FoodFormat.whole(Double(progress.targets.calories))) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("eaten")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            NutritionProteinBar(progress: progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var minorBars: some View {
        NutritionMiniBar(
            title: "Carbs",
            consumed: progress.consumed.carbsG,
            target: progress.targets.carbsG,
            fraction: progress.carbsFraction,
            tint: NutritionPalette.carbs
        )
        NutritionMiniBar(
            title: "Fat",
            consumed: progress.consumed.fatG,
            target: progress.targets.fatG,
            fraction: progress.fatFraction,
            tint: NutritionPalette.fat
        )
        NutritionMiniBar(
            title: "Fiber",
            consumed: progress.consumed.fiberG,
            target: progress.targets.fiberG,
            fraction: progress.fiberFraction,
            tint: NutritionPalette.fiber
        )
    }
}

// MARK: - Food log rows

/// The meal photo, or the meal's icon on a tinted square when there's no photo.
struct FoodEntryThumbnail: View {
    let photoData: Data?
    let mealType: MealType
    var size: CGFloat = 48

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        if let data = photoData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: mealType.systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: size, height: size)
                .background(Color.accentColor.opacity(0.14))
        }
    }
}

/// "AI estimate" or "Menu · Green Fork Kitchen"; nothing for entries typed in by hand.
struct FoodSourceTag: View {
    let source: FoodEntrySource
    let placeName: String?

    var body: some View {
        if let title {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(tint)
                .background(tint.opacity(0.12), in: Capsule())
        }
    }

    private var title: String? {
        switch source {
        case .aiPhoto, .aiText:
            return "AI estimate"
        case .menu:
            if let placeName, !placeName.isEmpty {
                return "Menu · \(placeName)"
            }
            return "Menu"
        case .manual, .repeatEntry:
            return nil
        }
    }

    private var systemImage: String {
        source == .menu ? "fork.knife" : "sparkles"
    }

    private var tint: Color {
        source == .menu ? Color.hakiPositive : Color.purple
    }
}

/// One logged food: photo or icon, name, portion, "520 kcal · 38 g protein", source tag and time.
struct FoodEntryRow: View {
    let entry: FoodEntry
    var showsTime: Bool = true
    var showsDate: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            FoodEntryThumbnail(photoData: entry.photoData, mealType: entry.mealType)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !entry.portion.isEmpty {
                    Text(entry.portion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(FoodFormat.macroLine(entry.macros))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                FoodSourceTag(source: entry.source, placeName: entry.placeName)
            }
            Spacer(minLength: 8)
            if showsTime || showsDate {
                Text(timeText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var timeText: String {
        if showsDate {
            return entry.eatenAt.formatted(.dateTime.month(.abbreviated).day())
        }
        return entry.eatenAt.formatted(.dateTime.hour().minute())
    }
}

#Preview("Day summary") {
    NutritionDaySummary(
        progress: NutritionProgress(
            consumed: Macros(calories: 1_240, proteinG: 82, carbsG: 120, fatG: 40, fiberG: 14),
            targets: .standard
        )
    )
    .hakiCard()
    .padding()
    .background(Color.hakiBackground)
    .previewEnvironment()
}

#Preview("Row") {
    List {
        FoodEntryRow(entry: PreviewData.sampleFoodEntry)
    }
    .previewEnvironment()
}
