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
    }
}

/// A calm launch screen shown while the saved session is restored.
private struct AuthLaunchView: View {
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var markSize: CGFloat = 84

    var body: some View {
        ZStack {
            Color.accentColor
            LinearGradient(
                colors: [Color.white.opacity(0.22), Color.white.opacity(0), Color.black.opacity(0.18)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(spacing: 18) {
                launchMark
                Text("Haki")
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                ProgressView()
                    .tint(.white)
                    .padding(.top, 8)
            }
            .scaleEffect(appeared || reduceMotion ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Haki")
        .accessibilityValue("Loading")
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
