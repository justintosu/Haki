//
//  NutritionGoalsView.swift
//  Haki
//
//  Daily calorie and macro targets. Optionally, a few details about the
//  person (kept on this device only) give suggested targets; the targets
//  themselves can always be edited directly.
//

import Foundation
import SwiftUI
import UIKit

struct NutritionGoalsView: View {
    @AppStorage(HealthSettings.targetsKey) private var targetsData = Data()
    @AppStorage(HealthSettings.profileKey) private var profileData = Data()
    @AppStorage(HealthSettings.weightUnitKey) private var weightUnitRaw = ""

    @State private var weightText = ""
    @State private var heightCmText = ""
    @State private var heightFeetText = ""
    @State private var heightInchesText = ""
    @State private var ageText = ""
    @State private var sex: BodySex = .unspecified
    @State private var activity: ActivityLevel = .light
    @State private var goal: WeightGoal = .maintain
    @State private var didLoad = false
    @State private var appliedCount = 0
    @State private var isConfirmingReset = false
    @State private var isConfirmingForget = false
    @FocusState private var focus: NutritionGoalsField?

    var body: some View {
        Form {
            aboutSection
            activitySection
            suggestionSection
            targetsSection
            resetSection
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Nutrition goals")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
        .onAppear(perform: loadProfile)
        .onChange(of: draftProfile) { _, newValue in
            saveProfileIfComplete(newValue)
        }
        .sensoryFeedback(.success, trigger: appliedCount)
        .confirmationDialog("Reset daily targets?", isPresented: $isConfirmingReset, titleVisibility: .visible) {
            Button("Reset to standard", role: .destructive) {
                withAnimation(.snappy) { targetsData = Data() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resetMessage)
        }
        .confirmationDialog("Forget your details?", isPresented: $isConfirmingForget, titleVisibility: .visible) {
            Button("Forget my details", role: .destructive) { forgetProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your weight, height and age are removed from this iPhone. Your daily targets stay as they are.")
        }
    }

    // MARK: About you

    private var aboutSection: some View {
        Section {
            weightRow
            heightRow
            NutritionGoalsNumberRow(
                title: "Age",
                unit: "years",
                spokenUnit: "years",
                placeholder: "30",
                text: $ageText,
                keyboard: .numberPad,
                focus: $focus,
                field: .age
            )
            Picker("Sex", selection: $sex) {
                ForEach(BodySex.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            Picker("Goal", selection: $goal) {
                ForEach(WeightGoal.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
        } header: {
            Text("About you")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Optional. Kept on this iPhone and used only to suggest targets; Haki doesn't send it to its servers.")
                if hasSavedProfile {
                    Button("Forget my details") {
                        isConfirmingForget = true
                    }
                    .font(.footnote.weight(.semibold))
                }
            }
        }
    }

    private var weightRow: some View {
        NutritionGoalsNumberRow(
            title: "Weight",
            unit: weightUnit.symbol,
            spokenUnit: weightUnit == .pounds ? "pounds" : "kilograms",
            placeholder: weightUnit == .pounds ? "160" : "72",
            text: $weightText,
            keyboard: .decimalPad,
            focus: $focus,
            field: .weight
        )
    }

    @ViewBuilder
    private var heightRow: some View {
        if usesFeetAndInches {
            HStack(spacing: 8) {
                Text("Height")
                Spacer(minLength: 8)
                NutritionGoalsCompactField(placeholder: "5", text: $heightFeetText, spokenLabel: "Height, feet", focus: $focus, field: .heightFeet)
                Text("ft")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                NutritionGoalsCompactField(placeholder: "9", text: $heightInchesText, spokenLabel: "Height, inches", focus: $focus, field: .heightInches)
                Text("in")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } else {
            NutritionGoalsNumberRow(
                title: "Height",
                unit: "cm",
                spokenUnit: "centimeters",
                placeholder: "175",
                text: $heightCmText,
                keyboard: .decimalPad,
                focus: $focus,
                field: .heightCm
            )
        }
    }

    private var activitySection: some View {
        Section {
            ForEach(ActivityLevel.allCases) { level in
                Button {
                    activity = level
                } label: {
                    NutritionActivityRow(level: level, isSelected: activity == level)
                }
                .foregroundStyle(.primary)
                .accessibilityAddTraits(activity == level ? .isSelected : [])
            }
        } header: {
            Text("How active are you?")
        }
    }

    // MARK: Suggestion

    @ViewBuilder
    private var suggestionSection: some View {
        if let profile = draftProfile, profile.isComplete {
            let suggested = NutritionGoals.targets(for: profile)
            let isInUse = suggested == targets
            Section {
                NutritionTargetsGrid(targets: suggested)
                Text("You burn about \(FoodFormat.kcal(NutritionGoals.maintenanceCalories(profile))) a day. \(goalExplanation(profile.goal))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    apply(suggested, profile: profile)
                } label: {
                    Label(isInUse ? "You're using these" : "Use these", systemImage: isInUse ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.body.weight(.semibold))
                }
                .disabled(isInUse)
            } header: {
                Text("Suggested for you")
            }
        } else {
            Section {
                Text(suggestionHint)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Suggested for you")
            }
        }
    }

    private var suggestionHint: String {
        if draftProfile != nil {
            return "Those numbers look off. Check your weight, height and age (13 or older) to see suggested targets."
        }
        return "Add your weight, height and age to see targets suggested for you."
    }

    private func goalExplanation(_ goal: WeightGoal) -> String {
        switch goal {
        case .lose:
            return "These targets are about 500 kcal below that, with extra protein to help keep muscle."
        case .maintain:
            return "These targets match it, with plenty of protein for an active body."
        case .gain:
            return "These targets add about 300 kcal to it, with protein to help build muscle."
        }
    }

    // MARK: Targets

    private var targetsSection: some View {
        Section {
            NutritionTargetRow(title: "Calories", unit: "kcal", spokenUnit: "kilocalories", value: targetBinding(\.calories), range: NutritionGoals.minimumCalories...6_000, step: 50, focus: $focus, field: .calories)
            NutritionTargetRow(title: "Protein", unit: "g", spokenUnit: "grams", value: targetBinding(\.proteinG), range: 0...400, step: 5, focus: $focus, field: .protein)
            NutritionTargetRow(title: "Carbs", unit: "g", spokenUnit: "grams", value: targetBinding(\.carbsG), range: 0...800, step: 5, focus: $focus, field: .carbs)
            NutritionTargetRow(title: "Fat", unit: "g", spokenUnit: "grams", value: targetBinding(\.fatG), range: 0...300, step: 5, focus: $focus, field: .fat)
            NutritionTargetRow(title: "Fiber", unit: "g", spokenUnit: "grams", value: targetBinding(\.fiberG), range: 0...100, step: 1, focus: $focus, field: .fiber)
        } header: {
            Text("Daily targets")
        } footer: {
            Text("Changes are saved right away. Protein and carbs have 4 kcal per gram, fat 9.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to standard") {
                isConfirmingReset = true
            }
            .disabled(targets == .standard)
        } footer: {
            Text("Targets are general estimates, not medical advice. Talk to a professional for a plan that fits you.")
        }
    }

    private var resetMessage: String {
        let standard = NutritionTargets.standard
        return "Back to \(FoodFormat.kcal(Double(standard.calories))), \(standard.proteinG) g protein, \(standard.carbsG) g carbs, \(standard.fatG) g fat and \(standard.fiberG) g fiber a day."
    }

    // MARK: Values

    private var targets: NutritionTargets {
        HealthSettings.targets(from: targetsData)
    }

    private var weightUnit: WeightUnit {
        HealthSettings.weightUnit(from: weightUnitRaw)
    }

    /// Feet and inches go with pounds; centimeters with kilograms.
    private var usesFeetAndInches: Bool {
        weightUnit == .pounds
    }

    private var hasSavedProfile: Bool {
        HealthSettings.profile(from: profileData) != nil
    }

    /// The details as typed, or nil while any of weight, height or age is missing.
    private var draftProfile: NutritionProfile? {
        guard let weight = FoodFormat.parse(weightText), weight > 0 else { return nil }
        let heightCm: Double
        if usesFeetAndInches {
            guard let feet = Int(heightFeetText.trimmingCharacters(in: .whitespacesAndNewlines)), feet > 0 else { return nil }
            let inches = FoodFormat.parse(heightInchesText) ?? 0
            heightCm = BodyUnits.centimeters(feet: feet, inches: inches)
        } else {
            guard let centimeters = FoodFormat.parse(heightCmText), centimeters > 0 else { return nil }
            heightCm = centimeters
        }
        guard let age = Int(ageText.trimmingCharacters(in: .whitespacesAndNewlines)), age > 0 else { return nil }
        return NutritionProfile(
            weightKg: weightUnit.toKilograms(weight),
            heightCm: heightCm,
            ageYears: age,
            sex: sex,
            activity: activity,
            goal: goal
        )
    }

    private func targetBinding(_ keyPath: WritableKeyPath<NutritionTargets, Int>) -> Binding<Int> {
        Binding(
            get: { targets[keyPath: keyPath] },
            set: { newValue in
                var updated = targets
                updated[keyPath: keyPath] = newValue
                targetsData = HealthSettings.encode(updated)
            }
        )
    }

    // MARK: Actions

    private func loadProfile() {
        guard !didLoad else { return }
        didLoad = true
        guard let profile = HealthSettings.profile(from: profileData) else { return }
        weightText = FoodFormat.fieldText(weightUnit.fromKilograms(profile.weightKg))
        if usesFeetAndInches {
            let height = BodyUnits.feetAndInches(fromCentimeters: profile.heightCm)
            heightFeetText = String(height.feet)
            heightInchesText = String(height.inches)
        } else {
            heightCmText = String(Int(profile.heightCm.rounded()))
        }
        ageText = String(profile.ageYears)
        sex = profile.sex
        activity = profile.activity
        goal = profile.goal
    }

    /// Keeps complete details so they're there next time; partial ones aren't saved.
    private func saveProfileIfComplete(_ profile: NutritionProfile?) {
        guard didLoad, let profile, profile.isComplete else { return }
        profileData = HealthSettings.encode(profile)
    }

    private func apply(_ suggested: NutritionTargets, profile: NutritionProfile) {
        withAnimation(.snappy) {
            targetsData = HealthSettings.encode(suggested)
        }
        profileData = HealthSettings.encode(profile)
        appliedCount += 1
        UIAccessibility.post(notification: .announcement, argument: "Daily targets updated")
    }

    private func forgetProfile() {
        profileData = Data()
        weightText = ""
        heightCmText = ""
        heightFeetText = ""
        heightInchesText = ""
        ageText = ""
        sex = .unspecified
        activity = .light
        goal = .maintain
    }
}

// MARK: - Pieces

private enum NutritionGoalsField: Hashable {
    case weight, heightCm, heightFeet, heightInches, age
    case calories, protein, carbs, fat, fiber
}

/// "Weight      [ 72 ] kg".
private struct NutritionGoalsNumberRow: View {
    let title: String
    let unit: String
    let spokenUnit: String
    let placeholder: String
    @Binding var text: String
    let keyboard: UIKeyboardType
    var focus: FocusState<NutritionGoalsField?>.Binding
    let field: NutritionGoalsField

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            TextField(placeholder, text: $text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused(focus, equals: field)
                .frame(maxWidth: 110)
                .accessibilityLabel("\(title) in \(spokenUnit)")
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(minWidth: 36, alignment: .leading)
                .accessibilityHidden(true)
        }
    }
}

/// A narrow number field for feet or inches.
private struct NutritionGoalsCompactField: View {
    let placeholder: String
    @Binding var text: String
    let spokenLabel: String
    var focus: FocusState<NutritionGoalsField?>.Binding
    let field: NutritionGoalsField

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .focused(focus, equals: field)
            .frame(minWidth: 28, maxWidth: 48)
            .accessibilityLabel(spokenLabel)
    }
}

/// An activity level with its description and a checkmark when chosen.
private struct NutritionActivityRow: View {
    let level: ActivityLevel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(level.title)
                    .foregroundStyle(.primary)
                Text(level.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// The five suggested numbers.
private struct NutritionTargetsGrid: View {
    let targets: NutritionTargets

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(FoodFormat.whole(Double(targets.calories)))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("kcal a day")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            HStack(alignment: .top, spacing: 8) {
                value("Protein", grams: targets.proteinG, tint: NutritionPalette.protein)
                value("Carbs", grams: targets.carbsG, tint: NutritionPalette.carbs)
                value("Fat", grams: targets.fatG, tint: NutritionPalette.fat)
                value("Fiber", grams: targets.fiberG, tint: NutritionPalette.fiber)
            }
        }
        .padding(.vertical, 4)
    }

    private func value(_ title: String, grams: Int, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("\(grams) g")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A daily target: a number field plus a stepper. Valid numbers save as
/// they're typed; anything out of range snaps back when the field loses focus.
private struct NutritionTargetRow: View {
    let title: String
    let unit: String
    let spokenUnit: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var focus: FocusState<NutritionGoalsField?>.Binding
    let field: NutritionGoalsField

    @State private var text = ""

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 8)
            TextField(title, text: $text)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .focused(focus, equals: field)
                .frame(minWidth: 48, maxWidth: 80)
                .accessibilityLabel("\(title) target in \(spokenUnit)")
            Text(unit)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Stepper(title, value: $value, in: range, step: step)
                .labelsHidden()
                .accessibilityLabel("\(title) target")
                .accessibilityValue("\(value) \(spokenUnit)")
        }
        .onAppear {
            text = String(value)
        }
        .onChange(of: value) { _, newValue in
            if Int(text) != newValue {
                text = String(newValue)
            }
        }
        .onChange(of: text) { _, newValue in
            guard let parsed = Int(newValue.filter { $0.isASCII && $0.isNumber }), range.contains(parsed), parsed != value else { return }
            value = parsed
        }
        .onChange(of: focus.wrappedValue) { _, newValue in
            if newValue != field {
                text = String(value)
            }
        }
    }
}

#Preview {
    NavigationStack {
        NutritionGoalsView()
    }
    .previewEnvironment()
}
