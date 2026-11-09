//
//  NutritionTodayCard.swift
//  Haki
//
//  The Health tab's food card: today's calories against the daily target
//  (ring with "N left" / "N over"), protein front and center, smaller bars
//  for carbs, fat and fiber, and the logging streak. The whole card opens
//  the food log.
//

import Foundation
import SwiftData
import SwiftUI

struct NutritionTodayCard: View {
    @AppStorage(HealthSettings.targetsKey) private var targetsData = Data()
    @Environment(\.scenePhase) private var scenePhase
    /// When "today" was last checked; moving it on past midnight redraws the card.
    @State private var now = Date.now

    /// The last few months of entries: today's for the totals, all of them
    /// for the streak. The predicate is fixed when the card is created, so
    /// "today" is picked out in memory (by `now`) and stays right past midnight.
    @Query private var recentEntries: [FoodEntry]

    init() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let start = calendar.date(byAdding: .day, value: -180, to: today) ?? today
        _recentEntries = Query(
            filter: #Predicate<FoodEntry> { $0.eatenAt >= start },
            sort: [SortDescriptor(\FoodEntry.eatenAt, order: .reverse)]
        )
    }

    var body: some View {
        let calendar = Calendar.current
        let todays = recentEntries.filter { calendar.isDate($0.eatenAt, inSameDayAs: now) }
        let progress = NutritionProgress(
            consumed: Macros.total(todays.map(\.macros)),
            targets: HealthSettings.targets(from: targetsData)
        )
        let streak = NutritionStats.loggingStreak(entryDates: recentEntries.map(\.eatenAt), now: now)

        NavigationLink {
            FoodLogView()
        } label: {
            NutritionTodayCardContent(progress: progress, mealCount: todays.count, streak: streak)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your food log")
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { followToday() }
        }
        .task {
            followToday()
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                followToday()
            }
        }
    }

    /// Moves `now` on once the day has changed, so the card shows today.
    private func followToday() {
        let current = Date.now
        if !Calendar.current.isDate(current, inSameDayAs: now) { now = current }
    }
}

/// What the card shows; split out so the card's body stays small.
private struct NutritionTodayCardContent: View {
    let progress: NutritionProgress
    let mealCount: Int
    let streak: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            NutritionDaySummary(progress: progress)
            footer
        }
        .hakiCard()
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label("Today", systemImage: "fork.knife")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if streak > 0 {
                NutritionStreakBadge(streak: streak)
            }
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var footer: some View {
        Text(footerText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footerText: String {
        switch mealCount {
        case 0:
            return "Nothing logged yet today. Snap a photo of your next meal and Haki estimates it."
        case 1:
            return "1 item logged today"
        default:
            return "\(mealCount) items logged today"
        }
    }
}

/// "🔥 5-day streak" as a capsule (an SF Symbol flame, not an emoji).
private struct NutritionStreakBadge: View {
    let streak: Int

    var body: some View {
        Label("\(streak)-day streak", systemImage: "flame.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.hakiWarning)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.orange.opacity(0.14), in: Capsule())
            .accessibilityLabel("Logging streak: \(streak) \(streak == 1 ? "day" : "days") in a row")
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            NutritionTodayCard()
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        ScrollView {
            NutritionTodayCard()
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment(empty: true)
}
