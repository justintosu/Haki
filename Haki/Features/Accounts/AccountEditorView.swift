//
//  AccountEditorView.swift
//  Haki
//
//  A sheet for adding an account or editing one: name, institution, type,
//  current balance, last digits and whether it counts toward net worth.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct AccountEditorView: View {
    /// The account to edit, or `nil` to create one.
    let account: Account?
    /// When set, deleting calls this instead of deleting right away, and the
    /// presenter deletes the account (with `LedgerStore.delete`) once the
    /// sheet is gone, so no screen reads a deleted model.
    private let onDelete: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var institution: String
    @State private var kind: AccountKind
    @State private var balanceText: String
    @State private var mask: String
    @State private var includeInNetWorth: Bool
    @State private var showsDeleteConfirmation = false
    @State private var transactionCount = 0
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case institution
        case balance
        case mask
    }

    init(account: Account?, onDelete: (() -> Void)? = nil) {
        self.account = account
        self.onDelete = onDelete
        _name = State(initialValue: account?.name ?? "")
        _institution = State(initialValue: account?.institution ?? "")
        _kind = State(initialValue: account?.kind ?? .checking)
        _balanceText = State(initialValue: account.map { Money.editableText(fromCents: $0.balanceCents) } ?? "")
        _mask = State(initialValue: account?.mask ?? "")
        _includeInNetWorth = State(initialValue: account?.includeInNetWorth ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                previewSection
                detailsSection
                typeSection
                balanceSection
                netWorthSection
                if account != nil {
                    deleteSection
                }
            }
            .navigationTitle(account == nil ? "New Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog("Delete this account?", isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Account", role: .destructive) {
                    deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
            .onAppear {
                if account == nil {
                    focusedField = .name
                }
            }
        }
    }

    // MARK: Sections

    /// A live preview of how the account will look in the list.
    private var previewSection: some View {
        Section {
            HStack(spacing: 12) {
                AccountKindIcon(kind: kind, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(trimmedName.isEmpty ? "Account name" : trimmedName)
                        .font(.headline)
                        .foregroundStyle(trimmedName.isEmpty ? Color.secondary : Color.primary)
                        .lineLimit(1)
                    Text(previewSubtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Money.format(parsedBalance ?? 0))
                        .font(.headline)
                        .monospacedDigit()
                    if kind.isLiability {
                        Text("owed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Preview")
            .accessibilityValue(previewAccessibilityValue)
        }
    }

    private var detailsSection: some View {
        Section {
            TextField("Account name", text: $name)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .institution }
            TextField("Institution (optional)", text: $institution)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focusedField, equals: .institution)
                .onSubmit { focusedField = .balance }
            TextField("Last 4 digits (optional)", text: $mask)
                .keyboardType(.numberPad)
                .focused($focusedField, equals: .mask)
                .onChange(of: mask) { _, newValue in
                    let digits = String(newValue.filter { $0.isASCII && $0.isNumber }.prefix(4))
                    if digits != newValue {
                        mask = digits
                    }
                }
        } header: {
            Text("Account")
        }
    }

    private var typeSection: some View {
        Section {
            Picker("Type", selection: $kind) {
                ForEach(AccountKind.allCases) { option in
                    Label(option.displayName, systemImage: option.systemImage)
                        .tag(option)
                }
            }
            .pickerStyle(.navigationLink)
        } footer: {
            Text(typeFooter)
        }
    }

    private var balanceSection: some View {
        Section {
            HStack {
                Text(kind.isLiability ? "Amount owed" : "Balance")
                Spacer(minLength: 12)
                TextField(Money.editableText(fromCents: 0), text: $balanceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .focused($focusedField, equals: .balance)
                    .accessibilityLabel(kind.isLiability ? "Amount owed" : "Current balance")
            }
        } header: {
            Text("Current balance")
        } footer: {
            Text(balanceFooter)
                .foregroundStyle(balanceIsInvalid ? Color.hakiNegative : Color.secondary)
        }
    }

    private var netWorthSection: some View {
        Section {
            Toggle("Include in net worth", isOn: $includeInNetWorth)
        } footer: {
            Text("Turn this off to keep tracking an account without counting it, like a joint account someone else manages.")
        }
    }

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                transactionCount = account?.transactions.count ?? 0
                showsDeleteConfirmation = true
            } label: {
                Text("Delete Account")
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: Derived values

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedBalance: Int? {
        AccountsStyle.parseCents(balanceText)
    }

    /// Text that isn't a number. An empty field means a zero balance.
    private var balanceIsInvalid: Bool {
        !balanceText.trimmingCharacters(in: .whitespaces).isEmpty && parsedBalance == nil
    }

    private var canSave: Bool {
        !trimmedName.isEmpty && !balanceIsInvalid
    }

    private var previewSubtitle: String {
        let trimmedInstitution = institution.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = [kind.displayName, trimmedInstitution, AccountsStyle.maskText(mask)]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var previewAccessibilityValue: String {
        let nameText = trimmedName.isEmpty ? "Unnamed account" : trimmedName
        let amount = Money.format(parsedBalance ?? 0)
        let balance = kind.isLiability ? amount + " owed" : amount
        return nameText + ", " + previewSubtitle + ", " + balance
    }

    private var typeFooter: String {
        if kind.isLiability { return "Credit cards and loans count as money you owe." }
        return kind.displayName + " accounts count as assets."
    }

    private var balanceFooter: String {
        if balanceIsInvalid { return "Enter an amount, like 1,234.56." }
        if kind.isLiability {
            return "Amount owed: what you currently owe. It's subtracted from your net worth."
        }
        if account == nil {
            return "What's in the account today. You can update it any time from the account's page."
        }
        return "Changing the balance records it in the account's history."
    }

    private var deleteMessage: String {
        switch transactionCount {
        case 0:
            return "Deletes the account and its balance history. This can't be undone."
        case 1:
            return "Deletes the account, its 1 transaction and its balance history. This can't be undone."
        default:
            return "Deletes the account, its \(transactionCount) transactions and its balance history. This can't be undone."
        }
    }

    // MARK: Actions

    private func save() {
        guard canSave else { return }
        let cents = parsedBalance ?? 0
        let trimmedInstitution = institution.trimmingCharacters(in: .whitespacesAndNewlines)
        if let account {
            account.name = trimmedName
            account.institution = trimmedInstitution
            account.kind = kind
            account.mask = mask
            account.includeInNetWorth = includeInNetWorth
            if cents != account.balanceCents {
                LedgerStore.updateBalance(of: account, to: cents, in: modelContext)
            } else {
                LedgerStore.save(modelContext)
            }
        } else {
            let created = LedgerStore.addAccount(
                in: modelContext,
                name: trimmedName,
                institution: trimmedInstitution,
                kind: kind,
                balanceCents: cents,
                mask: mask
            )
            if !includeInNetWorth {
                created.includeInNetWorth = false
                LedgerStore.save(modelContext)
            }
        }
        dismiss()
    }

    private func deleteAccount() {
        guard let account else { return }
        if let onDelete {
            onDelete()
            dismiss()
        } else {
            dismiss()
            LedgerStore.delete(account, in: modelContext)
        }
    }
}

#Preview("New account") {
    AccountEditorView(account: nil)
        .previewEnvironment()
}

#Preview("Edit account") {
    AccountEditorView(account: PreviewData.sampleAccount)
        .previewEnvironment()
}
