//
//  SettingsCategoriesView.swift
//  Haki
//
//  Every category, grouped by kind. Tap one to edit it, use Edit to drag
//  categories into order (`sortOrder`, used everywhere categories are listed)
//  and "+" to add one.
//

import Foundation
import SwiftData
import SwiftUI

struct SettingsCategoriesView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.name)])
    private var categories: [TransactionCategory]

    @State private var editorTarget: SettingsCategoryEditorTarget?

    var body: some View {
        List {
            ForEach(CategoryKind.allCases) { kind in
                section(for: kind)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Categories")
        .overlay {
            if categories.isEmpty {
                emptyState
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !categories.isEmpty {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorTarget = SettingsCategoryEditorTarget.new
                } label: {
                    Label("Add Category", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            CategoryEditorView(category: target.category)
        }
    }

    // MARK: Sections

    @ViewBuilder
    private func section(for kind: CategoryKind) -> some View {
        let items = categories.filter { $0.kind == kind }
        if !items.isEmpty {
            Section {
                ForEach(items) { category in
                    Button {
                        editorTarget = SettingsCategoryEditorTarget.edit(category)
                    } label: {
                        SettingsCategoryRow(category: category)
                    }
                    .accessibilityHint("Opens the category editor")
                }
                .onMove { source, destination in
                    move(kind: kind, from: source, to: destination)
                }
            } header: {
                Text(kind.displayName)
            } footer: {
                Text(footerText(for: kind))
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No categories", systemImage: "square.grid.2x2")
        } description: {
            Text("Categories sort your transactions so you can see where your money goes and set budgets.")
        } actions: {
            Button("Restore built-in categories") {
                LedgerStore.ensureDefaultCategories(in: modelContext)
            }
            .buttonStyle(.borderedProminent)
            Button("Add a category") {
                editorTarget = SettingsCategoryEditorTarget.new
            }
        }
    }

    private func footerText(for kind: CategoryKind) -> String {
        switch kind {
        case .expense:
            "Spending categories count toward your spending and budgets. Tap Edit to drag them into the order you like."
        case .income:
            "Money you receive, like paychecks, interest and reimbursements."
        case .transfer:
            "Money moving between your own accounts, like card payments. Transfers never count as spending or income."
        }
    }

    // MARK: Actions

    /// Reorders within one kind, then renumbers every category so `sortOrder`
    /// stays unique and follows the order shown here.
    private func move(kind: CategoryKind, from source: IndexSet, to destination: Int) {
        var reordered = categories.filter { $0.kind == kind }
        reordered.move(fromOffsets: source, toOffset: destination)

        var ordered: [TransactionCategory] = []
        for group in CategoryKind.allCases {
            if group == kind {
                ordered.append(contentsOf: reordered)
            } else {
                ordered.append(contentsOf: categories.filter { $0.kind == group })
            }
        }
        for (index, category) in ordered.enumerated() where category.sortOrder != index {
            category.sortOrder = index
        }
        LedgerStore.save(modelContext)
    }
}

// MARK: - Editor target

/// Which category the editor sheet opens for. The id is captured up front so
/// identifying the sheet never reads a model that was just deleted.
private struct SettingsCategoryEditorTarget: Identifiable {
    let id: String
    let category: TransactionCategory?

    static var new: SettingsCategoryEditorTarget {
        SettingsCategoryEditorTarget(id: "new", category: nil)
    }

    static func edit(_ category: TransactionCategory) -> SettingsCategoryEditorTarget {
        SettingsCategoryEditorTarget(id: category.id.uuidString, category: category)
    }
}

// MARK: - Row

/// Icon, name, budget (for spending) and how many transactions use it.
private struct SettingsCategoryRow: View {
    let category: TransactionCategory

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(category.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(detailText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let budgetText {
                Text(budgetText)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "$600/mo" for spending categories with a budget.
    private var budgetText: String? {
        guard category.kind == .expense, let budget = category.monthlyBudgetCents, budget > 0 else { return nil }
        return Money.format(budget, showsCents: false) + "/mo"
    }

    private var detailText: String {
        let count = SettingsFormat.count(category.transactions.count, "transaction", "transactions")
        guard category.kind == .expense else { return count }
        let budget = category.hasBudget ? "Monthly budget" : "No budget"
        return budget + " · " + count
    }
}

#Preview {
    NavigationStack {
        SettingsCategoriesView()
    }
    .previewEnvironment()
}
