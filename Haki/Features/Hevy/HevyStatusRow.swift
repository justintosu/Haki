//
//  HevyStatusRow.swift
//  Haki
//
//  A plain row showing the Hevy connection at a glance (icon, "Hevy", its
//  status, chevron). Screens put it in a NavigationLink label that opens
//  HevySettingsView.
//

import Foundation
import SwiftUI

struct HevyStatusRow: View {
    @Environment(HevySyncService.self) private var hevy

    private let showsChevron: Bool

    /// `showsChevron: false` inside a `List`, which draws its own.
    init(showsChevron: Bool = true) {
        self.showsChevron = showsChevron
    }

    var body: some View {
        HStack(spacing: 12) {
            HevyIconTile()
            VStack(alignment: .leading, spacing: 2) {
                Text("Hevy")
                    .foregroundStyle(.primary)
                status
            }
            Spacer(minLength: 8)
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: Status

    private var isPosting: Bool {
        hevy.isConnected && !hevy.uploadingWorkoutIDs.isEmpty
    }

    private var isBusy: Bool {
        hevy.isSyncing || isPosting
    }

    @ViewBuilder
    private var status: some View {
        if !hevy.isConnected {
            Text("Not connected")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if hevy.isSyncing {
            Text("Syncing…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if isPosting {
            Text("Posting to Hevy…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let error = hevy.lastError {
            Label {
                Text(error)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
            .foregroundStyle(Color.hakiWarning)
        } else {
            // Re-rendered every minute so "5 minutes ago" stays true.
            TimelineView(.everyMinute) { _ in
                Text(HevyFormat.syncedText(hevy.lastSyncAt))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        HevyStatusRow()
            .padding(.vertical, 10)
        Divider()
        HevyStatusRow()
            .padding(.vertical, 10)
            .environment(HevySyncService.makePreview(connected: false))
    }
    .hakiCard()
    .padding()
    .frame(maxHeight: .infinity, alignment: .top)
    .background(Color.hakiBackground)
    .previewEnvironment()
}
