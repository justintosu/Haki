//
//  InvestPositionsCard.swift
//  Haki
//
//  Every position across the connected accounts (holdings of the same
//  security merged), sortable, each pushing HoldingDetailView.
//

import Foundation
import SwiftUI

enum InvestPositionSort: String, CaseIterable, Identifiable {
    case value, gain, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .value: "Value"
        case .gain: "Gain"
        case .name: "Name"
        }
    }

    /// `costBases` (by symbol) supplies each position's return; positions
    /// missing from it use their own figures.
    func sorted(_ positions: [PortfolioPosition], costBases: [String: PositionCostBasis] = [:]) -> [PortfolioPosition] {
        switch self {
        case .value:
            return positions.sorted { $0.value != $1.value ? $0.value > $1.value : $0.symbol < $1.symbol }
        case .gain:
            func gainPct(_ position: PortfolioPosition) -> Double? {
                (costBases[position.symbol] ?? PositionCostBasis(position: position)).gainPct
            }
            return positions.sorted { lhs, rhs in
                switch (gainPct(lhs), gainPct(rhs)) {
                case let (left?, right?): return left != right ? left > right : lhs.value > rhs.value
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return lhs.value > rhs.value
                }
            }
        case .name:
            return positions.sorted {
                InvestStyle.displaySymbol(for: $0).localizedStandardCompare(InvestStyle.displaySymbol(for: $1)) == .orderedAscending
            }
        }
    }
}

struct InvestPositionsCard: View {
    let positions: [PortfolioPosition]
    /// `PortfolioService.costBases`: each position's return, counting only
    /// holdings that report what was paid.
    let costBases: [String: PositionCostBasis]
    let currency: String

    @State private var sort: InvestPositionSort = .value
    @State private var showsAll = false

    private let collapsedCount = 8

    var body: some View {
        let sorted = sort.sorted(positions, costBases: costBases)
        let visible = showsAll ? sorted : Array(sorted.prefix(collapsedCount))

        VStack(alignment: .leading, spacing: 8) {
            header
            if positions.isEmpty {
                InvestInlineNote(
                    systemImage: "clock.arrow.circlepath",
                    text: "No holdings yet. They show up here after your brokerage finishes its first sync, which can take a few minutes."
                )
                .padding(.top, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, position in
                        if index > 0 {
                            Divider().padding(.leading, 52)
                        }
                        NavigationLink {
                            HoldingDetailView(position: position)
                        } label: {
                            InvestPositionRow(position: position, costBasis: costBases[position.symbol], currency: currency)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if sorted.count > collapsedCount {
                    Button {
                        withAnimation(.snappy) { showsAll.toggle() }
                    } label: {
                        Text(showsAll ? "Show fewer" : "Show all \(sorted.count) positions")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
        }
        .hakiCard()
    }

    private var header: some View {
        HStack {
            Label("Positions", systemImage: "list.bullet.rectangle")
                .font(.headline)
            Spacer()
            if positions.count > 1 {
                Menu {
                    Picker("Sort by", selection: $sort) {
                        ForEach(InvestPositionSort.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sort.title)
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .accessibilityLabel("Sort positions")
                .accessibilityValue(sort.title)
            }
        }
    }
}

/// Symbol, name, value, weight and gain of one position.
struct InvestPositionRow: View {
    let position: PortfolioPosition
    /// The position's return counting only holdings that report a cost basis;
    /// `nil` uses the position's own figures.
    var costBasis: PositionCostBasis? = nil
    let currency: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var gainPct: Double? {
        (costBasis ?? PositionCostBasis(position: position)).gainPct
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedLayout
            } else {
                rowLayout
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(InvestStyle.displaySymbol(for: position)), \(position.name)")
        .accessibilityValue(spokenValue)
    }

    private var rowLayout: some View {
        HStack(spacing: 12) {
            badge
            VStack(alignment: .leading, spacing: 2) {
                symbolText
                    .lineLimit(1)
                nameText
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                valueText
                weightAndGain
            }
            chevron
        }
    }

    /// For accessibility text sizes: symbol and name on top, the figures below,
    /// so neither has to squeeze into a fraction of the width.
    private var stackedLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                badge
                symbolText
                    .lineLimit(2)
                Spacer(minLength: 8)
                chevron
            }
            nameText
                .lineLimit(3)
            valueText
            weightAndGain
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var badge: some View {
        HoldingSymbolBadge(
            symbol: position.symbol,
            name: position.name,
            assetClass: AssetClass(plaidType: position.securityType)
        )
    }

    private var symbolText: some View {
        Text(InvestStyle.displaySymbol(for: position))
            .font(.body.weight(.semibold))
    }

    private var nameText: some View {
        Text(position.name)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private var valueText: some View {
        Text(InvestFormat.money(position.value, currency: currency))
            .font(.body.weight(.semibold))
            .monospacedDigit()
    }

    private var weightAndGain: some View {
        HStack(spacing: 6) {
            Text(InvestFormat.percent(position.weightPct))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let gainPct {
                PercentChangeText(percent: gainPct)
            }
        }
        .font(.caption)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private var spokenValue: String {
        var parts = [
            InvestFormat.money(position.value, currency: currency),
            InvestFormat.percent(position.weightPct) + " of portfolio",
        ]
        if let gainPct {
            let direction = gainPct >= 0 ? "up" : "down"
            parts.append("\(direction) " + InvestFormat.percent(abs(gainPct)))
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            InvestPositionsCard(
                positions: PortfolioService.preview.positions,
                costBases: PortfolioService.preview.costBases,
                currency: "USD"
            )
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
