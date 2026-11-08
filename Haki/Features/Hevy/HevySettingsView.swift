//
//  HevySettingsView.swift
//  Haki
//
//  Connecting Haki to the person's Hevy account with their own API key:
//  what syncing does, where to get a key (Hevy Pro), the connection's
//  status, posting Haki workouts to Hevy, and disconnecting. Pushed from the
//  Health tab and from Workouts.
//

import Foundation
import SwiftData
import SwiftUI

struct HevySettingsView: View {
    @Environment(HevySyncService.self) private var hevy
    @Environment(\.modelContext) private var modelContext

    @AppStorage(HevySyncService.uploadPrivateKey) private var postsPrivately = false

    @Query(filter: #Predicate<WorkoutRecord> { $0.sourceRaw == "hevy" })
    private var copiedWorkouts: [WorkoutRecord]
    @Query(filter: #Predicate<WorkoutRecord> { $0.sourceRaw == "haki" && $0.hevyID != nil })
    private var postedWorkouts: [WorkoutRecord]

    @State private var apiKeyText = ""
    @State private var showsKey = false
    @State private var isConnecting = false
    @State private var connectError: String?
    @State private var showsDisconnectConfirmation = false
    @FocusState private var isKeyFieldFocused: Bool
    @ScaledMetric(relativeTo: .title2) private var introIconSize: CGFloat = 52

    var body: some View {
        @Bindable var bindableHevy = hevy
        Form {
            introSection
            if hevy.isConnected {
                accountSection
                postingSection(uploadEnabled: $bindableHevy.uploadEnabled)
                disconnectSection
            } else {
                howItWorksSection
                connectSection
            }
            privacySection
        }
        .navigationTitle("Hevy")
        .scrollDismissesKeyboard(.interactively)
        .animation(.snappy, value: hevy.isConnected)
        .refreshable {
            await refresh()
        }
        .task {
            hevy.syncIfDue(in: modelContext)
        }
        .onChange(of: hevy.isConnected) { _, connected in
            guard connected else { return }
            apiKeyText = ""
            showsKey = false
            connectError = nil
        }
        .onChange(of: apiKeyText) { _, _ in
            // An old error doesn't apply to a key that's being edited.
            if connectError != nil && !isConnecting {
                connectError = nil
            }
        }
        .sensoryFeedback(.success, trigger: hevy.isConnected, condition: { old, new in
            !old && new
        })
        .confirmationDialog("Disconnect Hevy?", isPresented: $showsDisconnectConfirmation, titleVisibility: .visible) {
            Button("Disconnect and remove copied workouts", role: .destructive) {
                disconnect(removingCopies: true)
            }
            Button("Disconnect, keep workouts") {
                disconnect(removingCopies: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(disconnectMessage)
        }
    }

    // MARK: Intro

    private var introSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                HevyIconTile(size: introIconSize, font: .title2.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync with Hevy")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("Your Hevy workouts appear in Haki; workouts you log in Haki can be posted to Hevy.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Not connected

    private var howItWorksSection: some View {
        Section {
            HevyFeatureRow(
                systemImage: "arrow.down.circle.fill",
                tint: HevyStyle.tint,
                title: "From Hevy to Haki",
                message: "Workouts you log in Hevy are copied into Haki, so your history, records and weekly stats include them. Edits and deletions in Hevy follow."
            )
            HevyFeatureRow(
                systemImage: "arrow.up.circle.fill",
                tint: .accentColor,
                title: "From Haki to Hevy",
                message: "If you like, workouts you finish in Haki are posted to your Hevy account too."
            )
            HevyFeatureRow(
                systemImage: "key.fill",
                tint: .orange,
                title: "Needs Hevy Pro",
                message: "Hevy gives API keys to Pro members. You create one on hevy.com under Settings → Developer."
            )
        } header: {
            Text("How it works")
        }
    }

    private var connectSection: some View {
        Section {
            if let url = URL(string: HevyAPI.developerSettingsURL) {
                Link(destination: url) {
                    Label("Get your API key on hevy.com", systemImage: "arrow.up.right.square")
                }
            }
            keyField
            connectButton
            if let connectError {
                Label {
                    Text(connectError)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
                .foregroundStyle(Color.hakiWarning)
            }
        } header: {
            Text("Connect your account")
        } footer: {
            Text("On hevy.com, open Settings → Developer, create an API key, then copy it and paste it here.")
        }
    }

    private var keyField: some View {
        HStack(spacing: 8) {
            Group {
                if showsKey {
                    TextField("API key", text: $apiKeyText)
                } else {
                    SecureField("API key", text: $apiKeyText)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .focused($isKeyFieldFocused)
            .submitLabel(.go)
            .onSubmit {
                connect()
            }
            .disabled(isConnecting)

            Button {
                // The visible and hidden fields are different views; keep
                // the keyboard up when switching between them.
                let wasFocused = isKeyFieldFocused
                showsKey.toggle()
                if wasFocused {
                    isKeyFieldFocused = true
                }
            } label: {
                Image(systemName: showsKey ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 32, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(showsKey ? "Hide API key" : "Show API key")
        }
    }

    private var connectButton: some View {
        Button {
            connect()
        } label: {
            HStack(spacing: 8) {
                if isConnecting {
                    ProgressView()
                }
                Text(isConnecting ? "Connecting…" : "Connect")
                    .font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(trimmedKey.isEmpty || isConnecting)
    }

    // MARK: Connected

    private var accountSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.hakiPositive)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(connectedTitle)
                        .font(.body.weight(.semibold))
                    Text(workoutStatsText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)

            LabeledContent("Last sync") {
                TimelineView(.everyMinute) { _ in
                    Text(hevy.isSyncing ? "Syncing…" : HevyFormat.lastSyncText(hevy.lastSyncAt))
                }
            }

            if let error = hevy.lastError, !hevy.isSyncing {
                Label {
                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
                .foregroundStyle(Color.hakiWarning)
            }

            syncButton
        } header: {
            Text("Account")
        } footer: {
            Text("Haki checks Hevy for new and changed workouts when you open Workouts, at most every 15 minutes. Pull down to sync now.")
        }
    }

    private var syncButton: some View {
        Button {
            Task {
                await hevy.sync(in: modelContext)
            }
        } label: {
            HStack(spacing: 8) {
                Label(hevy.isSyncing ? "Syncing…" : "Sync now", systemImage: HevyStyle.symbol)
                Spacer(minLength: 8)
                if hevy.isSyncing {
                    ProgressView()
                        .accessibilityHidden(true)
                }
            }
        }
        .disabled(hevy.isSyncing)
    }

    private func postingSection(uploadEnabled: Binding<Bool>) -> some View {
        Section {
            Toggle("Post workouts logged in Haki to Hevy", isOn: uploadEnabled)
            Toggle("Post as private workouts", isOn: $postsPrivately)
            if !hevy.uploadingWorkoutIDs.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Posting to Hevy…")
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Posting to Hevy")
        } footer: {
            Text(postingFooter(isOn: uploadEnabled.wrappedValue))
        }
    }

    private var disconnectSection: some View {
        Section {
            Button("Disconnect Hevy", role: .destructive) {
                showsDisconnectConfirmation = true
            }
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section {
            HevyFeatureRow(
                systemImage: "lock.fill",
                tint: .blue,
                title: "Your key stays on this iPhone",
                message: "Your API key is stored in this iPhone's Keychain. Haki talks to Hevy directly; your workouts aren't sent to Haki's servers."
            )
        } footer: {
            Text("Haki isn't affiliated with or endorsed by Hevy.")
        }
    }

    // MARK: Text

    private var trimmedKey: String {
        apiKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var connectedTitle: String {
        if let username = hevy.username, !username.isEmpty {
            return "Connected as @\(username)"
        }
        return "Connected"
    }

    private var workoutStatsText: String {
        let copied = HevyFormat.count(copiedWorkouts.count, "workout", "workouts") + " from Hevy"
        guard !postedWorkouts.isEmpty else { return copied }
        return copied + " · " + postedWorkouts.count.formatted() + " posted from Haki"
    }

    private func postingFooter(isOn: Bool) -> String {
        let privacy = postsPrivately
            ? "Posted workouts are private: only you see them in Hevy."
            : "Posted workouts are visible to your Hevy followers, like ones you log in Hevy."
        if isOn {
            return "When you finish a workout in Haki, it's posted to Hevy too. Exercises Hevy doesn't have are added to your Hevy account as custom exercises. " + privacy
        }
        return "Workouts you finish in Haki stay in Haki. You can still post one from its details. " + privacy
    }

    private var disconnectMessage: String {
        let base = "Haki stops syncing and removes your API key from this iPhone. Workouts you logged in Haki stay, and your Hevy account isn't affected."
        guard !copiedWorkouts.isEmpty else { return base }
        let copies = HevyFormat.count(copiedWorkouts.count, "workout", "workouts")
        return base + " The \(copies) copied from Hevy can stay in Haki or be removed."
    }

    // MARK: Actions

    private func connect() {
        let key = trimmedKey
        guard !key.isEmpty, !isConnecting else { return }
        guard HevyAPI.isPlausibleAPIKey(key) else {
            connectError = HevyClientError.malformedKey.localizedDescription
            return
        }
        isKeyFieldFocused = false
        connectError = nil
        isConnecting = true
        Task {
            do {
                try await hevy.connect(apiKey: key, in: modelContext)
            } catch {
                if !Backend.isCancellation(error) {
                    connectError = error.localizedDescription
                }
            }
            isConnecting = false
        }
    }

    private func refresh() async {
        await hevy.sync(in: modelContext)
    }

    private func disconnect(removingCopies: Bool) {
        withAnimation(.snappy) {
            hevy.disconnect(removeCopiedWorkouts: removingCopies, in: modelContext)
        }
    }
}

#Preview("Connected") {
    NavigationStack {
        HevySettingsView()
    }
    .previewEnvironment()
}

#Preview("Not connected") {
    NavigationStack {
        HevySettingsView()
    }
    .environment(HevySyncService.makePreview(connected: false))
    .previewEnvironment()
}
