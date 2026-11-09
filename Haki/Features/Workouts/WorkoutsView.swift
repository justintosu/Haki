//
//  WorkoutsView.swift
//  Haki
//
//  Workouts, pushed from the Health tab: start or resume a workout,
//  routines, the exercise library and Hevy, weekly progress, and every
//  finished workout grouped by month. Copies workouts from Hevy when a sync
//  is due, and on pull to refresh.
//

import Charts
import Foundation
import SwiftData
import SwiftUI

struct WorkoutsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HevySyncService.self) private var hevy
    @AppStorage(HealthSettings.weightUnitKey) private var weightUnitRaw = ""
    @AppStorage(HealthSettings.distanceUnitKey) private var distanceUnitRaw = ""
    @AppStorage(HealthSettings.restTimerEnabledKey) private var restTimerEnabled = true

    @Query(sort: [SortDescriptor(\WorkoutRecord.startedAt, order: .reverse)])
    private var workouts: [WorkoutRecord]

    @Query(sort: [SortDescriptor(\RoutineRecord.sortOrder), SortDescriptor(\RoutineRecord.name)])
    private var routines: [RoutineRecord]

    @State private var presentedWorkout: WorkoutRecord?
    @State private var routineSheet: WorkoutsRoutineSheet?
    @State private var routineToStart: RoutineRecord?
    @State private var routineToDelete: RoutineRecord?
    @State private var startFeedback = 0

    var body: some View {
        let finished = workouts.filter { $0.endedAt != nil }
        let active = workouts.first { $0.endedAt == nil }
        let weightUnit = HealthSettings.weightUnit(from: weightUnitRaw)

        content(finished: finished, active: active, weightUnit: weightUnit)
            .navigationTitle("Workouts")
            .toolbar { toolbarContent }
            .task { hevy.syncIfDue(in: modelContext) }
            .refreshable { await refreshFromHevy() }
            .fullScreenCover(item: $presentedWorkout) { workout in
                ActiveWorkoutView(workout: workout)
            }
            .sheet(item: $routineSheet) { sheet in
                RoutineEditorView(routine: sheet.routine)
            }
            .sensoryFeedback(.start, trigger: startFeedback)
    }

    // MARK: List

    private func content(finished: [WorkoutRecord], active: WorkoutRecord?, weightUnit: WeightUnit) -> some View {
        List {
            startSection(active: active)
            routinesSection
            librarySection
            unitsSection
            progressSection(finished: finished, weightUnit: weightUnit)
            historySections(finished: finished, weightUnit: weightUnit)
        }
        .listStyle(.insetGrouped)
        .confirmationDialog(
            routineToStart?.name ?? "Routine",
            isPresented: isConfirmingStart,
            titleVisibility: .visible,
            presenting: routineToStart
        ) { routine in
            if let active {
                Button("Resume workout in progress") { presentedWorkout = active }
            } else {
                Button("Start workout") { start(routine) }
            }
            Button("Edit routine") { routineSheet = .edit(routine) }
            Button("Cancel", role: .cancel) {}
        } message: { routine in
            Text(startMessage(for: routine, hasActive: active != nil))
        }
        .confirmationDialog(
            "Delete this routine?",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: routineToDelete
        ) { routine in
            Button("Delete routine", role: .destructive) { deleteRoutine(routine) }
            Button("Cancel", role: .cancel) {}
        } message: { routine in
            Text("“\(routine.name)” will be deleted. Workouts you logged from it stay.")
        }
    }

    private func startSection(active: WorkoutRecord?) -> some View {
        Section {
            WorkoutsStartControl(
                activeWorkout: active,
                routines: routines,
                onResume: { workout in presentedWorkout = workout },
                onStart: { routine in start(routine) }
            )
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }

    private var routinesSection: some View {
        Section {
            ForEach(routines) { routine in
                Button {
                    routineToStart = routine
                } label: {
                    WorkoutsRoutineRow(routine: routine)
                }
                .accessibilityHint("Start or edit this routine")
                .swipeActions(edge: .trailing) {
                    Button {
                        routineToDelete = routine
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                    Button {
                        routineSheet = .edit(routine)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(.blue)
                }
            }
            Button {
                routineSheet = .new
            } label: {
                Label("New routine", systemImage: "plus")
            }
        } header: {
            Text("Routines")
        } footer: {
            if routines.isEmpty {
                Text("Save the exercises you do often as a routine, then start it with last time's weights filled in.")
            }
        }
    }

    /// Weight and distance units and the rest timer (stored values are
    /// always kilograms and meters; only the display changes).
    private var unitsSection: some View {
        Section {
            Picker("Weight", selection: weightUnitBinding) {
                ForEach(WeightUnit.allCases) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            Picker("Distance", selection: distanceUnitBinding) {
                ForEach(DistanceUnit.allCases) { unit in
                    Text(unit.symbol).tag(unit)
                }
            }
            Toggle("Rest timer after each set", isOn: $restTimerEnabled)
        } header: {
            Text("Units and timer")
        }
    }

    private var weightUnitBinding: Binding<WeightUnit> {
        Binding(
            get: { HealthSettings.weightUnit(from: weightUnitRaw) },
            set: { weightUnitRaw = $0.rawValue }
        )
    }

    private var distanceUnitBinding: Binding<DistanceUnit> {
        Binding(
            get: { HealthSettings.distanceUnit(from: distanceUnitRaw) },
            set: { distanceUnitRaw = $0.rawValue }
        )
    }

    private var librarySection: some View {
        Section {
            NavigationLink {
                ExerciseBrowserView()
            } label: {
                Label("Exercises", systemImage: "list.bullet")
            }
            // A plain link, like the Health tab's Hevy row: this screen is
            // itself pushed by a NavigationLink, and pushing Hevy settings
            // through navigationDestination(isPresented:) here froze the app.
            NavigationLink {
                HevySettingsView()
            } label: {
                HevyStatusRow(showsChevron: false)
            }
            .accessibilityHint("Opens Hevy sync settings")
        } header: {
            Text("Library and sync")
        }
    }

    private func progressSection(finished: [WorkoutRecord], weightUnit: WeightUnit) -> some View {
        Section {
            WorkoutsProgressChart(
                points: WorkoutsWeekPoint.points(from: finished),
                stats: WorkoutsWeekStats(finished: finished),
                weightUnit: weightUnit
            )
        } header: {
            Text("Progress")
        }
    }

    @ViewBuilder
    private func historySections(finished: [WorkoutRecord], weightUnit: WeightUnit) -> some View {
        if finished.isEmpty {
            Section {
                ContentUnavailableView {
                    Label("No workouts yet", systemImage: "dumbbell")
                } description: {
                    Text("Finished workouts show up here, along with any you copy from Hevy.")
                }
            } header: {
                Text("History")
            }
        } else {
            ForEach(WorkoutsMonthGroup.groups(finished)) { group in
                Section {
                    ForEach(group.workouts) { workout in
                        NavigationLink {
                            WorkoutDetailView(workout: workout)
                        } label: {
                            WorkoutsHistoryRow(workout: workout, weightUnit: weightUnit)
                        }
                    }
                } header: {
                    Text(group.title)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                routineSheet = .new
            } label: {
                Label("New routine", systemImage: "plus")
            }
            .accessibilityLabel("New routine")
        }
    }

    // MARK: Dialogs

    private var isConfirmingStart: Binding<Bool> {
        Binding(
            get: { routineToStart != nil },
            set: { if !$0 { routineToStart = nil } }
        )
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { routineToDelete != nil },
            set: { if !$0 { routineToDelete = nil } }
        )
    }

    private func startMessage(for routine: RoutineRecord, hasActive: Bool) -> String {
        let count = WorkoutsFormat.exerciseCount(routine.exercises.count)
        if hasActive { return "\(count). Finish the workout in progress before starting another." }
        return "\(count), filled in with what you lifted last time."
    }

    // MARK: Actions

    /// Pull to refresh: copies new and changed workouts from Hevy (does
    /// nothing when Hevy isn't connected).
    private func refreshFromHevy() async {
        await hevy.sync(in: modelContext)
    }

    private func start(_ routine: RoutineRecord?) {
        if let active = workouts.first(where: { $0.endedAt == nil }) {
            presentedWorkout = active
            return
        }
        let workout = WorkoutStore.startWorkout(routine: routine, in: modelContext)
        startFeedback += 1
        presentedWorkout = workout
    }

    private func deleteRoutine(_ routine: RoutineRecord) {
        // Cleared first, so the closing dialog never reads the deleted routine.
        routineToDelete = nil
        routineToStart = nil
        withAnimation(.snappy) {
            WorkoutStore.deleteRoutine(routine, in: modelContext)
        }
    }
}

// MARK: - Support

/// The routine editor sheet: a new routine or an existing one. The id is
/// captured up front, so presenting never reads a routine deleted in the
/// editor.
private struct WorkoutsRoutineSheet: Identifiable {
    let id: String
    let routine: RoutineRecord?

    static var new: WorkoutsRoutineSheet {
        WorkoutsRoutineSheet(id: "new-\(UUID().uuidString)", routine: nil)
    }

    static func edit(_ routine: RoutineRecord) -> WorkoutsRoutineSheet {
        WorkoutsRoutineSheet(id: routine.id.uuidString, routine: routine)
    }
}

/// Finished workouts of one calendar month, newest first.
private struct WorkoutsMonthGroup: Identifiable {
    let id: Date
    let title: String
    let workouts: [WorkoutRecord]

    /// `workouts` newest first; the groups keep that order.
    static func groups(_ workouts: [WorkoutRecord], calendar: Calendar = .current) -> [WorkoutsMonthGroup] {
        var order: [Date] = []
        var byMonth: [Date: [WorkoutRecord]] = [:]
        for workout in workouts {
            let start = calendar.dateInterval(of: .month, for: workout.startedAt)?.start ?? calendar.startOfDay(for: workout.startedAt)
            if byMonth[start] == nil { order.append(start) }
            byMonth[start, default: []].append(workout)
        }
        return order.map { month in
            WorkoutsMonthGroup(id: month, title: month.formatted(.dateTime.month(.wide).year()), workouts: byMonth[month] ?? [])
        }
    }
}

/// One bar of the weekly chart.
private struct WorkoutsWeekPoint: Identifiable {
    let weekStart: Date
    let count: Int
    let isCurrent: Bool

    var id: Date { weekStart }

    /// "Nov 3", for VoiceOver.
    var label: String {
        weekStart.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "11/3", short enough for eight bars on a phone.
    var shortLabel: String {
        weekStart.formatted(.dateTime.month(.defaultDigits).day())
    }

    static func points(from finished: [WorkoutRecord], now: Date = .now) -> [WorkoutsWeekPoint] {
        let weeks = WorkoutMath.workoutsPerWeek(workoutDates: finished.map(\.startedAt), weeks: 8, now: now)
        let lastIndex = weeks.count - 1
        return weeks.enumerated().map { index, week in
            WorkoutsWeekPoint(weekStart: week.weekStart, count: week.count, isCurrent: index == lastIndex)
        }
    }
}

/// Workouts per week for the last 8 weeks, with this week's totals.
private struct WorkoutsProgressChart: View {
    let points: [WorkoutsWeekPoint]
    let stats: WorkoutsWeekStats
    let weightUnit: WeightUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WorkoutsStatTile(title: "This week", value: WorkoutsFormat.workoutCount(stats.thisWeekCount))
                WorkoutsStatTile(title: "Volume this week", value: WorkoutsFormat.volume(stats.thisWeekVolumeKg, unit: weightUnit))
                WorkoutsStatTile(title: "Streak", value: stats.weekStreak == 1 ? "1 week" : "\(stats.weekStreak) weeks")
            }
            chart
            Text("Workouts per week")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Week", point.shortLabel),
                    y: .value("Workouts", Double(point.count))
                )
                .foregroundStyle(point.isCurrent ? Color.accentColor : Color.accentColor.opacity(0.35))
                .cornerRadius(4)
            }
        }
        .chartYScale(domain: 0...yTop)
        .chartYAxis {
            AxisMarks(position: .trailing, values: yTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let count = value.as(Double.self) {
                        Text("\(Int(count.rounded()))")
                    }
                }
            }
        }
        .frame(height: 150)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Workouts per week, last 8 weeks")
        .accessibilityValue(accessibilitySummary)
    }

    private var yTop: Double {
        Double(max(points.map(\.count).max() ?? 0, 3))
    }

    private var yTicks: [Double] {
        let top = Int(yTop)
        if top <= 4 { return (0...top).map { Double($0) } }
        let middle = (top + 1) / 2
        return [0, Double(middle), Double(top)]
    }

    private var accessibilitySummary: String {
        points
            .map { "Week of \($0.label): \(WorkoutsFormat.workoutCount($0.count))" }
            .joined(separator: ", ")
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        WorkoutsView()
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        WorkoutsView()
    }
    .previewEnvironment(empty: true)
}
