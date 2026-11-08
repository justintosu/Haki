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
    @State private var database = AppDatabase()

    @State private var auth = AuthService.live
    @State private var social = SocialService.live
    @State private var portfolio = PortfolioService.live

    var body: some Scene {
        WindowGroup {
            HakiAppRoot(database: database)
                .environment(auth)
                .environment(social)
                .environment(portfolio)
                .onChange(of: auth.state) { _, state in
                    // Brokerage data belongs to the account, so drop it on sign-out.
                    if state == .signedOut {
                        portfolio.reset()
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
