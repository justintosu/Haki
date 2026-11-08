//
//  BrokerageLinkButton.swift
//  Haki
//
//  The one button that connects a brokerage, used on the Invest tab, the
//  compose screen and profiles. It runs the whole flow: link token from the
//  server → the secure Plaid sheet → exchanging the public token → refresh,
//  with progress, a success haptic and a confirmation, and an alert for every
//  failure. The LinkKit-specific parts live in BrokerageLinkFlow.swift (that
//  module declares its own `Environment` type, so this file doesn't import it).
//

import Foundation
import Observation
import SwiftUI

struct BrokerageLinkButton: View {
    let title: String

    init(title: String = "Connect a brokerage") {
        self.title = title
    }

    @Environment(PortfolioService.self) private var portfolio
    @State private var flow = BrokerageLinkFlow()

    var body: some View {
        Button {
            flow.start(using: portfolio)
        } label: {
            label
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        // Stays tinted while busy (the label shows progress); taps are ignored.
        .allowsHitTesting(!flow.isBusy)
        .accessibilityValue(busyText ?? "")
        .accessibilityHint("Opens a secure, read-only connection to your brokerage.")
        .sheet(isPresented: $flow.isPresentingLink, onDismiss: { flow.linkSheetDidDismiss() }) {
            BrokerageLinkSheetView(flow: flow)
        }
        .alert(flow.alert?.title ?? "", isPresented: alertBinding, presenting: flow.alert) { _ in
            Button("OK", role: .cancel) {}
        } message: { alert in
            Text(alert.message)
        }
        .onAppear { flow.isOnScreen = true }
        .onDisappear { flow.isOnScreen = false }
    }

    @ViewBuilder
    private var label: some View {
        switch flow.phase {
        case .idle, .linking:
            Label(title, systemImage: "link")
                .font(.body.weight(.semibold))
        case .preparing:
            progressLabel("Opening secure connection…")
        case .connecting:
            progressLabel("Connecting…")
        }
    }

    private func progressLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .tint(Color.white)
            Text(text)
                .font(.body.weight(.semibold))
        }
    }

    private var busyText: String? {
        switch flow.phase {
        case .idle, .linking: nil
        case .preparing: "Opening"
        case .connecting: "Connecting"
        }
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { flow.alert != nil },
            set: { if !$0 { flow.alert = nil } }
        )
    }
}

// MARK: - Alerts and notices

/// Something to tell the user after the flow: a confirmation or a failure.
struct BrokerageLinkAlert: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String

    static func connected(_ institutionName: String) -> BrokerageLinkAlert {
        BrokerageLinkAlert(
            title: "Connected \(institutionName)",
            message: "Your holdings are syncing now. It can take a minute for everything to show up."
        )
    }

    static func failure(_ error: any Error) -> BrokerageLinkAlert {
        if let backendError = error as? BackendError, backendError.code == "plaid_not_configured" {
            return BrokerageLinkAlert(
                title: "Not available yet",
                message: "Brokerage connections aren't set up on the server yet."
            )
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return BrokerageLinkAlert(
            title: "Couldn't connect",
            message: message.isEmpty ? "Something went wrong. Try again." : message
        )
    }
}

/// Connections that finished after the button that started them left the
/// screen (a first connection replaces the screen's empty state). The Invest
/// tab picks these up and confirms them with a toast.
@Observable final class BrokerageLinkCenter {
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        let institutionName: String
        let date = Date.now
    }

    static let shared = BrokerageLinkCenter()

    var unannounced: Notice?

    private init() {}
}

#Preview("In a card") {
    VStack(spacing: 16) {
        BrokerageLinkButton()
        BrokerageLinkButton(title: "Connect another brokerage")
    }
    .padding()
    .previewEnvironment()
}

#Preview("In a form") {
    Form {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect a brokerage first")
                    .font(.headline)
                BrokerageLinkButton()
            }
            .padding(.vertical, 6)
        }
    }
    .previewEnvironment()
}
