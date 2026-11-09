//
//  FoodLogView.swift
//  Haki
//
//  The food log, a day at a time: the day's totals against the targets,
//  entries grouped by meal, a 7-day view, and every way to add food (snap,
//  type it in, log something again).
//

import Charts
import Foundation
import SwiftData
import SwiftUI
import UIKit

struct FoodLogView: View {
    @AppStorage(HealthSettings.targetsKey) private var targetsData = Data()
    @Environment(\.scenePhase) private var scenePhase

    /// Start of the day being shown.
    @State private var day = Calendar.current.startOfDay(for: .now)
    /// The day that was today when `day` was last checked, so the log
    /// follows today past midnight.
    @State private var shownToday = Calendar.current.startOfDay(for: .now)
    @State private var sheet: FoodLogSheet?

    var body: some View {
        FoodLogDayList(
            day: day,
            targets: HealthSettings.targets(from: targetsData),
            onSelectDay: { newDay in
                withAnimation(.snappy) { day = newDay }
            },
            onPresent: { request in sheet = request }
        )
        .navigationTitle("Food log")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                FoodLogAddMenu(day: day, mealType: nil, onPresent: { request in sheet = request }) {
                    Label("Add food", systemImage: "plus")
                }
                .accessibilityLabel("Add food")
            }
        }
        .sheet(item: $sheet) { request in
            sheetContent(for: request)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { followToday() }
        }
        .task {
            // Also on coming back to the screen (another tab, a pushed
            // screen), where a day change may have been missed.
            followToday()
            for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                followToday()
            }
        }
    }

    /// After midnight, moves the log on to the new day if it was showing
    /// today; a past day the person picked stays.
    private func followToday() {
        let today = Calendar.current.startOfDay(for: .now)
        guard today != shownToday else { return }
        if day == shownToday { day = today }
        shownToday = today
    }

    @ViewBuilder
    private func sheetContent(for request: FoodLogSheet) -> some View {
        switch request.kind {
        case .capture:
            MealCaptureView(mealType: request.mealType, eatenAt: request.eatenAt)
        case .manual:
            FoodEntryEditorView(entry: nil, mealType: request.mealType, eatenAt: request.eatenAt)
        case .edit(let entry):
            FoodEntryEditorView(entry: entry)
        case .logAgain:
            FoodLogAgainSheet(eatenAt: request.eatenAt)
        }
    }
}

// MARK: - Sheets and timing

/// What the log presents in a sheet. The id is made up front, so identifying
/// the sheet never reads a model that was just deleted.
private struct FoodLogSheet: Identifiable {
    enum Kind {
        case capture
        case manual
        case edit(FoodEntry)
        case logAgain
    }

    let id = UUID()
    let kind: Kind
    var mealType: MealType?
    var eatenAt: Date?
}

private enum FoodLogTiming {
    /// When food added while looking at `day` was eaten: nil (now) for today;
    /// on an earlier day, the meal's usual time or else this time of day.
    static func eatenAt(on day: Date, mealType: MealType?, calendar: Calendar = .current) -> Date? {
        if calendar.isDateInToday(day) { return nil }
        let start = calendar.startOfDay(for: day)
        var hour = 12
        var minute = 0
        if let mealType {
            hour = usualHour(for: mealType)
            minute = usualMinute(for: mealType)
        } else {
            let now = calendar.dateComponents([.hour, .minute], from: .now)
            hour = now.hour ?? 12
            minute = now.minute ?? 0
        }
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
    }

    private static func usualHour(for meal: MealType) -> Int {
        switch meal {
        case .breakfast: 8
        case .lunch: 12
        case .dinner: 19
        case .snack: 15
        }
    }

    private static func usualMinute(for meal: MealType) -> Int {
        switch meal {
        case .breakfast, .dinner: 0
        case .lunch, .snack: 30
        }
    }
}

/// "Snap a meal", "Add manually", "Log again…" for a day (and maybe a meal).
private struct FoodLogAddMenu<MenuLabel: View>: View {
    let day: Date
    let mealType: MealType?
    let onPresent: (FoodLogSheet) -> Void
    @ViewBuilder let label: () -> MenuLabel

    var body: some View {
        Menu {
            Button {
                present(.capture)
            } label: {
                Label("Snap a meal", systemImage: "camera")
            }
            Button {
                present(.manual)
            } label: {
                Label("Add manually", systemImage: "square.and.pencil")
            }
            Button {
                present(.logAgain)
            } label: {
                Label("Log again…", systemImage: "arrow.counterclockwise")
            }
        } label: {
            label()
        }
    }

    private func present(_ kind: FoodLogSheet.Kind) {
        let eatenAt = FoodLogTiming.eatenAt(on: day, mealType: mealType)
        onPresent(FoodLogSheet(kind: kind, mealType: mealType, eatenAt: eatenAt))
    }
}

// MARK: - The day

/// Daily totals for the 7-day chart.
private struct FoodLogDayTotal: Identifiable {
    let day: Date
    let calories: Double
    var id: Date { day }
}

/// The list for one day. Its query covers that day and the six before it
/// (for the 7-day average), and is rebuilt whenever the day changes.
private struct FoodLogDayList: View {
    let day: Date
    let targets: NutritionTargets
    let onSelectDay: (Date) -> Void
    let onPresent: (FoodLogSheet) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var weekEntries: [FoodEntry]

    @State private var toast: String?
    @State private var loggedAgainCount = 0

    init(day: Date, targets: NutritionTargets, onSelectDay: @escaping (Date) -> Void, onPresent: @escaping (FoodLogSheet) -> Void) {
        self.day = day
        self.targets = targets
        self.onSelectDay = onSelectDay
        self.onPresent = onPresent
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let start = calendar.date(byAdding: .day, value: -6, to: dayStart) ?? dayStart
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)
        _weekEntries = Query(
            filter: #Predicate<FoodEntry> { $0.eatenAt >= start && $0.eatenAt < end },
            sort: [SortDescriptor(\FoodEntry.eatenAt)]
        )
    }

    var body: some View {
        let calendar = Calendar.current
        let dayEntries = weekEntries.filter { calendar.isDate($0.eatenAt, inSameDayAs: day) }
        let progress = NutritionProgress(consumed: Macros.total(dayEntries.map(\.macros)), targets: targets)

        List {
            Section {
                FoodLogDaySwitcher(day: day, onSelectDay: onSelectDay)
                    // Its separator would start under the day's name, not at the card's edge.
                    .listRowSeparator(.hidden)
                NutritionDaySummary(progress: progress)
                    .padding(.vertical, 6)
            }

            if dayEntries.isEmpty {
                emptySection
            } else {
                ForEach(MealType.allCases) { meal in
                    mealSection(meal, entries: dayEntries.filter { $0.mealType == meal })
                }
            }

            weekSection
        }
        .sensoryFeedback(.success, trigger: loggedAgainCount)
        .overlay(alignment: .bottom) { toastView }
        .task(id: toast) { await hideToastLater() }
    }

    // MARK: Meals

    private func mealSection(_ meal: MealType, entries: [FoodEntry]) -> some View {
        Section {
            if entries.isEmpty {
                FoodLogAddMenu(day: day, mealType: meal, onPresent: onPresent) {
                    Label("Add \(meal.title.lowercased())", systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                }
            } else {
                ForEach(entries) { entry in
                    entryRow(entry)
                }
            }
        } header: {
            FoodLogMealHeader(
                meal: meal,
                calories: Macros.total(entries.map(\.macros)).calories,
                hasEntries: !entries.isEmpty,
                day: day,
                onPresent: onPresent
            )
        }
    }

    private func entryRow(_ entry: FoodEntry) -> some View {
        Button {
            onPresent(FoodLogSheet(kind: .edit(entry)))
        } label: {
            FoodEntryRow(entry: entry)
        }
        .foregroundStyle(.primary)
        .accessibilityHint("Edit this entry")
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                FoodStore.delete(entry, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                logAgain(entry)
            } label: {
                Label("Log again", systemImage: "arrow.counterclockwise")
            }
            .tint(Color.accentColor)
        }
        .contextMenu {
            Button {
                logAgain(entry)
            } label: {
                Label("Log again now", systemImage: "arrow.counterclockwise")
            }
            Button(role: .destructive) {
                FoodStore.delete(entry, in: modelContext)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var emptySection: some View {
        Section {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: "fork.knife")
            } description: {
                Text("Snap a photo and Haki estimates the calories and protein, or type it in yourself.")
            } actions: {
                VStack(spacing: 10) {
                    Button {
                        present(.capture)
                    } label: {
                        Label("Snap a meal", systemImage: "camera.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    Button {
                        present(.manual)
                    } label: {
                        Label("Add manually", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                    Button {
                        present(.logAgain)
                    } label: {
                        Label("Log again…", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .listRowBackground(Color.clear)
        }
    }

    private var emptyTitle: String {
        Calendar.current.isDateInToday(day) ? "Nothing logged today" : "Nothing logged this day"
    }

    private func present(_ kind: FoodLogSheet.Kind) {
        onPresent(FoodLogSheet(kind: kind, mealType: nil, eatenAt: FoodLogTiming.eatenAt(on: day, mealType: nil)))
    }

    private func logAgain(_ entry: FoodEntry) {
        let now = Date.now
        let meal = MealType.suggested(for: now)
        let name = entry.name
        FoodStore.logAgain(entry, eatenAt: now, mealType: meal, in: modelContext)
        loggedAgainCount += 1
        let message = "Added \(name) to today's \(meal.title.lowercased())"
        withAnimation(.snappy) { toast = message }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    // MARK: Week

    @ViewBuilder
    private var weekSection: some View {
        let totals = dailyTotals()
        let average = NutritionStats.averagePerLoggedDay(averageInput())
        Section {
            if let average {
                FoodLogWeekAverageRow(average: average, loggedDays: totals.filter { $0.calories > 0 }.count, targets: targets)
                FoodLogWeekChart(totals: totals, selectedDay: Calendar.current.startOfDay(for: day), targetCalories: targets.calories)
                    .frame(height: 140)
                    .padding(.vertical, 4)
            }
            NavigationLink {
                NutritionGoalsView()
            } label: {
                FoodLogTargetsRow(targets: targets)
            }
        } header: {
            Text("Last 7 days")
        }
    }

    private func averageInput() -> [(date: Date, macros: Macros)] {
        weekEntries.map { entry in (date: entry.eatenAt, macros: entry.macros) }
    }

    /// Calories for each of the seven days ending on `day`, oldest first.
    private func dailyTotals() -> [FoodLogDayTotal] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        var byDay: [Date: Double] = [:]
        for entry in weekEntries {
            byDay[calendar.startOfDay(for: entry.eatenAt), default: 0] += entry.calories
        }
        var result: [FoodLogDayTotal] = []
        for offset in stride(from: -6, through: 0, by: 1) {
            guard let shifted = calendar.date(byAdding: .day, value: offset, to: dayStart) else { continue }
            let date = calendar.startOfDay(for: shifted)
            result.append(FoodLogDayTotal(day: date, calories: byDay[date] ?? 0))
        }
        return result
    }

    // MARK: Toast

    @ViewBuilder
    private var toastView: some View {
        if let toast {
            Label(toast, systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: Capsule())
                .padding(.horizontal)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onTapGesture {
                    withAnimation(.snappy) { self.toast = nil }
                }
        }
    }

    private func hideToastLater() async {
        guard toast != nil else { return }
        try? await Task.sleep(for: .seconds(2.5))
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) { toast = nil }
    }
}

// MARK: - Pieces

/// "‹ Today ›" with a jump back to today from earlier days. Can't go past today.
private struct FoodLogDaySwitcher: View {
    let day: Date
    let onSelectDay: (Date) -> Void

    var body: some View {
        let isToday = Calendar.current.isDateInToday(day)
        HStack(spacing: 4) {
            Button {
                shift(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Previous day")

            Spacer(minLength: 4)
            VStack(spacing: 2) {
                Text(FoodFormat.dayTitle(day))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if !isToday {
                    Button("Back to today") {
                        onSelectDay(Calendar.current.startOfDay(for: .now))
                    }
                    .font(.caption.weight(.semibold))
                }
            }
            Spacer(minLength: 4)

            Button {
                shift(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(isToday)
            .accessibilityLabel("Next day")
        }
        .buttonStyle(.borderless)
    }

    private func shift(by days: Int) {
        let calendar = Calendar.current
        guard let next = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: day)) else { return }
        let today = calendar.startOfDay(for: .now)
        onSelectDay(min(next, today))
    }
}

/// A meal's section header: icon and name, and once it has entries, its
/// calories and an add button (empty meals have an add row instead).
private struct FoodLogMealHeader: View {
    let meal: MealType
    let calories: Double
    let hasEntries: Bool
    let day: Date
    let onPresent: (FoodLogSheet) -> Void

    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 24

    var body: some View {
        HStack(spacing: 8) {
            Label {
                Text(meal.title)
            } icon: {
                // Meal symbols differ in width; a fixed icon column lines the titles up.
                Image(systemName: meal.systemImage)
                    .frame(width: iconWidth, alignment: .center)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if hasEntries {
                Text(FoodFormat.kcal(calories))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                FoodLogAddMenu(day: day, mealType: meal, onPresent: onPresent) {
                    Image(systemName: "plus.circle.fill")
                        .imageScale(.large)
                        .frame(minWidth: 44, minHeight: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Add to \(meal.title.lowercased())")
            }
        }
        .textCase(nil)
    }
}

/// "1,850 kcal · 112 g protein a day on average" over the logged days.
private struct FoodLogWeekAverageRow: View {
    let average: Macros
    let loggedDays: Int
    let targets: NutritionTargets

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Daily average")
                .font(.subheadline.weight(.semibold))
            Text(FoodFormat.macroLine(average))
                .font(.body.weight(.medium))
                .monospacedDigit()
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let days = loggedDays == 1 ? "1 logged day" : "\(loggedDays) logged days"
        let difference = Int(average.calories.rounded()) - targets.calories
        let comparison: String
        if abs(difference) < 25 {
            comparison = "Right on your calorie target"
        } else if difference < 0 {
            comparison = "\(FoodFormat.kcal(Double(-difference))) under your target"
        } else {
            comparison = "\(FoodFormat.kcal(Double(difference))) over your target"
        }
        return "\(comparison), over \(days). Days with nothing logged don't count."
    }
}

/// Calories per day for the week, with the daily target as a dashed line.
private struct FoodLogWeekChart: View {
    let totals: [FoodLogDayTotal]
    let selectedDay: Date
    let targetCalories: Int

    var body: some View {
        Chart {
            ForEach(totals) { total in
                BarMark(
                    x: .value("Day", total.day, unit: .day),
                    y: .value("Calories", total.calories)
                )
                .foregroundStyle(total.day == selectedDay ? Color.accentColor : Color.accentColor.opacity(0.35))
                .cornerRadius(4)
            }
            RuleMark(y: .value("Target", Double(targetCalories)))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 4]))
                .annotation(position: .top, alignment: .leading) {
                    Text("Target")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
        }
        .chartYScale(domain: 0...yTop)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: [0, Double(targetCalories)]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories over the last 7 days")
        .accessibilityValue(accessibilitySummary)
    }

    /// Scales to the bigger of the target and the busiest day, with headroom
    /// for the "Target" label, so the bars aren't squeezed under an empty
    /// band of the chart.
    private var yTop: Double {
        let highest = max(Double(targetCalories), totals.map(\.calories).max() ?? 0)
        return max(highest * 1.2, 100)
    }

    private var accessibilitySummary: String {
        totals
            .map { "\($0.day.formatted(.dateTime.weekday(.wide))): \(FoodFormat.kcal($0.calories))" }
            .joined(separator: ", ")
    }
}

/// The daily targets, linking to the goals screen.
private struct FoodLogTargetsRow: View {
    let targets: NutritionTargets

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "target")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.pink)
                .frame(width: 32, height: 32)
                .background(Color.pink.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Daily targets")
                Text("\(FoodFormat.kcal(Double(targets.calories))) · \(targets.proteinG) g protein")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Log again

/// Recent distinct foods; tapping one logs it again.
private struct FoodLogAgainSheet: View {
    let eatenAt: Date?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var recents: [FoodEntry] = []
    @State private var didLoad = false
    @State private var mealType: MealType
    @State private var searchText = ""

    init(eatenAt: Date?) {
        self.eatenAt = eatenAt
        _mealType = State(initialValue: MealType.suggested(for: eatenAt ?? .now))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Add to", selection: $mealType) {
                        ForEach(MealType.allCases) { meal in
                            Label(meal.title, systemImage: meal.systemImage)
                                .tag(meal)
                        }
                    }
                }
                Section {
                    ForEach(filtered) { entry in
                        Button {
                            log(entry)
                        } label: {
                            FoodEntryRow(entry: entry, showsTime: false, showsDate: true)
                        }
                        .foregroundStyle(.primary)
                        .accessibilityHint("Logs it again")
                    }
                } header: {
                    if !filtered.isEmpty {
                        Text("Recent")
                    }
                }
            }
            .overlay { emptyOverlay }
            .searchable(text: $searchText, prompt: "Search recent foods")
            .navigationTitle("Log again")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: loadIfNeeded)
        }
    }

    private var filtered: [FoodEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return recents }
        return recents.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    @ViewBuilder
    private var emptyOverlay: some View {
        if didLoad && recents.isEmpty {
            ContentUnavailableView(
                "Nothing to log again yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("Foods you log show up here, so you can add them again with one tap.")
            )
        } else if didLoad && filtered.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        recents = FoodStore.recentDistinct(limit: 40, in: modelContext)
        didLoad = true
    }

    private func log(_ entry: FoodEntry) {
        FoodStore.logAgain(entry, eatenAt: eatenAt ?? .now, mealType: mealType, in: modelContext)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        FoodLogView()
    }
    .previewEnvironment()
}

#Preview("Empty") {
    NavigationStack {
        FoodLogView()
    }
    .previewEnvironment(empty: true)
}
