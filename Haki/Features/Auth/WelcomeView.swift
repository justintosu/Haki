//
//  WelcomeView.swift
//  Haki
//
//  Shown when signed out: what Haki is, and the ways to sign in or sign up
//  (Google, Sign in with Apple, email).
//

import AuthenticationServices
import Foundation
import SwiftUI

struct WelcomeView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .largeTitle) private var markSize: CGFloat = 76

    @State private var busyMethod: WelcomeSignInMethod?
    @State private var errorMessage: String?
    @State private var showingEmailSignIn = false
    @State private var appeared = false

    private var isBusy: Bool { busyMethod != nil }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    header
                        .padding(.top, 36)
                    highlights
                        .padding(.top, 36)
                    Spacer(minLength: 36)
                    actions
                    footnote
                        .padding(.top, 18)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared || reduceMotion ? 0 : 16)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background { AuthBrandBackground() }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
        .sheet(isPresented: $showingEmailSignIn) {
            SignInEmailView()
        }
        .authErrorAlert(alertMessage)
    }

    /// Errors thrown by the sign-in buttons, or left by the service after a
    /// failed confirmation link. Hidden while the email sheet (which shows
    /// them itself) is up.
    private var alertMessage: Binding<String?> {
        Binding(
            get: { showingEmailSignIn ? nil : (errorMessage ?? auth.errorMessage) },
            set: { newValue in
                if newValue == nil {
                    errorMessage = nil
                    auth.errorMessage = nil
                }
            }
        )
    }

    // MARK: Sections

    private var header: some View {
        VStack(spacing: 14) {
            AuthBrandMark(size: markSize)
            Text("Haki")
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                .accessibilityAddTraits(.isHeader)
            Text("Your money, your investments, your people.")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var highlights: some View {
        VStack(alignment: .leading, spacing: 18) {
            WelcomeHighlightRow(
                systemImage: "chart.bar.xaxis",
                title: "Spending & budgets",
                detail: "See where every dollar goes and stay on pace with simple monthly budgets."
            )
            WelcomeHighlightRow(
                systemImage: "person.2.fill",
                title: "Investing with friends",
                detail: "Connect a brokerage, follow friends and talk about the stocks you actually own."
            )
            WelcomeHighlightRow(
                systemImage: "lock.shield.fill",
                title: "Private by default",
                detail: "Friends see percentages, never dollar amounts. Your budgets stay on this iPhone."
            )
        }
        .hakiCard(padding: 20)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            googleButton
            appleButton
            emailButton

            if isBusy {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Signing you in…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 4)
                .accessibilityElement(children: .combine)
                .transition(.opacity)
            }
        }
        .disabled(isBusy)
        .animation(.easeInOut(duration: 0.2), value: isBusy)
    }

    private var googleButton: some View {
        Button {
            Task { await continueWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                if busyMethod == .google {
                    ProgressView()
                } else {
                    AuthGoogleGlyph()
                }
                Text("Continue with Google")
            }
        }
        .buttonStyle(AuthButtonStyle(kind: .outlined))
        .accessibilityLabel("Continue with Google")
    }

    private var appleButton: some View {
        SignInWithAppleButton(.continue) { request in
            request.requestedScopes = [.fullName, .email]
            request.nonce = auth.prepareAppleSignIn()
        } onCompletion: { result in
            handleAppleCompletion(result)
        }
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 50)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(isBusy ? 0.5 : 1)
        // Re-create the button when the appearance changes so its style follows.
        .id(colorScheme)
    }

    private var emailButton: some View {
        Button {
            auth.errorMessage = nil
            showingEmailSignIn = true
        } label: {
            Label("Continue with email", systemImage: "envelope.fill")
        }
        .buttonStyle(AuthButtonStyle(kind: .tinted))
    }

    private var footnote: some View {
        VStack(spacing: 6) {
            Label("Your budgets and transactions stay on this iPhone.", systemImage: "lock.fill")
            Text("Friends only see what you choose to share — never your balances.")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func continueWithGoogle() async {
        guard !isBusy else { return }
        busyMethod = .google
        defer { busyMethod = nil }
        errorMessage = nil
        auth.errorMessage = nil
        do {
            try await auth.signInWithGoogle()
        } catch {
            errorMessage = AuthErrorFormatter.message(for: error)
        }
    }

    private func handleAppleCompletion(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = credential.identityToken
            else {
                errorMessage = "Sign in with Apple didn't return your account details. Try again."
                return
            }
            let fullName = credential.fullName
            Task { await completeAppleSignIn(identityToken: identityToken, fullName: fullName) }
        case .failure(let error):
            errorMessage = AuthErrorFormatter.message(for: error)
        }
    }

    private func completeAppleSignIn(identityToken: Data, fullName: PersonNameComponents?) async {
        guard !isBusy else { return }
        busyMethod = .apple
        defer { busyMethod = nil }
        errorMessage = nil
        auth.errorMessage = nil
        do {
            try await auth.completeAppleSignIn(identityToken: identityToken, fullName: fullName)
        } catch {
            errorMessage = AuthErrorFormatter.message(for: error)
        }
    }
}

private enum WelcomeSignInMethod: Hashable {
    case google
    case apple
}

private struct WelcomeHighlightRow: View {
    let systemImage: String
    let title: String
    let detail: String

    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: iconSize, height: iconSize)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WelcomeView()
        .previewEnvironment()
}

#Preview("Dark") {
    WelcomeView()
        .previewEnvironment()
        .preferredColorScheme(.dark)
}
