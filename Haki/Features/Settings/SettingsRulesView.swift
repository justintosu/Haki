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
        let targets: [MerchantRule] = offsets.map { rules[$0] }
        // Read everything before deleting: removing one merchant's rule also
        // removes its duplicates, which may be among the other targets.
        var keyedMerchants: [(key: String, name: String)] = []
        var seenKeys = Set<String>()
        var unkeyed: [MerchantRule] = []
        for rule in targets {
            let key = rule.merchantKey
            if key.isEmpty {
                unkeyed.append(rule)
            } else if seenKeys.insert(key).inserted {
                keyedMerchants.append((key: key, name: rule.merchantName))
            }
        }

        for rule in unkeyed {
            modelContext.delete(rule)
        }
        if !unkeyed.isEmpty {
            LedgerStore.save(modelContext)
        }
        for merchant in keyedMerchants {
            // Removes this merchant's rule and any duplicates of it.
            LedgerStore.setRule(merchantKey: merchant.key, merchantName: merchant.name,
                                category: nil, in: modelContext)
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
        CategoryPickerView(selection: selectionBinding, allowsNone: false)
    }

    /// Applies the choice as soon as the picker sets it. The picker pops right
    /// after setting the selection, so this doesn't wait for an `onChange` on
    /// a view that is on its way out.
    private var selectionBinding: Binding<TransactionCategory?> {
        Binding(
            get: { selection },
            set: { newValue in
                let previousID = selection?.id
                selection = newValue
                if let newValue, newValue.id != previousID {
                    apply(newValue)
                }
            }
        )
    }

    private func apply(_ category: TransactionCategory) {
        let key = rule.merchantKey
        if key.isEmpty {
            rule.category = category
            LedgerStore.save(modelContext)
        } else {
            LedgerStore.setRule(merchantKey: key, merchantName: rule.merchantName,
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
