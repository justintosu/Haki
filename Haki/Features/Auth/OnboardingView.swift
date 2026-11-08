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
    /// Continue stays disabled until the user agrees to the Community Guidelines.
    @State private var agreesToGuidelines = false
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
                guidelinesSection
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
            fillDisplayNameIfEmpty(auth.pendingAppleDisplayName)
        }
        .onChange(of: auth.profile?.id) {
            prefillIfNeeded()
        }
        // The name Sign in with Apple shared can arrive after this screen appears.
        .onChange(of: auth.profile?.displayName) { _, newValue in
            fillDisplayNameIfEmpty(newValue)
        }
        .onChange(of: auth.pendingAppleDisplayName) { _, newValue in
            fillDisplayNameIfEmpty(newValue)
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
            VStack(alignment: .leading, spacing: 4) {
                Label("People on Haki can find you as @\(username).", systemImage: "checkmark.circle")
                if usernameComesFromEmail {
                    Text("We suggested this from your email address. Usernames are public — pick something else if you'd rather not show it.")
                }
            }
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
            Text("People who view your profile see the stocks and funds you hold, each one's share of your portfolio and its return in percent, and your total return. Your posts about a stock you hold show a “holds” badge. Dollar amounts, balances and account details are never shown. You can change this any time in Settings.")
        }
    }

    private var guidelinesSection: some View {
        Section {
            NavigationLink {
                CommunityGuidelinesView()
            } label: {
                Label("Read the Community Guidelines", systemImage: "hand.raised")
            }
            Toggle("I agree to the Community Guidelines", isOn: $agreesToGuidelines)
                .disabled(isSaving)
        } header: {
            Text("Community")
        } footer: {
            Text("By continuing you agree to the Community Guidelines. Haki doesn't allow harassment, hate, scams or other objectionable content, and removes accounts that post it.")
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
            if !agreesToGuidelines {
                Text("Agree to the Community Guidelines to continue.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
            }
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
        UsernameRules.isValid(username) && usernameServerError == nil && agreesToGuidelines
            && !isSaving && !isLoadingPhoto && !isSigningOut
    }

    /// Whether the username is still the one the sign-up trigger made from the
    /// email address (its local part, perhaps with a number added).
    private var usernameComesFromEmail: Bool {
        guard let email = auth.email, let localPart = email.split(separator: "@").first else { return false }
        let base = String(UsernameRules.normalize(String(localPart)).prefix(18))
        guard base.count >= UsernameRules.lengthRange.lowerBound, username.hasPrefix(base) else { return false }
        return username.dropFirst(base.count).allSatisfy(\.isNumber)
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
        fillDisplayNameIfEmpty(profile.displayName)
        fillDisplayNameIfEmpty(auth.pendingAppleDisplayName)
        sharePortfolio = profile.sharePortfolio
    }

    /// Puts `name` in the name field while it's still empty (nothing typed yet),
    /// e.g. the name Sign in with Apple shared, which can arrive late.
    private func fillDisplayNameIfEmpty(_ name: String?) {
        guard displayName.isEmpty, let name else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        displayName = AuthText.limited(trimmed, to: Self.displayNameLimit)
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
            let jpeg: Data?
            if let data {
                jpeg = await ImageUpload.makeJPEG(from: data, maxDimension: 512, quality: 0.85)
            } else {
                jpeg = nil
            }
            guard photoItem == item else { return }
            guard let jpeg, let image = UIImage(data: jpeg) else {
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
