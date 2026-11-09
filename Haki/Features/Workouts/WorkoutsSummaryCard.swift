//
//  WorkoutsSummaryCard.swift
//  Haki
//
//  The Health tab's workout card: this week's workouts, the week streak and
//  the latest workout (the top links to Workouts), plus "Resume" for a
//  workout in progress or "Start workout" (empty or from a routine), which
//  opens the logger full screen.
//

import Foundation
import SwiftData
import SwiftUI

struct WorkoutsSummaryCard: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(HealthSettings.weightUnitKey) private var weightUnitRaw = ""

    @Query(filter: #Predicate<WorkoutRecord> { $0.endedAt == nil }, sort: [SortDescriptor(\WorkoutRecord.startedAt, order: .reverse)])
    private var activeWorkouts: [WorkoutRecord]

    @Query(filter: #Predicate<WorkoutRecord> { $0.endedAt != nil }, sort: [SortDescriptor(\WorkoutRecord.startedAt, order: .reverse)])
    private var finishedWorkouts: [WorkoutRecord]

    @Query(sort: [SortDescriptor(\RoutineRecord.sortOrder), SortDescriptor(\RoutineRecord.name)])
    private var routines: [RoutineRecord]

    @State private var presentedWorkout: WorkoutRecord?
    @State private var startFeedback = 0
    /// "Today" for this week's stats; moved forward when the day changes.
    @State private var now = Date.now

    var body: some View {
        let stats = WorkoutsWeekStats(finished: finishedWorkouts, now: now)
        let weightUnit = HealthSettings.weightUnit(from: weightUnitRaw)

        VStack(alignment: .leading, spacing: 16) {
            NavigationLink {
                WorkoutsView()
            } label: {
                WorkoutsSummaryCardContent(stats: stats, weightUnit: weightUnit)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens your workouts, routines and progress")

            WorkoutsStartControl(
                activeWorkout: activeWorkouts.first,
                routines: routines,
                onResume: { workout in presentedWorkout = workout },
                onStart: { routine in start(routine) }
            )
        }
        .hakiCard()
        .fullScreenCover(item: $presentedWorkout) { workout in
            ActiveWorkoutView(workout: workout)
        }
        .sensoryFeedback(.start, trigger: startFeedback)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDay() }
        }
        .task {
            refreshDay()
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                refreshDay()
            }
        }
    }

    private func refreshDay() {
        if !Calendar.current.isDate(Date.now, inSameDayAs: now) {
            now = .now
        }
    }

    private func start(_ routine: RoutineRecord?) {
        if let active = activeWorkouts.first {
            presentedWorkout = active
            return
        }
        let workout = WorkoutStore.startWorkout(routine: routine, in: modelContext)
        startFeedback += 1
        presentedWorkout = workout
    }
}

/// The linked part of the card: header, this week, streak, last workout.
private struct WorkoutsSummaryCardContent: View {
    let stats: WorkoutsWeekStats
    let weightUnit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if let last = stats.last {
                tiles
                lastWorkout(last)
            } else {
                Text("Log your lifts set by set, with last time's numbers, rest timers and personal records.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label("Workouts", systemImage: "dumbbell.fill")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if stats.weekStreak > 1 {
                WorkoutsStreakBadge(weeks: stats.weekStreak)
            }
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var tiles: some View {
        HStack(spacing: 12) {
            WorkoutsStatTile(title: "This week", value: WorkoutsFormat.workoutCount(stats.thisWeekCount))
            WorkoutsStatTile(title: "Volume this week", value: WorkoutsFormat.volume(stats.thisWeekVolumeKg, unit: weightUnit))
            WorkoutsStatTile(title: "Streak", value: stats.weekStreak == 1 ? "1 week" : "\(stats.weekStreak) weeks")
        }
    }

    private func lastWorkout(_ workout: WorkoutRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.purple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Last: \(workout.title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    WorkoutsSourceBadge(source: workout.source, hevyID: workout.hevyID)
                }
                Text(lastLine(workout))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Yesterday · 52m · 4,250 kg"
    private func lastLine(_ workout: WorkoutRecord) -> String {
        var parts = [WorkoutsFormat.day(workout.startedAt), WorkoutMath.formatDuration(seconds: workout.durationSeconds)]
        let volume = workout.volumeKg
        if volume > 0 {
            parts.append(WorkoutsFormat.volume(volume, unit: weightUnit))
        } else {
            parts.append(WorkoutsFormat.setCount(workout.completedSetCount))
        }
        return parts.joined(separator: " · ")
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            WorkoutsSummaryCard()
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        ScrollView {
            WorkoutsSummaryCard()
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment(empty: true)
}
