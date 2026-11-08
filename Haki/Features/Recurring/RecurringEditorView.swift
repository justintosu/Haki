//
//  RecurringEditorView.swift
//  Haki
//
//  Sheet for adding a recurring bill (from scratch or from a suggestion) or
//  editing one: name, amount, frequency, next due date, category, which
//  merchant's charges count as payments, active state and notes.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct RecurringEditorView: View {
    let item: RecurringItem?
    let candidate: RecurringCandidate?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var transactions: [TransactionRecord]

    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.name)])
    private var categories: [TransactionCategory]

    @State private var name: String
    @State private var amountText: String
    @State private var frequency: RecurrenceFrequency
    @State private var nextDueDate: Date
    @State private var category: TransactionCategory?
    @State private var merchantText: String
    /// The merchant text as first shown. While unchanged, an existing bill
    /// keeps its stored merchant key.
    @State private var initialMerchantText: String
    @State private var isActive: Bool
    @State private var notes: String
    @State private var didLoad = false
    @State private var showsDeleteConfirmation = false
    /// Set right before dismissing to delete; the delete happens once the
    /// sheet is gone, so nothing reads the deleted bill.
    @State private var deletesOnDisappear = false

    private let initialDueDate: Date
    private let initialFrequency: RecurrenceFrequency

    init(item: RecurringItem?, candidate: RecurringCandidate? = nil) {
        self.item = item
        self.candidate = candidate

        let startName: String
        let startAmount: String
        let startFrequency: RecurrenceFrequency
        let startDueDate: Date
        let startMerchant: String
        if let item {
            startName = item.name
            startAmount = Money.editableText(fromCents: item.amountCents)
            startFrequency = item.frequency
            startDueDate = item.nextDueDate()
            startMerchant = item.name
        } else if let candidate {
            startName = candidate.displayName
            startAmount = Money.editableText(fromCents: candidate.typicalAmountCents)
            startFrequency = candidate.frequency
            startDueDate = candidate.nextExpectedDate
            startMerchant = candidate.displayName
        } else {
            startName = ""
            startAmount = ""
            startFrequency = .monthly
            startDueDate = Calendar.current.noon(on: Date.now)
            startMerchant = ""
        }

        _name = State(initialValue: startName)
        _amountText = State(initialValue: startAmount)
        _frequency = State(initialValue: startFrequency)
        _nextDueDate = State(initialValue: startDueDate)
        _category = State(initialValue: item?.category)
        _merchantText = State(initialValue: startMerchant)
        _initialMerchantText = State(initialValue: startMerchant)
        _isActive = State(initialValue: item?.isActive ?? true)
        _notes = State(initialValue: item?.notes ?? "")
        initialDueDate = startDueDate
        initialFrequency = startFrequency
    }

    var body: some View {
        let matches = matchingTransactions(for: matchKey)
        NavigationStack {
            Form {
                if item == nil, let candidate {
                    suggestionSection(candidate)
                }
                billSection
                categorySection
                matchingSection(matches)
                if item != nil {
                    statusSection
                }
                notesSection
                if item != nil {
                    deleteSection
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saveTitle) {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(deleteTitle, isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Bill", role: .destructive) {
                    deletesOnDisappear = true
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Haki will stop tracking this bill. Your transactions won't change.")
            }
        }
        .onAppear {
            loadOnce()
        }
        .onDisappear {
            deleteIfRequested()
        }
    }

    // MARK: Sections

    private func suggestionSection(_ candidate: RecurringCandidate) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Found in your transactions")
                        .font(.subheadline.weight(.semibold))
                    Text(suggestionDetail(candidate))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private var billSection: some View {
        Section {
            TextField("Name", text: $name)
                .textInputAutocapitalization(.words)
            HStack {
                Text("Amount")
                Spacer(minLength: 12)
                TextField("Amount", text: $amountText, prompt: Text(Money.format(0)))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            Picker("Frequency", selection: $frequency) {
                ForEach(RecurrenceFrequency.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            DatePicker("Next due", selection: $nextDueDate, displayedComponents: .date)
        } header: {
            Text("Bill")
        } footer: {
            if let costFooter {
                Text(costFooter)
            }
        }
    }

    private var categorySection: some View {
        Section {
            NavigationLink {
                CategoryPickerView(selection: $category)
            } label: {
                HStack(spacing: 10) {
                    Text("Category")
                    Spacer(minLength: 12)
                    if let category {
                        CategoryIcon(category: category, size: 26)
                    }
                    Text(category?.name ?? "None")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private func matchingSection(_ matches: [TransactionRecord]) -> some View {
        Section {
            TextField("Merchant", text: $merchantText, prompt: Text(merchantPrompt))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
            ForEach(Array(matches.prefix(4))) { transaction in
                NavigationLink {
                    TransactionDetailView(transaction: transaction)
                } label: {
                    TransactionRow(transaction: transaction, showsDate: true)
                }
            }
        } header: {
            Text("Matches transactions from")
        } footer: {
            Text(matchFooter(matches))
        }
    }

    private var statusSection: some View {
        Section {
            Toggle("Active", isOn: $isActive)
        } footer: {
            Text("Paused bills stay in your list but aren't counted in your totals or this month's schedule.")
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Notes", text: $notes, axis: .vertical)
                .lineLimit(2...6)
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("Delete Bill", systemImage: "trash")
            }
        }
    }

    // MARK: Derived values

    private var title: String {
        if item != nil { return "Edit Bill" }
        return candidate == nil ? "New Bill" : "Add Bill"
    }

    private var saveTitle: String {
        item == nil ? "Add" : "Save"
    }

    private var deleteTitle: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Delete this bill?" : "Delete \(trimmed)?"
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Bills are money out, so the sign the user types doesn't matter.
    private var parsedCents: Int? {
        let separator = Character(Locale.current.decimalSeparator ?? ".")
        guard let cents = Money.parseCents(amountText, decimalSeparator: separator) else { return nil }
        return abs(cents)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && (parsedCents ?? 0) > 0
    }

    private var costFooter: String? {
        guard let cents = parsedCents, cents > 0 else { return nil }
        let yearly = Money.format(frequency.yearlyCents(cents))
        if frequency == .monthly {
            return "That's \(yearly) a year."
        }
        let monthly = Money.format(frequency.monthlyCents(cents))
        return "About \(monthly) a month, \(yearly) a year."
    }

    /// The merchant whose charges count as payments: the merchant field, or
    /// the bill's name when that's empty.
    private var merchantName: String {
        let merchant = merchantText.trimmingCharacters(in: .whitespacesAndNewlines)
        return merchant.isEmpty ? trimmedName : merchant
    }

    private var merchantPrompt: String {
        trimmedName.isEmpty ? "Same as the name" : trimmedName
    }

    private var merchantTextChanged: Bool {
        merchantText.trimmingCharacters(in: .whitespacesAndNewlines)
            != initialMerchantText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The key payments are matched by, reflecting edits as the user types.
    private var matchKey: String {
        if let item, !merchantTextChanged { return item.merchantKey }
        let source = merchantName
        return source.isEmpty ? "" : MerchantNormalizer.key(for: source)
    }

    private func matchingTransactions(for key: String) -> [TransactionRecord] {
        guard !key.isEmpty else { return [] }
        return transactions.filter { transaction in
            transaction.amountCents > 0
                && !transaction.isExcluded
                && Categorizer.ruleMatches(ruleKey: key, merchantKey: transaction.merchantKey)
        }
    }

    private func matchFooter(_ matches: [TransactionRecord]) -> String {
        guard !merchantName.isEmpty else {
            return "Enter the merchant as it appears on your transactions. Charges from it count as payments."
        }
        let merchant = matches.first?.merchant ?? MerchantNormalizer.displayName(for: merchantName)
        guard let latest = matches.first else {
            return "No charges from “\(merchant)” yet. Payments are matched automatically when they show up."
        }
        let count = RecurringFormat.count(matches.count, "charge", "charges")
        let date = RecurringFormat.shortDate(latest.date)
        let amount = Money.format(latest.amountCents)
        return "\(count) from “\(merchant)”, most recently \(amount) on \(date). A charge within a few days of a due date counts as paying it."
    }

    private func suggestionDetail(_ candidate: RecurringCandidate) -> String {
        let seen = RecurringFormat.count(candidate.occurrenceCount, "time", "times")
        let last = RecurringFormat.shortDate(candidate.lastDate)
        let amount = Money.format(candidate.typicalAmountCents)
        return "Seen \(seen), \(candidate.frequency.displayName.lowercased()). Last charged \(amount) on \(last)."
    }

    // MARK: Actions

    /// Fills in what needs the database. Runs once: `onAppear` fires again
    /// when coming back from the category picker.
    private func loadOnce() {
        guard !didLoad else { return }
        didLoad = true
        if let item {
            // Show the merchant as it appears on its latest payment.
            let key = item.merchantKey
            if let latest = transactions.first(where: {
                $0.amountCents > 0 && Categorizer.ruleMatches(ruleKey: key, merchantKey: $0.merchantKey)
            }) {
                merchantText = latest.merchant
                initialMerchantText = latest.merchant
            }
        } else if let candidate, category == nil, let categoryID = candidate.categoryID {
            category = categories.first { $0.ledgerID == categoryID }
        }
    }

    private func save() {
        guard let cents = parsedCents, cents > 0, !trimmedName.isEmpty else { return }
        let calendar = Calendar.current
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let item {
            item.name = trimmedName
            item.amountCents = cents
            if merchantTextChanged {
                item.merchantKey = MerchantNormalizer.key(for: merchantName)
            }
            let dueDateChanged = !calendar.isDate(nextDueDate, inSameDayAs: initialDueDate)
            if dueDateChanged || frequency != initialFrequency {
                // Later due dates are counted from the anchor.
                item.anchorDate = calendar.noon(on: nextDueDate)
            }
            item.frequency = frequency
            item.category = category
            item.isActive = isActive
            item.notes = trimmedNotes
            LedgerStore.save(modelContext)
        } else {
            let newItem = LedgerStore.addRecurring(
                in: modelContext,
                name: trimmedName,
                merchantName: merchantName,
                amountCents: cents,
                frequency: frequency,
                nextDueDate: nextDueDate,
                category: category
            )
            if !trimmedNotes.isEmpty {
                newItem.notes = trimmedNotes
                LedgerStore.save(modelContext)
            }
        }
        dismiss()
    }

    private func deleteIfRequested() {
        guard deletesOnDisappear, let item else { return }
        deletesOnDisappear = false
        modelContext.delete(item)
        LedgerStore.save(modelContext)
    }
}

#Preview("New bill") {
    RecurringEditorView(item: nil)
        .previewEnvironment()
}

#Preview("Edit bill") {
    RecurringEditorView(item: PreviewData.sampleRecurringItem)
        .previewEnvironment()
}

#Preview("From a suggestion") {
    RecurringEditorView(
        item: nil,
        candidate: RecurringCandidate(
            merchantKey: "thenewyorktimes",
            displayName: "The New York Times",
            frequency: .monthly,
            typicalAmountCents: 400,
            lastDate: Date.now.addingTimeInterval(-5 * 86_400),
            nextExpectedDate: Date.now.addingTimeInterval(25 * 86_400),
            occurrenceCount: 4,
            categoryID: nil
        )
    )
    .previewEnvironment()
}
