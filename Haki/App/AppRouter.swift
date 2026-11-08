//
//  AppRouter.swift
//  Haki
//
//  Cross-tab navigation. Injected at the root with `.environment(router)` and
//  read with `@Environment(AppRouter.self) private var router`.
//

import Foundation
import Observation

/// Filters for the Transactions tab.
enum TransactionFilter: Hashable {
    case all
    case needsReview
    case excluded
    case category(UUID)
    case uncategorized
    case account(UUID)
}

/// Money screens that live under the Home tab rather than having tabs of their own.
enum HomeDestination: String, Hashable, Identifiable {
    case budgets
    case recurring
    case accounts

    var id: String { rawValue }
}

@Observable
final class AppRouter {
    enum Tab: Hashable {
        case home
        case transactions
        case feed
        case invest
        case profile
    }

    var selectedTab: Tab = .home

    /// Set by `showTransactions(_:)`. `TransactionsView` applies it and sets
    /// it back to `nil`.
    var pendingTransactionFilter: TransactionFilter?

    /// A money screen to push on the Home tab. `OverviewView` presents it and
    /// clears it when the user navigates back.
    var homeDestination: HomeDestination?

    /// Switches to the Transactions tab with a filter applied.
    func showTransactions(_ filter: TransactionFilter) {
        pendingTransactionFilter = filter
        selectedTab = .transactions
    }

    /// Switches to the Home tab and opens Budgets, Recurring or Accounts.
    func showHome(_ destination: HomeDestination) {
        selectedTab = .home
        homeDestination = destination
    }
}
