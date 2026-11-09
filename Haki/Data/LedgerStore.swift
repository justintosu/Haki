//
//  LedgerStore.swift
//  Haki
//
//  Every write to the database goes through these helpers, so the rules
//  (insert before relating, keep merchant keys and balance history in sync,
//  apply categorization rules on import) live in one place.
//

import Foundation
import SwiftData

struct ImportSummary: Hashable {
    var inserted = 0
    var duplicatesSkipped = 0
    var autoCategorized = 0
}

enum LedgerStore {
    // MARK: Setup

    /// Inserts the built-in categories the first time the app runs (or after
    /// "Erase all data"). Does nothing if any category exists.
    static func ensureDefaultCategories(in context: ModelContext) {
        let existing = (try? context.fetchCount(FetchDescriptor<TransactionCategory>())) ?? 0
        guard existing == 0 else { return }
        for (index, preset) in DefaultCategories.all.enumerated() {
            context.insert(TransactionCategory(
                name: preset.name, emoji: preset.emoji, colorHex: preset.colorHex, kind: preset.kind,
                monthlyBudgetCents: nil, seedKey: preset.seedKey, sortOrder: index
            ))
        }
        save(context)
    }

    /// Whether the user has any accounts or transactions yet.
    static func hasUserData(in context: ModelContext) -> Bool {
        let accounts = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        let transactions = (try? context.fetchCount(FetchDescriptor<TransactionRecord>())) ?? 0
        return accounts + transactions > 0
    }

    /// Adds `SampleLedger` demo data: accounts with a year of balance history,
    /// a few months of transactions and tracked bills (except bills already
    /// tracked). Suggested budgets are added only to an empty Haki: no
    /// accounts, transactions or budgets yet. `removeSampleData` takes it out again.
    static func loadSampleData(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        ensureDefaultCategories(in: context)
        let ledger = SampleLedger.generate(now: now, calendar: calendar)

        // Loading twice would duplicate everything; skip if the demo accounts are already here.
        let sampleInstitutions = Set(ledger.accounts.map(\.institution))
        let existingInstitutions = Set(((try? context.fetch(FetchDescriptor<Account>())) ?? []).map(\.institution))
        guard sampleInstitutions.isDisjoint(with: existingInstitutions) else { return }
        let isEmpty = !hasUserData(in: context)
        let categories = allCategories(in: context)
        var categoryBySeed: [String: TransactionCategory] = [:]
        for category in categories {
            if let seedKey = category.seedKey { categoryBySeed[seedKey] = category }
        }

        var record = SampleDataRecord.load()
        // Never budget categories in someone's real setup they chose not to budget.
        if isEmpty, !categories.contains(where: { $0.monthlyBudgetCents != nil }) {
            for preset in DefaultCategories.all {
                if let category = categoryBySeed[preset.seedKey], let suggested = preset.suggestedBudgetCents {
                    category.monthlyBudgetCents = suggested
                    record.budgetSeedKeys.insert(preset.seedKey)
                }
            }
        }

        let existingAccounts = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        var accounts: [String: Account] = [:]
        for (index, spec) in ledger.accounts.enumerated() {
            let account = Account(name: spec.name, institution: spec.institution, kind: spec.kind,
                                  balanceCents: spec.balanceCents, mask: spec.mask, sortOrder: existingAccounts + index)
            account.balanceUpdatedAt = now
            context.insert(account)
            accounts[spec.key] = account
        }

        for spec in ledger.balances {
            guard let account = accounts[spec.accountKey] else { continue }
            let snapshot = BalanceSnapshot(date: spec.date, balanceCents: spec.balanceCents)
            context.insert(snapshot)
            snapshot.account = account
        }

        for spec in ledger.transactions {
            let transaction = TransactionRecord(
                date: spec.date,
                merchant: MerchantNormalizer.displayName(for: spec.description),
                amountCents: spec.amountCents,
                originalDescription: spec.description,
                isReviewed: spec.isReviewed,
                calendar: calendar
            )
            context.insert(transaction)
            transaction.account = accounts[spec.accountKey]
            transaction.category = spec.categorySeedKey.flatMap { categoryBySeed[$0] }
        }

        // Bills aren't tied to the demo accounts, so they outlive them; don't
        // add a second copy of one that's still tracked.
        let trackedKeys = Set(((try? context.fetch(FetchDescriptor<RecurringItem>())) ?? []).map(\.merchantKey))
        for spec in ledger.recurring where !trackedKeys.contains(spec.merchantKey) {
            let item = RecurringItem(name: spec.name, merchantKey: spec.merchantKey, amountCents: spec.amountCents,
                                     frequency: spec.frequency, anchorDate: spec.anchor, calendar: calendar)
            context.insert(item)
            item.category = spec.categorySeedKey.flatMap { categoryBySeed[$0] }
            record.billIDs.insert(item.id.uuidString)
        }
        save(context)
        record.save()
    }

    /// Whether any of these is demo data that `removeSampleData` would take out.
    static func hasSampleData(accounts: [Account], bills: [RecurringItem], categories: [TransactionCategory]) -> Bool {
        let institutions = SampleLedger.institutions
        if accounts.contains(where: { institutions.contains($0.institution) }) { return true }
        let record = SampleDataRecord.load()
        guard !record.isEmpty else { return false }
        return bills.contains { record.billIDs.contains($0.id.uuidString) }
            || categories.contains { record.hasSuggestedBudget($0) }
    }

    /// Takes out what `loadSampleData` added: the demo accounts with their
    /// transactions and balance history, the demo bills, and the suggested
    /// budgets that are still at the suggested amount.
    static func removeSampleData(in context: ModelContext) {
        let institutions = SampleLedger.institutions
        for account in (try? context.fetch(FetchDescriptor<Account>())) ?? [] where institutions.contains(account.institution) {
            // Transactions and balance snapshots cascade.
            context.delete(account)
        }

        let record = SampleDataRecord.load()
        for item in (try? context.fetch(FetchDescriptor<RecurringItem>())) ?? [] where record.billIDs.contains(item.id.uuidString) {
            context.delete(item)
        }
        for category in allCategories(in: context) where record.hasSuggestedBudget(category) {
            category.monthlyBudgetCents = nil
        }
        save(context)
        SampleDataRecord.clear()
    }

    /// Deletes every account, transaction, bill, rule and category, then
    /// restores the built-in categories.
    static func eraseAllData(in context: ModelContext) {
        deleteAll(TransactionRecord.self, in: context)
        deleteAll(BalanceSnapshot.self, in: context)
        deleteAll(RecurringItem.self, in: context)
        deleteAll(MerchantRule.self, in: context)
        deleteAll(Account.self, in: context)
        deleteAll(TransactionCategory.self, in: context)
        save(context)
        SampleDataRecord.clear()
        ensureDefaultCategories(in: context)
    }

    /// What `loadSampleData` added outside the demo accounts (which their
    /// institutions identify), so `removeSampleData` takes out only that.
    /// Forgets which bills and budgets sample data added (for a store that
    /// was set aside).
    static func forgetSampleDataRecord() {
        SampleDataRecord.clear()
    }

    private struct SampleDataRecord {
        private static let billIDsKey = "sampleData.billIDs"
        private static let budgetSeedKeysKey = "sampleData.budgetSeedKeys"

        /// `RecurringItem.id`s, as UUID strings.
        var billIDs: Set<String>
        /// Seed keys of the categories given a suggested budget.
        var budgetSeedKeys: Set<String>

        var isEmpty: Bool { billIDs.isEmpty && budgetSeedKeys.isEmpty }

        /// Whether the category still has the budget sample data gave it.
        func hasSuggestedBudget(_ category: TransactionCategory) -> Bool {
            guard let seedKey = category.seedKey, budgetSeedKeys.contains(seedKey),
                  let budget = category.monthlyBudgetCents
            else { return false }
            return budget == DefaultCategories.category(seedKey: seedKey)?.suggestedBudgetCents
        }

        static func load() -> SampleDataRecord {
            let defaults = UserDefaults.standard
            return SampleDataRecord(
                billIDs: Set(defaults.stringArray(forKey: billIDsKey) ?? []),
                budgetSeedKeys: Set(defaults.stringArray(forKey: budgetSeedKeysKey) ?? [])
            )
        }

        func save() {
            let defaults = UserDefaults.standard
            defaults.set(billIDs.sorted(), forKey: Self.billIDsKey)
            defaults.set(budgetSeedKeys.sorted(), forKey: Self.budgetSeedKeysKey)
        }

        static func clear() {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: billIDsKey)
            defaults.removeObject(forKey: budgetSeedKeysKey)
        }
    }

    // MARK: Transactions

    /// Adds a manually entered transaction. Manual entries start reviewed.
    @discardableResult
    static func addTransaction(
        in context: ModelContext,
        date: Date,
        merchant: String,
        amountCents: Int,
        account: Account?,
        category: TransactionCategory?,
        notes: String = "",
        calendar: Calendar = .current
    ) -> TransactionRecord {
        let name = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        let transaction = TransactionRecord(date: date, merchant: name.isEmpty ? "Unknown" : name,
                                            amountCents: amountCents, notes: notes, isReviewed: true, calendar: calendar)
        context.insert(transaction)
        transaction.account = account
        transaction.category = category
        save(context)
        return transaction
    }

    /// Other transactions from the same merchant, for "apply to all".
    static func otherTransactions(sameMerchantAs transaction: TransactionRecord, in context: ModelContext) -> [TransactionRecord] {
        let key = transaction.merchantKey
        let id = transaction.id
        let descriptor = FetchDescriptor<TransactionRecord>(
            predicate: #Predicate<TransactionRecord> { $0.merchantKey == key && $0.id != id })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Sets a transaction's category and marks it reviewed.
    /// - Parameters:
    ///   - applyToMerchant: also recategorize every other transaction from this merchant.
    ///   - rememberForMerchant: create or update a `MerchantRule` so future imports use this category.
    /// - Returns: how many other transactions were changed.
    @discardableResult
    static func setCategory(
        _ category: TransactionCategory?,
        for transaction: TransactionRecord,
        applyToMerchant: Bool = false,
        rememberForMerchant: Bool = false,
        in context: ModelContext
    ) -> Int {
        transaction.category = category
        transaction.isReviewed = true
        var changed = 0
        if applyToMerchant {
            for other in otherTransactions(sameMerchantAs: transaction, in: context) where other.category?.id != category?.id {
                other.category = category
                changed += 1
            }
        }
        if rememberForMerchant {
            setRule(merchantKey: transaction.merchantKey, merchantName: transaction.merchant, category: category, in: context)
        }
        save(context)
        return changed
    }

    static func setReviewed(_ transactions: [TransactionRecord], _ reviewed: Bool = true, in context: ModelContext) {
        for transaction in transactions { transaction.isReviewed = reviewed }
        save(context)
    }

    static func delete(_ transaction: TransactionRecord, in context: ModelContext) {
        context.delete(transaction)
        save(context)
    }

    // MARK: Rules

    /// Creates, updates or (with a `nil` category) removes the rule for a merchant.
    static func setRule(merchantKey: String, merchantName: String, category: TransactionCategory?, in context: ModelContext) {
        guard !merchantKey.isEmpty else { return }
        let key = merchantKey
        let existing = (try? context.fetch(FetchDescriptor<MerchantRule>(
            predicate: #Predicate<MerchantRule> { $0.merchantKey == key }))) ?? []
        guard let category else {
            for rule in existing { context.delete(rule) }
            save(context)
            return
        }
        if let rule = existing.first {
            rule.category = category
            rule.merchantName = merchantName
            for duplicate in existing.dropFirst() { context.delete(duplicate) }
        } else {
            let rule = MerchantRule(merchantKey: merchantKey, merchantName: merchantName)
            context.insert(rule)
            rule.category = category
        }
        save(context)
    }

    /// The category a rule assigns to a merchant, preferring exact matches.
    static func ruleCategory(forMerchantKey merchantKey: String, rules: [MerchantRule]) -> TransactionCategory? {
        if let exact = rules.first(where: { $0.merchantKey == merchantKey }) { return exact.category }
        return rules
            .filter { Categorizer.ruleMatches(ruleKey: $0.merchantKey, merchantKey: merchantKey) }
            .max { $0.merchantKey.count < $1.merchantKey.count }?
            .category
    }

    // MARK: Accounts

    @discardableResult
    static func addAccount(
        in context: ModelContext,
        name: String,
        institution: String = "",
        kind: AccountKind,
        balanceCents: Int,
        mask: String = "",
        now: Date = .now
    ) -> Account {
        let count = (try? context.fetchCount(FetchDescriptor<Account>())) ?? 0
        let account = Account(name: name, institution: institution, kind: kind, balanceCents: balanceCents,
                              mask: mask, sortOrder: count)
        account.balanceUpdatedAt = now
        context.insert(account)
        let snapshot = BalanceSnapshot(date: now, balanceCents: balanceCents)
        context.insert(snapshot)
        snapshot.account = account
        save(context)
        return account
    }

    /// Sets the current balance and records it in the balance history,
    /// replacing any snapshot already recorded that day.
    static func updateBalance(of account: Account, to cents: Int, on date: Date = .now, in context: ModelContext,
                              calendar: Calendar = .current) {
        account.balanceCents = cents
        account.balanceUpdatedAt = date
        if let sameDay = account.snapshots.first(where: { calendar.isDate($0.date, inSameDayAs: date) }) {
            sameDay.balanceCents = cents
            sameDay.date = date
        } else {
            let snapshot = BalanceSnapshot(date: date, balanceCents: cents)
            context.insert(snapshot)
            snapshot.account = account
        }
        save(context)
    }

    /// Deletes an account with its transactions and balance history.
    static func delete(_ account: Account, in context: ModelContext) {
        context.delete(account)
        save(context)
    }

    // MARK: Recurring

    /// Starts tracking a bill found by `RecurringDetector`.
    @discardableResult
    static func addRecurring(from candidate: RecurringCandidate, in context: ModelContext, calendar: Calendar = .current) -> RecurringItem {
        let item = RecurringItem(name: candidate.displayName, merchantKey: candidate.merchantKey,
                                 amountCents: candidate.typicalAmountCents, frequency: candidate.frequency,
                                 anchorDate: candidate.nextExpectedDate, calendar: calendar)
        context.insert(item)
        if let categoryID = candidate.categoryID {
            item.category = allCategories(in: context).first { $0.ledgerID == categoryID }
        }
        save(context)
        return item
    }

    @discardableResult
    static func addRecurring(
        in context: ModelContext,
        name: String,
        merchantName: String,
        amountCents: Int,
        frequency: RecurrenceFrequency,
        nextDueDate: Date,
        category: TransactionCategory?,
        calendar: Calendar = .current
    ) -> RecurringItem {
        let item = RecurringItem(name: name, merchantKey: MerchantNormalizer.key(for: merchantName.isEmpty ? name : merchantName),
                                 amountCents: amountCents, frequency: frequency, anchorDate: nextDueDate, calendar: calendar)
        context.insert(item)
        item.category = category
        save(context)
        return item
    }

    // MARK: Import

    /// Imports parsed CSV transactions, skipping ones already in the app.
    ///
    /// Each transaction's category comes from, in order: a merchant rule, a
    /// category in the file whose name matches one of yours, or the built-in
    /// keyword categorizer. Imported transactions start unreviewed.
    /// - Parameter account: the account to file them under. If `nil`, a
    ///   transaction goes to the account named in the file (when one matches
    ///   by name) or to no account.
    @discardableResult
    static func importTransactions(
        _ imported: [ImportedTransaction],
        into account: Account?,
        in context: ModelContext,
        calendar: Calendar = .current
    ) -> ImportSummary {
        let existing = (try? context.fetch(FetchDescriptor<TransactionRecord>())) ?? []
        let (fresh, duplicates) = ImportDeduplicator.newTransactions(
            imported, existingFingerprints: existing.map(\.importFingerprint), calendar: calendar)

        let categories = allCategories(in: context)
        let rules = (try? context.fetch(FetchDescriptor<MerchantRule>())) ?? []
        let accounts = (try? context.fetch(FetchDescriptor<Account>())) ?? []
        var categoryByName: [String: TransactionCategory] = [:]
        var categoryBySeed: [String: TransactionCategory] = [:]
        for category in categories {
            categoryByName[category.name.lowercased()] = category
            if let seedKey = category.seedKey { categoryBySeed[seedKey] = category }
        }

        var summary = ImportSummary(duplicatesSkipped: duplicates)
        for item in fresh {
            let transaction = TransactionRecord(
                date: item.date,
                merchant: item.merchantName,
                amountCents: item.amountCents,
                originalDescription: item.rawDescription,
                notes: item.notes ?? "",
                isReviewed: false,
                calendar: calendar
            )
            context.insert(transaction)

            if let account {
                transaction.account = account
            } else if let name = item.accountName?.lowercased() {
                transaction.account = accounts.first { $0.name.lowercased() == name }
            }

            let category = ruleCategory(forMerchantKey: transaction.merchantKey, rules: rules)
                ?? item.categoryName.flatMap { categoryByName[$0.lowercased()] }
                ?? Categorizer.suggestedSeedKey(description: item.rawDescription, amountCents: item.amountCents)
                    .flatMap { categoryBySeed[$0] }
            transaction.category = category
            if category != nil { summary.autoCategorized += 1 }
            summary.inserted += 1
        }
        save(context)
        return summary
    }

    // MARK: Helpers

    static func allCategories(in context: ModelContext) -> [TransactionCategory] {
        let descriptor = FetchDescriptor<TransactionCategory>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.name)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            assertionFailure("Haki couldn't save: \(error)")
        }
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for model in all { context.delete(model) }
    }
}
