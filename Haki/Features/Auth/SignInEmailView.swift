//
//  SignInEmailView.swift
//  Haki
//
//  Sheet: sign in or create an account with an email address and password,
//  reset a forgotten password, and the "check your inbox" step after sign-up.
//

import Foundation
import SwiftUI
import UIKit

struct SignInEmailView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var mode: SignInEmailMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var isBusy = false
    @State private var errorText: String?
    /// Offer to resend the confirmation email (after "email not confirmed").
    @State private var offersResend = false
    @State private var notice: SignInEmailNotice?
    /// Set after sign-up when the account still needs its email confirmed.
    @State private var confirmationAddress: String?
    @FocusState private var focusedField: SignInEmailField?

    private static let minimumPasswordLength = 8

    var body: some View {
        NavigationStack {
            Group {
                if let address = confirmationAddress {
                    checkInbox(address: address)
                        .transition(.opacity)
                } else {
                    form
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: confirmationAddress)
            .navigationTitle(confirmationAddress == nil ? mode.title : "Confirm your email")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(confirmationAddress == nil ? "Cancel" : "Close") {
                        dismiss()
                    }
                    .disabled(isBusy)
                }
            }
        }
        .interactiveDismissDisabled(isBusy)
        .alert(notice?.title ?? "", isPresented: noticeIsPresented, presenting: notice) { _ in
            Button("OK", role: .cancel) {}
        } message: { notice in
            Text(notice.message)
        }
        .task {
            // Bring up the keyboard once the sheet has settled.
            try? await Task.sleep(for: .milliseconds(500))
            if !Task.isCancelled, email.isEmpty, confirmationAddress == nil {
                focusedField = .email
            }
        }
        .onDisappear {
            // Whatever the service reported belongs to this attempt; don't show it again elsewhere.
            auth.errorMessage = nil
        }
    }

    // MARK: Form

    private var form: some View {
        Form {
            Section {
                Picker("Account", selection: $mode) {
                    ForEach(SignInEmailMode.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(mode.intro)
                    .padding(.top, 6)
            }

            Section {
                emailField
                passwordField
            } footer: {
                fieldHints
            }

            if let message = displayedError {
                errorSection(message)
            }

            Section {
                submitButton
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            if mode == .signIn {
                Section {
                    Button("Forgot password?") {
                        Task { await sendPasswordReset() }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isBusy)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: mode) {
            clearError()
        }
        .onChange(of: email) {
            if errorText != nil { clearError() }
        }
        .onChange(of: password) {
            if errorText != nil { clearError() }
        }
    }

    private var emailField: some View {
        TextField("Email", text: $email)
            .textContentType(.username)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .focused($focusedField, equals: .email)
            .onSubmit { focusedField = .password }
            .accessibilityLabel("Email address")
    }

    private var passwordField: some View {
        SecureField(mode == .createAccount ? "Choose a password" : "Password", text: $password)
            .textContentType(mode == .createAccount ? UITextContentType.newPassword : UITextContentType.password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.go)
            .focused($focusedField, equals: .password)
            .onSubmit { Task { await submit() } }
            // A new field per mode, so password autofill picks up the new content type.
            .id(mode)
            .accessibilityLabel("Password")
    }

    @ViewBuilder
    private var fieldHints: some View {
        let showsEmailHint = !trimmedEmail.isEmpty && !AuthText.looksLikeEmail(email) && focusedField != .email
        if showsEmailHint || mode == .createAccount {
            VStack(alignment: .leading, spacing: 4) {
                if showsEmailHint {
                    Label("Enter a valid email address.", systemImage: "exclamationmark.circle")
                        .foregroundStyle(Color.hakiWarning)
                }
                if mode == .createAccount {
                    Label(
                        "At least \(Self.minimumPasswordLength) characters",
                        systemImage: passwordIsLongEnough ? "checkmark.circle.fill" : "circle"
                    )
                    .foregroundStyle(passwordIsLongEnough ? Color.hakiPositive : Color.secondary)
                    .accessibilityValue(passwordIsLongEnough ? "Requirement met" : "Requirement not met")
                }
            }
            .padding(.top, 2)
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.hakiNegative)
                .accessibilityLabel("Error: \(message)")
            if offersResend {
                Button("Resend confirmation email") {
                    Task { await resendFromSignIn() }
                }
                .disabled(isBusy)
            }
        }
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                        .tint(.white)
                }
                Text(isBusy ? mode.busyTitle : mode.title)
            }
        }
        .buttonStyle(AuthButtonStyle(kind: .prominent))
        .disabled(!canSubmit)
    }

    // MARK: Check your inbox

    private func checkInbox(address: String) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "envelope.badge.fill")
                    .font(.largeTitle)
                    .imageScale(.large)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 24)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Check your inbox")
                        .font(.title2.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                    Text("We sent a confirmation link to")
                        .foregroundStyle(.secondary)
                    Text(address)
                        .font(.body.weight(.semibold))
                        .textSelection(.enabled)
                    Text("Open it on this iPhone to finish creating your account. It can take a minute to arrive — check your spam folder too.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

                if let message = displayedError {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.hakiNegative)
                        .multilineTextAlignment(.leading)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.hakiNegative.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                VStack(spacing: 12) {
                    Button {
                        Task { await resendConfirmation(to: address) }
                    } label: {
                        HStack(spacing: 8) {
                            if isBusy {
                                ProgressView()
                            }
                            Label("Resend email", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(AuthButtonStyle(kind: .tinted))

                    Button("I've confirmed — sign in") {
                        clearError()
                        mode = .signIn
                        confirmationAddress = nil
                        email = address
                        focusedField = .password
                    }
                    .buttonStyle(AuthButtonStyle(kind: .prominent))

                    Button("Use a different email") {
                        clearError()
                        mode = .createAccount
                        confirmationAddress = nil
                        email = ""
                        focusedField = .email
                    }
                    .font(.subheadline.weight(.semibold))
                    .padding(.top, 4)
                }
                .disabled(isBusy)
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

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var passwordIsLongEnough: Bool {
        password.count >= Self.minimumPasswordLength
    }

    private var canSubmit: Bool {
        guard !isBusy, AuthText.looksLikeEmail(email) else { return false }
        switch mode {
        case .signIn: return !password.isEmpty
        case .createAccount: return passwordIsLongEnough
        }
    }

    /// This screen's last error, or one the service reported (e.g. an expired confirmation link).
    private var displayedError: String? {
        errorText ?? auth.errorMessage
    }

    private var noticeIsPresented: Binding<Bool> {
        Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )
    }

    private func clearError() {
        errorText = nil
        offersResend = false
        auth.errorMessage = nil
    }

    // MARK: Actions

    private func submit() async {
        guard canSubmit else { return }
        focusedField = nil
        isBusy = true
        defer { isBusy = false }
        clearError()
        let address = trimmedEmail
        do {
            switch mode {
            case .signIn:
                try await auth.signIn(email: address, password: password)
                dismiss()
            case .createAccount:
                let outcome = try await auth.signUp(email: address, password: password)
                switch outcome {
                case .signedIn:
                    dismiss()
                case .confirmationEmailSent:
                    password = ""
                    confirmationAddress = address
                }
            }
        } catch {
            errorText = AuthErrorFormatter.message(for: error)
            offersResend = mode == .signIn && AuthErrorFormatter.isEmailNotConfirmed(error)
        }
    }

    private func sendPasswordReset() async {
        guard AuthText.looksLikeEmail(email) else {
            errorText = "Enter your email address above, then tap “Forgot password?” again."
            offersResend = false
            focusedField = .email
            return
        }
        guard !isBusy else { return }
        focusedField = nil
        isBusy = true
        defer { isBusy = false }
        clearError()
        let address = trimmedEmail
        do {
            try await auth.sendPasswordReset(email: address)
            notice = SignInEmailNotice(
                title: "Check your email",
                message: "If there's a Haki account for \(address), we've sent it a link to get back in. Open the link on this iPhone."
            )
        } catch {
            errorText = AuthErrorFormatter.message(for: error)
        }
    }

    /// From the sign-in form, after "confirm your email first".
    private func resendFromSignIn() async {
        guard !isBusy, AuthText.looksLikeEmail(email) else { return }
        isBusy = true
        defer { isBusy = false }
        let address = trimmedEmail
        clearError()
        do {
            try await auth.resendConfirmation(email: address)
            password = ""
            confirmationAddress = address
        } catch {
            errorText = AuthErrorFormatter.message(for: error)
        }
    }

    /// From the "check your inbox" screen.
    private func resendConfirmation(to address: String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        clearError()
        do {
            try await auth.resendConfirmation(email: address)
            notice = SignInEmailNotice(
                title: "Email sent",
                message: "We sent another confirmation link to \(address)."
            )
        } catch {
            errorText = AuthErrorFormatter.message(for: error)
        }
    }
}

// MARK: - Supporting types

private enum SignInEmailMode: String, CaseIterable, Identifiable {
    case signIn
    case createAccount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .signIn: "Sign in"
        case .createAccount: "Create account"
        }
    }

    var busyTitle: String {
        switch self {
        case .signIn: "Signing in…"
        case .createAccount: "Creating account…"
        }
    }

    var intro: String {
        switch self {
        case .signIn: "Welcome back. Sign in with the email and password you used before."
        case .createAccount: "Create your Haki account with an email address. You'll pick a username next."
        }
    }
}

private enum SignInEmailField: Hashable {
    case email
    case password
}

private struct SignInEmailNotice: Hashable {
    let title: String
    let message: String
}

#Preview("Sign in") {
    SignInEmailView()
        .previewEnvironment()
}
