//
//  MenuDishSheet.swift
//  Haki
//
//  A dish from a restaurant menu: what's in it, its nutrition for the
//  chosen number of servings, and "Log it" to add it to today's food log.
//

import Foundation
import SwiftData
import SwiftUI

struct MenuDishSheet: View {
    let dish: MenuDish
    let placeName: String
    let currency: String
    /// Called after the dish is logged, with the meal it was logged to.
    var onLogged: (MealType) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var servings: Double = 1
    @State private var mealType: MealType = MealType.suggested(for: .now)

    var body: some View {
        NavigationStack {
            Form {
                summarySection
                nutritionSection
                logSection
            }
            .navigationTitle("Dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log it") { log() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: Sections

    private var summarySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(dish.name)
                        .font(.title3.weight(.bold))
                    Spacer(minLength: 8)
                    MenuScoreBadge(score: dish.healthScore)
                }
                if !dish.description.isEmpty {
                    Text(dish.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if let price = dish.price, price > 0 {
                        Text(MenuFormat.price(price, currency: currency))
                            .font(.headline)
                            .monospacedDigit()
                    }
                }
                if !dish.tags.isEmpty {
                    MenuTagRow(tags: dish.tags)
                }
                MenuNutritionMarker(isOfficial: dish.isOfficialNutrition)
            }
            .padding(.vertical, 4)
        }
    }

    private var nutritionSection: some View {
        let macros = dish.macros.scaled(by: servings)
        return Section {
            LabeledContent("Calories", value: MenuFormat.kcal(macros.calories))
            LabeledContent("Protein", value: MenuFormat.grams(macros.proteinG))
            LabeledContent("Carbs", value: MenuFormat.grams(macros.carbsG))
            LabeledContent("Fat", value: MenuFormat.grams(macros.fatG))
            if let value = MenuFormat.proteinValueLine(dish, currency: currency) {
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(nutritionTitle)
        } footer: {
            Text(nutritionFootnote)
        }
    }

    private var nutritionTitle: String {
        servings == 1 ? "Nutrition" : "Nutrition for \(FoodStore.formatServings(servings)) servings"
    }

    private var nutritionFootnote: String {
        if dish.isOfficialNutrition {
            return "Nutrition published by \(placeName). Portions can vary."
        }
        return "Estimated by Haki's AI from the menu description. You can adjust it in your food log."
    }

    private var logSection: some View {
        Section {
            Stepper(value: $servings, in: 0.5...10, step: 0.5) {
                LabeledContent("Servings", value: FoodStore.formatServings(servings))
            }
            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases) { meal in
                    Label(meal.title, systemImage: meal.systemImage)
                        .tag(meal)
                }
            }
            Button {
                log()
            } label: {
                Label("Log it", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
        } header: {
            Text("Add to today's log")
        } footer: {
            Text(logFootnote)
        }
    }

    private var logFootnote: String {
        let macros = dish.macros.scaled(by: servings)
        return "Adds \(MenuFormat.kcal(macros.calories)) and \(MenuFormat.grams(macros.proteinG)) protein from \(placeName) to your \(mealType.title.lowercased())."
    }

    private var subtitle: String {
        let section = dish.section.trimmingCharacters(in: .whitespacesAndNewlines)
        return section.isEmpty ? placeName : "\(section) · \(placeName)"
    }

    // MARK: Actions

    private func log() {
        FoodStore.add(dish: dish, placeName: placeName, servings: servings, mealType: mealType, in: modelContext)
        onLogged(mealType)
        dismiss()
    }
}

#Preview {
    MenuDishSheet(
        dish: FoodAIPreviewSamples.menu.items.first ?? MenuDish(name: "Chicken Power Bowl", calories: 610, proteinG: 48),
        placeName: "Green Fork Kitchen",
        currency: "USD"
    )
    .previewEnvironment()
}
