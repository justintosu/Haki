//
//  OverviewWelcomeView.swift
//  Haki
//
//  The first thing a new user sees: what Haki does and three ways to start.
//

import Foundation
import SwiftUI

struct OverviewWelcomeView: View {
    let onExploreSample: () -> Void
    let onImportCSV: () -> Void
    let onAddAccount: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 24) {
                    hero
                    features
                    actions
                }
                .hakiCard(padding: 20)

                footnote
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color.hakiBackground)
    }

    // MARK: Sections

    private var hero: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "chart.pie.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 60, height: 60)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .accessibilityHidden(true)
            Text("Welcome to Haki")
                .font(.system(.title, design: .rounded).weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text("Haki brings your spending, budgets, bills and net worth together in one place, so you always know where your money is going.")
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(featureList, id: \.title) { feature in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feature.systemImage)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                            .font(.subheadline.weight(.semibold))
                        Text(feature.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                onExploreSample()
            } label: {
                Label("Explore with sample data", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button {
                onImportCSV()
            } label: {
                Label("Import transactions from a CSV", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                onAddAccount()
            } label: {
                Label("Add an account", systemImage: "plus.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .controlSize(.large)
    }

    private var footnote: some View {
        VStack(spacing: 6) {
            Label("Everything stays on this device.", systemImage: "lock.fill")
            Text("Sample data adds demo accounts and transactions. You can erase it any time in Settings.")
                .multilineTextAlignment(.center)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal)
    }

    private var featureList: [OverviewWelcomeFeature] {
        [
            OverviewWelcomeFeature(
                systemImage: "chart.xyaxis.line",
                title: "See where your money goes",
                detail: "Follow this month's spending day by day against last month."
            ),
            OverviewWelcomeFeature(
                systemImage: "chart.bar.fill",
                title: "Stay on budget",
                detail: "Give categories a monthly budget and watch your pace."
            ),
            OverviewWelcomeFeature(
                systemImage: "calendar.badge.clock",
                title: "Never miss a bill",
                detail: "Haki spots recurring charges and shows what's due next."
            ),
            OverviewWelcomeFeature(
                systemImage: "building.columns",
                title: "Know your net worth",
                detail: "Track what you own and owe across all your accounts."
            ),
        ]
    }
}

private struct OverviewWelcomeFeature {
    let systemImage: String
    let title: String
    let detail: String
}

#Preview {
    NavigationStack {
        OverviewWelcomeView(onExploreSample: {}, onImportCSV: {}, onAddAccount: {})
            .navigationTitle("Overview")
    }
    .previewEnvironment(empty: true)
}
