//
//  HevyModels.swift
//  Haki
//
//  Pure Foundation code (see Money.swift): the JSON shapes of Hevy's public
//  API (https://api.hevyapp.com/docs), v1. Requests need a Hevy Pro API key
//  in the `api-key` header. Pages hold at most 10 workouts or 100 templates.
//

import Foundation

nonisolated enum HevyAPI {
    static let baseURL = "https://api.hevyapp.com/v1"
    static let apiKeyHeader = "api-key"
    static let maxWorkoutPageSize = 10
    static let maxTemplatePageSize = 100
    /// Where people create a key (Hevy Pro): Settings › Developer on hevy.com.
    static let developerSettingsURL = "https://hevy.com/settings?developer"

    /// Hevy sends ISO 8601 timestamps, sometimes with fractional seconds.
    static func parseDate(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// "2024-08-14T12:00:00Z" (UTC, whole seconds), the form Hevy's examples use.
    static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// API keys are UUIDs; checks the shape before a request is made.
    static func isPlausibleAPIKey(_ key: String) -> Bool {
        UUID(uuidString: key.trimmingCharacters(in: .whitespacesAndNewlines)) != nil
    }
}

// MARK: - Responses

nonisolated struct HevySet: Equatable, Codable, Sendable {
    var index: Int?
    var type: String?
    var weightKg: Double?
    var reps: Double?
    var distanceMeters: Double?
    var durationSeconds: Double?
    var rpe: Double?
    var customMetric: Double?

    enum CodingKeys: String, CodingKey {
        case index, type, reps, rpe
        case weightKg = "weight_kg"
        case distanceMeters = "distance_meters"
        case durationSeconds = "duration_seconds"
        case customMetric = "custom_metric"
    }

    /// Hevy only returns sets that were logged, so they count as completed.
    var values: SetValues {
        SetValues(
            kind: type.flatMap(SetKind.init(rawValue:)) ?? .normal,
            weightKg: weightKg,
            reps: reps.map { Int($0.rounded()) },
            durationSeconds: durationSeconds.map { Int($0.rounded()) },
            distanceMeters: distanceMeters,
            rpe: rpe,
            isCompleted: true
        )
    }
}

nonisolated struct HevyExercise: Equatable, Codable, Sendable {
    var index: Int?
    var title: String
    var notes: String?
    var exerciseTemplateID: String?
    var supersetID: Int?
    var sets: [HevySet]

    enum CodingKeys: String, CodingKey {
        case index, title, notes, sets
        case exerciseTemplateID = "exercise_template_id"
        case supersetID = "superset_id"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Exercise"
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        exerciseTemplateID = try container.decodeIfPresent(String.self, forKey: .exerciseTemplateID)
        supersetID = try container.decodeIfPresent(Int.self, forKey: .supersetID)
        sets = try container.decodeIfPresent([HevySet].self, forKey: .sets) ?? []
    }
}

nonisolated struct HevyWorkout: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var title: String
    var routineID: String?
    var description: String?
    var startTime: String?
    var endTime: String?
    var updatedAt: String?
    var createdAt: String?
    var exercises: [HevyExercise]

    enum CodingKeys: String, CodingKey {
        case id, title, description, exercises
        case routineID = "routine_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Workout"
        routineID = try container.decodeIfPresent(String.self, forKey: .routineID)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        startTime = try container.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(String.self, forKey: .endTime)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        exercises = try container.decodeIfPresent([HevyExercise].self, forKey: .exercises) ?? []
    }

    var startDate: Date? { HevyAPI.parseDate(startTime) }
    var endDate: Date? { HevyAPI.parseDate(endTime) }
    var updatedDate: Date? { HevyAPI.parseDate(updatedAt) }
}

nonisolated struct HevyWorkoutPage: Equatable, Codable, Sendable {
    var page: Int
    var pageCount: Int
    var workouts: [HevyWorkout]

    enum CodingKeys: String, CodingKey {
        case page, workouts
        case pageCount = "page_count"
    }
}

/// One entry of GET /v1/workouts/events.
nonisolated enum HevyWorkoutEvent: Equatable, Decodable, Sendable {
    case updated(HevyWorkout)
    case deleted(id: String, deletedAt: Date?)
    /// A kind this version of Haki doesn't know; skipped.
    case unknown

    private enum CodingKeys: String, CodingKey {
        case type, workout, id
        case deletedAt = "deleted_at"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeIfPresent(String.self, forKey: .type) {
        case "updated":
            self = .updated(try container.decode(HevyWorkout.self, forKey: .workout))
        case "deleted":
            let id = try container.decode(String.self, forKey: .id)
            self = .deleted(id: id, deletedAt: HevyAPI.parseDate(try container.decodeIfPresent(String.self, forKey: .deletedAt)))
        default:
            self = .unknown
        }
    }
}

nonisolated struct HevyEventPage: Equatable, Decodable, Sendable {
    var page: Int
    var pageCount: Int
    var events: [HevyWorkoutEvent]

    enum CodingKeys: String, CodingKey {
        case page, events
        case pageCount = "page_count"
    }
}

nonisolated struct HevyWorkoutCount: Equatable, Codable, Sendable {
    var workoutCount: Int

    enum CodingKeys: String, CodingKey {
        case workoutCount = "workout_count"
    }
}

nonisolated struct HevyExerciseTemplate: Equatable, Codable, Sendable, Identifiable {
    var id: String
    var title: String
    var type: String?
    var primaryMuscleGroup: String?
    var secondaryMuscleGroups: [String]?
    var equipment: String?
    var isCustom: Bool?

    enum CodingKeys: String, CodingKey {
        case id, title, type, equipment
        case primaryMuscleGroup = "primary_muscle_group"
        case secondaryMuscleGroups = "secondary_muscle_groups"
        case isCustom = "is_custom"
    }

    var kind: ExerciseKind { type.flatMap(ExerciseKind.init(rawValue:)) ?? .weightReps }
    var muscle: MuscleGroup { primaryMuscleGroup.flatMap(MuscleGroup.init(rawValue:)) ?? .other }
    var equipmentValue: Equipment { equipment.flatMap(Equipment.init(rawValue:)) ?? .other }
}

nonisolated struct HevyTemplatePage: Equatable, Codable, Sendable {
    var page: Int
    var pageCount: Int
    var exerciseTemplates: [HevyExerciseTemplate]

    enum CodingKeys: String, CodingKey {
        case page
        case pageCount = "page_count"
        case exerciseTemplates = "exercise_templates"
    }
}

nonisolated struct HevyUserInfo: Equatable, Codable, Sendable {
    var id: String?
    var username: String?
    var name: String?
    var url: String?
    var weightUnit: String?
    var isPro: Bool?

    enum CodingKeys: String, CodingKey {
        case id, username, name, url
        case weightUnit = "weight_unit"
        case isPro = "is_pro"
    }
}

nonisolated struct HevyUserInfoResponse: Equatable, Codable, Sendable {
    var data: HevyUserInfo
}

/// Hevy's error body: {"error": "..."} or {"error": code, "message": "..."}.
nonisolated struct HevyErrorBody: Decodable, Sendable {
    var error: String?
    var message: String?
}

// MARK: - Creating a workout (POST /v1/workouts)

nonisolated struct HevyNewWorkout: Equatable, Encodable, Sendable {
    struct SetEntry: Equatable, Encodable, Sendable {
        var type: String
        var weightKg: Double?
        var reps: Int?
        var distanceMeters: Int?
        var durationSeconds: Int?
        var rpe: Double?

        enum CodingKeys: String, CodingKey {
            case type, reps, rpe
            case weightKg = "weight_kg"
            case distanceMeters = "distance_meters"
            case durationSeconds = "duration_seconds"
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(type, forKey: .type)
            // Hevy reads explicit nulls; send them so every field is present.
            try container.encode(weightKg, forKey: .weightKg)
            try container.encode(reps, forKey: .reps)
            try container.encode(distanceMeters, forKey: .distanceMeters)
            try container.encode(durationSeconds, forKey: .durationSeconds)
            try container.encode(rpe, forKey: .rpe)
        }
    }

    struct ExerciseEntry: Equatable, Encodable, Sendable {
        var exerciseTemplateID: String
        var supersetID: Int?
        var notes: String?
        var sets: [SetEntry]

        enum CodingKeys: String, CodingKey {
            case notes, sets
            case exerciseTemplateID = "exercise_template_id"
            case supersetID = "superset_id"
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(exerciseTemplateID, forKey: .exerciseTemplateID)
            try container.encode(supersetID, forKey: .supersetID)
            try container.encode(notes, forKey: .notes)
            try container.encode(sets, forKey: .sets)
        }
    }

    var title: String
    var description: String?
    var startTime: Date
    var endTime: Date
    var isPrivate: Bool
    var exercises: [ExerciseEntry]

    private enum OuterKeys: String, CodingKey { case workout }

    private enum CodingKeys: String, CodingKey {
        case title, description, exercises
        case startTime = "start_time"
        case endTime = "end_time"
        case isPrivate = "is_private"
    }

    /// Encodes as Hevy's request body: {"workout": {...}}.
    func encode(to encoder: any Encoder) throws {
        var outer = encoder.container(keyedBy: OuterKeys.self)
        var container = outer.nestedContainer(keyedBy: CodingKeys.self, forKey: .workout)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(HevyAPI.formatDate(startTime), forKey: .startTime)
        try container.encode(HevyAPI.formatDate(max(endTime, startTime)), forKey: .endTime)
        try container.encode(isPrivate, forKey: .isPrivate)
        try container.encode(exercises, forKey: .exercises)
    }

    /// Hevy accepts only these RPE values; others are dropped (sent as null).
    static let allowedRPE: [Double] = [6, 7, 7.5, 8, 8.5, 9, 9.5, 10]

    /// A set in Hevy's form, or nil for an unfinished set (Hevy has no
    /// "not done" state, so those aren't uploaded).
    static func set(from values: SetValues) -> SetEntry? {
        guard values.isCompleted else { return nil }
        let rpe = values.rpe.flatMap { value in allowedRPE.first { abs($0 - value) < 0.01 } }
        return SetEntry(
            type: values.kind.rawValue,
            weightKg: values.weightKg.map { ($0 * 1_000).rounded() / 1_000 },
            reps: values.reps,
            distanceMeters: values.distanceMeters.map { Int($0.rounded()) },
            durationSeconds: values.durationSeconds,
            rpe: rpe
        )
    }
}

nonisolated struct HevyCreatedWorkoutResponse: Decodable, Sendable {
    /// Hevy returns the created workout as a one-element array.
    var workout: [HevyWorkout]
}
