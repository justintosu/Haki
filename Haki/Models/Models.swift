//
//  Models.swift
//  Haki
//
//  SwiftData models. Conventions:
//
//  - Amounts are Int cents with the Plaid sign convention: positive = money
//    out. See `Money`.
//  - Enums are stored as raw strings (`kindRaw`) with a typed computed
//    property (`kind`), which keeps predicates and migrations simple.
//  - Every stored property has a default value and no attribute is unique,
//    so the schema stays compatible with iCloud (CloudKit) sync later.
//  - To create models with relationships, use the `LedgerStore` helpers: they
//    insert the model into a context *before* setting relationships, which
//    SwiftData requires.
//

import Foundation
import SwiftData

// MARK: - Account

@Model
final class Account {
    var id: UUID = UUID()
    var name: String = ""
    var institution: String = ""
    var kindRaw: String = AccountKind.checking.rawValue
    /// Current balance in cents. For credit cards and loans this is the amount
    /// owed, as a positive number.
    var balanceCents: Int = 0
    /// Last digits of the account number, e.g. "4821". May be empty.
    var mask: String = ""
    var includeInNetWorth: Bool = true
    var sortOrder: Int = 0
    var createdAt: Date = Date()
    var balanceUpdatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \TransactionRecord.account)
    var transactions: [TransactionRecord] = []

    @Relationship(deleteRule: .cascade, inverse: \BalanceSnapshot.account)
    var snapshots: [BalanceSnapshot] = []

    init(name: String, institution: String = "", kind: AccountKind, balanceCents: Int = 0, mask: String = "", sortOrder: Int = 0) {
        self.name = name
        self.institution = institution
        self.kindRaw = kind.rawValue
        self.balanceCents = balanceCents
        self.mask = mask
        self.sortOrder = sortOrder
    }

    var kind: AccountKind {
        get { AccountKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var isLiability: Bool { kind.isLiability }

    /// What this account adds to net worth: positive for assets, negative for
    /// liabilities, zero when excluded from net worth.
    var netWorthContributionCents: Int {
        guard includeInNetWorth else { return 0 }
        return isLiability ? -balanceCents : balanceCents
    }

    /// "Harborline Bank ••4821", or just one of the parts.
    var subtitle: String {
        let maskText = mask.isEmpty ? "" : "••\(mask)"
        return [institution, maskText].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Balance history for `NetWorthCalculator`.
    var balanceObservations: [BalanceObservation] {
        snapshots.map {
            BalanceObservation(accountID: id.uuidString, date: $0.date, balanceCents: $0.balanceCents, isLiability: isLiability)
        }
    }
}

// MARK: - Category

@Model
final class TransactionCategory {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "📦"
    /// "#RRGGBB"
    var colorHex: String = "#8E8E93"
    var kindRaw: String = CategoryKind.expense.rawValue
    /// Monthly budget in cents; `nil` means no budget.
    var monthlyBudgetCents: Int? = nil
    /// Set for built-in categories (`DefaultCategories`), `nil` for ones the user created.
    var seedKey: String? = nil
    var sortOrder: Int = 0

    @Relationship(deleteRule: .nullify, inverse: \TransactionRecord.category)
    var transactions: [TransactionRecord] = []

    @Relationship(deleteRule: .nullify, inverse: \RecurringItem.category)
    var recurringItems: [RecurringItem] = []

    @Relationship(deleteRule: .cascade, inverse: \MerchantRule.category)
    var rules: [MerchantRule] = []

    init(name: String, emoji: String, colorHex: String, kind: CategoryKind, monthlyBudgetCents: Int? = nil, seedKey: String? = nil, sortOrder: Int = 0) {
        self.name = name
        self.emoji = emoji
        self.colorHex = colorHex
        self.kindRaw = kind.rawValue
        self.monthlyBudgetCents = monthlyBudgetCents
        self.seedKey = seedKey
        self.sortOrder = sortOrder
    }

    var kind: CategoryKind {
        get { CategoryKind(rawValue: kindRaw) ?? .expense }
        set { kindRaw = newValue.rawValue }
    }

    /// The key analytics code uses for this category (`LedgerEntry.ledgerCategoryID`).
    var ledgerID: String { id.uuidString }

    var hasBudget: Bool { (monthlyBudgetCents ?? 0) > 0 }
}

// MARK: - Transaction

@Model
final class TransactionRecord {
    var id: UUID = UUID()
    /// Local noon on the transaction's calendar day (`Calendar.noon(on:)`).
    var date: Date = Date()
    /// Display name. Change it with `setMerchant(_:)` so `merchantKey` stays in sync.
    var merchant: String = ""
    /// `MerchantNormalizer.key(for: merchant)`, used for rules, recurring matching and de-duplication.
    var merchantKey: String = ""
    /// The bank's raw description, if imported. Read-only for the user.
    var originalDescription: String = ""
    /// Plaid sign convention: positive = money out.
    var amountCents: Int = 0
    var notes: String = ""
    /// `false` until the user has looked at it; drives the "To review" queue.
    var isReviewed: Bool = false
    /// Excluded transactions are ignored in every total.
    var isExcluded: Bool = false
    var isPending: Bool = false
    /// `TransactionFingerprint` at import time, for skipping duplicates.
    var importFingerprint: String = ""
    var createdAt: Date = Date()

    var account: Account?
    var category: TransactionCategory?

    init(date: Date, merchant: String, amountCents: Int, originalDescription: String = "", notes: String = "",
         isReviewed: Bool = false, isPending: Bool = false, calendar: Calendar = .current) {
        self.date = calendar.noon(on: date)
        self.merchant = merchant
        self.merchantKey = MerchantNormalizer.key(for: merchant)
        self.amountCents = amountCents
        self.originalDescription = originalDescription
        self.notes = notes
        self.isReviewed = isReviewed
        self.isPending = isPending
        self.importFingerprint = TransactionFingerprint.make(
            date: self.date,
            amountCents: amountCents,
            merchantKey: MerchantNormalizer.key(for: originalDescription.isEmpty ? merchant : originalDescription),
            calendar: calendar
        )
    }

    /// Renames the merchant and updates `merchantKey`.
    func setMerchant(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        merchant = trimmed.isEmpty ? "Unknown" : trimmed
        merchantKey = MerchantNormalizer.key(for: merchant)
    }

    var flow: LedgerFlow {
        LedgerFlow.resolve(categoryKind: category?.kind, isExcluded: isExcluded, amountCents: amountCents)
    }

    /// Money in (a paycheck or refund).
    var isMoneyIn: Bool { amountCents < 0 }
}

extension TransactionRecord: LedgerEntry {
    var ledgerDate: Date { date }
    var ledgerAmountCents: Int { amountCents }
    var ledgerFlow: LedgerFlow { flow }
    var ledgerCategoryID: String? { category?.ledgerID }
    var ledgerMerchant: String { merchant }
    var ledgerMerchantKey: String { merchantKey }
}

// MARK: - Recurring bill

@Model
final class RecurringItem {
    var id: UUID = UUID()
    var name: String = ""
    /// Transactions whose `merchantKey` matches this count as payments
    /// (see `Categorizer.ruleMatches`).
    var merchantKey: String = ""
    var amountCents: Int = 0
    var frequencyRaw: String = RecurrenceFrequency.monthly.rawValue
    /// The first due date; later ones are computed from it (`RecurringSchedule`).
    var anchorDate: Date = Date()
    var isActive: Bool = true
    var notes: String = ""
    var createdAt: Date = Date()

    var category: TransactionCategory?

    init(name: String, merchantKey: String, amountCents: Int, frequency: RecurrenceFrequency, anchorDate: Date, calendar: Calendar = .current) {
        self.name = name
        self.merchantKey = merchantKey
        self.amountCents = amountCents
        self.frequencyRaw = frequency.rawValue
        self.anchorDate = calendar.noon(on: anchorDate)
    }

    var frequency: RecurrenceFrequency {
        get { RecurrenceFrequency(rawValue: frequencyRaw) ?? .monthly }
        set { frequencyRaw = newValue.rawValue }
    }

    var schedule: RecurringSchedule {
        RecurringSchedule(anchor: anchorDate, frequency: frequency)
    }

    func nextDueDate(onOrAfter date: Date = .now, calendar: Calendar = .current) -> Date {
        schedule.nextOccurrence(onOrAfter: date, calendar: calendar)
    }

    /// Cost per month, for "monthly recurring total".
    var monthlyCostCents: Int { frequency.monthlyCents(amountCents) }
}

// MARK: - Balance history

@Model
final class BalanceSnapshot {
    var id: UUID = UUID()
    var date: Date = Date()
    var balanceCents: Int = 0

    var account: Account?

    init(date: Date, balanceCents: Int) {
        self.date = date
        self.balanceCents = balanceCents
    }
}

// MARK: - Categorization rule

/// "Always categorize transactions from this merchant as ...". Created when
/// the user recategorizes a transaction and applies it to the merchant.
@Model
final class MerchantRule {
    var id: UUID = UUID()
    /// `MerchantNormalizer.key(for:)` of the merchant.
    var merchantKey: String = ""
    /// The merchant's display name when the rule was made, for showing in Settings.
    var merchantName: String = ""
    var createdAt: Date = Date()

    var category: TransactionCategory?

    init(merchantKey: String, merchantName: String) {
        self.merchantKey = merchantKey
        self.merchantName = merchantName
    }
}

// MARK: - Schema

enum HakiSchema {
    static let models: [any PersistentModel.Type] = [
        Account.self,
        TransactionCategory.self,
        TransactionRecord.self,
        RecurringItem.self,
        BalanceSnapshot.self,
        MerchantRule.self,
        FoodEntry.self,
        WorkoutRecord.self,
        WorkoutExerciseRecord.self,
        WorkoutSetRecord.self,
        RoutineRecord.self,
        RoutineExerciseRecord.self,
        CustomExerciseRecord.self,
        ClothingItem.self,
        Outfit.self,
        OutfitPiece.self,
        Note.self,
        FlashcardDeck.self,
        Flashcard.self,
        AssistantThread.self,
        AssistantMessageRecord.self,
    ]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
