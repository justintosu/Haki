//
//  OverviewPreviewData.swift
//  Haki
//
//  Snapshots of the preview database for the Overview cards' previews.
//

import Foundation
import SwiftData

enum OverviewPreviewData {
    /// The dashboard snapshot for `PreviewData.container`'s sample data.
    static var snapshot: OverviewSnapshot {
        let context = PreviewData.context
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        let transactions = (try? context.fetch(FetchDescriptor<TransactionRecord>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
        let items = (try? context.fetch(FetchDescriptor<RecurringItem>())) ?? []
        return OverviewSnapshot(
            accounts: accounts,
            transactions: transactions,
            categories: LedgerStore.allCategories(in: context),
            recurringItems: items
        )
    }

    /// Unreviewed sample transactions, newest first.
    static var unreviewed: [TransactionRecord] {
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate<TransactionRecord> { !$0.isReviewed },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return (try? PreviewData.context.fetch(descriptor)) ?? []
    }
}
