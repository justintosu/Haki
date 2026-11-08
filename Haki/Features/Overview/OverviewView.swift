//
//  OverviewView.swift
//  Haki
//
//  The home dashboard for the current month: spending against last month,
//  the review queue, budgets, upcoming bills, net worth and cash flow. A
//  brand-new user gets a welcome card with three ways to start instead.
//

import Foundation
import SwiftData
import SwiftUI

struct OverviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppRouter.self) private var router

    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)])
    private var accounts: [Account]

    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var transactions: [TransactionRecord]

    @Query(filter: #Predicate<TransactionRecord> { !$0.isReviewed }, sort: \TransactionRecord.date, order: .reverse)
    private var unreviewed: [TransactionRecord]

    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.name)])
    private var categories: [TransactionCategory]

    @Query(sort: \RecurringItem.anchorDate)
    private var recurringItems: [RecurringItem]

    @State private var activeSheet: OverviewSheet?
    /// "Today" for every card. Refreshed when the app comes back to the foreground.
    @State private var now = Date.now
    @State private var sampleDataLoads = 0

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Overview")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            activeSheet = .settings
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
        }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .sensoryFeedback(.success, trigger: sampleDataLoads)
        .onAppear {
            now = .now
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now }
        }
        .onChange(of: router.selectedTab) { _, _ in
            // Another screen (e.g. "Review them" after a CSV import) switched
            // tabs: don't leave a sheet covering the new tab.
            activeSheet = nil
        }
    }

    // MARK: Content

    private var isBrandNew: Bool {
        accounts.isEmpty && transactions.isEmpty
    }

    @ViewBuilder
    private var content: some View {
        if isBrandNew {
            OverviewWelcomeView(
                onExploreSample: { loadSampleData() },
                onImportCSV: { activeSheet = .csvImport },
                onAddAccount: { activeSheet = .addAccount }
            )
        } else {
            dashboard(snapshot: makeSnapshot())
        }
    }

    private func makeSnapshot() -> OverviewSnapshot {
        OverviewSnapshot(
            accounts: accounts,
            transactions: transactions,
            categories: categories,
            recurringItems: recurringItems,
            now: now
        )
    }

    private func dashboard(snapshot: OverviewSnapshot) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                if transactions.isEmpty {
                    noTransactionsCard
                } else {
                    OverviewSpendingCard(snapshot: snapshot)
                    OverviewReviewCard(transactions: unreviewed)
                    OverviewBudgetsCard(snapshot: snapshot)
                }
                if snapshot.hasRecurringItems {
                    OverviewUpcomingBillsCard(bills: snapshot.upcomingBills)
                }
                OverviewNetWorthCard(snapshot: snapshot, onAddAccount: { activeSheet = .addAccount })
                if !transactions.isEmpty {
                    OverviewCashFlowCard(incomeCents: snapshot.incomeCents, spendingCents: snapshot.spentCents)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
            .animation(.snappy, value: unreviewed.count)
        }
        .background(Color.hakiBackground)
    }

    /// Accounts but no transactions yet.
    private var noTransactionsCard: some View {
        ContentUnavailableView {
            Label("No transactions yet", systemImage: "list.bullet.rectangle.portrait")
        } description: {
            Text("Import a CSV from your bank or add a transaction yourself to see your spending here.")
        } actions: {
            Button("Import from CSV") {
                activeSheet = .csvImport
            }
            .buttonStyle(.borderedProminent)
            Button("Add a transaction") {
                activeSheet = .addTransaction
            }
        }
        .hakiCard()
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(for sheet: OverviewSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsView()
        case .csvImport:
            NavigationStack {
                CSVImportView()
            }
        case .addAccount:
            AccountEditorView(account: nil)
        case .addTransaction:
            TransactionEditorView()
        }
    }

    // MARK: Actions

    private func loadSampleData() {
        withAnimation(.snappy) {
            LedgerStore.loadSampleData(into: modelContext)
        }
        now = .now
        sampleDataLoads += 1
    }
}

private enum OverviewSheet: String, Identifiable {
    case settings
    case csvImport
    case addAccount
    case addTransaction

    var id: String { rawValue }
}

#Preview("Dashboard") {
    OverviewView()
        .previewEnvironment()
}

#Preview("Welcome") {
    OverviewView()
        .previewEnvironment(empty: true)
}
