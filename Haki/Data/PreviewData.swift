//
//  PreviewData.swift
//  Haki
//
//  An in-memory database filled with sample data, for SwiftUI previews:
//
//      #Preview {
//          OverviewView()
//              .previewEnvironment()
//      }
//

import Foundation
import SwiftData
import SwiftUI

enum PreviewData {
    static let container: ModelContainer = {
        do {
            let container = try HakiSchema.makeContainer(inMemory: true)
            LedgerStore.loadSampleData(into: container.mainContext)
            return container
        } catch {
            fatalError("Couldn't create the preview database: \(error)")
        }
    }()

    /// An empty database with only the built-in categories, for empty-state previews.
    static let emptyContainer: ModelContainer = {
        do {
            let container = try HakiSchema.makeContainer(inMemory: true)
            LedgerStore.ensureDefaultCategories(in: container.mainContext)
            return container
        } catch {
            fatalError("Couldn't create the preview database: \(error)")
        }
    }()

    static var context: ModelContext { container.mainContext }

    static var sampleTransaction: TransactionRecord {
        let descriptor = FetchDescriptor<TransactionRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        guard let transaction = try? context.fetch(descriptor).first(where: { $0.category != nil }) else {
            fatalError("Preview data has no transactions")
        }
        return transaction
    }

    static var sampleAccount: Account {
        guard let account = try? context.fetch(FetchDescriptor<Account>(sortBy: [SortDescriptor(\.sortOrder)])).first else {
            fatalError("Preview data has no accounts")
        }
        return account
    }

    static var sampleCategory: TransactionCategory {
        guard let category = LedgerStore.allCategories(in: context).first(where: { $0.seedKey == "groceries" }) else {
            fatalError("Preview data has no categories")
        }
        return category
    }

    static var sampleRecurringItem: RecurringItem {
        guard let item = try? context.fetch(FetchDescriptor<RecurringItem>()).first else {
            fatalError("Preview data has no recurring items")
        }
        return item
    }
}

extension View {
    /// Sample database plus the environment objects the app provides. The
    /// services run in preview mode: sample data, no network.
    func previewEnvironment(empty: Bool = false) -> some View {
        modelContainer(empty ? PreviewData.emptyContainer : PreviewData.container)
            .environment(AppRouter())
            .environment(AuthService.preview)
            .environment(SocialService.preview)
            .environment(PortfolioService.preview)
    }
}
