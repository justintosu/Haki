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

@Observable
final class AppRouter {
    enum Tab: Hashable {
        case overview
        case transactions
        case budgets
        case recurring
        case accounts
    }

    var selectedTab: Tab = .overview

    /// Set by `showTransactions(_:)`. `TransactionsView` applies it and sets
    /// it back to `nil`.
    var pendingTransactionFilter: TransactionFilter?

    /// Switches to the Transactions tab with a filter applied.
    func showTransactions(_ filter: TransactionFilter) {
        pendingTransactionFilter = filter
        selectedTab = .transactions
    }
}
