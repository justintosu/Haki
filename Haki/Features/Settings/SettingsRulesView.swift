//
//  SettingsRulesView.swift
//  Haki
//
//  Merchant rules ("always file Corner Cafe under Coffee"). They're created
//  when the user recategorizes a transaction and applies it to every
//  transaction from that merchant. Swipe to delete; tap to change the category.
//

import Foundation
import SwiftData
import SwiftUI

struct SettingsRulesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\MerchantRule.merchantName)])
    private var rules: [MerchantRule]

    var body: some View {
        List {
            if !rules.isEmpty {
                Section {
                    ForEach(rules) { rule in
                        NavigationLink {
                            SettingsRuleCategoryPicker(rule: rule)
                        } label: {
                            SettingsRuleRow(rule: rule)
                        }
                    }
                    .onDelete { offsets in
                        deleteRules(at: offsets)
                    }
                } header: {
                    Text(SettingsFormat.count(rules.count, "rule", "rules"))
                } footer: {
                    Text("Transactions from these merchants, including future imports, are filed under the category shown. Tap a rule to change its category, or swipe left to delete it.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Rules")
        .overlay {
            if rules.isEmpty {
                emptyState
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !rules.isEmpty {
                    EditButton()
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No rules yet", systemImage: "wand.and.stars")
        } description: {
            Text("Rules are created when you recategorize a transaction and choose to apply it to all transactions from that merchant. Haki then files that merchant's future imports for you.")
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        let targets = offsets.map { rules[$0] }
        for rule in targets {
            if rule.merchantKey.isEmpty {
                modelContext.delete(rule)
                LedgerStore.save(modelContext)
            } else {
                // Removes this rule and any duplicates for the same merchant.
                LedgerStore.setRule(merchantKey: rule.merchantKey, merchantName: rule.merchantName,
                                    category: nil, in: modelContext)
            }
        }
    }
}

// MARK: - Row

/// "Corner Cafe → ☕️ Coffee", wrapping onto two lines when space is tight.
private struct SettingsRuleRow: View {
    let rule: MerchantRule

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                merchantText
                    .layoutPriority(1)
                arrow(systemImage: "arrow.right")
                categoryLabel
            }
            VStack(alignment: .leading, spacing: 4) {
                merchantText
                HStack(spacing: 6) {
                    arrow(systemImage: "arrow.turn.down.right")
                    categoryLabel
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(merchantName), filed under \(categoryName)")
    }

    private var merchantName: String {
        rule.merchantName.isEmpty ? rule.merchantKey : rule.merchantName
    }

    private var categoryName: String {
        rule.category?.name ?? "Uncategorized"
    }

    private var merchantText: some View {
        Text(merchantName)
            .font(.body.weight(.medium))
            .lineLimit(1)
    }

    private var categoryLabel: some View {
        HStack(spacing: 6) {
            CategoryIcon(category: rule.category, size: 24)
            Text(categoryName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func arrow(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }
}

// MARK: - Changing a rule's category

/// Pushes the shared category picker for a rule and saves the choice.
private struct SettingsRuleCategoryPicker: View {
    let rule: MerchantRule

    @Environment(\.modelContext) private var modelContext
    @State private var selection: TransactionCategory?

    init(rule: MerchantRule) {
        self.rule = rule
        _selection = State(initialValue: rule.category)
    }

    var body: some View {
        CategoryPickerView(selection: $selection, allowsNone: false)
            .onChange(of: selection) { _, newValue in
                apply(newValue)
            }
    }

    private func apply(_ category: TransactionCategory?) {
        guard let category, category.id != rule.category?.id else { return }
        if rule.merchantKey.isEmpty {
            rule.category = category
            LedgerStore.save(modelContext)
        } else {
            LedgerStore.setRule(merchantKey: rule.merchantKey, merchantName: rule.merchantName,
                                category: category, in: modelContext)
        }
    }
}

// MARK: - Previews

/// Adds a few rules to the shared preview database (once).
private func seedPreviewRules() {
    let context = PreviewData.context
    let existing = (try? context.fetchCount(FetchDescriptor<MerchantRule>())) ?? 0
    guard existing == 0 else { return }
    let categories = LedgerStore.allCategories(in: context)
    let samples: [(merchant: String, seedKey: String)] = [
        ("Corner Cafe", "coffee"),
        ("Trader Joe's", "groceries"),
        ("Netflix", "subscriptions"),
        ("Harborline Fitness Club Membership", "health"),
    ]
    for sample in samples {
        let category = categories.first { $0.seedKey == sample.seedKey }
        LedgerStore.setRule(merchantKey: MerchantNormalizer.key(for: sample.merchant),
                            merchantName: sample.merchant, category: category, in: context)
    }
}

#Preview("With rules") {
    NavigationStack {
        SettingsRulesView()
    }
    .previewEnvironment()
    .onAppear {
        seedPreviewRules()
    }
}

#Preview("Empty") {
    NavigationStack {
        SettingsRulesView()
    }
    .previewEnvironment(empty: true)
}
