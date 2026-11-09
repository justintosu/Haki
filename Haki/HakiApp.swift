//
//  HakiApp.swift
//  Haki
//
//  Created by Justin To on 7/14/26.
//

import Foundation
import SwiftData
import SwiftUI

@main
struct HakiApp: App {
    /// Opens the on-device store at launch. If it can't be opened the app
    /// shows a recovery screen instead of crashing.
    @State private var database: AppDatabase

    @State private var auth: AuthService
    @State private var social: SocialService
    @State private var portfolio: PortfolioService
    @State private var foodAI: FoodAIService
    @State private var hevy: HevySyncService

    init() {
        // A larger shared cache, so full-size feed photos aren't downloaded
        // again while scrolling back through the feed. Set first: creating the
        // services creates the Supabase client, which uses `URLSession.shared`.
        URLCache.shared = URLCache(memoryCapacity: 50 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024, directory: nil)
        if HakiLaunchOptions.isUITesting {
            // UI tests: signed in as a sample user, sample data in memory, no network.
            _database = State(initialValue: AppDatabase(uiTestingSampleData: ()))
            _auth = State(initialValue: AuthService.preview)
            _social = State(initialValue: SocialService.preview)
            _portfolio = State(initialValue: PortfolioService.preview)
            _foodAI = State(initialValue: FoodAIService.preview)
            _hevy = State(initialValue: HevySyncService.preview)
        } else {
            _database = State(initialValue: AppDatabase())
            _auth = State(initialValue: AuthService.live)
            _social = State(initialValue: SocialService.live)
            _portfolio = State(initialValue: PortfolioService.live)
            _foodAI = State(initialValue: FoodAIService.live)
            _hevy = State(initialValue: HevySyncService.live)
        }
    }

    var body: some Scene {
        WindowGroup {
            HakiAppRoot(database: database)
                .environment(auth)
                .environment(social)
                .environment(portfolio)
                .environment(foodAI)
                .environment(hevy)
                .onChange(of: auth.state) { _, state in
                    // Brokerage data belongs to the account, so drop it on sign-out.
                    if state == .signedOut {
                        portfolio.reset()
                        foodAI.reset()
                    }
                }
        }
    }
}

/// The sign-in gate (welcome → onboarding → the tab bar) once the database is
/// open; the recovery screen while it can't be opened.
private struct HakiAppRoot: View {
    let database: AppDatabase

    var body: some View {
        if let container = database.container {
            AuthGateView()
                .modelContainer(container)
        } else {
            AppDatabaseRecoveryView(database: database)
        }
    }
}
