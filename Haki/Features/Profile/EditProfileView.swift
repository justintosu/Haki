//
//  EditProfileView.swift
//  Haki
//
//  Sheet for editing your photo, name, username, bio and portfolio sharing.
//

import CoreGraphics
import Foundation
import PhotosUI
import SwiftUI
import UIKit

struct EditProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    /// The saved values the form started from; `nil` until the profile is loaded.
    @State private var original: EditProfileValues?
    @State private var displayName = ""
    @State private var username = ""
    @State private var bio = ""
    @State private var sharePortfolio = true

    @State private var photoItem: PhotosPickerItem?
    @State private var avatarJPEG: Data?
    @State private var avatarPreview: UIImage?
    @State private var isLoadingPhoto = false

    @State private var isLoadingProfile = true
    @State private var isSaving = false
    /// The server's verdict on the username, e.g. "That username is taken."
    @State private var usernameError: String?
    @State private var errorMessage: String?
    @State private var confirmingDiscard = false
    @FocusState private var focusedField: EditProfileField?

    private static let avatarSize: CGFloat = 96

    init() {}

    var body: some View {
        NavigationStack {
            Group {
                if original != nil {
                    form
                } else if isLoadingProfile {
                    ProgressView("Loading your profile…")
                } else {
                    ProfileLoadFailedView(
                        title: "Couldn't load your profile",
                        message: auth.errorMessage ?? "Check your connection and try again."
                    ) {
                        Task { await loadProfile() }
                    }
                }
            }
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard changes", role: .destructive) {
                    dismiss()
                }
                Button("Keep editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(hasChanges || isSaving)
        .task {
            await loadProfile()
        }
        .onChange(of: username) { _, newValue in
            let normalized = UsernameRules.normalize(newValue)
            if normalized != newValue {
                username = normalized
            }
            usernameError = nil
        }
        .onChange(of: displayName) { _, newValue in
            let limited = ProfileTextRules.limited(newValue, to: ProfileTextRules.displayNameLimit)
            if limited != newValue {
                displayName = limited
            }
        }
        .onChange(of: bio) { _, newValue in
            let limited = ProfileTextRules.limited(newValue, to: ProfileTextRules.bioLimit)
            if limited != newValue {
                bio = limited
            }
        }
        .onChange(of: photoItem) { _, newItem in
            Task { await loadPhoto(newItem) }
        }
        .sensoryFeedback(.error, trigger: usernameError) { _, newValue in
            newValue != nil
        }
        .profileErrorAlert($errorMessage)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                if hasChanges {
                    confirmingDiscard = true
                } else {
                    dismiss()
                }
            }
            .disabled(isSaving)
        }
        ToolbarItem(placement: .confirmationAction) {
            if isSaving {
                ProgressView()
                    .accessibilityLabel("Saving")
            } else {
                Button("Save") {
                    Task { await save() }
                }
                .fontWeight(.semibold)
                .disabled(!canSave)
            }
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            photoSection
            nameSection
            usernameSection
            bioSection
            privacySection
        }
        .scrollDismissesKeyboard(.interactively)
        .disabled(isSaving)
    }

    private var photoSection: some View {
        Section {
            VStack(spacing: 12) {
                avatar
                HStack(spacing: 12) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Change photo", systemImage: "camera.fill")
                    }
                    .buttonStyle(.bordered)

                    if avatarJPEG != nil {
                        Button {
                            avatarJPEG = nil
                            avatarPreview = nil
                            photoItem = nil
                        } label: {
                            Label("Undo", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Keep your current photo")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(isLoadingPhoto)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .listRowBackground(Color.clear)
        }
    }

    private var avatar: some View {
        ZStack {
            if let avatarPreview {
                Image(uiImage: avatarPreview)
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
                    .tint(Color.white)
            }
        }
        .frame(width: Self.avatarSize, height: Self.avatarSize)
        .accessibilityElement()
        .accessibilityLabel(avatarDescription)
    }

    private var nameSection: some View {
        Section {
            TextField("Your name", text: $displayName)
                .textContentType(.name)
                .submitLabel(.next)
                .focused($focusedField, equals: .displayName)
                .onSubmit { focusedField = .username }
                .accessibilityLabel("Display name")
        } header: {
            Text("Name")
        } footer: {
            Text("Shown on your profile and posts.")
        }
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
                    .textContentType(.username)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .username)
                    .onSubmit { focusedField = .bio }
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
        if usernameError != nil {
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
        if let message = usernameError {
            Label(message, systemImage: "xmark.circle")
                .foregroundStyle(Color.hakiNegative)
        } else if username.isEmpty {
            Text("Use \(UsernameRules.lengthRange.lowerBound)–\(UsernameRules.lengthRange.upperBound) characters: \(UsernameRules.allowedCharacters).")
        } else if let problem = UsernameRules.problem(with: username) {
            Label(problem, systemImage: "exclamationmark.circle")
                .foregroundStyle(Color.hakiWarning)
        } else if username != original?.username {
            Label("Friends will find you as @\(username).", systemImage: "checkmark.circle")
        } else {
            Text("Friends find you as @\(username).")
        }
    }

    private var bioSection: some View {
        Section {
            TextField("Tell people what you invest in", text: $bio, axis: .vertical)
                .lineLimit(3...6)
                .focused($focusedField, equals: .bio)
                .accessibilityLabel("Bio")
        } header: {
            Text("Bio")
        } footer: {
            HStack {
                Spacer()
                Text("\(bioLength)/\(ProfileTextRules.bioLimit)")
                    .monospacedDigit()
                    .foregroundStyle(bioLength >= ProfileTextRules.bioLimit ? Color.hakiWarning : Color.secondary)
                    .accessibilityLabel("\(bioLength) of \(ProfileTextRules.bioLimit) characters")
            }
        }
    }

    private var privacySection: some View {
        Section {
            Toggle("Share portfolio percentages", isOn: $sharePortfolio)
        } header: {
            Text("Privacy")
        } footer: {
            Text(privacyFooter)
        }
    }

    // MARK: Derived

    private var currentValues: EditProfileValues {
        EditProfileValues(
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username,
            bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
            sharePortfolio: sharePortfolio
        )
    }

    private var hasChanges: Bool {
        guard let original else { return false }
        return avatarJPEG != nil || original != currentValues
    }

    private var canSave: Bool {
        hasChanges
            && UsernameRules.isValid(username)
            && usernameError == nil
            && bioLength <= ProfileTextRules.bioLimit
            && !isSaving
            && !isLoadingPhoto
    }

    private var bioLength: Int {
        ProfileTextRules.length(bio)
    }

    private var previewName: String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? username : name
    }

    private var avatarDescription: String {
        if avatarPreview != nil { return "Your new profile photo" }
        return auth.profile?.avatarURL == nil ? "No profile photo yet" : "Your profile photo"
    }

    private var privacyFooter: String {
        if sharePortfolio {
            return "People who visit your profile see what you hold and each holding's share of your portfolio, plus your total return. Dollar amounts, balances and account details are never shown."
        }
        return "Your portfolio is hidden from everyone else. You still see it on your own profile."
    }

    // MARK: Actions

    /// Fills the form from the signed-in profile, loading it first if needed.
    private func loadProfile() async {
        if original == nil, let record = auth.profile {
            prefill(from: record)
        }
        guard original == nil else {
            isLoadingProfile = false
            return
        }
        isLoadingProfile = true
        await auth.refreshProfile()
        if original == nil, let record = auth.profile {
            prefill(from: record)
        }
        isLoadingProfile = false
    }

    private func prefill(from record: ProfileRecord) {
        let values = EditProfileValues(
            displayName: ProfileTextRules.limited(
                record.displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                to: ProfileTextRules.displayNameLimit
            ),
            username: UsernameRules.normalize(record.username),
            bio: ProfileTextRules.limited(
                record.bio.trimmingCharacters(in: .whitespacesAndNewlines),
                to: ProfileTextRules.bioLimit
            ),
            sharePortfolio: record.sharePortfolio
        )
        displayName = values.displayName
        username = values.username
        bio = values.bio
        sharePortfolio = values.sharePortfolio
        original = values
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let jpeg = ImageUpload.jpegData(from: data, maxDimension: 512, quality: 0.85),
                  let image = UIImage(data: jpeg)
            else {
                errorMessage = "Haki couldn't use that photo. Try a different one."
                return
            }
            avatarJPEG = jpeg
            avatarPreview = image
        } catch {
            errorMessage = "Haki couldn't load that photo. Try a different one."
        }
    }

    /// Sends only what changed (`nil` = unchanged).
    private func save() async {
        guard canSave, let original else { return }
        focusedField = nil
        isSaving = true
        defer { isSaving = false }

        let values = currentValues
        let newUsername: String? = values.username != original.username ? values.username : nil
        let newDisplayName: String? = values.displayName != original.displayName ? values.displayName : nil
        let newBio: String? = values.bio != original.bio ? values.bio : nil
        let newSharePortfolio: Bool? = values.sharePortfolio != original.sharePortfolio ? values.sharePortfolio : nil

        do {
            try await auth.updateProfile(
                username: newUsername,
                displayName: newDisplayName,
                bio: newBio,
                sharePortfolio: newSharePortfolio,
                avatarJPEG: avatarJPEG
            )
            dismiss()
        } catch {
            if ProfileErrorInfo.isCancellation(error) { return }
            if ProfileErrorInfo.isUsernameTaken(error) {
                usernameError = "That username is taken."
                focusedField = .username
            } else {
                errorMessage = ProfileErrorInfo.message(for: error)
            }
        }
    }
}

private nonisolated struct EditProfileValues: Equatable {
    var displayName: String
    var username: String
    var bio: String
    var sharePortfolio: Bool
}

private nonisolated enum EditProfileField: Hashable {
    case displayName
    case username
    case bio
}

#Preview {
    EditProfileView()
        .previewEnvironment()
}
