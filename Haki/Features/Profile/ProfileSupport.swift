//
//  ProfileSupport.swift
//  Haki
//
//  Small helpers shared by the profile screens: error handling, text limits
//  that mirror the database checks, and inline error / failure views.
//

import Foundation
import SwiftUI

// MARK: - Errors

/// How the profile screens read errors thrown by the services.
enum ProfileErrorInfo {
    /// Cancelled work (a view went away mid-request) is never shown to the user.
    static func isCancellation(_ error: any Error) -> Bool {
        Backend.isCancellation(error)
    }

    /// `AuthService` reports a username clash as `AuthServiceError.usernameTaken`
    /// ("That username is taken.").
    static func isUsernameTaken(_ error: any Error) -> Bool {
        if let authError = error as? AuthServiceError, authError == .usernameTaken {
            return true
        }
        return message(for: error).localizedCaseInsensitiveContains("username is taken")
    }

    /// The service errors' descriptions are already written for people.
    static func message(for error: any Error) -> String {
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "Something went wrong. Try again." : text
    }
}

// MARK: - Text limits

/// Limits from the `profiles` table checks. Postgres counts characters as
/// code points, so lengths are counted in Unicode scalars.
enum ProfileTextRules {
    static let displayNameLimit = 50
    static let bioLimit = 160

    static func length(_ text: String) -> Int {
        text.unicodeScalars.count
    }

    /// `text` cut to at most `limit` code points, never splitting a character.
    static func limited(_ text: String, to limit: Int) -> String {
        guard length(text) > limit else { return text }
        var result = ""
        var count = 0
        for character in text {
            let size = character.unicodeScalars.count
            if count + size > limit { break }
            result.append(character)
            count += size
        }
        return result
    }

    /// The first non-empty line of a caption, for grid tiles.
    static func firstLine(of text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(whereSeparator: { $0.isNewline }).first.map { String($0) }
        return firstLine ?? trimmed
    }
}

// MARK: - Views

/// A compact warning card with a retry button, for failures that leave the
/// rest of the screen usable.
struct ProfileInlineError: View {
    let message: String
    let retry: () -> Void

    init(message: String, retry: @escaping () -> Void) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.hakiWarning)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry", action: retry)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderless)
        }
        .hakiCard()
        .accessibilityElement(children: .contain)
    }
}

/// A full-screen failure with a "Try again" button, for when there's nothing to show.
struct ProfileLoadFailedView: View {
    let title: String
    let message: String
    let retry: () -> Void

    init(title: String, message: String, retry: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.retry = retry
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }
}

extension View {
    /// The standard "Something went wrong" alert, shown while `message` is non-nil.
    func profileErrorAlert(_ message: Binding<String?>) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { isPresented in
                    if !isPresented { message.wrappedValue = nil }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

#Preview("Inline error") {
    ScrollView {
        VStack(spacing: 16) {
            ProfileInlineError(message: "You're offline. Check your connection and try again.") {}
            ProfileLoadFailedView(title: "Couldn't load this profile", message: "The connection timed out. Try again.") {}
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
