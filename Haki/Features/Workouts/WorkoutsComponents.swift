//
//  WorkoutsComponents.swift
//  Haki
//
//  Pieces shared by the workout screens: numbers in the person's units, the
//  Hevy badge, stat tiles, the start / resume control, history and routine
//  rows, exercise rows and the muscle filter chips.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Formatting

/// Formatting for workouts. Weights are stored in kilograms and shown in the
/// person's unit; distances in meters.
enum WorkoutsFormat {
    /// Rest timer choices, in seconds (0 = off).
    static let standardRestChoices: [Int] = [0, 30, 60, 90, 120, 180, 240]

    /// `standardRestChoices` plus `current` when it isn't one of them
    /// (barbell lifts default to 150 s), so a picker always has a matching tag.
    static func restChoices(including current: Int) -> [Int] {
        let standard = standardRestChoices
        return standard.contains(current) ? standard : (standard + [current]).sorted()
    }

    /// "Off", "30s", "1:30".
    static func restTitle(_ seconds: Int) -> String {
        seconds <= 0 ? "Off" : WorkoutMath.formatTimer(seconds: seconds)
    }

    /// "62.5 kg"
    static func weight(_ kilograms: Double, unit: WeightUnit) -> String {
        "\(unit.format(kilograms: kilograms)) \(unit.symbol)"
    }

    /// "4,250 kg" — whole units with grouping, for volume.
    static func volume(_ kilograms: Double, unit: WeightUnit) -> String {
        let value = unit.fromKilograms(kilograms)
        guard value.isFinite, value >= 0, value < 1_000_000_000 else { return "0 \(unit.symbol)" }
        return "\(Int(value.rounded()).formatted()) \(unit.symbol)"
    }

    /// "1.20 km"
    static func distance(_ meters: Double, unit: DistanceUnit) -> String {
        "\(unit.format(meters: meters)) \(unit.symbol)"
    }

    /// "1:30" — what a duration field shows.
    static func durationField(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Reads "1:30", "1:02:09" or a plain number of seconds ("90"). Nil for
    /// nothing or nonsense.
    static func parseDuration(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map { String($0) }
        guard parts.count <= 3 else { return nil }
        var total = 0
        for part in parts {
            let digits = part.trimmingCharacters(in: .whitespaces)
            guard let value = Int(digits.isEmpty ? "0" : digits), value >= 0, value < 100_000 else { return nil }
            total = total * 60 + value
        }
        return total < 360_000 ? total : nil
    }

    /// "Today", "Yesterday", "Mon, Nov 3".
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "+" for extra weight on a bodyweight lift, "−" for assistance.
    static func weightPrefix(for kind: ExerciseKind) -> String {
        switch kind {
        case .bodyweightReps: return "+"
        case .assistedBodyweightReps: return "−"
        default: return ""
        }
    }

    /// One set in words: "60 kg × 8", "12 reps", "1.20 km · 6:30", "45s".
    static func setSummary(_ values: SetValues, kind: ExerciseKind, weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> String {
        var parts: [String] = []
        var weightText: String?
        if kind.logsWeight, let kilograms = values.weightKg, kilograms > 0 {
            weightText = weightPrefix(for: kind) + weight(kilograms, unit: weightUnit)
        }
        var repsCount: Int?
        if kind.logsReps, let reps = values.reps, reps > 0 {
            repsCount = reps
        }
        if let weightText, let repsCount {
            parts.append("\(weightText) × \(repsCount)")
        } else if let weightText {
            parts.append(weightText)
        } else if let repsCount {
            parts.append(repsCount == 1 ? "1 rep" : "\(repsCount) reps")
        }
        if kind.logsDistance, let meters = values.distanceMeters, meters > 0 {
            parts.append(distance(meters, unit: distanceUnit))
        }
        if kind.logsDuration, let seconds = values.durationSeconds, seconds > 0 {
            parts.append(WorkoutMath.formatTimer(seconds: seconds))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// A set without units, for the narrow "previous" column: "60 × 8".
    static func compactSummary(_ values: SetValues, kind: ExerciseKind, weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> String {
        var parts: [String] = []
        var weightText: String?
        if kind.logsWeight, let kilograms = values.weightKg, kilograms > 0 {
            weightText = weightPrefix(for: kind) + weightUnit.format(kilograms: kilograms)
        }
        var repsCount: Int?
        if kind.logsReps, let reps = values.reps, reps > 0 {
            repsCount = reps
        }
        if let weightText, let repsCount {
            parts.append("\(weightText) × \(repsCount)")
        } else if let weightText {
            parts.append(weightText)
        } else if let repsCount {
            parts.append("\(repsCount)")
        }
        if kind.logsDistance, let meters = values.distanceMeters, meters > 0 {
            parts.append(distanceUnit.format(meters: meters))
        }
        if kind.logsDuration, let seconds = values.durationSeconds, seconds > 0 {
            parts.append(WorkoutMath.formatTimer(seconds: seconds))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    /// An SF Symbol for what an exercise logs.
    static func symbol(for kind: ExerciseKind) -> String {
        switch kind {
        case .weightReps, .weightDuration, .weightDistance: return "dumbbell.fill"
        case .repsOnly, .bodyweightReps, .assistedBodyweightReps: return "figure.strengthtraining.functional"
        case .duration: return "timer"
        case .distanceDuration: return "figure.run"
        }
    }

    /// "2 workouts", "1 workout".
    static func workoutCount(_ count: Int) -> String {
        count == 1 ? "1 workout" : "\(count) workouts"
    }

    /// "12 sets", "1 set".
    static func setCount(_ count: Int) -> String {
        count == 1 ? "1 set" : "\(count) sets"
    }

    /// "3 exercises", "1 exercise".
    static func exerciseCount(_ count: Int) -> String {
        count == 1 ? "1 exercise" : "\(count) exercises"
    }

    /// "3-week streak"
    static func streak(_ weeks: Int) -> String {
        "\(weeks)-week streak"
    }

    /// "52m · 12 sets · 4,250 kg" (volume only when there is some).
    static func statsLine(durationSeconds: Int, sets: Int, volumeKg: Double, unit: WeightUnit) -> String {
        var parts = [WorkoutMath.formatDuration(seconds: durationSeconds), setCount(sets)]
        if volumeKg > 0 { parts.append(volume(volumeKg, unit: unit)) }
        return parts.joined(separator: " · ")
    }

    /// A record's value in words: "100 kg", "12 reps".
    static func recordValue(_ kind: RecordKind, records: PersonalRecords, unit: WeightUnit) -> String? {
        switch kind {
        case .heaviestWeight:
            return records.heaviestWeightKg.map { weight($0, unit: unit) }
        case .bestOneRepMax:
            return records.bestOneRepMaxKg.map { weight($0, unit: unit) }
        case .mostReps:
            return records.mostReps.map { $0 == 1 ? "1 rep" : "\($0) reps" }
        case .bestSetVolume:
            return records.bestSetVolumeKg.map { volume($0, unit: unit) }
        }
    }
}

/// Merges records from earlier workouts with sets already done today, so a
/// second heavy set only counts as a record when it beats the first. A
/// record with no history stays empty: a first time isn't a record.
enum WorkoutsRecordMath {
    static func merged(history: PersonalRecords, session: PersonalRecords) -> PersonalRecords {
        var result = history
        if let best = history.heaviestWeightKg {
            result.heaviestWeightKg = max(best, session.heaviestWeightKg ?? 0)
        }
        if let best = history.bestOneRepMaxKg {
            result.bestOneRepMaxKg = max(best, session.bestOneRepMaxKg ?? 0)
        }
        if let best = history.mostReps {
            result.mostReps = max(best, session.mostReps ?? 0)
        }
        if let best = history.bestSetVolumeKg {
            result.bestSetVolumeKg = max(best, session.bestSetVolumeKg ?? 0)
        }
        return result
    }

    /// Which completed sets of one logged exercise set records, in order,
    /// against `history` (records from before the workout).
    static func recordSets(_ sets: [WorkoutSetRecord], kind: ExerciseKind, history: PersonalRecords, date: Date) -> [UUID: Set<RecordKind>] {
        let countsWeight = kind.countsWeightForRecords
        var result: [UUID: Set<RecordKind>] = [:]
        var earlier: [SetValues] = []
        for set in sets where set.isCompleted {
            let values = set.values
            let session = WorkoutMath.records([ExercisePerformance(date: date, sets: earlier)], countsWeight: countsWeight)
            let baseline = merged(history: history, session: session)
            let beaten = WorkoutMath.newRecords(for: values, previous: baseline, countsWeight: countsWeight)
            if !beaten.isEmpty { result[set.id] = beaten }
            earlier.append(values)
        }
        return result
    }
}

/// Workouts this week, the week streak and the latest workout.
struct WorkoutsWeekStats {
    let thisWeekCount: Int
    let thisWeekVolumeKg: Double
    let weekStreak: Int
    let last: WorkoutRecord?

    /// `finished` newest first.
    init(finished: [WorkoutRecord], now: Date = .now, calendar: Calendar = .current) {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)
        let thisWeek = finished.filter { week?.contains($0.startedAt) ?? false }
        thisWeekCount = thisWeek.count
        thisWeekVolumeKg = thisWeek.reduce(0) { $0 + $1.volumeKg }
        weekStreak = WorkoutMath.weekStreak(workoutDates: finished.map(\.startedAt), now: now, calendar: calendar)
        last = finished.first
    }
}

// MARK: - Badges and tiles

/// "From Hevy" on workouts copied from Hevy, "Also in Hevy" on Haki
/// workouts that were posted there. Nothing otherwise.
struct WorkoutsSourceBadge: View {
    let source: WorkoutSource
    let hevyID: String?

    var body: some View {
        if let title {
            Label(title, systemImage: "arrow.triangle.2.circlepath")
                .labelStyle(.titleAndIcon)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: Capsule())
        }
    }

    private var title: String? {
        switch source {
        case .hevy: return "From Hevy"
        case .haki: return hevyID == nil ? nil : "Also in Hevy"
        }
    }
}

/// "🏆 PR" capsule (an SF Symbol, not an emoji) for a set that beat a record.
struct WorkoutsRecordBadge: View {
    var compact: Bool = false

    var body: some View {
        Label("PR", systemImage: "trophy.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.hakiWarning)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, compact ? 5 : 7)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.16), in: Capsule())
            .accessibilityLabel("Personal record")
    }
}

/// A number with a caption under it.
struct WorkoutsStatTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}

/// "🔥 3-week streak" capsule (an SF Symbol flame).
struct WorkoutsStreakBadge: View {
    let weeks: Int

    var body: some View {
        Label(WorkoutsFormat.streak(weeks), systemImage: "flame.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.hakiWarning)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.14), in: Capsule())
            .accessibilityLabel("Workout streak: \(weeks) \(weeks == 1 ? "week" : "weeks") in a row")
    }
}

// MARK: - Start and resume

/// "Resume Push day · 23:10" while a workout is in progress, otherwise a
/// "Start workout" menu: an empty workout or one of the routines.
struct WorkoutsStartControl: View {
    let activeWorkout: WorkoutRecord?
    let routines: [RoutineRecord]
    let onResume: (WorkoutRecord) -> Void
    let onStart: (RoutineRecord?) -> Void

    var body: some View {
        if let activeWorkout {
            WorkoutsResumeBanner(workout: activeWorkout, onResume: { onResume(activeWorkout) })
        } else {
            startMenu
        }
    }

    private var startMenu: some View {
        Menu {
            Button {
                onStart(nil)
            } label: {
                Label("Empty workout", systemImage: "plus")
            }
            if !routines.isEmpty {
                Section("From a routine") {
                    ForEach(routines) { routine in
                        Button {
                            onStart(routine)
                        } label: {
                            Label(routine.name, systemImage: "list.bullet.rectangle")
                        }
                    }
                }
            }
        } label: {
            Label("Start workout", systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .contentShape(Rectangle())
        }
        .accessibilityHint(routines.isEmpty ? "Starts an empty workout" : "Choose an empty workout or one of your routines")
    }
}

/// The banner for a workout in progress, with a live timer.
struct WorkoutsResumeBanner: View {
    let workout: WorkoutRecord
    let onResume: () -> Void

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: 12) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.title2.weight(.semibold))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "Resume \(displayTitle)")
                        .font(.headline)
                        .lineLimit(1)
                    TimelineView(.periodic(from: workout.startedAt, by: 1)) { context in
                        Text("In progress · \(WorkoutMath.formatTimer(seconds: elapsedSeconds(at: context.date)))")
                            .font(.subheadline)
                            .monospacedDigit()
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.up")
                    .font(.subheadline.weight(.bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(Color.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "Resume \(displayTitle)"))
        .accessibilityHint("Opens the workout in progress")
    }

    /// The name can be cleared while logging (finishing fills in a default).
    private var displayTitle: String {
        let trimmed = workout.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "workout" : trimmed
    }

    private func elapsedSeconds(at date: Date) -> Int {
        Int(max(0, date.timeIntervalSince(workout.startedAt)))
    }
}

// MARK: - Rows

/// A finished workout in a list: title, Hevy badge, day, exercises, stats.
struct WorkoutsHistoryRow: View {
    let workout: WorkoutRecord
    let weightUnit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(workout.title.isEmpty ? "Workout" : workout.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                WorkoutsSourceBadge(source: workout.source, hevyID: workout.hevyID)
                Spacer(minLength: 0)
                Text(WorkoutsFormat.day(workout.startedAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !exerciseNames.isEmpty {
                Text(exerciseNames)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(WorkoutsFormat.statsLine(
                durationSeconds: workout.durationSeconds,
                sets: workout.completedSetCount,
                volumeKg: workout.volumeKg,
                unit: weightUnit
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// "Bench Press (Barbell), Squat (Barbell) +2"
    private var exerciseNames: String {
        let names = workout.orderedExercises.map(\.name)
        guard !names.isEmpty else { return "" }
        let shown = names.prefix(2).joined(separator: ", ")
        return names.count > 2 ? "\(shown) +\(names.count - 2)" : shown
    }
}

/// A routine: name, exercise count, when it was last used.
struct WorkoutsRoutineRow: View {
    let routine: RoutineRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.rectangle.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.purple)
                .frame(width: 36, height: 36)
                .background(Color.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(routine.name)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [WorkoutsFormat.exerciseCount(routine.exercises.count)]
        if let lastUsed = routine.lastUsedAt {
            parts.append("Last done \(WorkoutsFormat.day(lastUsed).lowercasedIfRelative)")
        } else if !routine.notes.isEmpty {
            parts.append(routine.notes)
        }
        return parts.joined(separator: " · ")
    }
}

private extension String {
    /// "Today" → "today" mid-sentence; dates stay as they are.
    var lowercasedIfRelative: String {
        self == "Today" || self == "Yesterday" ? lowercased() : self
    }
}

/// An exercise from the library: icon, name, muscle and equipment.
struct ExerciseDefinitionRow: View {
    let definition: ExerciseDefinition
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 36

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: WorkoutsFormat.symbol(for: definition.kind))
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: iconSize, height: iconSize)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(definition.name)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [definition.primaryMuscle.title, definition.equipment.title]
        if definition.key.hasPrefix("custom:") { parts.append("Custom") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Muscle chips

/// "All", "Chest", "Back"… as toggling capsules in a horizontal scroller.
struct ExerciseMuscleChips: View {
    @Binding var selection: MuscleGroup?

    /// Every muscle group but the rarely used ones.
    static let muscles: [MuscleGroup] = {
        let hidden: Set<MuscleGroup> = [.neck, .abductors, .adductors, .other]
        return MuscleGroup.allCases.filter { !hidden.contains($0) }
    }()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isSelected: selection == nil) {
                    selection = nil
                }
                ForEach(Self.muscles) { muscle in
                    chip(title: muscle.title, isSelected: selection == muscle) {
                        selection = selection == muscle ? nil : muscle
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.14), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Previews

#Preview("Rows") {
    List {
        WorkoutsHistoryRow(workout: PreviewData.sampleWorkout, weightUnit: .kilograms)
        WorkoutsRoutineRow(routine: PreviewData.sampleRoutine)
        ExerciseDefinitionRow(definition: ExerciseLibrary.all[0])
        HStack {
            WorkoutsRecordBadge()
            WorkoutsStreakBadge(weeks: 3)
            WorkoutsSourceBadge(source: .hevy, hevyID: "abc")
        }
    }
    .previewEnvironment()
}

#Preview("Start") {
    VStack(spacing: 16) {
        WorkoutsStartControl(activeWorkout: nil, routines: [PreviewData.sampleRoutine], onResume: { _ in }, onStart: { _ in })
        WorkoutsResumeBanner(workout: PreviewData.sampleWorkout, onResume: {})
    }
    .padding()
    .previewEnvironment()
}
