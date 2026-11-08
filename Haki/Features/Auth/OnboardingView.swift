//
//  OnboardingView.swift
//  Haki
//
//  Shown once after the first sign-in (`AuthService.State.needsOnboarding`):
//  pick a username, a display name and an optional photo, and choose whether
//  the portfolio is shared (as percentages) on the profile.
//

import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct OnboardingView: View {
    @Environment(AuthService.self) private var auth

    @State private var username = ""
    @State private var displayName = ""
    @State private var sharePortfolio = true
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarJPEG: Data?
    /// `avatarJPEG` decoded once for the preview, so typing doesn't re-decode it.
    @State private var avatarImage: UIImage?
    @State private var isLoadingPhoto = false
    @State private var didPrefill = false
    /// The server's verdict on the username, e.g. "That username is taken."
    @State private var usernameServerError: String?
    @State private var isSaving = false
    @State private var isSigningOut = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: OnboardingField?

    /// `profiles.display_name` is limited to 50 characters.
    private static let displayNameLimit = 50
    private static let avatarSize: CGFloat = 96

    var body: some View {
        NavigationStack {
            Form {
                headerSection
                usernameSection
                nameSection
                privacySection
                accountSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Your profile")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                continueBar
            }
        }
        .onAppear {
            prefillIfNeeded()
        }
        .onChange(of: auth.profile?.id) {
            prefillIfNeeded()
        }
        .task {
            if auth.profile == nil {
                await auth.refreshProfile()
            }
        }
        .onChange(of: username) { _, newValue in
            let normalized = UsernameRules.normalize(newValue)
            if normalized != newValue {
                username = normalized
            }
            usernameServerError = nil
        }
        .onChange(of: displayName) { _, newValue in
            let limited = AuthText.limited(newValue, to: Self.displayNameLimit)
            if limited != newValue {
                displayName = limited
            }
        }
        .onChange(of: photoItem) { _, newItem in
            Task { await loadPhoto(newItem) }
        }
        .sensoryFeedback(.error, trigger: usernameServerError) { _, newValue in
            newValue != nil
        }
        .authErrorAlert(alertMessage)
    }

    // MARK: Sections

    private var headerSection: some View {
        Section {
            VStack(spacing: 16) {
                VStack(spacing: 6) {
                    Text("Welcome to Haki")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("Pick a username so friends can find you. You can change all of this later.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                avatar
                photoButtons
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private var avatar: some View {
        ZStack {
            if let avatarImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: Self.avatarSize, height: Self.avatarSize)
                    .clipShape(Circle())
            } else {
                AvatarView(url: auth.profile?.avatarURL, name: previewName, size: Self.avatarSize)
            }
            if isLoadingPhoto {
                Circle()
                    .fill(Color.black.opacity(0.35))
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .accessibilityElement()
        .accessibilityLabel(avatarJPEG == nil ? "No profile photo yet" : "Your new profile photo")
    }

    private var photoButtons: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $photoItem, matching: .images) {
                Label(avatarJPEG == nil ? "Add photo" : "Change photo", systemImage: "camera.fill")
            }
            .buttonStyle(.bordered)

            if avatarJPEG != nil {
                Button(role: .destructive) {
                    avatarJPEG = nil
                    avatarImage = nil
                    photoItem = nil
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .font(.subheadline.weight(.semibold))
        .disabled(isLoadingPhoto || isSaving)
    }

    private var usernameSection: some View {
        Section {
            HStack(spacing: 6) {
                Text("@")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .displayName }
                    .accessibilityLabel("Username")
                usernameStatusIcon
            }
        } header: {
            Text("Username")
        } footer: {
            usernameFeedback
        }
    }

    @ViewBuilder
    private var usernameStatusIcon: some View {
        if usernameServerError != nil {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.hakiNegative)
                .accessibilityHidden(true)
        } else if UsernameRules.isValid(username) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.hakiPositive)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var usernameFeedback: some View {
        if let usernameServerError {
            Label(usernameServerError, systemImage: "xmark.circle")
                .foregroundStyle(Color.hakiNegative)
        } else if username.isEmpty {
            Text("Use \(UsernameRules.lengthRange.lowerBound)–\(UsernameRules.lengthRange.upperBound) characters: \(UsernameRules.allowedCharacters).")
        } else if let problem = UsernameRules.problem(with: username) {
            Label(problem, systemImage: "exclamationmark.circle")
                .foregroundStyle(Color.hakiWarning)
        } else {
            Label("Friends can find you as @\(username).", systemImage: "checkmark.circle")
        }
    }

    private var nameSection: some View {
        Section {
            TextField("Your name", text: $displayName)
                .textContentType(.name)
                .submitLabel(.done)
                .focused($focusedField, equals: .displayName)
                .onSubmit { focusedField = nil }
                .accessibilityLabel("Display name")
        } header: {
            Text("Name")
        } footer: {
            Text("Shown on your profile and posts. Optional.")
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Show my portfolio as percentages on my profile", isOn: $sharePortfolio)
        } header: {
            Text("Privacy")
        } footer: {
            Text("People who view your profile see the stocks and funds you hold and each one's share of your portfolio. Dollar amounts, balances and account details are never shown. You can change this any time in Settings.")
        }
    }

    private var accountSection: some View {
        Section {
            Button {
                Task { await signOut() }
            } label: {
                HStack(spacing: 8) {
                    if isSigningOut {
                        ProgressView()
                    }
                    Text(isSigningOut ? "Signing out…" : "Not you? Sign out")
                }
            }
            .disabled(isSaving || isSigningOut)
        } footer: {
            if let email = auth.email {
                Text("Signed in as \(email)")
            }
        }
    }

    private var continueBar: some View {
        VStack(spacing: 0) {
            Divider()
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if isSaving {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSaving ? "Saving…" : "Continue")
                }
            }
            .buttonStyle(AuthButtonStyle(kind: .prominent))
            .disabled(!canContinue)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }

    // MARK: State

    private var previewName: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? username : name
    }

    private var canContinue: Bool {
        UsernameRules.isValid(username) && usernameServerError == nil
            && !isSaving && !isLoadingPhoto && !isSigningOut
    }

    private var alertMessage: Binding<String?> {
        Binding(
            get: { errorMessage ?? auth.errorMessage },
            set: { newValue in
                if newValue == nil {
                    errorMessage = nil
                    auth.errorMessage = nil
                }
            }
        )
    }

    // MARK: Actions

    /// Fills the fields from the profile the sign-up trigger created, once.
    private func prefillIfNeeded() {
        guard !didPrefill, let profile = auth.profile else { return }
        didPrefill = true
        if username.isEmpty {
            username = UsernameRules.normalize(profile.username)
        }
        if displayName.isEmpty {
            displayName = AuthText.limited(profile.displayName, to: Self.displayNameLimit)
        }
        sharePortfolio = profile.sharePortfolio
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoadingPhoto = true
        defer {
            // A newer pick that's still loading keeps the spinner.
            if photoItem == nil || photoItem == item {
                isLoadingPhoto = false
            }
        }
        do {
            let data = try await item.loadTransferable(type: Data.self)
            // A newer pick (or "Remove") replaced this one while it loaded.
            guard photoItem == item else { return }
            guard let data,
                  let jpeg = ImageUpload.jpegData(from: data, maxDimension: 512, quality: 0.85),
                  let image = UIImage(data: jpeg)
            else {
                photoItem = nil
                errorMessage = "Haki couldn't use that photo. Try a different one."
                return
            }
            avatarJPEG = jpeg
            avatarImage = image
        } catch {
            guard photoItem == item else { return }
            photoItem = nil
            errorMessage = "Haki couldn't load that photo. Try a different one."
        }
    }

    private func submit() async {
        guard canContinue else { return }
        focusedField = nil
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        auth.errorMessage = nil
        let name = AuthText.limited(
            displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            to: Self.displayNameLimit
        )
        do {
            try await auth.completeOnboarding(
                username: username,
                displayName: name,
                sharePortfolio: sharePortfolio,
                avatarJPEG: avatarJPEG
            )
        } catch {
            if AuthErrorFormatter.isUsernameTaken(error) {
                usernameServerError = "That username is taken."
                focusedField = .username
            } else if let problem = AuthErrorFormatter.usernameProblem(error) {
                usernameServerError = problem
                focusedField = .username
            } else {
                errorMessage = AuthErrorFormatter.message(for: error)
            }
        }
    }

    private func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        focusedField = nil
        await auth.signOut()
    }
}

private enum OnboardingField: Hashable {
    case username
    case displayName
}

#Preview {
    OnboardingView()
        .previewEnvironment()
}
