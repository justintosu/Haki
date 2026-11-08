//
//  AuthComponents.swift
//  Haki
//
//  Pieces shared by the sign-in, onboarding and account screens: the brand
//  mark and background, the sign-in button style, and error formatting.
//

import AuthenticationServices
import CoreGraphics
import Foundation
import SwiftUI

// MARK: - Brand

/// Haki's mark: a rounded square in the accent gradient with a rising line.
struct AuthBrandMark: View {
    var size: CGFloat = 72

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Color.accentColor.gradient)
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.28), Color.white.opacity(0)],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                )
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: size * 0.44, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.accentColor.opacity(0.35), radius: size * 0.18, y: size * 0.08)
        .accessibilityHidden(true)
    }
}

/// The grouped background with a soft accent glow at the top, for the
/// welcome and onboarding screens.
struct AuthBrandBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Color.hakiBackground
            LinearGradient(
                colors: [Color.accentColor.opacity(0.30), Color.accentColor.opacity(0.08), Color.accentColor.opacity(0)],
                startPoint: .top,
                endPoint: .center
            )
            Circle()
                .fill(Color.accentColor.opacity(0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 90)
                .offset(x: 140, y: -170)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A bold "G" drawn as text for the Google button (no bundled logo).
struct AuthGoogleGlyph: View {
    var body: some View {
        Text("G")
            .font(.system(.title3, design: .rounded).weight(.heavy))
            .accessibilityHidden(true)
    }
}

// MARK: - Buttons

/// Full-width, 50pt-tall buttons that line up with the Sign in with Apple button.
struct AuthButtonStyle: ButtonStyle {
    enum Kind {
        /// White on light, black on dark, with a hairline border (the Google button).
        case outlined
        /// Accent-tinted (secondary actions such as "Continue with email").
        case tinted
        /// Solid accent (the main call to action).
        case prominent
    }

    var kind: Kind

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return configuration.label
            .font(.body.weight(.semibold))
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .foregroundStyle(textColor)
            .background(fillColor, in: shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: kind == .outlined ? 1 : 0)
            }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var textColor: Color {
        switch kind {
        case .outlined: colorScheme == .dark ? Color.white : Color.black
        case .tinted: Color.accentColor
        case .prominent: Color.white
        }
    }

    private var fillColor: Color {
        switch kind {
        case .outlined: colorScheme == .dark ? Color.black : Color.white
        case .tinted: Color.accentColor.opacity(0.14)
        case .prominent: Color.accentColor
        }
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.35) : Color.black.opacity(0.18)
    }
}

// MARK: - Errors

/// Turns errors from sign-in and profile calls into alert text.
enum AuthErrorFormatter {
    static let fallback = "Something went wrong. Try again."

    /// The text to show for `error`, or `nil` when the user simply cancelled
    /// (closed the Google sheet, dismissed Sign in with Apple, left the screen).
    static func message(for error: any Error) -> String? {
        if isCancellation(error) { return nil }
        if error is ASAuthorizationError {
            return "Sign in with Apple didn't finish. Make sure you're signed in with your Apple Account in the Settings app, then try again."
        }
        let text = Backend.userFacingError(error, fallback: fallback)
            .localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? fallback : text
    }

    static func isCancellation(_ error: any Error) -> Bool {
        if Backend.isCancellation(error) { return true }
        if let appleError = error as? ASAuthorizationError, appleError.code == .canceled { return true }
        if let webError = error as? ASWebAuthenticationSessionError, webError.code == .canceledLogin { return true }
        return false
    }

    /// Whether the server rejected the username because someone else has it.
    static func isUsernameTaken(_ error: any Error) -> Bool {
        if let authError = error as? AuthServiceError, authError == .usernameTaken { return true }
        if let backendError = error as? BackendError, backendError.code == "23505" { return true }
        return false
    }

    /// The rule the username broke, when the server (or the service's own
    /// validation) rejected it as invalid.
    static func usernameProblem(_ error: any Error) -> String? {
        if case .invalidUsername(let problem)? = error as? AuthServiceError { return problem }
        return nil
    }

    /// Whether signing in failed because the email address isn't confirmed yet.
    static func isEmailNotConfirmed(_ error: any Error) -> Bool {
        if let authError = error as? AuthServiceError, authError == .emailNotConfirmed { return true }
        return false
    }
}

extension View {
    /// The standard "Something went wrong" alert, shown while `message` is non-nil.
    func authErrorAlert(_ message: Binding<String?>, title: String = "Something went wrong") -> some View {
        alert(
            title,
            isPresented: Binding(
                get: { message.wrappedValue != nil },
                set: { if !$0 { message.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}

// MARK: - Text limits

enum AuthText {
    /// Cuts `text` to at most `limit` Unicode scalars (how Postgres counts characters).
    static func limited(_ text: String, to limit: Int) -> String {
        guard text.unicodeScalars.count > limit else { return text }
        var result = ""
        result.unicodeScalars.append(contentsOf: text.unicodeScalars.prefix(limit))
        return result
    }

    /// Mirrors the service's check: one "@", something before it, a dot after it, no spaces.
    static func looksLikeEmail(_ text: String) -> Bool {
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !address.contains(" ") else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
    }
}

#Preview("Brand") {
    VStack(spacing: 24) {
        AuthBrandMark()
        Button {} label: {
            HStack(spacing: 10) {
                AuthGoogleGlyph()
                Text("Continue with Google")
            }
        }
        .buttonStyle(AuthButtonStyle(kind: .outlined))
        Button {} label: {
            Label("Continue with email", systemImage: "envelope.fill")
        }
        .buttonStyle(AuthButtonStyle(kind: .tinted))
        Button("Continue") {}
            .buttonStyle(AuthButtonStyle(kind: .prominent))
        Button("Disabled") {}
            .buttonStyle(AuthButtonStyle(kind: .prominent))
            .disabled(true)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { AuthBrandBackground() }
    .previewEnvironment()
}
