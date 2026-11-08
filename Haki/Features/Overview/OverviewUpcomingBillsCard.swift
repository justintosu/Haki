//
//  OverviewUpcomingBillsCard.swift
//  Haki
//
//  Active recurring bills due in the next two weeks, soonest first.
//

import Foundation
import SwiftUI

struct OverviewUpcomingBillsCard: View {
    /// Already filtered and sorted (see `OverviewSnapshot.upcomingBills`).
    let bills: [OverviewUpcomingBill]

    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CardHeader("Upcoming bills", systemImage: "calendar", actionTitle: "See all") {
                router.selectedTab = .recurring
            }
            if bills.isEmpty {
                Text("Nothing due in the next two weeks.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            } else {
                billList
            }
        }
        .hakiCard()
    }

    private var billList: some View {
        let firstID = bills.first?.id
        return VStack(spacing: 0) {
            ForEach(bills) { bill in
                if bill.id != firstID {
                    Divider()
                        .padding(.leading, 46)
                }
                OverviewBillRow(bill: bill)
                    .padding(.vertical, 8)
            }
        }
    }
}

/// Icon, name, when it's due and the amount; "Paid" once a matching charge shows up.
private struct OverviewBillRow: View {
    let bill: OverviewUpcomingBill

    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: bill.item.category, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(bill.item.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(dueText)
                    .font(.subheadline)
                    .foregroundStyle(isDueTodayAndUnpaid ? Color.hakiWarning : Color.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Money.format(bill.item.amountCents))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                if bill.isPaid {
                    Label("Paid", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.hakiPositive)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var isDueTodayAndUnpaid: Bool {
        bill.daysUntil == 0 && !bill.isPaid
    }

    private var dueText: String {
        switch bill.daysUntil {
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        default:
            let date = bill.dueDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            return "in \(bill.daysUntil) days · \(date)"
        }
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            OverviewUpcomingBillsCard(bills: OverviewPreviewData.snapshot.upcomingBills)
            OverviewUpcomingBillsCard(bills: [])
        }
        .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
