//
//  RecurringView.swift
//  Haki
//
//  Recurring bills: what they cost per month, which of this month's due
//  dates are paid, upcoming or late, every tracked bill, and suggestions for
//  repeating charges found in the transaction history.
//

import Foundation
import SwiftData
import SwiftUI

/// What the editor sheet is open for.
private enum RecurringEditorTarget: Identifiable {
    case new
    case edit(RecurringItem)
    case candidate(RecurringCandidate)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let item): "edit-" + item.id.uuidString
        case .candidate(let candidate): "candidate-" + candidate.merchantKey
        }
    }
}

struct RecurringView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \RecurringItem.name)
    private var items: [RecurringItem]

    @Query(sort: \TransactionRecord.date, order: .reverse)
    private var transactions: [TransactionRecord]

    @Query(sort: [SortDescriptor(\TransactionCategory.sortOrder), SortDescriptor(\TransactionCategory.name)])
    private var categories: [TransactionCategory]

    /// Merchant keys of dismissed suggestions, one per line.
    @AppStorage("dismissedRecurringSuggestions") private var dismissedSuggestionsText = ""

    @State private var editorTarget: RecurringEditorTarget?
    /// "Today" for every section. Refreshed when the app comes back to the foreground.
    @State private var now = Date.now
    @State private var addedSuggestions = 0
    /// Repeating charges found in the whole history. Scanning every
    /// transaction is expensive, so it runs when the screen appears, when
    /// transactions are added or removed, and when the app returns to the
    /// foreground, rather than on every render (opening a bill, pausing one,
    /// dismissing a suggestion).
    @State private var detectedCandidates: [RecurringCandidate] = []

    var body: some View {
        let model = RecurringScreenModel(
            items: items,
            transactions: transactions,
            candidates: detectedCandidates,
            dismissedKeys: Set(dismissedKeys),
            now: now
        )
        content(for: model)
            .navigationTitle("Recurring")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorTarget = .new
                    } label: {
                        Label("Add bill", systemImage: "plus")
                    }
                    .accessibilityLabel("Add recurring bill")
                }
            }
            .sheet(item: $editorTarget) { target in
                editor(for: target)
            }
            .sensoryFeedback(.success, trigger: addedSuggestions)
            .onAppear {
                refresh()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { refresh() }
            }
            .onChange(of: transactions.count) {
                detectCandidates(asOf: now)
            }
    }

    // MARK: Content

    @ViewBuilder
    private func content(for model: RecurringScreenModel) -> some View {
        if !model.hasBills && model.suggestions.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    if model.hasBills {
                        trackedCards(for: model)
                    } else {
                        RecurringIntroCard(suggestionCount: model.suggestions.count)
                        suggestionsCard(model.suggestions)
                    }
                    if !dismissedKeys.isEmpty {
                        restoreDismissedButton
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.hakiBackground)
        }
    }

    @ViewBuilder
    private func trackedCards(for model: RecurringScreenModel) -> some View {
        RecurringSummaryCard(model: model)
        if !model.activeBills.isEmpty {
            RecurringThisMonthCard(model: model, onSelect: { editorTarget = .edit($0) })
            RecurringBillsCard(
                title: "All bills",
                systemImage: "list.bullet",
                subtitle: "Soonest due first. Tap a bill to edit it.",
                bills: model.activeBills,
                now: model.now,
                onSelect: { editorTarget = .edit($0) },
                onToggleActive: { toggleActive($0) }
            )
        }
        if !model.pausedBills.isEmpty {
            RecurringBillsCard(
                title: "Paused",
                systemImage: "pause.circle",
                subtitle: "Paused bills aren't counted in your totals or this month's schedule.",
                bills: model.pausedBills,
                now: model.now,
                onSelect: { editorTarget = .edit($0) },
                onToggleActive: { toggleActive($0) }
            )
        }
        if !model.suggestions.isEmpty {
            suggestionsCard(model.suggestions)
        }
    }

    private func suggestionsCard(_ suggestions: [RecurringCandidate]) -> some View {
        RecurringSuggestionsCard(
            suggestions: suggestions,
            categoriesByID: categoriesByID,
            onOpen: { editorTarget = .candidate($0) },
            onAdd: { add($0) },
            onDismiss: { dismissSuggestion($0) }
        )
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No recurring bills yet", systemImage: "arrow.triangle.2.circlepath")
        } description: {
            Text("Track rent, subscriptions and utilities to see what they cost each month, what's due next and what's already paid. As your transactions come in, Haki suggests bills it spots.")
        } actions: {
            Button("Add a bill") {
                editorTarget = .new
            }
            .buttonStyle(.borderedProminent)
            if !dismissedKeys.isEmpty {
                Button("Show dismissed suggestions") {
                    restoreDismissedSuggestions()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.hakiBackground)
    }

    private var restoreDismissedButton: some View {
        Button {
            restoreDismissedSuggestions()
        } label: {
            Label(restoreTitle, systemImage: "arrow.uturn.backward")
        }
        .font(.footnote)
        .padding(.top, 4)
    }

    private var restoreTitle: String {
        let count = RecurringFormat.count(dismissedKeys.count, "dismissed suggestion", "dismissed suggestions")
        return "Show \(count) again"
    }

    @ViewBuilder
    private func editor(for target: RecurringEditorTarget) -> some View {
        switch target {
        case .new:
            RecurringEditorView(item: nil)
        case .edit(let item):
            RecurringEditorView(item: item)
        case .candidate(let candidate):
            RecurringEditorView(item: nil, candidate: candidate)
        }
    }

    // MARK: Data

    private var dismissedKeys: [String] {
        dismissedSuggestionsText
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var categoriesByID: [String: TransactionCategory] {
        var result: [String: TransactionCategory] = [:]
        for category in categories where result[category.ledgerID] == nil {
            result[category.ledgerID] = category
        }
        return result
    }

    // MARK: Actions

    /// Moves "today" forward and rescans the history for suggestions.
    private func refresh() {
        let today = Date.now
        now = today
        detectCandidates(asOf: today)
    }

    private func detectCandidates(asOf date: Date) {
        detectedCandidates = RecurringDetector.candidates(from: transactions, now: date)
    }

    private func add(_ candidate: RecurringCandidate) {
        withAnimation(.snappy) {
            _ = LedgerStore.addRecurring(from: candidate, in: modelContext)
        }
        addedSuggestions += 1
    }

    private func dismissSuggestion(_ candidate: RecurringCandidate) {
        var keys = dismissedKeys
        guard !keys.contains(candidate.merchantKey) else { return }
        keys.append(candidate.merchantKey)
        withAnimation(.snappy) {
            dismissedSuggestionsText = keys.joined(separator: "\n")
        }
    }

    private func restoreDismissedSuggestions() {
        withAnimation(.snappy) {
            dismissedSuggestionsText = ""
        }
    }

    private func toggleActive(_ item: RecurringItem) {
        withAnimation(.snappy) {
            item.isActive.toggle()
        }
        LedgerStore.save(modelContext)
    }
}

// MARK: - Summary

/// Monthly and yearly cost, plus how much of this month's bills are paid.
private struct RecurringSummaryCard: View {
    let model: RecurringScreenModel

    /// Grows with Dynamic Type so the percentage inside stays legible.
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 80

    init(model: RecurringScreenModel) {
        self.model = model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Monthly recurring")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(Money.format(model.monthlyTotalCents, showsCents: false))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(yearlyLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                if model.dueThisMonthCents > 0 {
                    RecurringPaidRing(fraction: model.paidFraction)
                        .frame(width: ringSize, height: ringSize)
                }
            }
            if model.dueThisMonthCents > 0 {
                Divider()
                paidSection
            }
        }
        .hakiCard()
        .animation(.snappy, value: model.monthlyTotalCents)
    }

    private var paidSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(paidLine)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text(remainingLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    chips
                }
                VStack(alignment: .leading, spacing: 6) {
                    chips
                }
            }
        }
    }

    @ViewBuilder
    private var chips: some View {
        if model.paidCount > 0 {
            RecurringStatusChip(kind: .paid, count: model.paidCount)
        }
        if model.upcomingCount > 0 {
            RecurringStatusChip(kind: .upcoming, count: model.upcomingCount)
        }
        if model.lateCount > 0 {
            RecurringStatusChip(kind: .late, count: model.lateCount)
        }
    }

    private var yearlyLine: String {
        let yearly = Money.format(model.yearlyTotalCents, showsCents: false)
        let bills = RecurringFormat.count(model.activeBills.count, "active bill", "active bills")
        return "\(yearly) a year · \(bills)"
    }

    private var paidLine: String {
        let paid = Money.format(model.paidThisMonthCents)
        let due = Money.format(model.dueThisMonthCents)
        return "\(paid) of \(due) paid this month"
    }

    private var remainingLine: String {
        if model.remainingThisMonthCents <= 0 {
            return "Everything due in \(model.month.title()) is paid."
        }
        return "\(Money.format(model.remainingThisMonthCents)) left to pay"
    }
}

// MARK: - This month

/// A month calendar plus every due date this month with its status.
private struct RecurringThisMonthCard: View {
    let model: RecurringScreenModel
    let onSelect: (RecurringItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CardHeader("This month", systemImage: "calendar")
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            RecurringMonthCalendar(month: model.month, today: todayNumber, marks: model.dayMarks)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(calendarLabel)
                .accessibilityValue(calendarSummary)
            RecurringStatusLegend()
            if model.occurrences.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Divider()
                occurrenceList
            }
        }
        .hakiCard()
    }

    private var occurrenceList: some View {
        let firstID = model.occurrences.first?.id
        return VStack(spacing: 0) {
            ForEach(model.occurrences) { occurrence in
                if occurrence.id != firstID {
                    Divider()
                        .padding(.leading, 58)
                }
                Button {
                    onSelect(occurrence.item)
                } label: {
                    RecurringOccurrenceRow(occurrence: occurrence)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the bill to edit it")
            }
        }
    }

    private var todayNumber: Int? {
        let calendar = Calendar.current
        guard model.month.contains(model.now, calendar: calendar) else { return nil }
        return calendar.component(.day, from: model.now)
    }

    private var subtitle: String {
        let bills = RecurringFormat.count(model.occurrences.count, "bill", "bills")
        return "\(model.month.title()) · \(bills) due"
    }

    private var emptyText: String {
        "No bills are due in \(model.month.title())."
    }

    private var calendarLabel: String {
        "Bill calendar for \(model.month.title())"
    }

    private var calendarSummary: String {
        var parts: [String] = []
        if model.paidCount > 0 { parts.append("\(model.paidCount) paid") }
        if model.upcomingCount > 0 { parts.append("\(model.upcomingCount) upcoming") }
        if model.lateCount > 0 { parts.append("\(model.lateCount) late") }
        guard !parts.isEmpty else { return "No bills due" }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Bill lists

/// "All bills" and "Paused": tap a row to edit, long-press to pause or resume.
private struct RecurringBillsCard: View {
    let title: String
    let systemImage: String
    let subtitle: String?
    let bills: [RecurringScreenModel.Bill]
    let now: Date
    let onSelect: (RecurringItem) -> Void
    let onToggleActive: (RecurringItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                CardHeader(title, systemImage: systemImage)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            billList
        }
        .hakiCard()
    }

    private var billList: some View {
        let firstID = bills.first?.id
        return VStack(spacing: 0) {
            ForEach(bills) { bill in
                if bill.id != firstID {
                    Divider()
                        .padding(.leading, 48)
                }
                Button {
                    onSelect(bill.item)
                } label: {
                    RecurringBillRow(item: bill.item, nextDueDate: bill.nextDueDate, now: now)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens the bill to edit it")
                .contextMenu {
                    Button {
                        onSelect(bill.item)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button {
                        onToggleActive(bill.item)
                    } label: {
                        if bill.item.isActive {
                            Label("Pause", systemImage: "pause.circle")
                        } else {
                            Label("Resume", systemImage: "play.circle")
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Suggestions

/// Shown instead of the summary when nothing is tracked yet but Haki found
/// bills in the transaction history.
private struct RecurringIntroCard: View {
    let suggestionCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Track your bills", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Text("See what your subscriptions and bills cost each month, what's due next and what's already been paid.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(foundLine)
                .font(.subheadline.weight(.medium))
        }
        .hakiCard()
    }

    private var foundLine: String {
        let bills = RecurringFormat.count(suggestionCount, "repeating charge", "repeating charges")
        return "Haki found \(bills) in your transactions. Add them below, or tap + to add a bill yourself."
    }
}

private struct RecurringSuggestionsCard: View {
    let suggestions: [RecurringCandidate]
    let categoriesByID: [String: TransactionCategory]
    let onOpen: (RecurringCandidate) -> Void
    let onAdd: (RecurringCandidate) -> Void
    let onDismiss: (RecurringCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CardHeader("Suggestions", systemImage: "sparkles")
                Text("Repeating charges from your transactions. Tap one to review it before adding.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            suggestionList
        }
        .hakiCard()
    }

    private var suggestionList: some View {
        let firstID = suggestions.first?.id
        return VStack(spacing: 0) {
            ForEach(suggestions) { candidate in
                if candidate.id != firstID {
                    Divider()
                        .padding(.vertical, 4)
                }
                RecurringSuggestionRow(
                    candidate: candidate,
                    category: candidate.categoryID.flatMap { categoriesByID[$0] },
                    onOpen: { onOpen(candidate) },
                    onAdd: { onAdd(candidate) },
                    onDismiss: { onDismiss(candidate) }
                )
                .padding(.vertical, 6)
            }
        }
    }
}

private struct RecurringSuggestionRow: View {
    let candidate: RecurringCandidate
    let category: TransactionCategory?
    let onOpen: () -> Void
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    CategoryIcon(category: category)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.displayName)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        Text(detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text(RecurringFormat.amount(candidate.typicalAmountCents, candidate.frequency))
                        .font(.body.weight(.medium))
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Review before adding")

            HStack(spacing: 10) {
                Button(action: onAdd) {
                    Label("Add", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Add " + candidate.displayName)

                Button(action: onDismiss) {
                    Text("Dismiss")
                }
                .buttonStyle(.bordered)
                .tint(Color.secondary)
                .accessibilityLabel("Dismiss suggestion " + candidate.displayName)

                Spacer(minLength: 0)

                Text(nextLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            .controlSize(.small)
        }
    }

    private var detail: String {
        let seen = RecurringFormat.count(candidate.occurrenceCount, "time", "times")
        return "\(candidate.frequency.displayName) · Seen \(seen)"
    }

    private var nextLine: String {
        "Next around \(RecurringFormat.shortDate(candidate.nextExpectedDate))"
    }
}

#Preview {
    NavigationStack { RecurringView() }
        .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack { RecurringView() }
        .previewEnvironment(empty: true)
}
