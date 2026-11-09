//
//  ChartAxis.swift
//  Haki
//
//  Shared x-axis helpers for the date charts (net worth, balances, portfolio).
//

import Charts
import Foundation
import SwiftUI

enum ChartAxis {
    /// Where a date label sits against its tick: centered under it, so the
    /// gaps between labels match the gaps between dates. A label whose tick is
    /// near an edge would run past the plot (Swift Charts then truncates it,
    /// e.g. "No…"), so near the right edge it ends at its tick and near the
    /// left edge it starts at it. 8% of the plot is about half a "Nov 30"
    /// label on the narrowest phones.
    static func dateLabelAnchor(for value: AxisValue, in domain: ClosedRange<Date>) -> UnitPoint? {
        guard let date = value.as(Date.self) else { return nil }
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return nil }
        let fromEnd = domain.upperBound.timeIntervalSince(date) / span
        let fromStart = date.timeIntervalSince(domain.lowerBound) / span
        if fromEnd < 0.08 { return .topTrailing }
        if fromStart < 0.08 { return .topLeading }
        return .top
    }
}
