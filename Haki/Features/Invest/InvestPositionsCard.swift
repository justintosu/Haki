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

    func sorted(_ positions: [PortfolioPosition]) -> [PortfolioPosition] {
        switch self {
        case .value:
            return positions.sorted { $0.value != $1.value ? $0.value > $1.value : $0.symbol < $1.symbol }
        case .gain:
            return positions.sorted { lhs, rhs in
                switch (lhs.gainPct, rhs.gainPct) {
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
    let currency: String

    @State private var sort: InvestPositionSort = .value
    @State private var showsAll = false

    private let collapsedCount = 8

    var body: some View {
        let sorted = sort.sorted(positions)
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
                            InvestPositionRow(position: position, currency: currency)
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
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            HoldingSymbolBadge(
                symbol: position.symbol,
                name: position.name,
                assetClass: AssetClass(plaidType: position.securityType)
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(InvestStyle.displaySymbol(for: position))
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                Text(position.name)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(InvestFormat.money(position.value, currency: currency))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                HStack(spacing: 6) {
                    Text(InvestFormat.percent(position.weightPct))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    if let gainPct = position.gainPct {
                        PercentChangeText(percent: gainPct)
                    }
                }
                .font(.caption)
            }
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(InvestStyle.displaySymbol(for: position)), \(position.name)")
        .accessibilityValue(spokenValue)
    }

    private var spokenValue: String {
        var parts = [
            InvestFormat.money(position.value, currency: currency),
            InvestFormat.percent(position.weightPct) + " of portfolio",
        ]
        if let gainPct = position.gainPct {
            let direction = gainPct >= 0 ? "up" : "down"
            parts.append("\(direction) " + InvestFormat.percent(abs(gainPct)))
        }
        return parts.joined(separator: ", ")
    }
}

#Preview {
    NavigationStack {
        ScrollView {
            InvestPositionsCard(positions: PortfolioService.preview.positions, currency: "USD")
                .padding()
        }
        .background(Color.hakiBackground)
    }
    .previewEnvironment()
}
