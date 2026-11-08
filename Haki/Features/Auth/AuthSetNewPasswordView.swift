//
//  AuthSetNewPasswordView.swift
//  Haki
//
//  Sheet: choose a new password. AuthGateView shows it after a password-reset
//  link is opened (`AuthService.isRecoveringPassword`); Settings shows it as
//  "Change password" for accounts that sign in with email.
//

import Foundation
import SwiftUI
import UIKit

struct AuthSetNewPasswordView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var password = ""
    @State private var confirmation = ""
    @State private var isSaving = false
    @State private var errorText: String?
    @State private var didSave = false
    @FocusState private var focusedField: AuthNewPasswordField?

    var body: some View {
        NavigationStack {
            Group {
                if didSave {
                    saved
                        .transition(.opacity)
                } else {
                    form
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: didSave)
            .navigationTitle(didSave ? "Password updated" : "New password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !didSave {
                        Button(auth.isRecoveringPassword ? "Not now" : "Cancel") {
                            finish()
                        }
                        .disabled(isSaving)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .sensoryFeedback(.success, trigger: didSave) { _, newValue in
            newValue
        }
        .task {
            // Bring up the keyboard once the sheet has settled.
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled, password.isEmpty, !didSave {
                focusedField = .password
            }
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .font(.largeTitle)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text(intro)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                SecureField("New password", text: $password)
                    .textContentType(UITextContentType.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focusedField, equals: .password)
                    .onSubmit { focusedField = .confirmation }
                    .accessibilityLabel("New password")
                SecureField("Confirm new password", text: $confirmation)
                    .textContentType(UITextContentType.newPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .focused($focusedField, equals: .confirmation)
                    .onSubmit { Task { await save() } }
                    .accessibilityLabel("Confirm new password")
            } footer: {
                hints
            }

            if let errorText {
                Section {
                    Label(errorText, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.hakiNegative)
                        .accessibilityLabel("Error: \(errorText)")
                }
            }

            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack(spacing: 8) {
                        if isSaving {
                            ProgressView()
                                .tint(.white)
                        }
                        Text(isSaving ? "Saving…" : "Save password")
                    }
                }
                .buttonStyle(AuthButtonStyle(kind: .prominent))
                .disabled(!canSave)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: password) {
            if errorText != nil { errorText = nil }
        }
        .onChange(of: confirmation) {
            if errorText != nil { errorText = nil }
        }
    }

    private var hints: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(
                "At least \(AuthService.minimumPasswordLength) characters",
                systemImage: isLongEnough ? "checkmark.circle.fill" : "circle"
            )
            .foregroundStyle(isLongEnough ? Color.hakiPositive : Color.secondary)
            .accessibilityValue(isLongEnough ? "Requirement met" : "Requirement not met")
            if !confirmation.isEmpty {
                Label(
                    passwordsMatch ? "Passwords match" : "Passwords don't match",
                    systemImage: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle"
                )
                .foregroundStyle(passwordsMatch ? Color.hakiPositive : Color.hakiWarning)
            }
        }
        .padding(.top, 2)
    }

    // MARK: Saved

    private var saved: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.hakiPositive)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Your new password is saved")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(savedDetail)
                        .foregroundStyle(.secondary)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                Button("Done") {
                    finish()
                }
                .buttonStyle(AuthButtonStyle(kind: .prominent))
                .padding(.top, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color.hakiBackground)
    }

    // MARK: State

    private var accountName: String {
        if let email = auth.email, !email.isEmpty { return email }
        return "your Haki account"
    }

    private var intro: String {
        if auth.isRecoveringPassword {
            return "You opened a password reset link. Choose a new password for \(accountName) — you'll use it the next time you sign in."
        }
        return "Choose a new password for \(accountName)."
    }

    private var savedDetail: String {
        "Use it the next time you sign in to \(accountName) with your email."
    }

    private var isLongEnough: Bool {
        password.count >= AuthService.minimumPasswordLength
    }

    private var passwordsMatch: Bool {
        !confirmation.isEmpty && confirmation == password
    }

    private var canSave: Bool {
        !isSaving && isLongEnough && passwordsMatch
    }

    // MARK: Actions

    private func save() async {
        guard canSave else { return }
        focusedField = nil
        isSaving = true
        defer { isSaving = false }
        errorText = nil
        do {
            try await auth.updatePassword(password)
            password = ""
            confirmation = ""
            didSave = true
        } catch {
            errorText = AuthErrorFormatter.message(for: error)
        }
    }

    /// Closes the sheet; a pending reset link is done either way.
    private func finish() {
        auth.endPasswordRecovery()
        dismiss()
    }
}

private enum AuthNewPasswordField: Hashable {
    case password
    case confirmation
}

#Preview {
    AuthSetNewPasswordView()
        .previewEnvironment()
}
