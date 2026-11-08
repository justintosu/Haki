//
//  Backend.swift
//  Haki
//
//  The one Supabase client the app talks to. Services take it as a
//  dependency (`AuthService(client: Backend.client)`), and pass `nil` in
//  previews so nothing touches the network.
//

import Foundation
import Supabase

enum Backend {
    /// The shared Supabase client (PKCE flow, redirect to BackendConfig.authCallbackURL).
    static let client: SupabaseClient = SupabaseClient(
        supabaseURL: BackendConfig.supabaseURL,
        supabaseKey: BackendConfig.supabasePublishableKey,
        options: SupabaseClientOptions(
            db: SupabaseClientOptions.DatabaseOptions(decoder: makeDatabaseDecoder()),
            auth: SupabaseClientOptions.AuthOptions(
                redirectToURL: BackendConfig.authCallbackURL,
                flowType: .pkce,
                // Emit the stored session right away at launch (even if it needs a
                // refresh), so a signed-in user goes straight into the app offline too.
                emitLocalSessionAsInitialSession: true
            )
        )
    )

    /// Decodes database rows. `timestamptz` values come back from PostgREST as
    /// ISO-8601 strings with microseconds and an offset
    /// ("2026-11-08T17:04:05.123456+00:00"); this decoder parses every variant
    /// Postgres produces, independent of Foundation's ISO-8601 parser.
    private static func makeDatabaseDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = backendParseTimestamp(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date format: \(string)"
            )
        }
        return decoder
    }
}

// MARK: - Errors

/// A failed backend call, with a message that can be shown to the user as is
/// (`localizedDescription`).
nonisolated struct BackendError: LocalizedError, Hashable {
    /// The server's code when there is one: an edge-function code such as
    /// "plaid_not_configured", a Postgres SQLSTATE such as "23505", or "network".
    var code: String?
    var message: String

    var errorDescription: String? { message }
}

extension Backend {
    /// Whether `error` means the work was cancelled (a cancelled task or a
    /// cancelled URL request), which should never be shown to the user.
    nonisolated static func isCancellation(_ error: any Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// Turns SDK, network and server errors into errors whose
    /// `localizedDescription` reads well in an alert. Errors that already do
    /// (`BackendError`, `AuthServiceError`) and cancellations pass through.
    nonisolated static func userFacingError(
        _ error: any Error,
        fallback: String = "Something went wrong. Try again."
    ) -> any Error {
        if isCancellation(error) || error is BackendError || error is AuthServiceError {
            return error
        }
        if let urlError = error as? URLError {
            return BackendError(code: "network", message: networkMessage(for: urlError))
        }
        if let postgrestError = error as? PostgrestError {
            return BackendError(code: postgrestError.code, message: databaseMessage(for: postgrestError) ?? fallback)
        }
        if let body = functionErrorBody(error) {
            if body.status == 401 || body.code == "unauthorized" {
                return BackendError(code: body.code ?? "unauthorized", message: "Your session has expired. Sign in again.")
            }
            if body.status >= 500, body.code == nil {
                return BackendError(code: nil, message: "Haki's server ran into a problem. Try again in a moment.")
            }
            return BackendError(code: body.code, message: body.message ?? fallback)
        }
        if error is FunctionsError {
            return BackendError(code: "network", message: "Couldn't reach Haki's servers. Try again in a moment.")
        }
        if let storageError = error as? StorageError {
            if storageError.statusCode == "413" {
                return BackendError(code: storageError.statusCode, message: "That photo is too large. Try a smaller one.")
            }
            return BackendError(code: storageError.statusCode, message: "Couldn't upload the photo. Try again.")
        }
        if let authError = error as? AuthError {
            if case .sessionMissing = authError {
                return BackendError(code: "signed_out", message: "You're signed out. Sign in again.")
            }
            return BackendError(code: authError.errorCode.rawValue, message: authError.message)
        }
        if error is DecodingError {
            return BackendError(code: "decoding", message: "Haki got an unexpected response from the server. Try again.")
        }
        return BackendError(code: nil, message: fallback)
    }

    /// The status, code and message of an edge function's non-2xx response.
    /// Haki's functions answer `{"error": {"code": String, "message": String}}`;
    /// the gateway in front of them answers `{"code": ..., "message": ...}` or `{"msg": ...}`.
    nonisolated static func functionErrorBody(_ error: any Error) -> (status: Int, code: String?, message: String?)? {
        guard let functionsError = error as? FunctionsError,
              case .httpError(let status, let data) = functionsError
        else { return nil }

        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        var code: String?
        var message: String?
        if let inner = object?["error"] as? [String: Any] {
            code = inner["code"] as? String
            message = inner["message"] as? String
        } else if let text = object?["error"] as? String {
            message = text
        }
        if code == nil {
            code = object?["code"] as? String
        }
        if message == nil {
            message = (object?["message"] as? String) ?? (object?["msg"] as? String)
        }
        if let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty {
            message = nil
        }
        return (status, code, message)
    }

    nonisolated private static func networkMessage(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            "You're offline. Check your connection and try again."
        case .timedOut:
            "The connection timed out. Try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
            "Couldn't reach Haki's servers. Try again in a moment."
        default:
            "A network error occurred. Try again."
        }
    }

    nonisolated private static func databaseMessage(for error: PostgrestError) -> String? {
        switch error.code {
        case "23505": "That already exists."
        case "23514", "22001", "23502": "Some of those details aren't allowed."
        case "23503", "PGRST116": "That's no longer available."
        case "42501": "You don't have permission to do that."
        case "PGRST301", "PGRST302", "PGRST303": "Your session has expired. Sign in again."
        case "57014": "The server took too long. Try again."
        default: nil
        }
    }
}

// MARK: - Timestamp parsing

/// Parses "yyyy-MM-dd", optionally followed by "T" or " " and "HH:mm[:ss[.fraction]]",
/// optionally followed by "Z" or an offset "±HH", "±HHmm" or "±HH:mm". A missing
/// offset means UTC.
nonisolated private func backendParseTimestamp(_ string: String) -> Date? {
    let bytes = Array(string.utf8)
    var index = 0

    func digits(_ count: Int) -> Int? {
        guard index + count <= bytes.count else { return nil }
        var value = 0
        for position in index..<(index + count) {
            let byte = bytes[position]
            guard byte >= 48, byte <= 57 else { return nil }
            value = value * 10 + Int(byte - 48)
        }
        index += count
        return value
    }

    func consume(_ character: Unicode.Scalar) -> Bool {
        guard index < bytes.count, bytes[index] == UInt8(ascii: character) else { return false }
        index += 1
        return true
    }

    guard let year = digits(4), consume("-"),
          let month = digits(2), consume("-"),
          let day = digits(2),
          (1...12).contains(month), (1...31).contains(day)
    else { return nil }

    var hour = 0
    var minute = 0
    var second = 0
    var fraction = 0.0

    if consume("T") || consume("t") || consume(" ") {
        guard let parsedHour = digits(2), consume(":"), let parsedMinute = digits(2) else { return nil }
        hour = parsedHour
        minute = parsedMinute
        if consume(":") {
            guard let parsedSecond = digits(2) else { return nil }
            second = parsedSecond
            if consume(".") || consume(",") {
                var scale = 0.1
                var digitCount = 0
                while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
                    fraction += Double(bytes[index] - 48) * scale
                    scale /= 10
                    index += 1
                    digitCount += 1
                }
                guard digitCount > 0 else { return nil }
            }
        }
        guard (0...24).contains(hour), (0...59).contains(minute), (0...60).contains(second) else { return nil }
    }

    var offsetSeconds = 0
    if consume("Z") || consume("z") {
        offsetSeconds = 0
    } else if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
        let sign = bytes[index] == UInt8(ascii: "-") ? -1 : 1
        index += 1
        guard let offsetHours = digits(2) else { return nil }
        var offsetMinutes = 0
        if consume(":") {
            guard let parsed = digits(2) else { return nil }
            offsetMinutes = parsed
        } else if let parsed = digits(2) {
            offsetMinutes = parsed
        }
        offsetSeconds = sign * (offsetHours * 3600 + offsetMinutes * 60)
    }

    guard index == bytes.count else { return nil }

    let days = backendDaysFromCivil(year: year, month: month, day: day)
    let wholeSeconds = days * 86_400 + hour * 3_600 + minute * 60 + second - offsetSeconds
    return Date(timeIntervalSince1970: Double(wholeSeconds) + fraction)
}

/// Days since 1970-01-01 in the proleptic Gregorian calendar.
nonisolated private func backendDaysFromCivil(year: Int, month: Int, day: Int) -> Int {
    let shiftedYear = month <= 2 ? year - 1 : year
    let era = (shiftedYear >= 0 ? shiftedYear : shiftedYear - 399) / 400
    let yearOfEra = shiftedYear - era * 400
    let shiftedMonth = (month + 9) % 12
    let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return era * 146_097 + dayOfEra - 719_468
}
