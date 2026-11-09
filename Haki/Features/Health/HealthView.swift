//
//  HealthView.swift
//  Haki
//
//  The Health tab: today's calories and protein, quick ways to log a meal or
//  find healthy food nearby, this week's workouts, and links to the food
//  log, workouts, nutrition goals and Hevy.
//

import Foundation
import SwiftUI

struct HealthView: View {
    @State private var activeSheet: HealthSheet?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NutritionTodayCard()
                    quickActions
                    WorkoutsSummaryCard()
                    moreCard
                    disclaimer
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color.hakiBackground)
            .navigationTitle("Health")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    AssistantToolbarButton()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        activeSheet = .captureMeal
                    } label: {
                        Label("Log a meal", systemImage: "plus")
                    }
                    .accessibilityLabel("Log a meal")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .captureMeal:
                MealCaptureView()
            case .manualEntry:
                FoodEntryEditorView(entry: nil)
            }
        }
    }

    // MARK: Quick actions

    private var quickActions: some View {
        HStack(spacing: 10) {
            Button {
                activeSheet = .captureMeal
            } label: {
                HealthActionTile(title: "Snap a meal", systemImage: "camera.fill", tint: .orange)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Take or choose a photo and Haki estimates calories and protein")

            Button {
                activeSheet = .manualEntry
            } label: {
                HealthActionTile(title: "Add food", systemImage: "square.and.pencil", tint: .blue)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Type in a food with its calories and protein")

            NavigationLink {
                PlacesView()
            } label: {
                HealthActionTile(title: "Eat nearby", systemImage: "fork.knife", tint: .green)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Find restaurants and stores near you and their healthiest options")
        }
    }

    // MARK: More

    private var moreCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                FoodLogView()
            } label: {
                HealthLinkRow(title: "Food log", systemImage: "list.bullet.clipboard", tint: .orange)
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                WorkoutsView()
            } label: {
                HealthLinkRow(title: "Workouts", systemImage: "dumbbell.fill", tint: .purple)
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                NutritionGoalsView()
            } label: {
                HealthLinkRow(title: "Nutrition goals", systemImage: "target", tint: .pink)
            }
            Divider().padding(.leading, 52)
            NavigationLink {
                HevySettingsView()
            } label: {
                HevyStatusRow()
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .hakiCard()
    }

    private var disclaimer: some View {
        Text("Calories, protein and menu details from Haki's AI are estimates. Haki isn't medical or dietary advice.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
    }
}

private enum HealthSheet: String, Identifiable {
    case captureMeal
    case manualEntry

    var id: String { rawValue }
}

/// A square shortcut with a tinted icon.
private struct HealthActionTile: View {
    let title: String
    let systemImage: String
    let tint: Color
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 40

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: iconSize, height: iconSize)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
        .background(Color.hakiCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// A row in the "more" card: icon, title, chevron.
private struct HealthLinkRow: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

#Preview {
    HealthView()
        .previewEnvironment()
}
