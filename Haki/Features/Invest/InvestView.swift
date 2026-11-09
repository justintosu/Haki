//
//  InvestView.swift
//  Haki
//
//  The Invest tab: every connected brokerage in one place — value, gain,
//  performance, allocation, positions, recent activity — and sharing the
//  portfolio with friends as percentages. Before anything is connected it
//  explains the idea and offers the connect button.
//

import Foundation
import SwiftUI
import UIKit

struct InvestView: View {
    @Environment(PortfolioService.self) private var portfolio
    @Environment(\.scenePhase) private var scenePhase

    @State private var isSharing = false
    @State private var toast: BrokerageLinkCenter.Notice?

    /// The tab reloads on appear only when its data is older than this.
    private let staleAfter: TimeInterval = 5 * 60

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    content
                }
                .padding(.horizontal)
                .padding(.bottom)
                .animation(.snappy, value: portfolio.hasConnections)
            }
            .background(Color.hakiBackground)
            .navigationTitle("Invest")
            .toolbar { toolbarContent }
            .refreshable { await pullToRefresh() }
            .task { await loadIfStale() }
            .onChange(of: scenePhase) { _, phase in
                // Back from the background (maybe the next day): reload and sync if due.
                guard phase == .active else { return }
                Task { await loadIfStale() }
            }
            .onChange(of: portfolio.isLoading) { _, isLoading in
                // A load that ended with neither data nor an error (superseded by a
                // sign-out, say) mustn't leave the spinner up with nothing coming.
                guard !isLoading, portfolio.lastLoaded == nil, portfolio.errorMessage == nil else { return }
                Task { await portfolio.refresh() }
            }
            .sheet(isPresented: $isSharing) {
                ComposePostView(prefill: PostDraft(kind: .portfolio, attachment: portfolio.sharedPortfolio(limit: 5)))
            }
            .overlay(alignment: .top) { toastOverlay }
            .onChange(of: BrokerageLinkCenter.shared.unannounced) { _, notice in
                showToast(for: notice)
            }
            .onAppear {
                showToast(for: BrokerageLinkCenter.shared.unannounced)
            }
            .task(id: toast?.id) { await hideToastLater() }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if portfolio.hasConnections {
            InvestConnectedContent(onShare: { isSharing = true })
        } else if portfolio.lastLoaded == nil {
            if let message = portfolio.errorMessage, !portfolio.isLoading {
                loadFailed(message)
            } else {
                loading
            }
        } else {
            if let message = portfolio.errorMessage {
                InvestErrorBanner(
                    message: message,
                    onRetry: { Task { await portfolio.refresh() } },
                    onDismiss: { portfolio.errorMessage = nil }
                )
            }
            InvestHeroCard()
        }
    }

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading your investments…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 120)
        .accessibilityElement(children: .combine)
    }

    private func loadFailed(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load your investments", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again") {
                Task { await portfolio.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.top, 60)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            AssistantToolbarButton()
        }
        ToolbarItem(placement: .topBarTrailing) {
            if portfolio.hasConnections {
                // Same rule as the share card: cash alone has nothing to share.
                let nothingToShare = portfolio.sharedPortfolio(limit: 5).holdings.isEmpty
                Button {
                    isSharing = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(nothingToShare)
                .accessibilityLabel("Share my portfolio")
                .accessibilityHint(nothingToShare ? InvestShareCard.nothingToShareText : "")
            }
        }
    }

    // MARK: Toast

    @ViewBuilder
    private var toastOverlay: some View {
        if let toast {
            InvestToast(message: "Connected \(toast.institutionName)")
                .padding(.top, 8)
                .padding(.horizontal)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture {
                    withAnimation(.snappy) { self.toast = nil }
                }
        }
    }

    private func showToast(for notice: BrokerageLinkCenter.Notice?) {
        guard let notice else { return }
        BrokerageLinkCenter.shared.unannounced = nil
        // Only fresh news: a connection made elsewhere minutes ago isn't worth a toast.
        guard Date.now.timeIntervalSince(notice.date) < 30 else { return }
        withAnimation(.snappy) { toast = notice }
        UIAccessibility.post(notification: .announcement, argument: "Connected \(notice.institutionName)")
    }

    private func hideToastLater() async {
        guard toast != nil else { return }
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        withAnimation(.snappy) { toast = nil }
    }

    // MARK: Loading

    private func loadIfStale() async {
        if let last = portfolio.lastLoaded, Date.now.timeIntervalSince(last) < staleAfter {
            // The tables are fresh, but the brokerages may not have synced today.
            portfolio.syncIfDue()
            return
        }
        // A refresh already under way (started by another screen) finishes on
        // its own, with data or an error, and syncs if one is due.
        guard !portfolio.isLoading else { return }
        await portfolio.refresh()
    }

    private func pullToRefresh() async {
        if portfolio.hasConnections {
            try? await portfolio.sync()
        } else {
            await portfolio.refresh()
        }
    }
}

// MARK: - Connected

/// Every card shown once at least one brokerage is connected.
private struct InvestConnectedContent: View {
    let onShare: () -> Void

    @Environment(PortfolioService.self) private var portfolio

    var body: some View {
        // Derived values are computed once per render, not per card.
        let positions = portfolio.positions
        let costBases = portfolio.costBases
        let currency = InvestFormat.currencyCode(holdings: portfolio.holdings, accounts: portfolio.accounts)
        let accountNames = Dictionary(portfolio.accounts.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })

        VStack(spacing: 16) {
            if let message = portfolio.errorMessage {
                InvestErrorBanner(
                    message: message,
                    onRetry: { Task { try? await portfolio.sync() } },
                    onDismiss: { portfolio.errorMessage = nil }
                )
            }

            InvestSummaryCard(
                totals: portfolio.totals,
                positionCount: positions.count,
                accountCount: portfolio.accounts.count,
                lastSynced: InvestFormat.lastSynced(portfolio.connections),
                isSyncing: portfolio.isSyncing,
                needsAttentionCount: portfolio.connections.filter(\.needsAttention).count,
                currency: currency,
                onSync: { Task { try? await portfolio.sync() } }
            )

            InvestPerformanceCard(
                snapshots: portfolio.snapshots,
                currency: currency,
                costCoverage: InvestChartCostCoverage(holdings: portfolio.holdings)
            )

            InvestAllocationCard(slices: portfolio.allocation, positionCount: positions.count, currency: currency)

            InvestPositionsCard(positions: positions, costBases: costBases, currency: currency)

            InvestShareCard(preview: portfolio.sharedPortfolio(limit: 5), onShare: onShare)

            InvestRecentActivityCard(
                transactions: Array(portfolio.transactions.prefix(5)),
                totalCount: portfolio.transactions.count,
                accountNames: accountNames,
                currency: currency
            )

            InvestConnectionsCard(connections: portfolio.connections, accounts: portfolio.accounts)

            Text("Haki reads your holdings through read-only connections and can't place trades or move money. Values come from your brokerages and may be delayed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
        }
    }
}

// MARK: - Previews

#Preview("Connected") {
    InvestView()
        .previewEnvironment()
}

#Preview("Not connected") {
    InvestView()
        .environment(InvestViewPreviewSupport.emptyPortfolio())
        .previewEnvironment()
}

private enum InvestViewPreviewSupport {
    static func emptyPortfolio() -> PortfolioService {
        let service = PortfolioService(client: nil)
        service.reset()
        return service
    }
}
