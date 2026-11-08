//
//  OverviewComponents.swift
//  Haki
//
//  Small views shared by the Overview cards.
//

import Foundation
import SwiftUI

/// A thin bar filled to `fraction` (0...1), for comparing amounts side by side.
/// Purely visual: the row it sits in carries the amount as text.
struct OverviewMeterBar: View {
    let fraction: Double
    var tint: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.15))
                Capsule()
                    .fill(tint)
                    .frame(width: fillWidth(in: proxy.size.width))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func fillWidth(in width: CGFloat) -> CGFloat {
        let clamped = CGFloat(min(1, max(0, fraction)))
        guard clamped > 0 else { return 0 }
        return max(height, width * clamped)
    }
}

/// A line sample and a title, for chart legends that don't rely on color:
/// solid, dashed and dotted lines read differently on their own.
struct OverviewLegendItem: View {
    let title: String
    let color: Color
    var dash: [CGFloat] = []

    var body: some View {
        HStack(spacing: 6) {
            Path { path in
                path.move(to: CGPoint(x: 2, y: 2))
                path.addLine(to: CGPoint(x: 20, y: 2))
            }
            .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: dash))
            .frame(width: 22, height: 4)
            .accessibilityHidden(true)
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        OverviewMeterBar(fraction: 0.7, tint: .hakiPositive)
        OverviewMeterBar(fraction: 0.35, tint: .hakiWarning)
        HStack(spacing: 16) {
            OverviewLegendItem(title: "This month", color: .accentColor)
            OverviewLegendItem(title: "Last month", color: .hakiComparison, dash: [5, 4])
            OverviewLegendItem(title: "Budget", color: .secondary, dash: [1, 4])
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .padding()
    .previewEnvironment()
}
