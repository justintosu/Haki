//
//  TransactionsView.swift
//  Haki
//
//  Every transaction, newest first, grouped by day: search, filters, the
//  review queue and swipe actions.
//

import Foundation
import SwiftData
import SwiftUI

struct TransactionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router

    @Query(sort: [
        SortDescriptor(\TransactionRecord.date, order: .reverse),
        SortDescriptor(\TransactionRecord.createdAt, order: .reverse),
    ])
    private var transactions: [TransactionRecord]

    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.name)])
    private var categories: [TransactionCategory]

    @Query(sort: [SortDescriptor(\Account.sortOrder), SortDescriptor(\Account.name)])
    private var accounts: [Account]

    @State private var filter: TransactionFilter
    /// Whether this list applies filters sent through `AppRouter.showTransactions`.
    /// Only the list Home presents does; one pushed from another screen with
    /// its own filter (Budgets' "Uncategorized", an account's "See all")
    /// leaves them to that list.
    private let appliesRouterFilters: Bool
    @State private var searchText = ""
    /// `searchText` once typing pauses: what the list is filtered by, so
    /// each keystroke doesn't refilter and regroup every transaction.
    @State private var appliedSearch = ""
    @State private var activeSheet: Sheet? = nil
    @State private var pendingDeletion: TransactionRecord? = nil
    @State private var reviewFeedback = 0
    /// Transactions whose detail screen was opened from the list. They stay
    /// listed even if an edit makes them stop matching the filter or search
    /// (say, marking one reviewed in "Needs review"), so the list doesn't
    /// change under the open screen. Cleared when the list shows again.
    @State private var pinnedIDs: Set<UUID> = []
    /// The transaction opened from the list. Pushed from here, not from its
    /// row, so an edit that moves it to another day (and so another section)
    /// doesn't pop the detail screen.
    @State private var openedTransaction: TransactionRecord?

    /// - Parameter initialFilter: The filter to start with, for a list pushed
    ///   from another screen. `nil` (Home's list) starts with every transaction
    ///   and applies filters sent through `AppRouter.showTransactions`.
    init(initialFilter: TransactionFilter? = nil) {
        _filter = State(initialValue: initialFilter ?? .all)
        appliesRouterFilters = initialFilter == nil
    }

    private enum Sheet: String, Identifiable {
        case newTransaction
        case importCSV

        var id: String { rawValue }
    }

    var body: some View {
        let visible = visibleTransactions
        // Pushed from Home (AppRouter.showTransactions / HomeDestination.transactions),
        // or with a filter from Budgets and an account's page.
        content(visible: visible)
            .navigationTitle("Transactions")
            .toolbar { toolbarContent }
            // Outside the list and the empty state, so a row going away (or
            // the last transaction being deleted) doesn't remove it.
            .navigationDestination(item: $openedTransaction) { transaction in
                TransactionDetailView(transaction: transaction)
            }
        .sheet(item: $activeSheet) { sheet in
            sheetContent(sheet)
        }
        .confirmationDialog(
            "Delete this transaction?",
            isPresented: deletionDialogBinding,
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { transaction in
            Button("Delete", role: .destructive) {
                delete(transaction)
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: { transaction in
            Text(deletionMessage(for: transaction))
        }
        .sensoryFeedback(.success, trigger: reviewFeedback)
        .onAppear {
            applyPendingFilter()
        }
        .onChange(of: router.pendingTransactionFilter) { _, _ in
            applyPendingFilter()
        }
        .onChange(of: searchText) { _, _ in
            pinnedIDs.removeAll()
        }
        .task(id: searchText) {
            await applySearchWhenTypingPauses()
        }
    }

    // MARK: Content

    @ViewBuilder
    private func content(visible: [TransactionRecord]) -> some View {
        if transactions.isEmpty {
            emptyLedger
        } else {
            transactionList(visible: visible)
                .searchable(text: $searchText, prompt: "Merchant, category, account or amount")
        }
    }

    private func transactionList(visible: [TransactionRecord]) -> some View {
        let sections = TransactionsListLogic.daySections(visible)
        let unreviewedCount: Int = transactions.reduce(0) { count, transaction in
            transaction.isReviewed ? count : count + 1
        }
        let showsReviewPrompt: Bool = filter == .all && unreviewedCount > 0 && appliedSearch.isEmpty
        return List {
            if filter != .all {
                Section {
                    filterBar(visible: visible)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } else if showsReviewPrompt {
                Section {
                    reviewPrompt(count: unreviewedCount)
                }
            }

            ForEach(sections) { section in
                Section {
                    ForEach(section.transactions) { transaction in
                        row(for: transaction)
                    }
                } header: {
                    TransactionsDayHeader(section: section)
                }
            }
        }
        .listSectionSpacing(.compact)
        .overlay {
            if visible.isEmpty {
                emptyResults
            }
        }
        .onAppear {
            // Back from a detail screen: let rows that no longer match go.
            if !pinnedIDs.isEmpty {
                withAnimation { pinnedIDs.removeAll() }
            }
        }
    }

    private func row(for transaction: TransactionRecord) -> some View {
        Button {
            pin(transaction.id)
            openedTransaction = transaction
        } label: {
            HStack(spacing: 8) {
                TransactionRow(transaction: transaction)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            // List buttons tint unstyled label text with the accent color. A
            // concrete color (not the hierarchical `.primary`, which resolves
            // to that tint) undoes it, so `.secondary` text inside is gray.
            .foregroundStyle(Color.primary)
            .contentShape(Rectangle())
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                toggleReviewed(transaction)
            } label: {
                if transaction.isReviewed {
                    Label("Unreview", systemImage: "arrow.uturn.backward")
                } else {
                    Label("Reviewed", systemImage: "checkmark")
                }
            }
            .tint(transaction.isReviewed ? Color.gray : Color.accentColor)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Not `role: .destructive`: that removes the row before the
            // confirmation is answered.
            Button {
                pendingDeletion = transaction
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color.red)

            Button {
                toggleExcluded(transaction)
            } label: {
                if transaction.isExcluded {
                    Label("Include", systemImage: "eye")
                } else {
                    Label("Exclude", systemImage: "eye.slash")
                }
            }
            .tint(Color.indigo)
        }
        .contextMenu {
            Button {
                toggleReviewed(transaction)
            } label: {
                if transaction.isReviewed {
                    Label("Mark as unreviewed", systemImage: "arrow.uturn.backward.circle")
                } else {
                    Label("Mark as reviewed", systemImage: "checkmark.circle")
                }
            }
            Button {
                toggleExcluded(transaction)
            } label: {
                if transaction.isExcluded {
                    Label("Include in totals", systemImage: "eye")
                } else {
                    Label("Exclude from totals", systemImage: "eye.slash")
                }
            }
            Divider()
            Button(role: .destructive) {
                pendingDeletion = transaction
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: Review prompt and filter bar

    private func reviewPrompt(count: Int) -> some View {
        Button {
            setFilter(.needsReview)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tray.full.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reviewPromptTitle(count))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Check categories and amounts, then mark them reviewed.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            // Undo the list-button tint (see row(for:)); the icon keeps its explicit accent color.
            .foregroundStyle(Color.primary)
        }
        .accessibilityHint("Shows only transactions that need review")
    }

    private func reviewPromptTitle(_ count: Int) -> String {
        count == 1 ? "1 transaction to review" : "\(count.formatted()) transactions to review"
    }

    private func filterBar(visible: [TransactionRecord]) -> some View {
        let unreviewed = visible.filter { !$0.isReviewed }
        let showsMarkAll: Bool = filter == .needsReview && !unreviewed.isEmpty
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filterChip(count: visible.count)
                Spacer(minLength: 0)
                if showsMarkAll {
                    markAllButton(unreviewed)
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                filterChip(count: visible.count)
                if showsMarkAll {
                    markAllButton(unreviewed)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func filterChip(count: Int) -> some View {
        let title = filterTitle
        let countText = count.formatted()
        return Button {
            setFilter(.all)
        } label: {
            HStack(spacing: 6) {
                Text("\(title) · \(countText)")
                    .lineLimit(1)
                Image(systemName: "xmark.circle.fill")
                    .accessibilityHidden(true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.accentColor.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter: \(title), \(countText) transactions")
        .accessibilityHint("Removes the filter")
    }

    private func markAllButton(_ unreviewed: [TransactionRecord]) -> some View {
        Button {
            markAllReviewed(unreviewed)
        } label: {
            Label("Mark all as reviewed", systemImage: "checkmark.circle")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    // MARK: Toolbar and filter menu

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if !transactions.isEmpty {
                filterMenu
            }
            Button {
                activeSheet = .newTransaction
            } label: {
                Label("Add transaction", systemImage: "plus")
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Section {
                filterOption("All transactions", systemImage: "tray.full", value: .all)
                filterOption("Needs review", systemImage: "exclamationmark.circle", value: .needsReview)
                filterOption("Excluded", systemImage: "eye.slash", value: .excluded)
                filterOption("Uncategorized", systemImage: "questionmark.circle", value: .uncategorized)
            }
            Section {
                Menu {
                    ForEach(CategoryKind.allCases) { kind in
                        let items = categories.filter { $0.kind == kind }
                        if !items.isEmpty {
                            Section(kind.displayName) {
                                ForEach(items) { category in
                                    filterOption("\(category.emoji)  \(category.name)", value: .category(category.id))
                                }
                            }
                        }
                    }
                } label: {
                    Label("Category", systemImage: "tag")
                }
                if !accounts.isEmpty {
                    Menu {
                        ForEach(accounts) { account in
                            filterOption(account.name, systemImage: account.kind.systemImage, value: .account(account.id))
                        }
                    } label: {
                        Label("Account", systemImage: "building.columns")
                    }
                }
            }
        } label: {
            Label("Filter", systemImage: filterSymbol)
        }
        .accessibilityLabel("Filter")
        .accessibilityValue(filterAccessibilityValue)
    }

    /// A menu item with a checkmark when its filter is active. Choosing the
    /// active one again goes back to all transactions.
    private func filterOption(_ title: String, systemImage: String? = nil, value: TransactionFilter) -> some View {
        Toggle(isOn: Binding(
            get: { filter == value },
            set: { isOn in setFilter(isOn ? value : .all) }
        )) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
    }

    private var filterSymbol: String {
        filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
    }

    private var filterAccessibilityValue: String {
        filter == .all ? "All transactions" : filterTitle
    }

    private var filterTitle: String {
        switch filter {
        case .all:
            return "All transactions"
        case .needsReview:
            return "Needs review"
        case .excluded:
            return "Excluded"
        case .uncategorized:
            return "Uncategorized"
        case .category(let id):
            if let category = categories.first(where: { $0.id == id }) {
                return "\(category.emoji) \(category.name)"
            }
            return "Category"
        case .account(let id):
            return accounts.first(where: { $0.id == id })?.name ?? "Account"
        }
    }

    // MARK: Empty states

    private var emptyLedger: some View {
        ContentUnavailableView {
            Label("No transactions yet", systemImage: "list.bullet.rectangle.portrait")
        } description: {
            Text("Add a purchase or paycheck by hand, or import a CSV export from your bank. Everything you add shows up here, newest first.")
        } actions: {
            Button {
                activeSheet = .newTransaction
            } label: {
                Label("Add transaction", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)

            Button {
                activeSheet = .importCSV
            } label: {
                Label("Import from CSV", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hakiBackground)
    }

    @ViewBuilder
    private var emptyResults: some View {
        if !TransactionsSearchQuery(appliedSearch).isEmpty {
            ContentUnavailableView.search(text: appliedSearch)
        } else {
            switch filter {
            case .needsReview:
                ContentUnavailableView {
                    Label("All caught up", systemImage: "checkmark.seal")
                } description: {
                    Text("You've reviewed every transaction. New imports wait here until you've checked them.")
                } actions: {
                    Button("Show all transactions") { setFilter(.all) }
                }
            case .excluded:
                ContentUnavailableView {
                    Label("Nothing excluded", systemImage: "eye.slash")
                } description: {
                    Text("Swipe left on a transaction and tap Exclude to leave it out of your totals, like a reimbursed expense.")
                } actions: {
                    Button("Show all transactions") { setFilter(.all) }
                }
            case .uncategorized:
                ContentUnavailableView {
                    Label("Everything is categorized", systemImage: "tag")
                } description: {
                    Text("Every transaction has a category, so your budgets are complete.")
                } actions: {
                    Button("Show all transactions") { setFilter(.all) }
                }
            default:
                ContentUnavailableView {
                    Label("No transactions", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Nothing matches this filter yet.")
                } actions: {
                    Button("Show all transactions") { setFilter(.all) }
                }
            }
        }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: Sheet) -> some View {
        switch sheet {
        case .newTransaction:
            TransactionEditorView()
        case .importCSV:
            NavigationStack {
                CSVImportView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { activeSheet = nil }
                        }
                    }
            }
        }
    }

    private var deletionDialogBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { isPresented in
                if !isPresented { pendingDeletion = nil }
            }
        )
    }

    private func deletionMessage(for transaction: TransactionRecord) -> String {
        let cents = transaction.amountCents
        let amount = cents < 0 ? Money.format(-cents, alwaysShowsSign: true) : Money.format(cents)
        let date = transaction.date.formatted(.dateTime.month(.abbreviated).day().year())
        return "\(transaction.merchant), \(amount) on \(date). This can't be undone."
    }

    // MARK: Data

    private var visibleTransactions: [TransactionRecord] {
        let activeFilter = filter
        let query = TransactionsSearchQuery(appliedSearch)
        let pinned = pinnedIDs
        guard activeFilter != .all || !query.isEmpty else { return transactions }
        return transactions.filter { transaction in
            if !pinned.isEmpty, pinned.contains(transaction.id) { return true }
            return TransactionsListLogic.matches(transaction, filter: activeFilter) && query.matches(transaction)
        }
    }

    // MARK: Actions

    /// Keeps a row listed while its detail screen is open (see `pinnedIDs`).
    /// Only needed while a filter or search hides some transactions.
    private func pin(_ id: UUID) {
        guard filter != .all || !appliedSearch.isEmpty, !pinnedIDs.contains(id) else { return }
        pinnedIDs.insert(id)
    }

    /// Filters by the search text after a short pause in typing. Clearing
    /// the search applies at once.
    private func applySearchWhenTypingPauses() async {
        let text = searchText
        if !text.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
        }
        if appliedSearch != text {
            appliedSearch = text
        }
    }

    private func setFilter(_ newValue: TransactionFilter) {
        withAnimation(.snappy) {
            pinnedIDs.removeAll()
            filter = newValue
        }
    }

    private func toggleReviewed(_ transaction: TransactionRecord) {
        let reviewed = !transaction.isReviewed
        withAnimation {
            LedgerStore.setReviewed([transaction], reviewed, in: modelContext)
        }
        if reviewed {
            reviewFeedback += 1
        }
    }

    private func toggleExcluded(_ transaction: TransactionRecord) {
        withAnimation {
            transaction.isExcluded.toggle()
        }
        LedgerStore.save(modelContext)
    }

    private func markAllReviewed(_ items: [TransactionRecord]) {
        guard !items.isEmpty else { return }
        withAnimation {
            LedgerStore.setReviewed(items, true, in: modelContext)
        }
        reviewFeedback += 1
    }

    private func delete(_ transaction: TransactionRecord) {
        pendingDeletion = nil
        withAnimation {
            LedgerStore.delete(transaction, in: modelContext)
        }
    }

    /// Applies a filter sent from another screen or tab (`AppRouter.showTransactions`),
    /// then clears it so it's applied only once. A list pushed with its own
    /// filter leaves it to Home's list (see `appliesRouterFilters`).
    private func applyPendingFilter() {
        guard appliesRouterFilters, let pending = router.pendingTransactionFilter else { return }
        router.pendingTransactionFilter = nil
        // Back to the list, so the filtered transactions are what shows.
        openedTransaction = nil
        pinnedIDs.removeAll()
        filter = pending
        searchText = ""
        appliedSearch = ""
        activeSheet = nil
        pendingDeletion = nil
    }
}

// MARK: - Day header

/// "Today ............ $45.20" — the day and its net spending.
private struct TransactionsDayHeader: View {
    let section: TransactionsDaySection

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(section.title)
            Spacer(minLength: 8)
            if section.netSpendingCents != 0 {
                Text(amountText)
                    .monospacedDigit()
                    .foregroundStyle(section.netSpendingCents < 0 ? Color.hakiPositive : Color.secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
        .textCase(nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isHeader)
    }

    private var amountText: String {
        let cents = section.netSpendingCents
        return cents < 0 ? Money.format(-cents, alwaysShowsSign: true) : Money.format(cents)
    }

    private var accessibilityText: String {
        let cents = section.netSpendingCents
        if cents > 0 { return "\(section.title), spent \(Money.format(cents))" }
        if cents < 0 { return "\(section.title), net refunds \(Money.format(-cents))" }
        return section.title
    }
}

// MARK: - Previews

#Preview("Transactions") {
    NavigationStack {
        TransactionsView()
    }
    .previewEnvironment()
}

#Preview("No transactions") {
    NavigationStack {
        TransactionsView()
    }
    .previewEnvironment(empty: true)
}
