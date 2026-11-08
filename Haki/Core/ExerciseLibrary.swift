//
//  ExerciseLibrary.swift
//  Haki
//
//  Pure Foundation code (see Money.swift): the built-in exercises for the
//  workout logger. Muscle groups, equipment and exercise kinds use the same
//  raw values as Hevy's public API so workouts move between the two cleanly.
//

import Foundation

nonisolated enum MuscleGroup: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case chest, shoulders, triceps, biceps, forearms
    case lats
    case upperBack = "upper_back"
    case lowerBack = "lower_back"
    case traps, abdominals, glutes, quadriceps, hamstrings, calves, abductors, adductors, neck, cardio
    case fullBody = "full_body"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: "Chest"
        case .shoulders: "Shoulders"
        case .triceps: "Triceps"
        case .biceps: "Biceps"
        case .forearms: "Forearms"
        case .lats: "Lats"
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        case .traps: "Traps"
        case .abdominals: "Abs"
        case .glutes: "Glutes"
        case .quadriceps: "Quads"
        case .hamstrings: "Hamstrings"
        case .calves: "Calves"
        case .abductors: "Abductors"
        case .adductors: "Adductors"
        case .neck: "Neck"
        case .cardio: "Cardio"
        case .fullBody: "Full body"
        case .other: "Other"
        }
    }

    /// Broad body region, for weekly summaries.
    var region: BodyRegion {
        switch self {
        case .chest, .shoulders, .triceps, .biceps, .forearms, .lats, .upperBack, .traps, .neck: .upper
        case .glutes, .quadriceps, .hamstrings, .calves, .abductors, .adductors: .lower
        case .abdominals, .lowerBack: .core
        case .cardio, .fullBody, .other: .other
        }
    }
}

nonisolated enum BodyRegion: String, CaseIterable, Sendable {
    case upper, lower, core, other

    var title: String {
        switch self {
        case .upper: "Upper body"
        case .lower: "Lower body"
        case .core: "Core"
        case .other: "Other"
        }
    }
}

nonisolated enum Equipment: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case none, barbell, dumbbell, kettlebell, machine, plate
    case resistanceBand = "resistance_band"
    case suspension, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Bodyweight"
        case .barbell: "Barbell"
        case .dumbbell: "Dumbbell"
        case .kettlebell: "Kettlebell"
        case .machine: "Machine"
        case .plate: "Plate"
        case .resistanceBand: "Band"
        case .suspension: "Suspension"
        case .other: "Other"
        }
    }
}

/// What gets logged for each set.
nonisolated enum ExerciseKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case weightReps = "weight_reps"
    case repsOnly = "reps_only"
    case bodyweightReps = "bodyweight_reps"
    case assistedBodyweightReps = "bodyweight_assisted_reps"
    case duration
    case weightDuration = "weight_duration"
    case distanceDuration = "distance_duration"
    case weightDistance = "short_distance_weight"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weightReps: "Weight & reps"
        case .repsOnly: "Reps only"
        case .bodyweightReps: "Bodyweight & extra weight"
        case .assistedBodyweightReps: "Assisted bodyweight"
        case .duration: "Duration"
        case .weightDuration: "Weight & duration"
        case .distanceDuration: "Distance & duration"
        case .weightDistance: "Weight & distance"
        }
    }

    var logsWeight: Bool {
        switch self {
        case .weightReps, .bodyweightReps, .assistedBodyweightReps, .weightDuration, .weightDistance: true
        case .repsOnly, .duration, .distanceDuration: false
        }
    }

    var logsReps: Bool {
        switch self {
        case .weightReps, .repsOnly, .bodyweightReps, .assistedBodyweightReps: true
        case .duration, .weightDuration, .distanceDuration, .weightDistance: false
        }
    }

    var logsDuration: Bool {
        switch self {
        case .duration, .weightDuration, .distanceDuration: true
        default: false
        }
    }

    var logsDistance: Bool {
        switch self {
        case .distanceDuration, .weightDistance: true
        default: false
        }
    }

    /// Whether the logged weight counts toward volume and one-rep-max records.
    /// Assisted weight is help, not load, and bodyweight extra load is partial.
    var countsWeightForRecords: Bool { self == .weightReps }
}

nonisolated struct ExerciseDefinition: Equatable, Hashable, Identifiable, Sendable {
    /// Stable key stored with logged exercises. Built-in keys never change.
    let key: String
    /// Written "Name (Equipment)" like most loggers, which also lets Haki
    /// match Hevy's exercise templates by title.
    let name: String
    let primaryMuscle: MuscleGroup
    let secondaryMuscles: [MuscleGroup]
    let equipment: Equipment
    let kind: ExerciseKind

    var id: String { key }

    init(_ key: String, _ name: String, _ primary: MuscleGroup, _ secondary: [MuscleGroup] = [], _ equipment: Equipment, _ kind: ExerciseKind = .weightReps) {
        self.key = key
        self.name = name
        self.primaryMuscle = primary
        self.secondaryMuscles = secondary
        self.equipment = equipment
        self.kind = kind
    }

    /// Default rest between sets, in seconds.
    var defaultRestSeconds: Int {
        switch kind {
        case .duration, .distanceDuration: 60
        default: equipment == .barbell ? 150 : 90
        }
    }
}

nonisolated enum ExerciseLibrary {
    static let all: [ExerciseDefinition] = [
        // Chest
        ExerciseDefinition("bench_press_barbell", "Bench Press (Barbell)", .chest, [.triceps, .shoulders], .barbell),
        ExerciseDefinition("bench_press_dumbbell", "Bench Press (Dumbbell)", .chest, [.triceps, .shoulders], .dumbbell),
        ExerciseDefinition("incline_bench_press_barbell", "Incline Bench Press (Barbell)", .chest, [.shoulders, .triceps], .barbell),
        ExerciseDefinition("incline_bench_press_dumbbell", "Incline Bench Press (Dumbbell)", .chest, [.shoulders, .triceps], .dumbbell),
        ExerciseDefinition("decline_bench_press_barbell", "Decline Bench Press (Barbell)", .chest, [.triceps], .barbell),
        ExerciseDefinition("chest_press_machine", "Chest Press (Machine)", .chest, [.triceps, .shoulders], .machine),
        ExerciseDefinition("chest_fly_dumbbell", "Chest Fly (Dumbbell)", .chest, [.shoulders], .dumbbell),
        ExerciseDefinition("chest_fly_machine", "Chest Fly (Machine)", .chest, [.shoulders], .machine),
        ExerciseDefinition("cable_crossover", "Cable Crossover", .chest, [.shoulders], .machine),
        ExerciseDefinition("push_up", "Push Up", .chest, [.triceps, .shoulders], .none, .repsOnly),
        ExerciseDefinition("chest_dip", "Chest Dip", .chest, [.triceps], .none, .bodyweightReps),
        // Back
        ExerciseDefinition("deadlift_barbell", "Deadlift (Barbell)", .lowerBack, [.hamstrings, .glutes, .traps], .barbell),
        ExerciseDefinition("romanian_deadlift_barbell", "Romanian Deadlift (Barbell)", .hamstrings, [.glutes, .lowerBack], .barbell),
        ExerciseDefinition("romanian_deadlift_dumbbell", "Romanian Deadlift (Dumbbell)", .hamstrings, [.glutes, .lowerBack], .dumbbell),
        ExerciseDefinition("bent_over_row_barbell", "Bent Over Row (Barbell)", .upperBack, [.lats, .biceps], .barbell),
        ExerciseDefinition("dumbbell_row", "Dumbbell Row", .upperBack, [.lats, .biceps], .dumbbell),
        ExerciseDefinition("seated_cable_row", "Seated Cable Row", .upperBack, [.lats, .biceps], .machine),
        ExerciseDefinition("t_bar_row", "T Bar Row", .upperBack, [.lats, .biceps], .barbell),
        ExerciseDefinition("lat_pulldown_cable", "Lat Pulldown (Cable)", .lats, [.biceps], .machine),
        ExerciseDefinition("pull_up", "Pull Up", .lats, [.biceps, .upperBack], .none, .bodyweightReps),
        ExerciseDefinition("assisted_pull_up", "Pull Up (Assisted)", .lats, [.biceps], .machine, .assistedBodyweightReps),
        ExerciseDefinition("chin_up", "Chin Up", .lats, [.biceps], .none, .bodyweightReps),
        ExerciseDefinition("face_pull", "Face Pull", .shoulders, [.upperBack], .machine),
        ExerciseDefinition("shrug_dumbbell", "Shrug (Dumbbell)", .traps, [], .dumbbell),
        ExerciseDefinition("back_extension", "Back Extension", .lowerBack, [.glutes, .hamstrings], .none, .bodyweightReps),
        // Shoulders
        ExerciseDefinition("overhead_press_barbell", "Overhead Press (Barbell)", .shoulders, [.triceps], .barbell),
        ExerciseDefinition("shoulder_press_dumbbell", "Shoulder Press (Dumbbell)", .shoulders, [.triceps], .dumbbell),
        ExerciseDefinition("shoulder_press_machine", "Shoulder Press (Machine)", .shoulders, [.triceps], .machine),
        ExerciseDefinition("lateral_raise_dumbbell", "Lateral Raise (Dumbbell)", .shoulders, [], .dumbbell),
        ExerciseDefinition("lateral_raise_cable", "Lateral Raise (Cable)", .shoulders, [], .machine),
        ExerciseDefinition("rear_delt_fly_dumbbell", "Rear Delt Fly (Dumbbell)", .shoulders, [.upperBack], .dumbbell),
        ExerciseDefinition("front_raise_dumbbell", "Front Raise (Dumbbell)", .shoulders, [], .dumbbell),
        ExerciseDefinition("arnold_press_dumbbell", "Arnold Press (Dumbbell)", .shoulders, [.triceps], .dumbbell),
        // Arms
        ExerciseDefinition("bicep_curl_barbell", "Bicep Curl (Barbell)", .biceps, [.forearms], .barbell),
        ExerciseDefinition("bicep_curl_dumbbell", "Bicep Curl (Dumbbell)", .biceps, [.forearms], .dumbbell),
        ExerciseDefinition("hammer_curl_dumbbell", "Hammer Curl (Dumbbell)", .biceps, [.forearms], .dumbbell),
        ExerciseDefinition("preacher_curl_ez", "Preacher Curl (Barbell)", .biceps, [], .barbell),
        ExerciseDefinition("bicep_curl_cable", "Bicep Curl (Cable)", .biceps, [], .machine),
        ExerciseDefinition("triceps_pushdown_cable", "Triceps Pushdown (Cable)", .triceps, [], .machine),
        ExerciseDefinition("overhead_triceps_extension_dumbbell", "Overhead Triceps Extension (Dumbbell)", .triceps, [], .dumbbell),
        ExerciseDefinition("skullcrusher_barbell", "Skullcrusher (Barbell)", .triceps, [], .barbell),
        ExerciseDefinition("close_grip_bench_press", "Bench Press Close Grip (Barbell)", .triceps, [.chest], .barbell),
        ExerciseDefinition("triceps_dip", "Triceps Dip", .triceps, [.chest], .none, .bodyweightReps),
        ExerciseDefinition("wrist_curl_dumbbell", "Wrist Curl (Dumbbell)", .forearms, [], .dumbbell),
        // Legs
        ExerciseDefinition("squat_barbell", "Squat (Barbell)", .quadriceps, [.glutes, .hamstrings], .barbell),
        ExerciseDefinition("front_squat_barbell", "Front Squat (Barbell)", .quadriceps, [.glutes, .abdominals], .barbell),
        ExerciseDefinition("goblet_squat", "Goblet Squat", .quadriceps, [.glutes], .dumbbell),
        ExerciseDefinition("hack_squat_machine", "Hack Squat (Machine)", .quadriceps, [.glutes], .machine),
        ExerciseDefinition("leg_press_machine", "Leg Press (Machine)", .quadriceps, [.glutes, .hamstrings], .machine),
        ExerciseDefinition("leg_extension_machine", "Leg Extension (Machine)", .quadriceps, [], .machine),
        ExerciseDefinition("lying_leg_curl_machine", "Lying Leg Curl (Machine)", .hamstrings, [], .machine),
        ExerciseDefinition("seated_leg_curl_machine", "Seated Leg Curl (Machine)", .hamstrings, [], .machine),
        ExerciseDefinition("bulgarian_split_squat", "Bulgarian Split Squat", .quadriceps, [.glutes], .dumbbell),
        ExerciseDefinition("lunge_dumbbell", "Lunge (Dumbbell)", .quadriceps, [.glutes], .dumbbell),
        ExerciseDefinition("walking_lunge", "Walking Lunge", .quadriceps, [.glutes], .none, .repsOnly),
        ExerciseDefinition("hip_thrust_barbell", "Hip Thrust (Barbell)", .glutes, [.hamstrings], .barbell),
        ExerciseDefinition("glute_bridge", "Glute Bridge", .glutes, [.hamstrings], .none, .repsOnly),
        ExerciseDefinition("standing_calf_raise_machine", "Standing Calf Raise (Machine)", .calves, [], .machine),
        ExerciseDefinition("seated_calf_raise", "Seated Calf Raise", .calves, [], .machine),
        ExerciseDefinition("hip_abduction_machine", "Hip Abduction (Machine)", .abductors, [], .machine),
        ExerciseDefinition("hip_adduction_machine", "Hip Adduction (Machine)", .adductors, [], .machine),
        ExerciseDefinition("kettlebell_swing", "Kettlebell Swing", .glutes, [.hamstrings, .lowerBack], .kettlebell),
        // Core
        ExerciseDefinition("plank", "Plank", .abdominals, [], .none, .duration),
        ExerciseDefinition("crunch", "Crunch", .abdominals, [], .none, .repsOnly),
        ExerciseDefinition("hanging_leg_raise", "Hanging Leg Raise", .abdominals, [], .none, .repsOnly),
        ExerciseDefinition("cable_crunch", "Cable Crunch", .abdominals, [], .machine),
        ExerciseDefinition("russian_twist", "Russian Twist", .abdominals, [], .none, .repsOnly),
        ExerciseDefinition("ab_wheel", "Ab Wheel", .abdominals, [], .other, .repsOnly),
        ExerciseDefinition("side_plank", "Side Plank", .abdominals, [], .none, .duration),
        // Full body and cardio
        ExerciseDefinition("farmers_walk", "Farmers Walk", .forearms, [.traps, .fullBody], .dumbbell, .weightDistance),
        ExerciseDefinition("burpee", "Burpee", .fullBody, [], .none, .repsOnly),
        ExerciseDefinition("treadmill", "Treadmill", .cardio, [], .machine, .distanceDuration),
        ExerciseDefinition("running", "Running", .cardio, [], .none, .distanceDuration),
        ExerciseDefinition("cycling", "Cycling", .cardio, [], .machine, .distanceDuration),
        ExerciseDefinition("rowing_machine", "Rowing Machine", .cardio, [.upperBack], .machine, .distanceDuration),
        ExerciseDefinition("elliptical", "Elliptical Trainer", .cardio, [], .machine, .distanceDuration),
        ExerciseDefinition("stair_machine", "Stair Machine", .cardio, [], .machine, .duration),
        ExerciseDefinition("jump_rope", "Jump Rope", .cardio, [], .other, .duration),
    ]

    private static let byKey: [String: ExerciseDefinition] = Dictionary(
        all.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first }
    )

    static func exercise(key: String) -> ExerciseDefinition? { byKey[key] }

    private static let byNormalizedTitle: [String: ExerciseDefinition] = Dictionary(
        all.map { (normalizedTitle($0.name), $0) }, uniquingKeysWith: { first, _ in first }
    )

    /// The built-in exercise with this title (see `normalizedTitle`), e.g.
    /// for a workout copied from Hevy.
    static func builtIn(matchingTitle title: String) -> ExerciseDefinition? {
        byNormalizedTitle[normalizedTitle(title)]
    }

    /// Built-in exercises whose name, muscles or equipment match `query`,
    /// optionally limited to one muscle group, sorted by name.
    static func search(_ query: String, muscle: MuscleGroup? = nil, in exercises: [ExerciseDefinition] = all) -> [ExerciseDefinition] {
        let words = query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        return exercises
            .filter { definition in
                if let muscle, definition.primaryMuscle != muscle, !definition.secondaryMuscles.contains(muscle) {
                    return false
                }
                guard !words.isEmpty else { return true }
                let haystack = ([definition.name, definition.primaryMuscle.title, definition.equipment.title]
                    + definition.secondaryMuscles.map(\.title)).joined(separator: " ").lowercased()
                return words.allSatisfy { haystack.contains($0) }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// A comparable form of an exercise title: lowercase letters and digits
    /// only, so "Bench Press (Barbell)" and "bench press - barbell" match.
    static func normalizedTitle(_ title: String) -> String {
        String(title.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// The id of the template in `templates` whose title matches `name`
    /// (see `normalizedTitle`), preferring Hevy's built-in templates over
    /// custom ones. Nil when nothing matches.
    static func matchingTemplateID(for name: String, in templates: [(id: String, title: String, isCustom: Bool)]) -> String? {
        let target = normalizedTitle(name)
        guard !target.isEmpty else { return nil }
        let matches = templates.filter { normalizedTitle($0.title) == target }
        return (matches.first { !$0.isCustom } ?? matches.first)?.id
    }
}
