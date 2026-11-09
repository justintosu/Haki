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
    /// Where a date label sits against its tick. Swift Charts starts a date
    /// label at its tick, so one close to the right edge runs into the value
    /// labels and truncates ("No…"); that label ends at its tick instead.
    /// The rest keep the default, which can't run off the left edge.
    static func dateLabelAnchor(for value: AxisValue, in domain: ClosedRange<Date>) -> UnitPoint? {
        guard let date = value.as(Date.self) else { return nil }
        let span = domain.upperBound.timeIntervalSince(domain.lowerBound)
        guard span > 0 else { return nil }
        return domain.upperBound.timeIntervalSince(date) / span < 0.15 ? .topTrailing : nil
    }
}
