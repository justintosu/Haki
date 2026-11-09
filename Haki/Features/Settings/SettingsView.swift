//
//  SettingsView.swift
//  Haki
//
//  The Settings sheet (presented from Home and Profile): your account and
//  privacy, importing and managing money data, categories and merchant
//  rules, and about the app.
//

import Foundation
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Environment(HevySyncService.self) private var hevy

    @Query private var accounts: [Account]
    @Query private var categories: [TransactionCategory]
    @Query private var rules: [MerchantRule]
    @Query private var recurringItems: [RecurringItem]

    /// Owned by Recurring; cleared on "Erase all data" so a fresh start shows every suggestion again.
    @AppStorage("dismissedRecurringSuggestions") private var dismissedRecurringSuggestions = ""

    @State private var showsSampleDataConfirmation = false
    @State private var showsRemoveSampleDataConfirmation = false
    @State private var showsEraseConfirmation = false
    /// Counted rather than queried: Settings only shows the number, and a
    /// query would load every transaction.
    @State private var transactionCount = 0
    @State private var statusMessage: String?
    @State private var feedbackTrigger = 0

    var body: some View {
        NavigationStack {
            List {
                profileSection
                AccountSettingsSection()
                dataSection
                organizeSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .onAppear {
                // Also runs when coming back from Import CSV.
                refreshTransactionCount()
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Load sample data?", isPresented: $showsSampleDataConfirmation, titleVisibility: .visible) {
                Button("Load Sample Data") {
                    loadSampleData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Adds demo accounts with balance history, a few months of transactions and recurring bills so you can explore Haki. They count toward your totals until you remove them here. Suggested budgets are added only when Haki is empty; your own transactions and budgets aren't changed.")
            }
            .confirmationDialog("Remove sample data?", isPresented: $showsRemoveSampleDataConfirmation, titleVisibility: .visible) {
                Button("Remove Sample Data", role: .destructive) {
                    removeSampleData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Deletes the demo accounts with everything in them, including transactions you added to them, plus the demo bills and the suggested budgets you haven't changed. The rest of your data stays as it is.")
            }
            .confirmationDialog("Erase all data?", isPresented: $showsEraseConfirmation, titleVisibility: .visible) {
                Button("Erase All Data", role: .destructive) {
                    eraseAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(eraseMessage)
            }
        }
        .sensoryFeedback(.success, trigger: feedbackTrigger)
        .onChange(of: router.selectedTab) { _, _ in
            // Something inside (e.g. "Review them" after an import) switched
            // tabs: get out of the way so the new tab is visible.
            dismiss()
        }
    }

    // MARK: Sections

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                SettingsIconTile(systemImage: "chart.pie.fill", tint: .accentColor, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Haki")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    // Breaks between the parts, never inside one or after a "·".
                    ViewThatFits(in: .horizontal) {
                        Text(statsParts.joined(separator: " · "))
                            .lineLimit(1)
                        Text(statsParts.prefix(2).joined(separator: " · ") + "\n" + statsParts[2])
                        Text(statsParts.joined(separator: "\n"))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(statsText)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    private var dataSection: some View {
        Section {
            NavigationLink {
                CSVImportView()
            } label: {
                SettingsIconLabel("Import from CSV", systemImage: "tray.and.arrow.down.fill", tint: .accentColor)
            }

            Button {
                showsSampleDataConfirmation = true
            } label: {
                SettingsIconLabel("Load sample data", systemImage: "sparkles", tint: .purple)
            }
            .accessibilityHint("Adds demo accounts and transactions")

            if LedgerStore.hasSampleData(accounts: accounts, bills: recurringItems, categories: categories) {
                Button {
                    showsRemoveSampleDataConfirmation = true
                } label: {
                    SettingsIconLabel("Remove sample data", systemImage: "minus.circle.fill", tint: .gray)
                }
                .accessibilityHint("Asks for confirmation before deleting the demo accounts, transactions and bills")
            }

            Button(role: .destructive) {
                showsEraseConfirmation = true
            } label: {
                SettingsIconLabel("Erase all data", systemImage: "trash.fill", tint: .red, titleColor: .hakiNegative)
            }
            .accessibilityHint("Asks for confirmation before deleting everything")
        } header: {
            Text("Data")
        } footer: {
            if let statusMessage {
                Label(statusMessage, systemImage: "checkmark.circle.fill")
            } else {
                Text("Bring in transactions exported from your bank, or explore Haki with demo data first.")
            }
        }
    }

    private var organizeSection: some View {
        Section {
            NavigationLink {
                SettingsCategoriesView()
            } label: {
                LabeledContent {
                    Text(categories.count.formatted())
                        .monospacedDigit()
                } label: {
                    SettingsIconLabel("Categories", systemImage: "square.grid.2x2.fill", tint: .orange)
                }
            }

            NavigationLink {
                SettingsRulesView()
            } label: {
                LabeledContent {
                    Text(rules.count.formatted())
                        .monospacedDigit()
                } label: {
                    SettingsIconLabel("Rules", systemImage: "wand.and.stars", tint: .indigo)
                }
            }
        } header: {
            Text("Organize")
        } footer: {
            Text("Rules file a merchant's transactions under the category you chose, including future imports.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent {
                Text(versionText)
                    .monospacedDigit()
            } label: {
                SettingsIconLabel("Version", systemImage: "info.circle.fill", tint: .gray)
            }

            SettingsNoteRow(
                title: "Private by design",
                message: "Your money data — accounts, transactions, budgets and bills — stays on this device, except what you choose to send to Haki's AI (Ask Haki and photo features), which is processed by Anthropic's Claude and not stored by Haki. Your profile, posts and connected brokerage holdings are saved to your Haki account. Other people only ever see your portfolio as percentages, and only if you share it.",
                systemImage: "lock.fill",
                tint: .blue
            )

            SettingsNoteRow(
                title: "Connections",
                message: "Connect a brokerage read-only from the Invest tab. Automatic bank transaction sync isn't available yet, so export a CSV from your bank and use Import from CSV.",
                systemImage: "building.columns.fill",
                tint: .teal
            )

            NavigationLink {
                CommunityGuidelinesView()
            } label: {
                SettingsIconLabel("Community Guidelines", systemImage: "person.2.fill", tint: .green)
            }

            if let url = AppInfo.privacyPolicyURL {
                Link(destination: url) {
                    SettingsIconLabel("Privacy Policy", systemImage: "hand.raised.fill", tint: .blue)
                }
                .accessibilityHint("Opens Haki's privacy policy")
            }

            if let url = AppInfo.termsURL {
                Link(destination: url) {
                    SettingsIconLabel("Terms of Use", systemImage: "doc.text.fill", tint: .gray)
                }
                .accessibilityHint("Opens Haki's terms of use")
            }

            if let supportURL {
                Link(destination: supportURL) {
                    SettingsIconLabel("Contact support", systemImage: "envelope.fill", tint: .blue)
                }
                .accessibilityHint("Opens an email to Haki support")
            }
        } header: {
            Text("About")
        }
    }

    /// A mailto: link to `AppInfo.supportEmail`, or nil while it isn't set.
    private var supportURL: URL? {
        let email = AppInfo.supportEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { return nil }
        return URL(string: "mailto:\(email)")
    }

    // MARK: Text

    /// "3 accounts", "120 transactions", "14 categories".
    private var statsParts: [String] {
        [
            SettingsFormat.count(accounts.count, "account", "accounts"),
            SettingsFormat.count(transactionCount, "transaction", "transactions"),
            SettingsFormat.count(categories.count, "category", "categories"),
        ]
    }

    /// Spoken as one phrase whichever layout is showing.
    private var statsText: String {
        statsParts.joined(separator: ", ")
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var eraseMessage: String {
        var parts: [String] = []
        if !accounts.isEmpty { parts.append(SettingsFormat.count(accounts.count, "account", "accounts")) }
        if transactionCount > 0 { parts.append(SettingsFormat.count(transactionCount, "transaction", "transactions")) }
        if !recurringItems.isEmpty { parts.append(SettingsFormat.count(recurringItems.count, "bill", "bills")) }
        if !rules.isEmpty { parts.append(SettingsFormat.count(rules.count, "rule", "rules")) }

        let reset = "Your food log, workouts, wardrobe, notes, flashcards and assistant chats on this device are deleted too, and your categories go back to the built-in set. This can't be undone."
        guard !parts.isEmpty else { return reset }
        let list: String
        if parts.count == 1 {
            list = parts[0]
        } else {
            list = parts.dropLast().joined(separator: ", ") + " and " + (parts.last ?? "")
        }
        return "This permanently deletes \(list) from this device. " + reset
    }

    // MARK: Actions

    private func loadSampleData() {
        let before = (try? modelContext.fetchCount(FetchDescriptor<TransactionRecord>())) ?? 0
        withAnimation(.snappy) {
            LedgerStore.loadSampleData(into: modelContext)
        }
        let after = (try? modelContext.fetchCount(FetchDescriptor<TransactionRecord>())) ?? 0
        transactionCount = after
        if after > before {
            statusMessage = "Sample data added. Take a look around Home, where Budgets, Recurring and Accounts open too."
            feedbackTrigger += 1
        } else {
            statusMessage = "Sample data is already loaded."
        }
    }

    private func removeSampleData() {
        withAnimation(.snappy) {
            LedgerStore.removeSampleData(in: modelContext)
        }
        refreshTransactionCount()
        statusMessage = "Sample data removed."
        feedbackTrigger += 1
    }

    private func eraseAllData() {
        // Stop a Hevy sync first, so it can't write its old sync time back after the erase.
        hevy.forgetSyncedWorkouts()
        withAnimation(.snappy) {
            LedgerStore.eraseAllData(in: modelContext)
            FoodStore.eraseAll(in: modelContext)
            WorkoutStore.eraseAll(in: modelContext)
            WardrobeStore.eraseAll(in: modelContext)
            StudyStore.eraseAll(in: modelContext)
            AssistantStore.eraseAll(in: modelContext)
        }
        refreshTransactionCount()
        dismissedRecurringSuggestions = ""
        statusMessage = "All data erased. The built-in categories were restored."
        feedbackTrigger += 1
    }

    private func refreshTransactionCount() {
        transactionCount = (try? modelContext.fetchCount(FetchDescriptor<TransactionRecord>())) ?? 0
    }
}

#Preview("Sample data") {
    SettingsView()
        .previewEnvironment()
}

#Preview("Empty") {
    SettingsView()
        .previewEnvironment(empty: true)
}
