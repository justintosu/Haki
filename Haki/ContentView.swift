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
/// `NavigationStack`. Budgets, Recurring and Accounts open from Home.
struct RootView: View {
    @State private var router = AppRouter()

    @Query(filter: #Predicate<TransactionRecord> { !$0.isReviewed })
    private var unreviewed: [TransactionRecord]

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Home", systemImage: "house", value: AppRouter.Tab.home) {
                OverviewView()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle.portrait", value: AppRouter.Tab.transactions) {
                TransactionsView()
            }
            .badge(unreviewed.count)

            Tab("Feed", systemImage: "rectangle.stack", value: AppRouter.Tab.feed) {
                FeedView()
            }
            Tab("Invest", systemImage: "chart.line.uptrend.xyaxis", value: AppRouter.Tab.invest) {
                InvestView()
            }
            Tab("Profile", systemImage: "person.crop.circle", value: AppRouter.Tab.profile) {
                MyProfileView()
            }
        }
        .environment(router)
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
