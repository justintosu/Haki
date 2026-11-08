//
//  AuthGateView.swift
//  Haki
//
//  The app's root: a launch screen while the saved session is restored, then
//  the welcome screen, onboarding, or the tab bar, depending on `AuthService.state`.
//

import CoreGraphics
import Foundation
import Observation
import SwiftUI

struct AuthGateView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PortfolioService.self) private var portfolio
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Follows `asksForNewPassword`, a moment late (see the `.task` below).
    @State private var showingNewPassword = false

    var body: some View {
        ZStack {
            switch auth.state {
            case .loading:
                AuthLaunchView()
                    .transition(.opacity)
            case .signedOut:
                WelcomeView()
                    .transition(.opacity)
            case .needsOnboarding:
                OnboardingView()
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .trailing).combined(with: .opacity))
            case .signedIn:
                RootView()
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? Animation.easeInOut(duration: 0.2) : Animation.smooth(duration: 0.4), value: auth.state)
        .task {
            await auth.start()
        }
        .onOpenURL { url in
            Task {
                await auth.handleOpenURL(url)
            }
        }
        .onChange(of: auth.userID) { oldValue, newValue in
            // Signed out, deleted the account, or switched accounts: drop the
            // previous user's brokerage data so it never shows for someone else.
            if let oldValue, oldValue != newValue {
                portfolio.reset()
            }
        }
        // A password-reset link was opened: ask for a new password, over
        // whichever screen is showing.
        .sheet(isPresented: $showingNewPassword, onDismiss: {
            // Swiped away: keep the current password.
            auth.endPasswordRecovery()
        }) {
            AuthSetNewPasswordView()
        }
        .task(id: asksForNewPassword) {
            guard asksForNewPassword else {
                // Keep an open sheet through state changes; close it once recovery ends.
                if !auth.isRecoveringPassword {
                    showingNewPassword = false
                }
                return
            }
            // Let the welcome screen's sheet (email sign-in) finish closing first.
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, asksForNewPassword else { return }
            showingNewPassword = true
        }
    }

    /// A reset link was opened and the account's screen is up (so the welcome
    /// screen, and any sheet it had open, is gone).
    private var asksForNewPassword: Bool {
        auth.isRecoveringPassword && (auth.state == .signedIn || auth.state == .needsOnboarding)
    }
}

/// A calm launch screen shown while the saved session is restored. When the
/// signed-in user's profile can't be loaded (or takes long), it offers to try
/// again or sign out.
private struct AuthLaunchView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.scenePhase) private var scenePhase
    @State private var appeared = false
    /// Set after a few seconds without a profile.
    @State private var isTakingLong = false
    @State private var isRetrying = false
    @State private var isSigningOut = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var markSize: CGFloat = 84

    /// Only for a signed-in user (not while the saved session is being read).
    private var showsOptions: Bool {
        auth.userID != nil && (auth.errorMessage != nil || isTakingLong)
    }

    /// The profile load gave up; the spinner stops until "Try again".
    private var isSpinning: Bool {
        isRetrying || auth.userID == nil || auth.errorMessage == nil
    }

    var body: some View {
        ZStack {
            Color.accentColor
            LinearGradient(
                colors: [Color.white.opacity(0.22), Color.white.opacity(0), Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 18) {
                VStack(spacing: 18) {
                    launchMark
                    Text("Haki")
                        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                    if isSpinning {
                        ProgressView()
                            .tint(.white)
                            .padding(.top, 8)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Haki")
                .accessibilityValue(isSpinning ? Text("Loading") : Text(verbatim: ""))

                if showsOptions {
                    options
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: 420)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            .animation(.easeInOut(duration: 0.25), value: showsOptions)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
        .task {
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            isTakingLong = true
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Back from Settings (e.g. after turning Wi-Fi on): try again right away.
            if newPhase == .active, auth.userID != nil, auth.errorMessage != nil {
                Task { await retry() }
            }
        }
    }

    private var options: some View {
        VStack(spacing: 14) {
            Text(auth.errorMessage ?? "This is taking longer than usual. Check your connection.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await retry() }
            } label: {
                Text(isRetrying ? "Trying again…" : "Try again")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isRetrying || isSigningOut)

            Button {
                Task { await signOut() }
            } label: {
                Text(isSigningOut ? "Signing out…" : "Sign out")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isRetrying || isSigningOut)
        }
    }

    private func retry() async {
        guard !isRetrying, !isSigningOut else { return }
        isRetrying = true
        defer { isRetrying = false }
        await auth.refreshProfile()
    }

    private func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await auth.signOut()
    }

    private var launchMark: some View {
        ZStack {
            RoundedRectangle(cornerRadius: markSize * 0.28, style: .continuous)
                .fill(Color.white.opacity(0.18))
            RoundedRectangle(cornerRadius: markSize * 0.28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: markSize * 0.44, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: markSize, height: markSize)
    }
}

#Preview("Gate") {
    AuthGateView()
        .previewEnvironment()
}

#Preview("Launch screen") {
    AuthLaunchView()
        .previewEnvironment()
}
