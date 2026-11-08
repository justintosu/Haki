//
//  WorkoutSetTable.swift
//  Haki
//
//  The logging table of the active workout: one list section per exercise
//  (name, notes, options menu, column titles, a row per set, "Add set"),
//  the set rows with their compact number fields, and the rest timer bar.
//
//  Set rows keep the text being typed in local state and write the parsed
//  value to the model as it changes; the screen saves when a field loses
//  focus, when a set is ticked and when the workout is finished.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

/// Which text field of the active workout has focus.
enum WorkoutSetFocus: Hashable {
    case title
    case notes(UUID)
    case weight(UUID)
    case reps(UUID)
    case distance(UUID)
    case duration(UUID)
}

// MARK: - Exercise section

/// One exercise of the active workout as a list section.
struct WorkoutExerciseSection: View {
    let exercise: WorkoutExerciseRecord
    let position: Int
    let exerciseCount: Int
    /// Last time's sets, by position (the "previous" column).
    let previous: [SetValues]
    /// Records beaten, by set id.
    let recordSets: [UUID: Set<RecordKind>]
    let weightUnit: WeightUnit
    let distanceUnit: DistanceUnit
    let focus: FocusState<WorkoutSetFocus?>.Binding
    let onOpenHistory: () -> Void
    let onToggleSet: (WorkoutSetRecord) -> Void
    let onRemoveSet: (WorkoutSetRecord) -> Void
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let sets = exercise.orderedSets
        let labels = Self.setLabels(sets)
        let kind = exercise.kind

        Section {
            WorkoutExerciseHeaderRow(
                exercise: exercise,
                position: position,
                exerciseCount: exerciseCount,
                onOpenHistory: onOpenHistory,
                onSetRest: { seconds in setRest(seconds) },
                onMove: onMove,
                onRemove: onRemove
            )
            notesField
            WorkoutSetColumnsHeader(kind: kind, weightUnit: weightUnit, distanceUnit: distanceUnit)
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, setRecord in
                setRow(setRecord, index: index, label: labels[setRecord.id] ?? "\(index + 1)", kind: kind)
            }
            addSetButton
        }
    }

    private func setRow(_ setRecord: WorkoutSetRecord, index: Int, label: String, kind: ExerciseKind) -> some View {
        WorkoutSetRow(
            setRecord: setRecord,
            label: label,
            kind: kind,
            previous: index < previous.count ? previous[index] : nil,
            records: recordSets[setRecord.id] ?? [],
            weightUnit: weightUnit,
            distanceUnit: distanceUnit,
            focus: focus,
            onToggle: { onToggleSet(setRecord) }
        )
        .listRowBackground(setRecord.isCompleted ? Color.hakiPositive.opacity(0.14) : Color.hakiCardBackground)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onRemoveSet(setRecord)
            } label: {
                Label("Delete set", systemImage: "trash")
            }
        }
    }

    private var notesField: some View {
        TextField("Add notes", text: notesBinding, axis: .vertical)
            .font(.subheadline)
            .lineLimit(1...4)
            .focused(focus, equals: .notes(exercise.id))
            .accessibilityLabel("Notes for \(exercise.name)")
    }

    private var notesBinding: Binding<String> {
        Binding(
            get: { exercise.notes },
            set: { exercise.notes = $0 }
        )
    }

    private var addSetButton: some View {
        Button {
            withAnimation(.snappy) {
                _ = WorkoutStore.addSet(to: exercise, in: modelContext)
            }
        } label: {
            Label("Add set", systemImage: "plus")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Add a set to \(exercise.name)")
    }

    private func setRest(_ seconds: Int) {
        exercise.restSeconds = max(0, seconds)
        WorkoutStore.save(in: modelContext)
    }

    /// "W" for warm-ups, "D" / "F" for drop sets and sets to failure, and
    /// numbers for the rest (warm-ups aren't counted).
    static func setLabels(_ sets: [WorkoutSetRecord]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        var number = 0
        for set in sets {
            let kind = set.kind
            if kind == .warmup {
                result[set.id] = kind.badge ?? "W"
            } else {
                number += 1
                result[set.id] = kind.badge ?? "\(number)"
            }
        }
        return result
    }
}

// MARK: - Header row

/// The exercise name (opens its history), muscle and rest time, and the
/// options menu: rest timer, move up / down, remove.
private struct WorkoutExerciseHeaderRow: View {
    let exercise: WorkoutExerciseRecord
    let position: Int
    let exerciseCount: Int
    let onOpenHistory: () -> Void
    let onSetRest: (Int) -> Void
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onOpenHistory) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityHint("Shows your history and records for this exercise")

            optionsMenu
        }
        .buttonStyle(.borderless)
    }

    private var subtitle: String {
        "\(exercise.primaryMuscle.title) · Rest \(WorkoutsFormat.restTitle(exercise.restSeconds))"
    }

    private var optionsMenu: some View {
        Menu {
            Menu {
                Picker("Rest timer", selection: restBinding) {
                    ForEach(WorkoutsFormat.restChoices(including: exercise.restSeconds), id: \.self) { seconds in
                        Text(WorkoutsFormat.restTitle(seconds)).tag(seconds)
                    }
                }
            } label: {
                Label("Rest timer: \(WorkoutsFormat.restTitle(exercise.restSeconds))", systemImage: "timer")
            }
            Button {
                onMove(-1)
            } label: {
                Label("Move up", systemImage: "arrow.up")
            }
            .disabled(position == 0)
            Button {
                onMove(1)
            } label: {
                Label("Move down", systemImage: "arrow.down")
            }
            .disabled(position >= exerciseCount - 1)
            Divider()
            Button(role: .destructive, action: onRemove) {
                Label("Remove exercise", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Options for \(exercise.name)")
    }

    private var restBinding: Binding<Int> {
        Binding(
            get: { exercise.restSeconds },
            set: { onSetRest($0) }
        )
    }
}

// MARK: - Columns

/// "SET  PREVIOUS  KG  REPS  ✓". Its column widths match `WorkoutSetRow`'s
/// and scale with Dynamic Type.
private struct WorkoutSetColumnsHeader: View {
    let kind: ExerciseKind
    let weightUnit: WeightUnit
    let distanceUnit: DistanceUnit

    @ScaledMetric(relativeTo: .body) private var setWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .body) private var checkWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: 8) {
            Text("SET")
                .frame(width: setWidth)
            Text("PREVIOUS")
                .frame(maxWidth: .infinity, alignment: .leading)
            if kind.logsWeight {
                Text(weightTitle)
                    .frame(width: fieldWidth)
            }
            if kind.logsReps {
                Text("REPS")
                    .frame(width: fieldWidth)
            }
            if kind.logsDistance {
                Text(distanceUnit.symbol.uppercased())
                    .frame(width: fieldWidth)
            }
            if kind.logsDuration {
                Text("TIME")
                    .frame(width: fieldWidth)
            }
            Image(systemName: "checkmark")
                .frame(width: checkWidth)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityHidden(true)
    }

    private var weightTitle: String {
        WorkoutsFormat.weightPrefix(for: kind) + weightUnit.symbol.uppercased()
    }
}

// MARK: - Set row

/// One set: its number (tap to change the set type), last time's numbers
/// (tap to copy them), the fields the exercise logs and the done button.
struct WorkoutSetRow: View {
    let setRecord: WorkoutSetRecord
    let label: String
    let kind: ExerciseKind
    let previous: SetValues?
    let records: Set<RecordKind>
    let weightUnit: WeightUnit
    let distanceUnit: DistanceUnit
    let focus: FocusState<WorkoutSetFocus?>.Binding
    let onToggle: () -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var weightText = ""
    @State private var repsText = ""
    @State private var distanceText = ""
    @State private var durationText = ""

    @ScaledMetric(relativeTo: .body) private var setWidth: CGFloat = 34
    @ScaledMetric(relativeTo: .body) private var fieldWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .body) private var checkWidth: CGFloat = 40

    var body: some View {
        HStack(spacing: 8) {
            kindMenu
            previousColumn
            fields
            checkButton
        }
        .buttonStyle(.borderless)
        .onAppear { load() }
        .onChange(of: weightText) { _, newValue in applyWeight(newValue) }
        .onChange(of: repsText) { _, newValue in applyReps(newValue) }
        .onChange(of: distanceText) { _, newValue in applyDistance(newValue) }
        .onChange(of: durationText) { _, newValue in applyDuration(newValue) }
    }

    // MARK: Columns

    private var kindMenu: some View {
        Menu {
            ForEach(SetKind.allCases) { option in
                Button {
                    setKind(option)
                } label: {
                    if option == setRecord.kind {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Text(label)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: setWidth)
                .frame(minHeight: 32)
                .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityLabel(spokenSetName)
        .accessibilityHint("Changes the set type")
    }

    private var previousColumn: some View {
        HStack(spacing: 4) {
            Button {
                copyPrevious()
            } label: {
                Text(previousText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .disabled(previous == nil)
            .accessibilityLabel(previousAccessibilityLabel)
            .accessibilityHint(previousAccessibilityHint)

            if !records.isEmpty {
                WorkoutsRecordBadge(compact: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var fields: some View {
        if kind.logsWeight {
            numberField(
                text: $weightText,
                focusValue: .weight(setRecord.id),
                keyboard: .decimalPad,
                spokenName: "\(spokenSetName) weight in \(weightUnit == .kilograms ? "kilograms" : "pounds")"
            )
        }
        if kind.logsReps {
            numberField(
                text: $repsText,
                focusValue: .reps(setRecord.id),
                keyboard: .numberPad,
                spokenName: "\(spokenSetName) reps"
            )
        }
        if kind.logsDistance {
            numberField(
                text: $distanceText,
                focusValue: .distance(setRecord.id),
                keyboard: .decimalPad,
                spokenName: "\(spokenSetName) distance in \(distanceUnit == .kilometers ? "kilometers" : "miles")"
            )
        }
        if kind.logsDuration {
            numberField(
                text: $durationText,
                focusValue: .duration(setRecord.id),
                keyboard: .numbersAndPunctuation,
                spokenName: "\(spokenSetName) time, minutes and seconds"
            )
        }
    }

    private func numberField(text: Binding<String>, focusValue: WorkoutSetFocus, keyboard: UIKeyboardType, spokenName: String) -> some View {
        TextField("–", text: text)
            .keyboardType(keyboard)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .font(.body.weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.vertical, 6)
            .padding(.horizontal, 2)
            .frame(width: fieldWidth)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .focused(focus, equals: focusValue)
            .accessibilityLabel(spokenName)
    }

    private var checkButton: some View {
        Button(action: onToggle) {
            Image(systemName: setRecord.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(setRecord.isCompleted ? Color.hakiPositive : Color.secondary)
                .frame(width: checkWidth)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(spokenSetName)
        .accessibilityValue(setRecord.isCompleted ? "Done" : "Not done")
        .accessibilityHint(setRecord.isCompleted ? "Marks the set as not done" : "Marks the set as done")
        .sensoryFeedback(.selection, trigger: setRecord.isCompleted)
    }

    // MARK: Text

    private var labelColor: Color {
        switch setRecord.kind {
        case .normal: return .primary
        case .warmup: return .hakiWarning
        case .dropset: return .purple
        case .failure: return .hakiNegative
        }
    }

    private var spokenSetName: String {
        switch setRecord.kind {
        case .normal: return "Set \(label)"
        case .warmup: return "Warm-up set"
        case .dropset: return "Drop set"
        case .failure: return "Set to failure"
        }
    }

    private var previousText: String {
        guard let previous else { return "—" }
        return WorkoutsFormat.compactSummary(previous, kind: kind, weightUnit: weightUnit, distanceUnit: distanceUnit)
    }

    private var previousAccessibilityLabel: String {
        guard let previous else { return "No previous set" }
        let summary = WorkoutsFormat.setSummary(previous, kind: kind, weightUnit: weightUnit, distanceUnit: distanceUnit)
        return "Last time: \(summary)"
    }

    private var previousAccessibilityHint: String {
        previous == nil ? "" : "Copies last time's numbers into this set"
    }

    // MARK: Editing

    /// False once the set was deleted (swiped away, or dropped when the
    /// workout was finished): its values can't be read or written then.
    private var isLive: Bool {
        !setRecord.isDeleted && setRecord.modelContext != nil
    }

    private func weightField(_ kilograms: Double?) -> String {
        guard let kilograms else { return "" }
        return weightUnit.format(kilograms: kilograms)
    }

    private func repsField(_ reps: Int?) -> String {
        guard let reps else { return "" }
        return String(reps)
    }

    private func distanceField(_ meters: Double?) -> String {
        guard let meters else { return "" }
        return distanceUnit.format(meters: meters)
    }

    private func durationField(_ seconds: Int?) -> String {
        guard let seconds else { return "" }
        return WorkoutsFormat.durationField(seconds)
    }

    private func load() {
        guard isLive else { return }
        weightText = weightField(setRecord.weightKg)
        repsText = repsField(setRecord.reps)
        distanceText = distanceField(setRecord.distanceMeters)
        durationText = durationField(setRecord.durationSeconds)
    }

    private func applyWeight(_ text: String) {
        guard isLive, text != weightField(setRecord.weightKg) else { return }
        setRecord.weightKg = weightUnit.parse(text)
    }

    private func applyReps(_ text: String) {
        guard isLive, text != repsField(setRecord.reps) else { return }
        let digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(digits), value >= 0, value < 10_000 {
            setRecord.reps = value
        } else {
            setRecord.reps = nil
        }
    }

    private func applyDistance(_ text: String) {
        guard isLive, text != distanceField(setRecord.distanceMeters) else { return }
        setRecord.distanceMeters = distanceUnit.parse(text)
    }

    private func applyDuration(_ text: String) {
        guard isLive, text != durationField(setRecord.durationSeconds) else { return }
        setRecord.durationSeconds = WorkoutsFormat.parseDuration(text)
    }

    private func copyPrevious() {
        guard let previous, isLive else { return }
        if kind.logsWeight { weightText = weightField(previous.weightKg) }
        if kind.logsReps { repsText = repsField(previous.reps) }
        if kind.logsDistance { distanceText = distanceField(previous.distanceMeters) }
        if kind.logsDuration { durationText = durationField(previous.durationSeconds) }
    }

    private func setKind(_ option: SetKind) {
        guard isLive else { return }
        setRecord.kind = option
        WorkoutStore.save(in: modelContext)
    }
}

// MARK: - Rest timer

/// Counts down to `endsAt` (a date, so it stays right after the app was in
/// the background), with −15 s / +15 s and Skip.
struct WorkoutRestTimerBar: View {
    let endsAt: Date
    let totalSeconds: Int
    let onAdjust: (Int) -> Void
    let onSkip: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(remaining: remainingSeconds(at: context.date))
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func remainingSeconds(at date: Date) -> Int {
        max(0, Int(endsAt.timeIntervalSince(date).rounded(.up)))
    }

    private func fraction(_ remaining: Int) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, Double(remaining) / Double(totalSeconds)))
    }

    private func content(remaining: Int) -> some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label("Rest", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(WorkoutMath.formatTimer(seconds: remaining))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest timer")
            .accessibilityValue("\(WorkoutMath.formatTimer(seconds: remaining)) left")

            ProgressView(value: fraction(remaining))
                .tint(Color.accentColor)
                .accessibilityHidden(true)

            HStack(spacing: 10) {
                adjustButton("−15 s", delta: -15, spoken: "15 seconds less")
                adjustButton("+15 s", delta: 15, spoken: "15 seconds more")
                Spacer(minLength: 8)
                Button("Skip", action: onSkip)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("Skip rest")
            }
        }
    }

    private func adjustButton(_ title: String, delta: Int, spoken: String) -> some View {
        Button {
            onAdjust(delta)
        } label: {
            Text(title)
                .monospacedDigit()
                .frame(minWidth: 44)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(spoken)
    }
}

// MARK: - Previews

#Preview("Rest timer") {
    VStack {
        Spacer()
        WorkoutRestTimerBar(endsAt: .now.addingTimeInterval(75), totalSeconds: 90, onAdjust: { _ in }, onSkip: {})
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
