//
//  WorkoutMath.swift
//  Haki
//
//  Pure Foundation code (see Money.swift): sets, volume, personal records,
//  streaks and weight units for the workout logger. Weights are stored in
//  kilograms and converted for display.
//

import Foundation

// MARK: - Sets

/// Same raw values as Hevy's API.
nonisolated enum SetKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case normal, warmup, dropset, failure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .warmup: "Warm-up"
        case .dropset: "Drop set"
        case .failure: "To failure"
        }
    }

    /// One-letter badge shown in place of the set number.
    var badge: String? {
        switch self {
        case .normal: nil
        case .warmup: "W"
        case .dropset: "D"
        case .failure: "F"
        }
    }

    /// Warm-ups don't count toward volume or records.
    var countsAsWorkingSet: Bool { self != .warmup }
}

nonisolated struct SetValues: Equatable, Hashable, Sendable {
    var kind: SetKind = .normal
    var weightKg: Double?
    var reps: Int?
    var durationSeconds: Int?
    var distanceMeters: Double?
    var rpe: Double?
    var isCompleted: Bool = false

    /// Weight × reps, when both are logged and positive.
    var volumeKg: Double {
        guard let weightKg, let reps, weightKg > 0, reps > 0 else { return 0 }
        return weightKg * Double(reps)
    }

    /// Estimated one-rep max for this set (see `WorkoutMath.estimatedOneRepMax`).
    var estimatedOneRepMaxKg: Double? {
        guard let weightKg, let reps else { return nil }
        return WorkoutMath.estimatedOneRepMax(weightKg: weightKg, reps: reps)
    }
}

// MARK: - Units

nonisolated enum WeightUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case kilograms = "kg"
    case pounds = "lbs"

    var id: String { rawValue }
    var symbol: String { self == .kilograms ? "kg" : "lb" }

    /// Pounds for the US, Liberia and Myanmar; kilograms elsewhere.
    static func preferred(for locale: Locale = .current) -> WeightUnit {
        locale.measurementSystem == .us ? .pounds : .kilograms
    }

    func fromKilograms(_ kilograms: Double) -> Double {
        self == .kilograms ? kilograms : BodyUnits.pounds(fromKilograms: kilograms)
    }

    func toKilograms(_ value: Double) -> Double {
        self == .kilograms ? value : BodyUnits.kilograms(fromPounds: value)
    }

    /// "62.5" / "135" — at most one decimal, no trailing ".0".
    func format(kilograms: Double) -> String {
        let value = (fromKilograms(kilograms) * 10).rounded() / 10
        return value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Parses what someone typed ("62,5" or "62.5"); nil for nothing or nonsense.
    func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0, value < 10_000 else { return nil }
        return toKilograms(value)
    }
}

nonisolated enum DistanceUnit: String, CaseIterable, Codable, Identifiable, Sendable {
    case kilometers, miles

    var id: String { rawValue }
    var symbol: String { self == .kilometers ? "km" : "mi" }

    static func preferred(for locale: Locale = .current) -> DistanceUnit {
        locale.measurementSystem == .metric ? .kilometers : .miles
    }

    var metersPerUnit: Double { self == .kilometers ? 1_000 : 1_609.344 }

    func format(meters: Double) -> String {
        String(format: "%.2f", meters / metersPerUnit)
    }

    func parse(_ text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0, value < 1_000 else { return nil }
        return value * metersPerUnit
    }
}

// MARK: - Records

nonisolated struct ExercisePerformance: Equatable, Sendable {
    let date: Date
    let sets: [SetValues]
}

nonisolated enum RecordKind: String, CaseIterable, Hashable, Sendable {
    case heaviestWeight, bestOneRepMax, mostReps, bestSetVolume

    var title: String {
        switch self {
        case .heaviestWeight: "Heaviest weight"
        case .bestOneRepMax: "Best est. 1RM"
        case .mostReps: "Most reps"
        case .bestSetVolume: "Best set volume"
        }
    }
}

nonisolated struct PersonalRecords: Equatable, Sendable {
    var heaviestWeightKg: Double?
    var bestOneRepMaxKg: Double?
    var mostReps: Int?
    var bestSetVolumeKg: Double?

    static let none = PersonalRecords()
}

nonisolated enum WorkoutMath {
    /// Epley's estimate: weight × (1 + reps / 30), the weight itself for a
    /// single. Nil past 15 reps, where the estimate stops meaning much.
    static func estimatedOneRepMax(weightKg: Double, reps: Int) -> Double? {
        guard weightKg > 0, weightKg.isFinite, reps > 0, reps <= 15 else { return nil }
        return reps == 1 ? weightKg : weightKg * (1 + Double(reps) / 30)
    }

    /// Completed working sets only (no warm-ups, nothing unticked).
    static func workingSets(_ sets: [SetValues]) -> [SetValues] {
        sets.filter { $0.isCompleted && $0.kind.countsAsWorkingSet }
    }

    /// Total weight × reps over completed working sets.
    static func volumeKg(_ sets: [SetValues]) -> Double {
        workingSets(sets).reduce(0) { $0 + $1.volumeKg }
    }

    /// The completed working set with the best estimated 1RM (heaviest
    /// weight breaks ties; then most reps).
    static func bestSet(_ sets: [SetValues]) -> SetValues? {
        workingSets(sets).max { a, b in
            let ea = a.estimatedOneRepMaxKg ?? 0
            let eb = b.estimatedOneRepMaxKg ?? 0
            if ea != eb { return ea < eb }
            if (a.weightKg ?? 0) != (b.weightKg ?? 0) { return (a.weightKg ?? 0) < (b.weightKg ?? 0) }
            return (a.reps ?? 0) < (b.reps ?? 0)
        }
    }

    /// Records across `performances`. With `countsWeight` false (assisted,
    /// bodyweight or timed exercises) only `mostReps` is tracked.
    static func records(_ performances: [ExercisePerformance], countsWeight: Bool = true) -> PersonalRecords {
        var records = PersonalRecords()
        for performance in performances {
            for set in workingSets(performance.sets) {
                merge(set, into: &records, countsWeight: countsWeight)
            }
        }
        return records
    }

    /// Which records `set` would beat. Needs an earlier record to beat: the
    /// first time someone does an exercise isn't a "PR".
    static func newRecords(for set: SetValues, previous: PersonalRecords, countsWeight: Bool = true) -> Set<RecordKind> {
        guard set.isCompleted, set.kind.countsAsWorkingSet else { return [] }
        var beaten = Set<RecordKind>()
        if countsWeight {
            if let weight = set.weightKg, weight > 0, let best = previous.heaviestWeightKg, weight > best + 0.001 {
                beaten.insert(.heaviestWeight)
            }
            if let e1rm = set.estimatedOneRepMaxKg, let best = previous.bestOneRepMaxKg, e1rm > best + 0.001 {
                beaten.insert(.bestOneRepMax)
            }
            if set.volumeKg > 0, let best = previous.bestSetVolumeKg, set.volumeKg > best + 0.001 {
                beaten.insert(.bestSetVolume)
            }
        }
        if let reps = set.reps, reps > 0, let best = previous.mostReps, reps > best {
            beaten.insert(.mostReps)
        }
        return beaten
    }

    private static func merge(_ set: SetValues, into records: inout PersonalRecords, countsWeight: Bool) {
        if countsWeight {
            if let weight = set.weightKg, weight > 0 {
                records.heaviestWeightKg = max(records.heaviestWeightKg ?? 0, weight)
            }
            if let e1rm = set.estimatedOneRepMaxKg {
                records.bestOneRepMaxKg = max(records.bestOneRepMaxKg ?? 0, e1rm)
            }
            if set.volumeKg > 0 {
                records.bestSetVolumeKg = max(records.bestSetVolumeKg ?? 0, set.volumeKg)
            }
        }
        if let reps = set.reps, reps > 0 {
            records.mostReps = max(records.mostReps ?? 0, reps)
        }
    }

    // MARK: Streaks and summaries

    /// Consecutive calendar weeks with at least one workout, ending this
    /// week — or last week when there's none yet this week.
    static func weekStreak(workoutDates: [Date], now: Date = .now, calendar: Calendar = .current) -> Int {
        let weeks = Set(workoutDates.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
        guard var week = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(week) {
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { return 0 }
            week = previous
        }
        var streak = 0
        while weeks.contains(week) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: week) else { break }
            week = previous
        }
        return streak
    }

    /// Workouts in each of the last `weeks` calendar weeks, oldest first.
    static func workoutsPerWeek(workoutDates: [Date], weeks: Int, now: Date = .now, calendar: Calendar = .current) -> [(weekStart: Date, count: Int)] {
        guard weeks > 0, let current = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        var counts: [Date: Int] = [:]
        for date in workoutDates {
            if let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start {
                counts[start, default: 0] += 1
            }
        }
        return (0..<weeks).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: current) else { return nil }
            return (start, counts[start] ?? 0)
        }
    }

    /// Completed working sets per primary muscle group.
    static func setsPerMuscle(_ exercises: [(muscle: MuscleGroup, sets: [SetValues])]) -> [MuscleGroup: Int] {
        var result: [MuscleGroup: Int] = [:]
        for exercise in exercises {
            let count = workingSets(exercise.sets).count
            if count > 0 { result[exercise.muscle, default: 0] += count }
        }
        return result
    }

    /// "45s", "12:05", "1:02:09".
    static func formatTimer(seconds: Int) -> String {
        let s = max(seconds, 0)
        let hours = s / 3_600
        let minutes = (s % 3_600) / 60
        let secs = s % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        if minutes > 0 { return String(format: "%d:%02d", minutes, secs) }
        return "\(secs)s"
    }

    /// "45s", "52m", "1h 05m". Under a minute shows seconds (like the live
    /// timer) rather than "0m".
    static func formatDuration(seconds: Int) -> String {
        let total = max(seconds, 0)
        if total < 60 { return "\(total)s" }
        let minutes = total / 60
        if minutes >= 60 { return String(format: "%dh %02dm", minutes / 60, minutes % 60) }
        return "\(minutes)m"
    }
}
