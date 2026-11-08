//
//  BrokerageLinkFlow.swift
//  Haki
//
//  The Plaid Link part of connecting a brokerage. Owned by
//  BrokerageLinkButton (in its @State). Nothing in this file may use
//  SwiftUI's `@Environment`: LinkKit declares a type with the same name.
//

import Foundation
import LinkKit
import Observation
import SwiftUI
import UIKit

@Observable final class BrokerageLinkFlow {
    enum Phase: Equatable {
        /// Ready to start.
        case idle
        /// Fetching a link token from the server.
        case preparing
        /// The Plaid sheet is up.
        case linking
        /// Exchanging the public token and syncing for the first time.
        case connecting
    }

    private(set) var phase: Phase = .idle
    /// Drives the button's `.sheet`.
    var isPresentingLink = false
    /// Drives the button's `.alert`.
    var alert: BrokerageLinkAlert?
    private(set) var session: PlaidLinkSession?

    /// Whether the button is on screen, so a success can be confirmed there.
    @ObservationIgnored var isOnScreen = false
    /// True from presenting the Plaid sheet until it has fully dismissed.
    @ObservationIgnored private var isSheetUp = false
    /// An alert that has to wait for the Plaid sheet to finish dismissing.
    @ObservationIgnored private var pendingAlert: BrokerageLinkAlert?
    @ObservationIgnored private var portfolio: PortfolioService?

    var isBusy: Bool { phase != .idle }

    func start(using portfolio: PortfolioService) {
        guard phase == .idle else { return }
        self.portfolio = portfolio
        alert = nil
        phase = .preparing
        Task { await openLink(portfolio) }
    }

    /// Called from the sheet's `onDismiss`, once the Plaid sheet is fully gone.
    func linkSheetDidDismiss() {
        isSheetUp = false
        isPresentingLink = false
        session = nil
        if phase == .linking {
            // Swiped away without finishing.
            phase = .idle
        }
        if let pendingAlert {
            self.pendingAlert = nil
            alert = pendingAlert
        }
    }

    // MARK: Steps

    private func openLink(_ portfolio: PortfolioService) async {
        do {
            let token = try await portfolio.createLinkToken()
            let newSession = try Plaid.createPlaidLinkSession(configuration: makeConfiguration(token: token))
            session = newSession
            phase = .linking
            isSheetUp = true
            isPresentingLink = true
        } catch {
            phase = .idle
            if !Backend.isCancellation(error) {
                present(BrokerageLinkAlert.failure(error))
            }
        }
    }

    private func makeConfiguration(token: String) -> LinkTokenConfiguration {
        LinkTokenConfiguration(
            token: token,
            onSuccess: { [weak self] success in
                guard let self else { return }
                let publicToken = success.publicToken
                let institutionID = success.metadata.institution.id
                let institutionName = success.metadata.institution.name
                Task { @MainActor in
                    self.linkSucceeded(
                        publicToken: publicToken,
                        institutionID: institutionID,
                        institutionName: institutionName
                    )
                }
            },
            onExit: { [weak self] exit in
                guard let self else { return }
                let message = exit.error.map { BrokerageLinkFlow.exitMessage(for: $0) }
                Task { @MainActor in
                    self.linkExited(errorMessage: message)
                }
            },
            onEvent: nil,
            onLoad: nil
        )
    }

    private func linkSucceeded(publicToken: String, institutionID: String, institutionName: String) {
        isPresentingLink = false
        guard let portfolio else {
            phase = .idle
            return
        }
        phase = .connecting
        let trimmedID = institutionID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = institutionName.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            await connect(
                portfolio,
                publicToken: publicToken,
                institutionID: trimmedID.isEmpty ? nil : trimmedID,
                institutionName: trimmedName.isEmpty ? nil : trimmedName
            )
        }
    }

    private func connect(
        _ portfolio: PortfolioService,
        publicToken: String,
        institutionID: String?,
        institutionName: String?
    ) async {
        // Known only once loaded: otherwise every existing connection would look new.
        let knownConnectionIDs: Set<UUID>? = portfolio.lastLoaded == nil ? nil : Set(portfolio.connections.map(\.id))
        do {
            try await portfolio.completeLink(
                publicToken: publicToken,
                institutionID: institutionID,
                institutionName: institutionName
            )
        } catch {
            // The reply can be lost (dropped network, app suspended) after the
            // server saved the connection; `completeLink` reloads, and a new
            // connection means it worked. Saying otherwise invites linking twice.
            let appeared = knownConnectionIDs.map { known in
                portfolio.connections.contains { !known.contains($0.id) }
            } ?? false
            guard appeared else {
                phase = .idle
                if !Backend.isCancellation(error) {
                    present(BrokerageLinkAlert.failure(error))
                }
                return
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Let the screen settle first: a first connection usually replaces
        // the empty state that hosts this button.
        try? await Task.sleep(for: .milliseconds(450))
        phase = .idle
        let name = institutionName ?? "your brokerage"
        if isOnScreen {
            present(BrokerageLinkAlert.connected(name))
        } else {
            BrokerageLinkCenter.shared.unannounced = BrokerageLinkCenter.Notice(institutionName: name)
        }
    }

    private func linkExited(errorMessage: String?) {
        if phase == .linking {
            phase = .idle
        }
        isPresentingLink = false
        if let errorMessage {
            present(BrokerageLinkAlert(title: "Couldn't connect", message: errorMessage))
        }
    }

    /// Alerts can't appear while the Plaid sheet is still on screen or dismissing.
    private func present(_ newAlert: BrokerageLinkAlert) {
        if isSheetUp {
            pendingAlert = newAlert
        } else {
            alert = newAlert
        }
    }

    /// Plaid's message for the user if it has one, else its technical one.
    nonisolated static func exitMessage(for error: ExitError) -> String {
        if let display = error.displayMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !display.isEmpty {
            return display
        }
        let message = error.errorMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? "Your brokerage couldn't be connected. Try again." : message
    }
}

/// The content of the button's sheet: Plaid's own Link UI.
struct BrokerageLinkSheetView: View {
    let flow: BrokerageLinkFlow

    var body: some View {
        if let session = flow.session {
            session.sheet()
                .ignoresSafeArea()
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview("Waiting for Link") {
    BrokerageLinkSheetView(flow: BrokerageLinkFlow())
        .previewEnvironment()
}
