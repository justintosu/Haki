//
//  AccountBalanceUpdateView.swift
//  Haki
//
//  A small sheet for entering an account's current balance. Saving records
//  it in the balance history (`LedgerStore.updateBalance`).
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct AccountBalanceUpdateView: View {
    let account: Account
    private let onSave: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var amountText: String
    @FocusState private var isAmountFocused: Bool

    /// - Parameter onSave: called after the new balance is saved (e.g. for a haptic).
    init(account: Account, onSave: @escaping () -> Void = {}) {
        self.account = account
        self.onSave = onSave
        _amountText = State(initialValue: Money.editableText(fromCents: account.balanceCents))
    }

    var body: some View {
        NavigationStack {
            Form {
                accountSection
                amountSection
            }
            .navigationTitle("Update Balance")
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
                    .disabled(parsedCents == nil)
                }
            }
            .onAppear {
                isAmountFocused = true
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                AccountKindIcon(kind: account.kind)
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(currentText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var amountSection: some View {
        Section {
            TextField(Money.editableText(fromCents: 0), text: $amountText)
                .keyboardType(.decimalPad)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .focused($isAmountFocused)
                .accessibilityLabel(account.isLiability ? "Amount owed" : "New balance")
        } header: {
            Text(account.isLiability ? "Amount owed today" : "Balance today")
        } footer: {
            Text(footerText)
                .foregroundStyle(isInvalid ? Color.hakiNegative : Color.secondary)
        }
    }

    // MARK: Logic

    private var parsedCents: Int? {
        AccountsStyle.parseCents(amountText)
    }

    private var isInvalid: Bool {
        !amountText.trimmingCharacters(in: .whitespaces).isEmpty && parsedCents == nil
    }

    private var currentText: String {
        let amount = Money.format(account.balanceCents)
        let current = account.isLiability ? amount + " owed" : amount
        return current + " · " + AccountsStyle.updatedText(account.balanceUpdatedAt).lowercased()
    }

    private var footerText: String {
        if isInvalid { return "Enter an amount, like 1,234.56." }
        guard let cents = parsedCents else {
            return account.isLiability ? "Enter what you owe today." : "Enter the balance shown by your bank today."
        }
        let difference = cents - account.balanceCents
        if difference == 0 {
            return "Saving confirms the balance is still current and records it in the history."
        }
        let change = Money.format(difference, alwaysShowsSign: true)
        return "That's " + change + " since the last update. It's added to the balance history."
    }

    private func save() {
        guard let cents = parsedCents else { return }
        LedgerStore.updateBalance(of: account, to: cents, in: modelContext)
        onSave()
        dismiss()
    }
}

#Preview {
    AccountBalanceUpdateView(account: PreviewData.sampleAccount)
        .previewEnvironment()
}
