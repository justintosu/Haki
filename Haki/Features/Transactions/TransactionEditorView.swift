//
//  TransactionEditorView.swift
//  Haki
//
//  A sheet for adding a transaction by hand.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct TransactionEditorView: View {
    /// The account the new transaction starts in (the user can change it).
    let account: Account?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Past merchants, for suggestions while typing.
    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var pastTransactions: [TransactionRecord]

    @State private var direction: Direction = .expense
    @State private var amountText = ""
    @State private var merchant = ""
    @State private var date = Date.now
    @State private var category: TransactionCategory? = nil
    @State private var selectedAccount: Account?
    @State private var notes = ""
    @State private var didAutoFocus = false
    @FocusState private var focusedField: Field?

    private enum Direction: String, CaseIterable, Identifiable {
        case expense
        case income

        var id: String { rawValue }

        var title: String {
            switch self {
            case .expense: return "Expense"
            case .income: return "Income"
            }
        }
    }

    private enum Field: Hashable {
        case amount
        case merchant
        case notes
    }

    private struct MerchantSuggestion: Identifiable {
        /// The merchant key.
        let id: String
        let name: String
        let category: TransactionCategory?
    }

    init(account: Account? = nil) {
        self.account = account
        _selectedAccount = State(initialValue: account)
    }

    var body: some View {
        NavigationStack {
            Form {
                directionSection
                amountSection
                merchantSection
                let suggestions = merchantSuggestions
                if !suggestions.isEmpty {
                    suggestionsSection(suggestions)
                }
                detailsSection
                notesSection
            }
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .interactiveDismissDisabled(hasChanges)
            .task {
                await focusAmountOnAppear()
            }
        }
    }

    // MARK: Sections

    private var directionSection: some View {
        Section {
            Picker("Type", selection: $direction) {
                ForEach(Direction.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    private var amountSection: some View {
        Section {
            VStack(spacing: 6) {
                TextField(Money.editableText(fromCents: 0), text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(direction == .income ? Color.hakiPositive : Color.primary)
                    .focused($focusedField, equals: .amount)
                    .accessibilityLabel("Amount")
                Text(amountCaption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    private var merchantSection: some View {
        Section {
            TextField(merchantPlaceholder, text: $merchant)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focusedField, equals: .merchant)
                .onSubmit { focusedField = nil }
        } header: {
            Text(merchantHeader)
        }
    }

    private func suggestionsSection(_ suggestions: [MerchantSuggestion]) -> some View {
        Section("Previously used") {
            ForEach(suggestions) { suggestion in
                Button {
                    useSuggestion(suggestion)
                } label: {
                    HStack(spacing: 12) {
                        CategoryIcon(category: suggestion.category, size: 28)
                        Text(suggestion.name)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.left")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityLabel("Use \(suggestion.name)")
            }
        }
    }

    private var detailsSection: some View {
        Section {
            DatePicker("Date", selection: $date, displayedComponents: .date)
            NavigationLink {
                CategoryPickerView(selection: $category)
            } label: {
                LabeledContent("Category") {
                    HStack(spacing: 8) {
                        CategoryIcon(category: category, size: 26)
                        Text(category?.name ?? "Uncategorized")
                    }
                }
            }
            AccountPicker(title: "Account", selection: $selectedAccount)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .focused($focusedField, equals: .notes)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") { save() }
                .disabled(!canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            if focusedField == .amount {
                Button("Next") { focusedField = .merchant }
            } else {
                Button("Done") { focusedField = nil }
            }
        }
    }

    // MARK: Derived values

    private var parsedCents: Int? {
        guard let cents = TransactionInput.parseCents(amountText) else { return nil }
        return abs(cents)
    }

    private var canSave: Bool {
        guard let cents = parsedCents, cents > 0 else { return false }
        return !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasChanges: Bool {
        !amountText.isEmpty || !merchant.isEmpty || !notes.isEmpty
    }

    private var navigationTitleText: String {
        direction == .income ? "New Income" : "New Expense"
    }

    private var merchantHeader: String {
        direction == .income ? "From" : "Merchant"
    }

    private var merchantPlaceholder: String {
        direction == .income ? "Who paid you?" : "Where did you spend it?"
    }

    private var amountCaption: String {
        guard let cents = parsedCents, cents > 0 else {
            return direction == .income ? "Money coming in" : "Money going out"
        }
        switch direction {
        case .expense:
            return "\(Money.format(cents)) going out"
        case .income:
            return "\(Money.format(cents, alwaysShowsSign: true)) coming in"
        }
    }

    /// Up to three past merchants containing the typed text, most recent
    /// first. Hidden once the text matches a merchant exactly.
    private var merchantSuggestions: [MerchantSuggestion] {
        let query = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        var seen = Set<String>()
        var matches: [MerchantSuggestion] = []
        for transaction in pastTransactions {
            let key = transaction.merchantKey
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            if transaction.merchant.caseInsensitiveCompare(query) == .orderedSame { return [] }
            if matches.count < 3, transaction.merchant.localizedStandardContains(query) {
                matches.append(MerchantSuggestion(id: key, name: transaction.merchant, category: transaction.category))
            }
        }
        return matches
    }

    // MARK: Actions

    private func useSuggestion(_ suggestion: MerchantSuggestion) {
        merchant = suggestion.name
        if category == nil {
            category = suggestion.category
        }
        focusedField = nil
    }

    private func focusAmountOnAppear() async {
        guard !didAutoFocus else { return }
        didAutoFocus = true
        // Wait for the sheet to finish presenting, or the keyboard may not appear.
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled, focusedField == nil else { return }
        focusedField = .amount
    }

    private func save() {
        guard canSave, let cents = parsedCents else { return }
        let signed = direction == .income ? -cents : cents
        LedgerStore.addTransaction(
            in: modelContext,
            date: date,
            merchant: merchant,
            amountCents: signed,
            account: selectedAccount,
            category: category,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        dismiss()
    }
}

// MARK: - Previews

#Preview("New transaction") {
    TransactionEditorView()
        .previewEnvironment()
}

#Preview("From an account") {
    TransactionEditorView(account: PreviewData.sampleAccount)
        .previewEnvironment()
}
