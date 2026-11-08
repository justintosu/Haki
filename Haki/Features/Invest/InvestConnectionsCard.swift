//
//  InvestConnectionsCard.swift
//  Haki
//
//  The linked brokerages: status, last sync, accounts, and removing one.
//

import Foundation
import SwiftUI

struct InvestConnectionsCard: View {
    let connections: [BrokerageConnection]
    let accounts: [InvestmentAccount]

    @Environment(PortfolioService.self) private var portfolio

    @State private var pendingRemoval: BrokerageConnection?
    @State private var removingIDs: Set<UUID> = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader("Connections", systemImage: "building.columns")
            VStack(spacing: 0) {
                ForEach(Array(connections.enumerated()), id: \.element.id) { index, connection in
                    if index > 0 {
                        Divider().padding(.leading, 52)
                    }
                    row(connection)
                }
            }
            BrokerageLinkButton(title: "Connect another brokerage")
            Text("Connections are read-only. Removing one deletes its holdings and history from Haki; your brokerage account isn't affected.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .hakiCard()
        .confirmationDialog(
            "Remove \(pendingRemoval?.institutionName ?? "this connection")?",
            isPresented: removalBinding,
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { connection in
            Button("Remove \(connection.institutionName)", role: .destructive) {
                Task { await remove(connection) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { connection in
            Text("Haki stops syncing \(connection.institutionName) and deletes its accounts, holdings and history from Haki. Your brokerage account itself isn't affected.")
        }
        .alert("Couldn't remove the connection", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Row

    @ViewBuilder
    private func row(_ connection: BrokerageConnection) -> some View {
        let linked = accounts.filter { $0.connectionID == connection.id }
        let tint = connection.needsAttention ? Color.hakiWarning : Color.accentColor

        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                Image(systemName: connection.needsAttention ? "exclamationmark.triangle.fill" : "building.columns.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
            }
            .frame(width: 40, height: 40)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.institutionName)
                    .font(.body.weight(.semibold))
                status(connection)
                if !linked.isEmpty {
                    Text(accountsText(linked))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)

            Spacer(minLength: 8)

            if removingIDs.contains(connection.id) {
                ProgressView()
                    .frame(width: 44, height: 44)
                    .accessibilityLabel("Removing \(connection.institutionName)")
            } else {
                Menu {
                    removeButton(connection)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Options for \(connection.institutionName)")
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .contextMenu {
            removeButton(connection)
        }
    }

    @ViewBuilder
    private func status(_ connection: BrokerageConnection) -> some View {
        if connection.needsAttention {
            Label(connection.status == "error" ? "Sync error" : "Needs attention", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.hakiWarning)
            if let message = connection.errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !message.isEmpty {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("To fix it, remove this connection and connect it again. " + InvestFormat.syncedText(connection.lastSyncedAt) + ".")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(InvestFormat.syncedText(connection.lastSyncedAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func removeButton(_ connection: BrokerageConnection) -> some View {
        Button(role: .destructive) {
            pendingRemoval = connection
        } label: {
            Label("Remove connection", systemImage: "trash")
        }
    }

    private func accountsText(_ linked: [InvestmentAccount]) -> String {
        linked.map { account in
            if let mask = account.mask, !mask.isEmpty {
                return "\(account.name) ••\(mask)"
            }
            return account.name
        }
        .joined(separator: ", ")
    }

    // MARK: Actions

    private func remove(_ connection: BrokerageConnection) async {
        removingIDs.insert(connection.id)
        defer { removingIDs.remove(connection.id) }
        do {
            try await portfolio.removeConnection(connection)
        } catch {
            if !Backend.isCancellation(error) {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

#Preview {
    let portfolio = PortfolioService.preview
    ScrollView {
        InvestConnectionsCard(connections: portfolio.connections, accounts: portfolio.accounts)
            .padding()
    }
    .background(Color.hakiBackground)
    .previewEnvironment()
}
