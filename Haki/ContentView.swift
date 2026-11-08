//
//  ContentView.swift
//  Haki
//
//  Created by Justin To on 7/14/26.
//

import Foundation
import SwiftData
import SwiftUI

/// The tab bar shown once signed in. Each tab's root view owns its own
/// `NavigationStack`. Transactions, Budgets, Recurring and Accounts open from Home.
struct RootView: View {
    @State private var router = AppRouter()
    @Environment(PortfolioService.self) private var portfolio
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<TransactionRecord> { !$0.isReviewed })
    private var unreviewed: [TransactionRecord]

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: AppRouter.Tab.home) {
                OverviewView()
            }
            .badge(unreviewed.count)

            Tab("Feed", systemImage: "rectangle.stack", value: AppRouter.Tab.feed) {
                FeedView()
            }
            Tab("Invest", systemImage: "chart.line.uptrend.xyaxis", value: AppRouter.Tab.invest) {
                InvestView()
            }
            Tab("Health", systemImage: "heart.text.square", value: AppRouter.Tab.health) {
                HealthView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppRouter.Tab.profile) {
                MyProfileView()
            }
        }
        .environment(router)
        .onChange(of: scenePhase) { _, phase in
            // Back in the foreground (maybe the next day): pull fresh brokerage
            // data if it's due, whichever tab is showing. Throttled by the service.
            guard phase == .active else { return }
            portfolio.syncIfDue()
        }
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
