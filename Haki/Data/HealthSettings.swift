//
//  HealthSettings.swift
//  Haki
//
//  Health preferences kept in UserDefaults (on this device only). Screens
//  bind with @AppStorage using these keys and decode with the helpers:
//
//      @AppStorage(HealthSettings.targetsKey) private var targetsData = Data()
//      var targets: NutritionTargets { HealthSettings.targets(from: targetsData) }
//

import Foundation

enum HealthSettings {
    /// JSON `NutritionTargets`. Empty = `NutritionTargets.standard`.
    static let targetsKey = "health.nutritionTargets"
    /// JSON `NutritionProfile`, if the person filled it in.
    static let profileKey = "health.nutritionProfile"
    /// `WeightUnit` raw value. Empty = the locale's preference.
    static let weightUnitKey = "health.weightUnit"
    /// `DistanceUnit` raw value. Empty = the locale's preference.
    static let distanceUnitKey = "health.distanceUnit"
    /// Bool: start the rest timer when a set is ticked (default on).
    static let restTimerEnabledKey = "health.restTimerEnabled"
    /// Bool: upload finished Haki workouts to Hevy (default off).
    static let hevyUploadEnabledKey = "health.hevyUploadEnabled"
    /// ISO 8601 string: the last time Hevy workout events were synced.
    static let hevyLastSyncKey = "health.hevyLastSync"
    /// Hevy username, shown in Settings once connected.
    static let hevyUsernameKey = "health.hevyUsername"
    /// Bool: the person agreed to send meal photos/descriptions to Haki's AI.
    static let foodAIConsentKey = "health.foodAIConsent"

    static func targets(from data: Data) -> NutritionTargets {
        guard !data.isEmpty, let targets = try? JSONDecoder().decode(NutritionTargets.self, from: data) else {
            return .standard
        }
        return targets
    }

    static func profile(from data: Data) -> NutritionProfile? {
        guard !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(NutritionProfile.self, from: data)
    }

    static func encode(_ targets: NutritionTargets) -> Data {
        (try? JSONEncoder().encode(targets)) ?? Data()
    }

    static func encode(_ profile: NutritionProfile) -> Data {
        (try? JSONEncoder().encode(profile)) ?? Data()
    }

    static func weightUnit(from raw: String) -> WeightUnit {
        WeightUnit(rawValue: raw) ?? .preferred()
    }

    static func distanceUnit(from raw: String) -> DistanceUnit {
        DistanceUnit(rawValue: raw) ?? .preferred()
    }

    /// Clears every health preference and the Hevy sync state (the Hevy API
    /// key lives in the Keychain and is removed separately).
    static func reset(in defaults: UserDefaults = .standard) {
        for key in [targetsKey, profileKey, weightUnitKey, distanceUnitKey, restTimerEnabledKey, hevyUploadEnabledKey, hevyLastSyncKey, hevyUsernameKey, foodAIConsentKey] {
            defaults.removeObject(forKey: key)
        }
    }
}
