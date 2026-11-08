//
//  ContentView.swift
//  Haki
//
//  Created by Justin To on 7/14/26.
//

import Foundation
import SwiftData
import SwiftUI

/// The tab bar. Each tab's root view owns its own `NavigationStack`.
struct RootView: View {
    @State private var router = AppRouter()

    @Query(filter: #Predicate<TransactionRecord> { !$0.isReviewed })
    private var unreviewed: [TransactionRecord]

    var body: some View {
        TabView(selection: $router.selectedTab) {
            Tab("Overview", systemImage: "square.grid.2x2", value: AppRouter.Tab.overview) {
                OverviewView()
            }
            Tab("Transactions", systemImage: "list.bullet.rectangle.portrait", value: AppRouter.Tab.transactions) {
                TransactionsView()
            }
            .badge(unreviewed.count)

            Tab("Budgets", systemImage: "chart.bar.xaxis", value: AppRouter.Tab.budgets) {
                BudgetsView()
            }
            Tab("Recurring", systemImage: "arrow.triangle.2.circlepath", value: AppRouter.Tab.recurring) {
                RecurringView()
            }
            Tab("Accounts", systemImage: "building.columns", value: AppRouter.Tab.accounts) {
                AccountsView()
            }
        }
        .environment(router)
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
