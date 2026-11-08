//
//  HevyClient.swift
//  Haki
//
//  A small client for Hevy's public API (https://api.hevyapp.com/docs, v1).
//  Haki talks to Hevy directly from the iPhone with the person's own API key;
//  nothing goes through Haki's servers. The JSON shapes live in
//  Core/HevyModels.swift. The key is sent only in the `api-key` header and is
//  never logged or included in an error.
//

import Foundation

nonisolated struct HevyClient: Sendable {
    let apiKey: String
    let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    /// How long one request may take.
    static let timeout: TimeInterval = 20

    // MARK: Account

    /// The account the key belongs to. Also how a key is checked: Hevy
    /// answers 401/403 (or 404) for a key it doesn't know.
    func userInfo() async throws -> HevyUserInfo {
        let request = try makeRequest(path: "/user/info")
        let data = try await send(request, failure: .userInfo)
        let response = try decode(HevyUserInfoResponse.self, from: data)
        return response.data
    }

    // MARK: Workouts

    /// One page of workouts, newest first. `pageSize` is at most 10.
    func workouts(page: Int, pageSize: Int = HevyAPI.maxWorkoutPageSize) async throws -> HevyWorkoutPage {
        let request = try makeRequest(path: "/workouts", query: pageQuery(page: page, pageSize: pageSize, limit: HevyAPI.maxWorkoutPageSize))
        let data = try await send(request, failure: .read)
        return try decode(HevyWorkoutPage.self, from: data)
    }

    /// How many workouts the account has.
    func workoutCount() async throws -> Int {
        let request = try makeRequest(path: "/workouts/count")
        let data = try await send(request, failure: .read)
        return try decode(HevyWorkoutCount.self, from: data).workoutCount
    }

    /// Workouts updated or deleted since `since`, newest first. `pageSize` is at most 10.
    func workoutEvents(since: Date, page: Int, pageSize: Int = HevyAPI.maxWorkoutPageSize) async throws -> HevyEventPage {
        var query = pageQuery(page: page, pageSize: pageSize, limit: HevyAPI.maxWorkoutPageSize)
        query.append(URLQueryItem(name: "since", value: HevyAPI.formatDate(since)))
        let request = try makeRequest(path: "/workouts/events", query: query)
        let data = try await send(request, failure: .read)
        return try decode(HevyEventPage.self, from: data)
    }

    /// Posts a finished workout; returns it as Hevy stored it.
    func createWorkout(_ workout: HevyNewWorkout) async throws -> HevyWorkout {
        let body = try encode(workout)
        let request = try makeRequest(path: "/workouts", method: "POST", body: body)
        let data = try await send(request, failure: .write)
        let response = try decode(HevyCreatedWorkoutResponse.self, from: data)
        guard let created = response.workout.first else { throw HevyClientError.decoding }
        return created
    }

    // MARK: Exercise templates

    /// One page of the exercise templates on the account (Hevy's library plus
    /// custom ones). `pageSize` is at most 100.
    func exerciseTemplates(page: Int, pageSize: Int = HevyAPI.maxTemplatePageSize) async throws -> HevyTemplatePage {
        let request = try makeRequest(path: "/exercise_templates", query: pageQuery(page: page, pageSize: pageSize, limit: HevyAPI.maxTemplatePageSize))
        let data = try await send(request, failure: .read)
        return try decode(HevyTemplatePage.self, from: data)
    }

    /// Creates a custom exercise template. Returns its id when Hevy's answer
    /// includes one (nil otherwise; reload the templates to find it).
    /// Free accounts are limited to 7 custom exercises (403).
    func createCustomExerciseTemplate(
        title: String,
        kind: ExerciseKind,
        primaryMuscle: MuscleGroup,
        otherMuscles: [MuscleGroup] = [],
        equipment: Equipment
    ) async throws -> String? {
        let others = otherMuscles.filter { $0 != primaryMuscle }.map(\.rawValue)
        let payload = HevyCustomTemplateRequest(
            exercise: HevyCustomTemplateFields(
                title: title,
                exerciseType: kind.rawValue,
                equipmentCategory: equipment.rawValue,
                muscleGroup: primaryMuscle.rawValue,
                otherMuscles: others
            )
        )
        let body = try encode(payload)
        let request = try makeRequest(path: "/exercise_templates", method: "POST", body: body)
        let data = try await send(request, failure: .createTemplate)
        let response = try? JSONDecoder().decode(HevyCreatedTemplateResponse.self, from: data)
        return response?.id
    }

    // MARK: Requests

    /// What a failed request was doing, which decides what 403/404 mean.
    private enum Failure {
        /// Checking the key: 401, 403 and 404 all mean Hevy doesn't know it.
        case userInfo
        case read
        case write
        /// 403 here is Hevy's custom-exercise limit.
        case createTemplate
    }

    private func pageQuery(page: Int, pageSize: Int, limit: Int) -> [URLQueryItem] {
        [
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "pageSize", value: String(min(max(pageSize, 1), limit))),
        ]
    }

    private func makeRequest(path: String, query: [URLQueryItem] = [], method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard var components = URLComponents(string: HevyAPI.baseURL + path) else {
            throw HevyClientError.unexpectedResponse
        }
        if !query.isEmpty {
            components.queryItems = query
        }
        guard let url = components.url else {
            throw HevyClientError.unexpectedResponse
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.timeout)
        request.httpMethod = method
        request.setValue(apiKey, forHTTPHeaderField: HevyAPI.apiKeyHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    /// Sends `request` and returns the body of a 2xx answer; anything else
    /// becomes a `HevyClientError`. Cancellations pass through unchanged.
    private func send(_ request: URLRequest, failure: Failure) async throws -> Data {
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch let error as URLError {
            if error.code == .cancelled { throw error }
            throw HevyClientError.network(HevyClientError.networkMessage(for: error.code))
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else {
            throw HevyClientError.unexpectedResponse
        }
        let status = http.statusCode
        if (200..<300).contains(status) {
            return data
        }
        throw Self.error(status: status, body: data, failure: failure)
    }

    private static func error(status: Int, body: Data, failure: Failure) -> HevyClientError {
        let parsed = try? JSONDecoder().decode(HevyErrorBody.self, from: body)
        let message = cleaned(parsed?.message) ?? cleaned(parsed?.error)
        switch status {
        case 401:
            return .invalidKey
        case 403:
            switch failure {
            case .userInfo:
                return .invalidKey
            case .createTemplate:
                return .notAllowed(cleaned(parsed?.message) ?? "Hevy didn't allow another custom exercise. Free accounts can have up to 7.")
            case .read, .write:
                return .notAllowed(message ?? "Hevy didn't allow that. Check that your Hevy Pro subscription is active.")
            }
        case 404:
            return failure == .userInfo ? .invalidKey : .notFound
        case 429:
            return .rateLimited
        case 400, 422:
            return .badRequest(message)
        case 500...599:
            return .server(status: status)
        default:
            return .unexpectedStatus(status)
        }
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(300))
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw HevyClientError.decoding
        }
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw HevyClientError.unexpectedResponse
        }
    }
}

// MARK: - Errors

/// A failed Hevy request, with a message that reads well in the UI
/// (`localizedDescription`).
nonisolated enum HevyClientError: LocalizedError, Equatable {
    /// The text isn't shaped like a Hevy API key (checked before any request).
    case malformedKey
    /// Hevy doesn't know the key (401/403 on user info).
    case invalidKey
    /// 403 with Hevy's explanation, e.g. the custom-exercise limit.
    case notAllowed(String)
    case notFound
    /// 429.
    case rateLimited
    /// 5xx.
    case server(status: Int)
    /// 400 with Hevy's `error` text, if any.
    case badRequest(String?)
    /// A transport failure, already worded for people.
    case network(String)
    /// Hevy answered with JSON Haki doesn't understand.
    case decoding
    case unexpectedStatus(Int)
    case unexpectedResponse

    var errorDescription: String? {
        switch self {
        case .malformedKey:
            "That doesn't look like a Hevy API key. It's a long code like 1a2b3c4d-5e6f-7a8b-9c0d-1e2f3a4b5c6d."
        case .invalidKey:
            "Hevy didn't accept that API key. Check it on hevy.com under Settings → Developer (needs Hevy Pro)."
        case .notAllowed(let message):
            message
        case .notFound:
            "Hevy couldn't find that. It may have been deleted."
        case .rateLimited:
            "Hevy is getting too many requests right now. Try again in a few minutes."
        case .server:
            "Hevy's servers ran into a problem. Try again in a moment."
        case .badRequest(let message):
            if let message {
                "Hevy didn't accept the request: \(message)"
            } else {
                "Hevy didn't accept the request. Try again."
            }
        case .network(let message):
            message
        case .decoding:
            "Hevy sent a response Haki doesn't understand. Try again later."
        case .unexpectedStatus(let status):
            "Hevy answered with an unexpected error (\(status)). Try again."
        case .unexpectedResponse:
            "Something went wrong talking to Hevy. Try again."
        }
    }

    /// Same wording style as Haki's own network errors.
    static func networkMessage(for code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            "You're offline. Check your connection and try again."
        case .timedOut:
            "Hevy took too long to answer. Try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            "Couldn't reach Hevy. Try again in a moment."
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            "Couldn't open a secure connection to Hevy. Check your network and try again."
        default:
            "A network error occurred. Try again."
        }
    }
}

// MARK: - Request and response bodies

/// POST /v1/exercise_templates: {"exercise": {...}}.
nonisolated private struct HevyCustomTemplateRequest: Encodable {
    var exercise: HevyCustomTemplateFields
}

nonisolated private struct HevyCustomTemplateFields: Encodable {
    var title: String
    var exerciseType: String
    var equipmentCategory: String
    var muscleGroup: String
    var otherMuscles: [String]

    enum CodingKeys: String, CodingKey {
        case title
        case exerciseType = "exercise_type"
        case equipmentCategory = "equipment_category"
        case muscleGroup = "muscle_group"
        case otherMuscles = "other_muscles"
    }
}

/// Hevy documents `{"id": 123}`; template ids elsewhere are strings, so
/// both are accepted.
nonisolated private struct HevyCreatedTemplateResponse: Decodable {
    var id: String?

    enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .id) {
            id = text
        } else if let number = try? container.decode(Int.self, forKey: .id) {
            id = String(number)
        } else {
            id = nil
        }
    }
}
