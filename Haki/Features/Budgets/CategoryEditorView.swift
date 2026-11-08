//
//  CategoryEditorView.swift
//  Haki
//
//  Creates or edits a category: name, emoji, color, kind and (for spending
//  categories) a monthly budget, with a live preview of the icon. Editing
//  also offers "Delete Category".
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct CategoryEditorView: View {
    /// `nil` creates a new category.
    let category: TransactionCategory?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.name)])
    private var categories: [TransactionCategory]

    @State private var name: String
    @State private var emoji: String
    @State private var colorHex: String
    @State private var kind: CategoryKind
    @State private var hasBudget: Bool
    @State private var budgetText: String
    @State private var showsDeleteConfirmation = false
    /// Set right before deleting, so the body never reads a deleted model.
    @State private var didDelete = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case emoji
        case budget
    }

    init(category: TransactionCategory?) {
        self.category = category
        // A category deleted while this sheet was being dismissed must not be read.
        let source: TransactionCategory? = Self.isLive(category) ? category : nil
        let budget = source?.monthlyBudgetCents ?? 0
        _name = State(initialValue: source?.name ?? "")
        _emoji = State(initialValue: source?.emoji ?? "🏷️")
        _colorHex = State(initialValue: source?.colorHex ?? Self.defaultColorHex)
        _kind = State(initialValue: source?.kind ?? .expense)
        _hasBudget = State(initialValue: budget > 0)
        _budgetText = State(initialValue: budget > 0 ? Money.editableText(fromCents: budget) : "")
    }

    var body: some View {
        NavigationStack {
            Group {
                if didDelete {
                    Color.clear
                } else {
                    form
                }
            }
            .navigationTitle(title)
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
            .confirmationDialog(deleteTitle, isPresented: $showsDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete Category", role: .destructive) {
                    deleteCategory()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
        }
    }

    private var form: some View {
        Form {
            previewSection
            nameSection
            emojiSection
            colorSection
            kindSection
            if kind == .expense {
                budgetSection
            }
            if category != nil {
                deleteSection
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: emoji) { oldValue, newValue in
            keepSingleCharacter(oldValue: oldValue, newValue: newValue)
        }
        .onAppear {
            if category == nil {
                focusedField = .name
            }
        }
    }

    private var title: String {
        category == nil ? "New Category" : "Edit Category"
    }

    // MARK: Preview

    private var previewSection: some View {
        Section {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color(hex: colorHex).opacity(0.18))
                    Text(emoji.isEmpty ? "?" : emoji)
                        .font(.system(size: 38))
                }
                .frame(width: 80, height: 80)
                Text(previewName)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(previewSubtitle)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(previewAccessibilityLabel)
        }
        .listRowBackground(Color.clear)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var previewName: String {
        if !trimmedName.isEmpty { return trimmedName }
        return category == nil ? "New Category" : "Untitled"
    }

    private var previewSubtitle: String {
        guard kind == .expense else { return kind.displayName }
        if hasBudget, let cents = parsedBudgetCents {
            return "\(kind.displayName) · \(Money.format(cents, showsCents: false)) a month"
        }
        return "\(kind.displayName) · No budget"
    }

    private var previewAccessibilityLabel: String {
        "Preview: \(emoji) \(previewName), \(previewSubtitle)"
    }

    // MARK: Name

    private var nameSection: some View {
        Section {
            TextField("Name", text: $name)
                .focused($focusedField, equals: .name)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
        } header: {
            Text("Name")
        } footer: {
            if let duplicateWarning {
                Text(duplicateWarning)
            }
        }
    }

    private var duplicateWarning: String? {
        let lowered = trimmedName.lowercased()
        guard !lowered.isEmpty else { return nil }
        let editingID = category?.id
        let clash = categories.contains { $0.id != editingID && $0.name.lowercased() == lowered }
        return clash ? "You already have a category with this name." : nil
    }

    // MARK: Emoji

    private var emojiSection: some View {
        Section {
            TextField("Emoji", text: $emoji)
                .font(.title2)
                .focused($focusedField, equals: .emoji)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Self.suggestedEmoji, id: \.self) { option in
                        emojiButton(option)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        } header: {
            Text("Emoji")
        } footer: {
            Text("Type any emoji, or pick one above.")
        }
    }

    private func emojiButton(_ option: String) -> some View {
        let isSelected = option == emoji
        return Button {
            emoji = option
        } label: {
            Text(option)
                .font(.title2)
                .padding(6)
                .background(isSelected ? Color(hex: colorHex).opacity(0.25) : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    /// Keeps a single character: the first one of whatever was just typed,
    /// so typing a new emoji after the current one replaces it.
    private func keepSingleCharacter(oldValue: String, newValue: String) {
        guard newValue.count > 1 else { return }
        let typed: Substring
        if !oldValue.isEmpty && newValue.hasPrefix(oldValue) {
            typed = newValue.dropFirst(oldValue.count)
        } else {
            typed = Substring(newValue)
        }
        let cleaned = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = cleaned.first {
            emoji = String(first)
        } else if let first = newValue.first {
            emoji = String(first)
        }
    }

    // MARK: Color

    private var colorSection: some View {
        Section("Color") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 12)], spacing: 12) {
                ForEach(swatches, id: \.self) { hex in
                    colorSwatch(hex)
                }
            }
            .padding(.vertical, 6)
        }
    }

    /// The palette, plus the current color first if it isn't one of them.
    private var swatches: [String] {
        let palette = CategoryPalette.hexColors
        let current = colorHex.uppercased()
        if palette.contains(where: { $0.uppercased() == current }) {
            return palette
        }
        return [colorHex] + palette
    }

    private func colorSwatch(_ hex: String) -> some View {
        let isSelected = hex.uppercased() == colorHex.uppercased()
        return Button {
            colorHex = hex
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: hex))
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(colorName(hex))
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private func colorName(_ hex: String) -> String {
        Self.colorNames[hex.uppercased()] ?? "Custom color"
    }

    // MARK: Kind

    private var kindSection: some View {
        Section {
            Picker("Type", selection: $kind) {
                ForEach(CategoryKind.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Type")
        } footer: {
            Text(kindFooter)
        }
    }

    private var kindFooter: String {
        switch kind {
        case .expense:
            return "Spending categories count toward your spending totals and can have a monthly budget."
        case .income:
            return "Income categories count money you receive, like paychecks and interest."
        case .transfer:
            return "Transfers are money moving between your own accounts, like card payments. They're left out of spending and income."
        }
    }

    // MARK: Budget

    private var budgetSection: some View {
        Section {
            Toggle("Set a monthly budget", isOn: $hasBudget.animation())
            if hasBudget {
                HStack(spacing: 12) {
                    Text("Monthly budget")
                    Spacer(minLength: 12)
                    TextField(Money.format(0, showsCents: false), text: $budgetText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .focused($focusedField, equals: .budget)
                        .accessibilityLabel("Monthly budget amount")
                }
            }
        } header: {
            Text("Budget")
        } footer: {
            budgetFooter
        }
    }

    private var budgetFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasBudget && !budgetText.isEmpty && parsedBudgetCents == nil {
                Text("Enter an amount greater than zero.")
                    .foregroundStyle(Color.hakiNegative)
            }
            if let suggestion = suggestedBudgetCents {
                Text(suggestionText(suggestion))
                if !hasBudget || parsedBudgetCents != suggestion {
                    Button(useSuggestionTitle(suggestion)) {
                        applySuggestion(suggestion)
                    }
                    .font(.footnote.weight(.semibold))
                }
            } else {
                Text("Haki tracks this category against its budget every month and shows whether you're on pace.")
            }
        }
    }

    private var parsedBudgetCents: Int? {
        let separator = Character(Locale.current.decimalSeparator ?? ".")
        guard let cents = Money.parseCents(budgetText, decimalSeparator: separator), cents > 0 else {
            return nil
        }
        return cents
    }

    /// The last three full months' average spending in this category, rounded
    /// up to a whole $5, as a starting point for a budget.
    private var suggestedBudgetCents: Int? {
        guard !didDelete, let category, Self.isLive(category), category.kind == .expense else { return nil }
        let months = MonthInterval.trailing(3, endingAt: MonthInterval.current().previous)
        let average = SpendingAnalytics.averageMonthlySpending(category.transactions, months: months)
        guard average >= 100 else { return nil }
        return ((average + 499) / 500) * 500
    }

    private func suggestionText(_ cents: Int) -> String {
        "You've spent about \(Money.format(cents, showsCents: false)) a month here recently."
    }

    private func useSuggestionTitle(_ cents: Int) -> String {
        "Use \(Money.format(cents, showsCents: false))"
    }

    private func applySuggestion(_ cents: Int) {
        budgetText = Money.editableText(fromCents: cents)
        withAnimation {
            hasBudget = true
        }
    }

    // MARK: Delete

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showsDeleteConfirmation = true
            } label: {
                Label("Delete Category", systemImage: "trash")
            }
        } footer: {
            Text("Its transactions stay, but become uncategorized.")
        }
    }

    private var deleteTitle: String {
        trimmedName.isEmpty ? "Delete this category?" : "Delete “\(trimmedName)”?"
    }

    private var deleteMessage: String {
        guard !didDelete, let category, Self.isLive(category) else { return "" }
        let count = category.transactions.count
        var parts: [String] = []
        switch count {
        case 0:
            parts.append("No transactions use this category.")
        case 1:
            parts.append("Its 1 transaction will become uncategorized.")
        default:
            parts.append("Its \(count) transactions will become uncategorized.")
        }
        if !category.rules.isEmpty {
            parts.append("Merchant rules that use it will be removed.")
        }
        if !category.recurringItems.isEmpty {
            parts.append("Recurring bills in it will have no category.")
        }
        parts.append("This can't be undone.")
        return parts.joined(separator: " ")
    }

    // MARK: Saving

    private var canSave: Bool {
        guard !didDelete, !trimmedName.isEmpty else { return false }
        if kind == .expense && hasBudget {
            return parsedBudgetCents != nil
        }
        return true
    }

    private func save() {
        let finalName = trimmedName
        guard !finalName.isEmpty else { return }
        let typedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalEmoji = typedEmoji.isEmpty ? "📦" : String(typedEmoji.prefix(1))
        let budget: Int? = (kind == .expense && hasBudget) ? parsedBudgetCents : nil

        if let category {
            category.name = finalName
            category.emoji = finalEmoji
            category.colorHex = colorHex
            category.kind = kind
            category.monthlyBudgetCents = budget
        } else {
            let nextSortOrder = (categories.map { $0.sortOrder }.max() ?? -1) + 1
            let newCategory = TransactionCategory(
                name: finalName,
                emoji: finalEmoji,
                colorHex: colorHex,
                kind: kind,
                monthlyBudgetCents: budget,
                sortOrder: nextSortOrder
            )
            modelContext.insert(newCategory)
        }
        LedgerStore.save(modelContext)
        dismiss()
    }

    private func deleteCategory() {
        guard let category else { return }
        didDelete = true
        modelContext.delete(category)
        LedgerStore.save(modelContext)
        dismiss()
    }

    // MARK: Helpers

    /// Whether a category can still be read (it exists and hasn't been deleted).
    private static func isLive(_ category: TransactionCategory?) -> Bool {
        guard let category else { return false }
        return !category.isDeleted && category.modelContext != nil
    }

    private static var defaultColorHex: String {
        CategoryPalette.hexColors.first ?? "#3FB97B"
    }

    private static let suggestedEmoji: [String] = [
        "🛒", "🍽️", "☕️", "🛍️", "🚗", "⛽️", "✈️", "🏠", "💡", "📺", "🎬", "🎮",
        "💪", "💊", "💇", "🐶", "👶", "🎁", "📚", "🎓", "🍷", "💼", "💰", "🧾", "📦",
    ]

    private static let colorNames: [String: String] = [
        "#3FB97B": "Green",
        "#1FA67A": "Emerald",
        "#2BB5C9": "Teal",
        "#4F8EF7": "Blue",
        "#6C63FF": "Indigo",
        "#9B6DF2": "Purple",
        "#E05FA3": "Magenta",
        "#F78FB3": "Pink",
        "#EB5757": "Red",
        "#F2994A": "Orange",
        "#E2B93B": "Yellow",
        "#A0673D": "Brown",
        "#8D7B68": "Taupe",
        "#7F8C8D": "Slate",
        "#8E8E93": "Gray",
        "#34495E": "Navy",
    ]
}

#Preview("New") {
    CategoryEditorView(category: nil)
        .previewEnvironment()
}

#Preview("Edit") {
    CategoryEditorView(category: PreviewData.sampleCategory)
        .previewEnvironment()
}
