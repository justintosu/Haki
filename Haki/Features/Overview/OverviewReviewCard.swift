//
//  OverviewReviewCard.swift
//  Haki
//
//  "To review": the newest transactions that still need a look, each with a
//  one-tap "mark reviewed" button, or a small all-caught-up state.
//

import Foundation
import SwiftData
import SwiftUI

struct OverviewReviewCard: View {
    /// Unreviewed transactions, newest first.
    let transactions: [TransactionRecord]

    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @State private var reviewedCount = 0

    private static let visibleCount = 3

    var body: some View {
        Group {
            if transactions.isEmpty {
                caughtUp
            } else {
                queue
            }
        }
        .hakiCard()
        .sensoryFeedback(.success, trigger: reviewedCount)
    }

    // MARK: Queue

    private var visible: [TransactionRecord] {
        Array(transactions.prefix(Self.visibleCount))
    }

    private var countText: String {
        transactions.count == 1 ? "1 transaction to review" : "\(transactions.count) transactions to review"
    }

    private var queue: some View {
        let rows = visible
        let firstID = rows.first?.id
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                CardHeader("To review", systemImage: "tray.full")
                Text(countText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                ForEach(rows) { transaction in
                    if transaction.id != firstID {
                        Divider()
                            .padding(.leading, 48)
                    }
                    row(for: transaction)
                }
            }

            Button {
                router.showTransactions(.needsReview)
            } label: {
                Text("Review all")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func row(for transaction: TransactionRecord) -> some View {
        HStack(spacing: 4) {
            NavigationLink {
                TransactionDetailView(transaction: transaction)
            } label: {
                TransactionRow(transaction: transaction, showsDate: true)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                markReviewed(transaction)
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Mark \(transaction.merchant) as reviewed")
        }
        .padding(.vertical, 4)
    }

    private func markReviewed(_ transaction: TransactionRecord) {
        withAnimation(.snappy) {
            LedgerStore.setReviewed([transaction], true, in: modelContext)
        }
        reviewedCount += 1
    }

    // MARK: Caught up

    private var caughtUp: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title2)
                .foregroundStyle(Color.hakiPositive)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("You're all caught up")
                    .font(.headline)
                Text("New and imported transactions show up here for a quick review.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("To review") {
    NavigationStack {
        ScrollView {
            OverviewReviewCard(transactions: OverviewPreviewData.unreviewed)
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}

#Preview("Caught up") {
    ScrollView {
        OverviewReviewCard(transactions: [])
            .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
