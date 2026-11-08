//
//  AccountSettingsSection.swift
//  Haki
//
//  The account part of Settings: who's signed in, editing the profile,
//  changing the password, portfolio sharing, signing out and deleting the account. Embedded in
//  SettingsView's list as a few `Section`s.
//

import Foundation
import SwiftUI

struct AccountSettingsSection: View {
    @Environment(AuthService.self) private var auth

    @State private var showingEditProfile = false
    @State private var showingChangePassword = false
    @State private var confirmingSignOut = false
    @State private var confirmingDelete = false
    @State private var isSigningOut = false
    @State private var isDeleting = false
    @State private var isRefreshingProfile = false
    /// The sharing choice while it's being saved (optimistic), `nil` otherwise.
    @State private var pendingSharePortfolio: Bool?
    @State private var sharingError: String?
    @State private var deleteError: String?

    private var isBusy: Bool { isSigningOut || isDeleting }

    var body: some View {
        accountSection
        privacySection
        deleteSection
    }

    // MARK: Account

    private var accountSection: some View {
        Section {
            if let profile = auth.profile {
                profileRow(profile)
            } else {
                missingProfileRow
            }

            LabeledContent("Signed in as") {
                Text(signedInAs)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Button {
                showingEditProfile = true
            } label: {
                Label("Edit profile", systemImage: "person.crop.circle")
            }
            .disabled(auth.profile == nil || isBusy)
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
            }

            if auth.signsInWithPassword {
                Button {
                    showingChangePassword = true
                } label: {
                    Label("Change password", systemImage: "key")
                }
                .disabled(isBusy)
                .sheet(isPresented: $showingChangePassword) {
                    AuthSetNewPasswordView()
                }
            }

            Button(role: .destructive) {
                confirmingSignOut = true
            } label: {
                if isSigningOut {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Signing out…")
                    }
                } else {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            .disabled(isBusy)
            .confirmationDialog("Sign out of Haki?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await signOut() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your budgets and transactions stay on this iPhone. Sign back in any time to see your feed and portfolio.")
            }
        } header: {
            Text("Account")
        }
    }

    private func profileRow(_ profile: ProfileRecord) -> some View {
        HStack(spacing: 12) {
            AvatarView(url: profile.avatarURL, name: profile.name, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
                Text("@\(profile.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var missingProfileRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Profile not loaded")
                    .font(.headline)
                Text(auth.errorMessage ?? "Check your connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if isRefreshingProfile {
                ProgressView()
            } else {
                Button("Retry") {
                    Task { await refreshProfile() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Privacy

    private var privacySection: some View {
        Section {
            Toggle(isOn: sharePortfolioBinding) {
                HStack(spacing: 8) {
                    Text("Share portfolio percentages")
                    if pendingSharePortfolio != nil {
                        ProgressView()
                            .accessibilityLabel("Saving")
                    }
                }
            }
            .disabled(auth.profile == nil || pendingSharePortfolio != nil || isBusy)
            .authErrorAlert($sharingError, title: "Couldn't update sharing")
        } header: {
            Text("Privacy")
        } footer: {
            Text("When this is on, people who view your profile see the stocks and funds you hold, each one's share of your portfolio and its return in percent, and your overall gain or loss in percent. Your posts about a stock you hold show a “holds” badge. Dollar amounts, balances and account details are never shared.")
        }
    }

    private var sharePortfolioBinding: Binding<Bool> {
        Binding(
            get: { pendingSharePortfolio ?? auth.profile?.sharePortfolio ?? false },
            set: { newValue in
                guard pendingSharePortfolio == nil else { return }
                pendingSharePortfolio = newValue
                Task { await saveSharePortfolio(newValue) }
            }
        )
    }

    // MARK: Delete

    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                if isDeleting {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Deleting your account…")
                    }
                } else {
                    Label("Delete account", systemImage: "trash")
                }
            }
            .disabled(isBusy)
            .interactiveDismissDisabled(isDeleting)
            .confirmationDialog("Delete your Haki account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete account", role: .destructive) {
                    Task { await deleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes your profile, posts, comments, follows and brokerage connections. It can't be undone. Budgets and transactions on this iPhone stay unless you erase them separately in Settings.")
            }
            .authErrorAlert($deleteError, title: "Couldn't delete your account")
        } footer: {
            Text("Deleting your account removes everything Haki stores online. Money data on this iPhone isn't affected.")
        }
    }

    // MARK: State

    private var signedInAs: String {
        if let email = auth.email, !email.isEmpty { return email }
        if let username = auth.profile?.username { return "@\(username)" }
        return "—"
    }

    // MARK: Actions

    private func saveSharePortfolio(_ value: Bool) async {
        defer { pendingSharePortfolio = nil }
        do {
            try await auth.updateProfile(
                username: nil,
                displayName: nil,
                bio: nil,
                sharePortfolio: value,
                avatarJPEG: nil
            )
        } catch {
            // The toggle falls back to the saved value when `pendingSharePortfolio` clears.
            sharingError = AuthErrorFormatter.message(for: error)
        }
    }

    private func refreshProfile() async {
        guard !isRefreshingProfile else { return }
        isRefreshingProfile = true
        defer { isRefreshingProfile = false }
        await auth.refreshProfile()
    }

    private func signOut() async {
        guard !isBusy else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await auth.signOut()
    }

    private func deleteAccount() async {
        guard !isBusy else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await auth.deleteAccount()
        } catch {
            deleteError = AuthErrorFormatter.message(for: error)
        }
    }
}

#Preview {
    NavigationStack {
        Form {
            AccountSettingsSection()
        }
        .navigationTitle("Settings")
    }
    .previewEnvironment()
}
