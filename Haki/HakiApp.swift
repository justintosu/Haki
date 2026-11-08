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
    private let container: ModelContainer

    @State private var auth = AuthService.live
    @State private var social = SocialService.live
    @State private var portfolio = PortfolioService.live

    init() {
        do {
            container = try HakiSchema.makeContainer()
        } catch {
            fatalError("Haki couldn't open its database: \(error)")
        }
        LedgerStore.ensureDefaultCategories(in: container.mainContext)
    }

    var body: some Scene {
        WindowGroup {
            // Sign-in gate: welcome → onboarding → the tab bar (RootView).
            AuthGateView()
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
        .modelContainer(container)
    }
}
