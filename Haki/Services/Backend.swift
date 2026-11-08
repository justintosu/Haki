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
