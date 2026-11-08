//
//  ExerciseHistoryView.swift
//  Haki
//
//  One exercise over time: personal records, a chart of the best set per
//  session (estimated one-rep max for weighted lifts, otherwise reps, time
//  or distance) and every past session with its sets.
//

import Charts
import Foundation
import SwiftData
import SwiftUI

struct ExerciseHistoryView: View {
    let exerciseKey: String
    let name: String

    @Environment(\.modelContext) private var modelContext
    @AppStorage(HealthSettings.weightUnitKey) private var weightUnitRaw = ""
    @AppStorage(HealthSettings.distanceUnitKey) private var distanceUnitRaw = ""

    @State private var performances: [ExercisePerformance] = []
    @State private var definition: ExerciseDefinition?
    @State private var hasLoaded = false

    private var weightUnit: WeightUnit { HealthSettings.weightUnit(from: weightUnitRaw) }
    private var distanceUnit: DistanceUnit { HealthSettings.distanceUnit(from: distanceUnitRaw) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                content
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    @ViewBuilder
    private var content: some View {
        if !hasLoaded {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else if performances.isEmpty {
            header(kind: definition?.kind ?? .weightReps)
            ContentUnavailableView {
                Label("No sessions yet", systemImage: "chart.line.uptrend.xyaxis")
            } description: {
                Text("Finish a workout with \(name) and your records and progress show up here.")
            }
            .hakiCard()
        } else {
            loadedContent
        }
    }

    private var loadedContent: some View {
        let kind = definition?.kind ?? Self.inferredKind(performances)
        let metric = ExerciseHistoryMetric(kind: kind)
        let points = Self.points(performances, metric: metric, weightUnit: weightUnit, distanceUnit: distanceUnit)
        let items = Self.recordItems(performances, kind: kind, weightUnit: weightUnit, distanceUnit: distanceUnit)

        return VStack(spacing: 16) {
            header(kind: kind)
            if !items.isEmpty {
                ExerciseRecordsCard(items: items)
            }
            ExerciseProgressCard(points: points, metric: metric, weightUnit: weightUnit, distanceUnit: distanceUnit)
            sessions(kind: kind)
        }
    }

    private func header(kind: ExerciseKind) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.title2.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle(kind: kind))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .hakiCard()
    }

    private func subtitle(kind: ExerciseKind) -> String {
        var parts: [String] = []
        if let definition {
            parts.append(definition.primaryMuscle.title)
            parts.append(definition.equipment.title)
        } else {
            parts.append(kind.title)
        }
        if let last = performances.first {
            let count = performances.count
            parts.append(count == 1 ? "1 session" : "\(count) sessions")
            parts.append("last \(WorkoutsFormat.day(last.date))")
        }
        return parts.joined(separator: " · ")
    }

    private func sessions(kind: ExerciseKind) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Sessions", systemImage: "calendar")
                .padding(.horizontal, 4)
            LazyVStack(spacing: 12) {
                ForEach(Array(performances.enumerated()), id: \.offset) { _, performance in
                    ExerciseSessionCard(performance: performance, kind: kind, weightUnit: weightUnit, distanceUnit: distanceUnit)
                }
            }
        }
    }

    private func load() {
        performances = WorkoutStore.performances(exerciseKey: exerciseKey, in: modelContext)
        definition = WorkoutStore.definition(forKey: exerciseKey, in: modelContext)
        hasLoaded = true
    }

    // MARK: Derived values

    /// What an exercise without a library entry logs, from its sets.
    static func inferredKind(_ performances: [ExercisePerformance]) -> ExerciseKind {
        let sets = performances.flatMap(\.sets)
        let hasWeight = sets.contains { ($0.weightKg ?? 0) > 0 }
        let hasReps = sets.contains { ($0.reps ?? 0) > 0 }
        let hasDistance = sets.contains { ($0.distanceMeters ?? 0) > 0 }
        let hasDuration = sets.contains { ($0.durationSeconds ?? 0) > 0 }
        if hasDistance { return hasWeight ? .weightDistance : .distanceDuration }
        if hasReps { return hasWeight ? .weightReps : .repsOnly }
        if hasDuration { return hasWeight ? .weightDuration : .duration }
        return .weightReps
    }

    /// The best value per session, oldest first, in display units.
    static func points(_ performances: [ExercisePerformance], metric: ExerciseHistoryMetric, weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> [ExerciseHistoryPoint] {
        var result: [ExerciseHistoryPoint] = []
        for (index, performance) in performances.reversed().enumerated() {
            let working = WorkoutMath.workingSets(performance.sets)
            var best: Double?
            switch metric {
            case .oneRepMax:
                let estimates = working.compactMap(\.estimatedOneRepMaxKg)
                let heaviest = working.compactMap(\.weightKg).filter { $0 > 0 }
                if let kilograms = estimates.max() ?? heaviest.max() {
                    best = weightUnit.fromKilograms(kilograms)
                }
            case .reps:
                best = working.compactMap(\.reps).max().map { Double($0) }
            case .duration:
                best = working.compactMap(\.durationSeconds).max().map { Double($0) / 60 }
            case .distance:
                best = working.compactMap(\.distanceMeters).max().map { $0 / distanceUnit.metersPerUnit }
            }
            if let best, best > 0, best.isFinite {
                result.append(ExerciseHistoryPoint(id: index, date: performance.date, value: best))
            }
        }
        return result
    }

    /// Records worth showing for this kind of exercise.
    static func recordItems(_ performances: [ExercisePerformance], kind: ExerciseKind, weightUnit: WeightUnit, distanceUnit: DistanceUnit) -> [ExerciseRecordItem] {
        let records = WorkoutMath.records(performances, countsWeight: kind.countsWeightForRecords)
        var items: [ExerciseRecordItem] = []
        for recordKind in RecordKind.allCases {
            if let value = WorkoutsFormat.recordValue(recordKind, records: records, unit: weightUnit) {
                items.append(ExerciseRecordItem(id: recordKind.rawValue, title: recordKind.title, value: value, systemImage: symbol(for: recordKind)))
            }
        }
        let working = performances.flatMap { WorkoutMath.workingSets($0.sets) }
        if kind.logsDuration, let longest = working.compactMap(\.durationSeconds).max(), longest > 0 {
            items.append(ExerciseRecordItem(id: "duration", title: "Longest time", value: WorkoutMath.formatTimer(seconds: longest), systemImage: "timer"))
        }
        if kind.logsDistance, let farthest = working.compactMap(\.distanceMeters).max(), farthest > 0 {
            items.append(ExerciseRecordItem(id: "distance", title: "Longest distance", value: WorkoutsFormat.distance(farthest, unit: distanceUnit), systemImage: "point.topleft.down.to.point.bottomright.curvepath"))
        }
        let loads = working.compactMap(\.weightKg).filter { $0 > 0 }
        if kind == .assistedBodyweightReps, let least = loads.min() {
            // Less help is the better result for assisted lifts.
            items.append(ExerciseRecordItem(id: "weight", title: "Least assistance", value: WorkoutsFormat.weight(least, unit: weightUnit), systemImage: "scalemass"))
        } else if !kind.countsWeightForRecords, kind.logsWeight, let heaviest = loads.max() {
            let title = kind == .bodyweightReps ? "Most added weight" : "Heaviest weight"
            items.append(ExerciseRecordItem(id: "weight", title: title, value: WorkoutsFormat.weight(heaviest, unit: weightUnit), systemImage: "scalemass"))
        }
        return items
    }

    private static func symbol(for kind: RecordKind) -> String {
        switch kind {
        case .heaviestWeight: return "scalemass.fill"
        case .bestOneRepMax: return "trophy.fill"
        case .mostReps: return "repeat"
        case .bestSetVolume: return "chart.bar.fill"
        }
    }
}

// MARK: - Model

/// What the progress chart plots.
enum ExerciseHistoryMetric {
    case oneRepMax, reps, duration, distance

    init(kind: ExerciseKind) {
        if kind.countsWeightForRecords {
            self = .oneRepMax
        } else if kind.logsReps {
            self = .reps
        } else if kind.logsDuration {
            self = .duration
        } else {
            self = .distance
        }
    }

    var title: String {
        switch self {
        case .oneRepMax: return "Best est. 1RM"
        case .reps: return "Most reps"
        case .duration: return "Longest time"
        case .distance: return "Longest distance"
        }
    }

    /// Explains the chart under its title.
    var detail: String {
        switch self {
        case .oneRepMax: return "Estimated one-rep max of your best set each session"
        case .reps: return "Most reps in a set each session"
        case .duration: return "Longest set each session, in minutes"
        case .distance: return "Longest set each session"
        }
    }
}

struct ExerciseHistoryPoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double
}

struct ExerciseRecordItem: Identifiable {
    let id: String
    let title: String
    let value: String
    let systemImage: String
}

// MARK: - Cards

/// Personal records in a two-column grid.
private struct ExerciseRecordsCard: View {
    let items: [ExerciseRecordItem]

    private let columns = [GridItem(.flexible(), spacing: 12, alignment: .topLeading), GridItem(.flexible(), spacing: 12, alignment: .topLeading)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader("Personal records", systemImage: "trophy")
            LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.hakiWarning)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                        WorkoutsStatTile(title: item.title, value: item.value)
                    }
                }
            }
        }
        .hakiCard()
    }
}

/// The best set per session as a line.
private struct ExerciseProgressCard: View {
    let points: [ExerciseHistoryPoint]
    let metric: ExerciseHistoryMetric
    let weightUnit: WeightUnit
    let distanceUnit: DistanceUnit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Progress", systemImage: "chart.line.uptrend.xyaxis")
            Text(metric.detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if points.count >= 2 {
                chart
            } else {
                Text("Log this exercise in another workout to see a trend.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .multilineTextAlignment(.center)
            }
        }
        .hakiCard()
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Best", point.value)
                )
                .foregroundStyle(Color.accentColor)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Best", point.value)
                )
                .foregroundStyle(Color.accentColor)
                .symbolSize(36)
            }
        }
        .chartYScale(domain: yDomain)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(axisLabel(amount))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 180)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.title) by session")
        .accessibilityValue(accessibilitySummary)
    }

    /// Padded so a flat line sits in the middle.
    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value)
        let low = values.min() ?? 0
        let high = values.max() ?? 1
        let padding = max((high - low) * 0.2, max(high * 0.05, 1))
        return max(0, low - padding)...(high + padding)
    }

    private func axisLabel(_ value: Double) -> String {
        switch metric {
        case .oneRepMax:
            return "\(Int(value.rounded())) \(weightUnit.symbol)"
        case .reps:
            return "\(Int(value.rounded()))"
        case .duration:
            return "\(Int(value.rounded()))m"
        case .distance:
            return String(format: "%.1f \(distanceUnit.symbol)", value)
        }
    }

    private func spokenValue(_ value: Double) -> String {
        switch metric {
        case .oneRepMax:
            return WorkoutsFormat.weight(weightUnit.toKilograms(value), unit: weightUnit)
        case .reps:
            return "\(Int(value.rounded())) reps"
        case .duration:
            return WorkoutMath.formatTimer(seconds: Int((value * 60).rounded()))
        case .distance:
            return String(format: "%.2f \(distanceUnit.symbol)", value)
        }
    }

    private var accessibilitySummary: String {
        guard let first = points.first, let last = points.last else { return "" }
        let start = "\(spokenValue(first.value)) on \(first.date.formatted(.dateTime.month(.wide).day()))"
        let end = "\(spokenValue(last.value)) on \(last.date.formatted(.dateTime.month(.wide).day()))"
        let best = points.map(\.value).max() ?? last.value
        return "\(points.count) sessions, from \(start) to \(end). Best \(spokenValue(best))."
    }
}

/// One past session: its day, volume and sets, with the best set marked.
private struct ExerciseSessionCard: View {
    let performance: ExercisePerformance
    let kind: ExerciseKind
    let weightUnit: WeightUnit
    let distanceUnit: DistanceUnit

    var body: some View {
        let best = WorkoutMath.bestSet(performance.sets)
        let bestIndex = best.flatMap { target in performance.sets.firstIndex(of: target) }
        let labels = Self.labels(performance.sets)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(WorkoutsFormat.day(performance.date))
                    .font(.headline)
                Spacer(minLength: 8)
                if volume > 0 {
                    Text(WorkoutsFormat.volume(volume, unit: weightUnit))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            ForEach(Array(performance.sets.enumerated()), id: \.offset) { index, values in
                setLine(values, label: index < labels.count ? labels[index] : "\(index + 1)", isBest: index == bestIndex)
            }
        }
        .hakiCard()
        .accessibilityElement(children: .combine)
    }

    private var volume: Double {
        kind.countsWeightForRecords ? WorkoutMath.volumeKg(performance.sets) : 0
    }

    private func setLine(_ values: SetValues, label: String, isBest: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(values.kind == .warmup ? Color.hakiWarning : Color.secondary)
                .frame(minWidth: 22, alignment: .leading)
            Text(WorkoutsFormat.setSummary(values, kind: kind, weightUnit: weightUnit, distanceUnit: distanceUnit))
                .font(.subheadline)
                .monospacedDigit()
            Spacer(minLength: 8)
            if isBest {
                Label("Best set", systemImage: "star.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// "W" for warm-ups, badges for drop sets and failure sets, numbers otherwise.
    static func labels(_ sets: [SetValues]) -> [String] {
        var result: [String] = []
        var number = 0
        for values in sets {
            if values.kind == .warmup {
                result.append("W")
            } else {
                number += 1
                result.append(values.kind.badge ?? "\(number)")
            }
        }
        return result
    }
}

// MARK: - Previews

#Preview {
    NavigationStack {
        ExerciseHistoryView(exerciseKey: "bench_press_barbell", name: "Bench Press (Barbell)")
    }
    .previewEnvironment()
}

#Preview("No history") {
    NavigationStack {
        ExerciseHistoryView(exerciseKey: "plank", name: "Plank")
    }
    .previewEnvironment()
}
