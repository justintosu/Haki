//
//  TransactionDetailView.swift
//  Haki
//
//  One transaction: a large header, the review button, editable fields,
//  recategorizing (optionally for the whole merchant), history from the same
//  merchant and delete.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct TransactionDetailView: View {
    @Bindable var transaction: TransactionRecord

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// For "More from <merchant>". Filtered in memory so renames and
    /// deletions are always reflected.
    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var allTransactions: [TransactionRecord]

    @State private var merchantDraft: String
    @State private var amountText: String
    @State private var isMoneyIn: Bool
    @State private var dateSelection: Date
    @State private var categorySelection: TransactionCategory?
    @State private var categoryProposal: CategoryProposal? = nil
    @State private var categoryPromptRequest = 0
    @State private var showsCategoryPrompt = false
    @State private var showsDeleteConfirmation = false
    /// Set right before deleting, so the body never reads a deleted model.
    @State private var isDeleted = false
    @State private var successFeedback = 0
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case merchant
        case amount
        case notes
    }

    /// A category picked for a merchant that has other transactions, waiting
    /// for the user to choose whether it applies to all of them.
    private struct CategoryProposal {
        let category: TransactionCategory?
        let otherCount: Int
    }

    init(transaction: TransactionRecord) {
        self.transaction = transaction
        _merchantDraft = State(initialValue: transaction.merchant)
        _amountText = State(initialValue: Money.editableText(fromCents: abs(transaction.amountCents)))
        _isMoneyIn = State(initialValue: transaction.amountCents < 0)
        _dateSelection = State(initialValue: transaction.date)
        _categorySelection = State(initialValue: transaction.category)
    }

    var body: some View {
        Group {
            if isDeleted {
                Color.hakiBackground
            } else {
                form
            }
        }
        .navigationTitle("Transaction")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Form

    // The modifiers are split over three properties so no single expression
    // gets long enough to strain the type checker.

    private var form: some View {
        formWithDialogs
            .sensoryFeedback(.success, trigger: successFeedback)
    }

    /// The form with its keyboard toolbar and the handlers that save edits.
    private var editableForm: some View {
        formContent
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .onChange(of: focusedField) { oldValue, _ in
                fieldLostFocus(oldValue)
            }
            .onChange(of: isMoneyIn) { _, _ in
                commitAmount()
            }
            .onChange(of: dateSelection) { _, newValue in
                commitDate(newValue)
            }
            .onChange(of: categorySelection) { _, newValue in
                categorySelectionChanged(to: newValue)
            }
            .onChange(of: transaction.isReviewed) { _, _ in
                LedgerStore.save(modelContext)
            }
            .onChange(of: transaction.isExcluded) { _, _ in
                LedgerStore.save(modelContext)
            }
            .onChange(of: transaction.account?.id) { _, _ in
                LedgerStore.save(modelContext)
            }
            .onChange(of: showsCategoryPrompt) { _, isShown in
                if !isShown { finishCategoryPrompt() }
            }
            .task(id: categoryPromptRequest) {
                await presentCategoryPromptIfNeeded()
            }
            .onDisappear {
                commitPendingEdits()
            }
    }

    /// The "apply to all from this merchant" question and the delete confirmation.
    private var formWithDialogs: some View {
        editableForm
            .confirmationDialog(
                categoryPromptTitle,
                isPresented: $showsCategoryPrompt,
                titleVisibility: .visible,
                presenting: categoryProposal
            ) { proposal in
                Button("All \(transaction.merchant) transactions") {
                    applyCategory(proposal.category, toWholeMerchant: true)
                }
                Button("Only this one") {
                    applyCategory(proposal.category, toWholeMerchant: false)
                }
                Button("Cancel", role: .cancel) {}
            } message: { proposal in
                Text(categoryPromptMessage(for: proposal))
            }
            .confirmationDialog(
                "Delete this transaction?",
                isPresented: $showsDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete transaction", role: .destructive) {
                    deleteTransaction()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will be removed from your totals and budgets. This can't be undone.")
            }
    }

    private var formContent: some View {
        Form {
            Section {
                header
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))

            detailsSection
            notesSection
            statusSection
            if !transaction.originalDescription.isEmpty {
                bankDescriptionSection
            }
            merchantHistorySection
            deleteSection
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            CategoryIcon(category: transaction.category, size: 64)
                .padding(.bottom, 4)
            Text(amountTitle)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(amountColor)
                .strikethrough(transaction.isExcluded)
                .contentTransition(.numericText())
                .accessibilityLabel(amountAccessibilityLabel)
            Text(transaction.merchant)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(headerSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if transaction.isPending || transaction.isExcluded {
                HStack(spacing: 6) {
                    if transaction.isPending {
                        TransactionDetailBadge(title: "Pending", systemImage: "clock")
                    }
                    if transaction.isExcluded {
                        TransactionDetailBadge(title: "Excluded", systemImage: "eye.slash")
                    }
                }
                .padding(.top, 2)
            }
            if !transaction.isReviewed {
                Button {
                    markReviewed()
                } label: {
                    Label("Mark as reviewed", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
    }

    private var amountTitle: String {
        let cents = transaction.amountCents
        return cents < 0 ? Money.format(-cents, alwaysShowsSign: true) : Money.format(cents)
    }

    private var amountColor: Color {
        if transaction.isExcluded { return Color.secondary }
        return transaction.amountCents < 0 ? Color.hakiPositive : Color.primary
    }

    private var amountAccessibilityLabel: String {
        let magnitude = Money.format(abs(transaction.amountCents))
        var label = transaction.amountCents < 0 ? "Received \(magnitude)" : "Spent \(magnitude)"
        if transaction.isExcluded { label += ", excluded from totals" }
        return label
    }

    private var headerSubtitle: String {
        var parts = [transaction.date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())]
        if let account = transaction.account { parts.append(account.name) }
        return parts.joined(separator: " · ")
    }

    // MARK: Sections

    private var detailsSection: some View {
        Section {
            NavigationLink {
                CategoryPickerView(selection: $categorySelection)
            } label: {
                LabeledContent("Category") {
                    HStack(spacing: 8) {
                        CategoryIcon(category: transaction.category, size: 26)
                        Text(transaction.category?.name ?? "Uncategorized")
                    }
                }
            }

            LabeledContent("Merchant") {
                TextField("Merchant", text: $merchantDraft)
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focusedField, equals: .merchant)
                    .onSubmit { commitMerchant() }
            }

            Picker("Direction", selection: $isMoneyIn) {
                Text("Money out").tag(false)
                Text("Money in").tag(true)
            }
            .pickerStyle(.segmented)

            LabeledContent("Amount") {
                TextField(Money.editableText(fromCents: 0), text: $amountText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focusedField, equals: .amount)
            }

            DatePicker("Date", selection: $dateSelection, displayedComponents: .date)

            AccountPicker(title: "Account", selection: $transaction.account)
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            TextField("Add a note", text: $transaction.notes, axis: .vertical)
                .lineLimit(2...6)
                .focused($focusedField, equals: .notes)
        }
    }

    private var statusSection: some View {
        Section {
            Toggle(isOn: $transaction.isReviewed) {
                Label("Reviewed", systemImage: "checkmark.circle")
            }
            Toggle(isOn: $transaction.isExcluded) {
                Label("Exclude from totals", systemImage: "eye.slash")
            }
        } footer: {
            Text("Excluded transactions stay in your list but don't count toward spending, income or budgets.")
        }
    }

    private var bankDescriptionSection: some View {
        Section {
            Text(transaction.originalDescription)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        } header: {
            Text("Bank description")
        } footer: {
            Text("The original text from your bank or import file.")
        }
    }

    @ViewBuilder
    private var merchantHistorySection: some View {
        let others = merchantHistory
        if !others.isEmpty {
            let totals = merchantTotals(others: others)
            let recent = Array(others.prefix(5))
            Section {
                LabeledContent("Transactions", value: (others.count + 1).formatted())
                if totals.spent != 0 {
                    LabeledContent("Total spent", value: Money.format(totals.spent))
                }
                if totals.received != 0 {
                    LabeledContent("Total received", value: Money.format(totals.received))
                }
                ForEach(recent) { other in
                    NavigationLink {
                        TransactionDetailView(transaction: other)
                    } label: {
                        TransactionRow(transaction: other, showsDate: true)
                    }
                }
            } header: {
                Text("More from \(transaction.merchant)")
            } footer: {
                if others.count > recent.count {
                    Text("Showing the \(recent.count.formatted()) most recent.")
                }
            }
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("Delete transaction", systemImage: "trash")
            }
        }
    }

    // MARK: Merchant history

    private var merchantHistory: [TransactionRecord] {
        let key = transaction.merchantKey
        let id = transaction.id
        guard !key.isEmpty else { return [] }
        return allTransactions.filter { $0.merchantKey == key && $0.id != id }
    }

    private func merchantTotals(others: [TransactionRecord]) -> (spent: Int, received: Int) {
        let everything = others + [transaction]
        let allTime = DateInterval(start: .distantPast, end: .distantFuture)
        let spent = SpendingAnalytics.spending(everything, in: allTime)
        let received = SpendingAnalytics.income(everything, in: allTime)
        return (spent, received)
    }

    // MARK: Category

    private var categoryPromptTitle: String {
        guard let proposal = categoryProposal else { return "Recategorize" }
        let noun = proposal.otherCount == 1 ? "transaction" : "transactions"
        return "Also recategorize \(proposal.otherCount) other \(transaction.merchant) \(noun)?"
    }

    private func categoryPromptMessage(for proposal: CategoryProposal) -> String {
        if let category = proposal.category {
            return "Choosing all also files future \(transaction.merchant) imports under \(category.name)."
        }
        return "Choosing all also stops filing future \(transaction.merchant) imports automatically."
    }

    private func categorySelectionChanged(to newValue: TransactionCategory?) {
        guard !isDeleted, newValue?.id != transaction.category?.id else { return }
        let newID = newValue?.id
        let others = LedgerStore.otherTransactions(sameMerchantAs: transaction, in: modelContext)
        let affected = others.filter { $0.category?.id != newID }.count
        if affected == 0 {
            // Nothing else to change: set it and remember it for future imports.
            withAnimation {
                _ = LedgerStore.setCategory(newValue, for: transaction, rememberForMerchant: true, in: modelContext)
            }
            successFeedback += 1
        } else {
            categoryProposal = CategoryProposal(category: newValue, otherCount: affected)
            categoryPromptRequest += 1
        }
    }

    /// Presents the "apply to all" question once the category list has
    /// finished popping (presenting during the transition can fail).
    private func presentCategoryPromptIfNeeded() async {
        guard categoryProposal != nil else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled, categoryProposal != nil, !isDeleted else { return }
        showsCategoryPrompt = true
    }

    private func applyCategory(_ category: TransactionCategory?, toWholeMerchant: Bool) {
        withAnimation {
            _ = LedgerStore.setCategory(
                category,
                for: transaction,
                applyToMerchant: toWholeMerchant,
                rememberForMerchant: toWholeMerchant,
                in: modelContext
            )
        }
        categorySelection = category
        categoryProposal = nil
        successFeedback += 1
    }

    /// Runs when the dialog closes, whichever way. If it was cancelled the
    /// picker selection goes back to the transaction's category.
    private func finishCategoryPrompt() {
        categoryProposal = nil
        guard !isDeleted else { return }
        categorySelection = transaction.category
    }

    // MARK: Edits

    private func fieldLostFocus(_ field: Field?) {
        switch field {
        case .merchant:
            commitMerchant()
        case .amount:
            commitAmount()
        case .notes:
            if !isDeleted { LedgerStore.save(modelContext) }
        case nil:
            break
        }
    }

    private func commitMerchant() {
        guard !isDeleted else { return }
        let trimmed = merchantDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            merchantDraft = transaction.merchant
            return
        }
        if trimmed != transaction.merchant {
            transaction.setMerchant(trimmed)
            LedgerStore.save(modelContext)
        }
        merchantDraft = transaction.merchant
    }

    private func commitAmount() {
        guard !isDeleted else { return }
        guard let parsed = TransactionInput.parseCents(amountText) else {
            amountText = Money.editableText(fromCents: abs(transaction.amountCents))
            return
        }
        let magnitude = abs(parsed)
        let signed = isMoneyIn ? -magnitude : magnitude
        if signed != transaction.amountCents {
            withAnimation {
                transaction.amountCents = signed
            }
            LedgerStore.save(modelContext)
        }
        amountText = Money.editableText(fromCents: magnitude)
    }

    private func commitDate(_ date: Date) {
        guard !isDeleted else { return }
        let noon = Calendar.current.noon(on: date)
        guard noon != transaction.date else { return }
        transaction.date = noon
        LedgerStore.save(modelContext)
    }

    private func commitPendingEdits() {
        guard !isDeleted else { return }
        commitMerchant()
        commitAmount()
        LedgerStore.save(modelContext)
    }

    private func markReviewed() {
        withAnimation(.snappy) {
            LedgerStore.setReviewed([transaction], true, in: modelContext)
        }
        successFeedback += 1
    }

    private func deleteTransaction() {
        focusedField = nil
        isDeleted = true
        LedgerStore.delete(transaction, in: modelContext)
        dismiss()
    }
}

// MARK: - Badge

private struct TransactionDetailBadge: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        TransactionDetailView(transaction: PreviewData.sampleTransaction)
    }
    .previewEnvironment()
}

#Preview("Needs review") {
    let transaction = PreviewData.sampleTransaction
    transaction.isReviewed = false
    return NavigationStack {
        TransactionDetailView(transaction: transaction)
    }
    .previewEnvironment()
}
