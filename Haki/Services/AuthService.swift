//
//  AuthService.swift
//  Haki
//
//  Sign-in (Google, Sign in with Apple, email and password), the signed-in
//  user's profile, and the app's auth state. Injected at the root with
//  `.environment(AuthService.live)` and read with
//  `@Environment(AuthService.self) private var auth`.
//

import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import Supabase
import UIKit

nonisolated enum EmailSignUpOutcome: Hashable {
    /// Email confirmation is off: the account was created and the user is signed in.
    case signedIn
    /// The user has to tap the link in the confirmation email first.
    case confirmationEmailSent
}

/// Errors thrown by `AuthService`, with user-facing descriptions.
nonisolated enum AuthServiceError: LocalizedError, Hashable {
    case notSignedIn
    case usernameTaken
    /// The username breaks the rules; the associated text explains how.
    case invalidUsername(String)
    case invalidEmail
    case invalidCredentials
    case emailNotConfirmed
    case accountExists
    case weakPassword
    case rateLimited
    case linkExpired
    case appleSignInFailed
    case unavailable
    /// Any other failure, already phrased for the user.
    case message(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You're signed out. Sign in again."
        case .usernameTaken: "That username is taken."
        case .invalidUsername(let problem): problem
        case .invalidEmail: "Enter a valid email address."
        case .invalidCredentials: "Email or password is incorrect."
        case .emailNotConfirmed: "Confirm your email first — tap the link we sent you."
        case .accountExists: "An account with this email already exists. Sign in instead."
        case .weakPassword: "Choose a stronger password: at least 8 characters, mixing letters and numbers."
        case .rateLimited: "Too many attempts. Wait a few minutes and try again."
        case .linkExpired: "This link has expired or was opened on another device. Sign in with your email and password, or request a new link."
        case .appleSignInFailed: "Sign in with Apple didn't complete. Try again."
        case .unavailable: "This sign-in method isn't available right now."
        case .message(let text): text
        }
    }
}

@Observable final class AuthService {
    nonisolated enum State: Equatable {
        /// Restoring the saved session (launch screen).
        case loading
        case signedOut
        /// Signed in, but the user hasn't picked a username yet.
        case needsOnboarding
        case signedIn
    }

    private(set) var state: State
    private(set) var profile: ProfileRecord?
    private(set) var userID: UUID?
    private(set) var email: String?
    /// User-facing message from the last failed action, if any.
    ///
    /// Set by the actions that don't throw (`start`, `handleOpenURL`,
    /// `refreshProfile`); the throwing ones report through their error instead.
    var errorMessage: String?
    /// The name Sign in with Apple shared, kept until onboarding is done.
    ///
    /// Apple shares it only on the first authorization, and onboarding can
    /// appear before it's saved to the profile, so onboarding prefills from it.
    private(set) var pendingAppleDisplayName: String?
    /// Set when a password-reset link was just opened: the app asks for a new
    /// password (`AuthSetNewPasswordView`) until `endPasswordRecovery()`.
    private(set) var isRecoveringPassword = false
    /// Whether the signed-in account has an email-and-password sign-in (so it can change its password).
    private(set) var signsInWithPassword = false

    private let client: SupabaseClient?
    @ObservationIgnored private var authObservation: Task<Void, Never>?
    @ObservationIgnored private var appleRawNonce: String?
    @ObservationIgnored private var profileFetch: Task<ProfileRecord?, any Error>?
    @ObservationIgnored private var profileFetchUserID: UUID?

    /// `nil` = preview mode (no network; signed in as a sample user).
    init(client: SupabaseClient?) {
        self.client = client
        if client == nil {
            let sample = SocialPreviewData.signedInProfile
            state = .signedIn
            profile = sample
            userID = sample.id
            email = "you@example.com"
            signsInWithPassword = true
        } else {
            state = .loading
        }
    }

    /// Signed in as a sample profile.
    static let preview = AuthService(client: nil)
    /// Uses `Backend.client`.
    static let live = AuthService(client: Backend.client)

    // MARK: Session

    /// Restores the session and keeps `state` in sync with auth state changes. Call once from the root view's `.task`.
    func start() async {
        guard let client else { return }
        // One observer for the app's lifetime, however often this is called.
        guard authObservation == nil else { return }

        authObservation = Task { [weak self] in
            for await change in client.auth.authStateChanges {
                guard let self else { return }
                await self.handleAuthChange(change.event, session: change.session)
            }
        }

        if let session = client.auth.currentSession {
            await adopt(session.user)
        } else {
            resetToSignedOut()
        }
    }

    func signInWithGoogle() async throws {
        guard let client else {
            previewSignIn()
            return
        }
        pendingAppleDisplayName = nil
        do {
            let session = try await client.auth.signInWithOAuth(
                provider: .google,
                redirectTo: BackendConfig.authCallbackURL,
                queryParams: [(name: "prompt", value: "select_account")]
            )
            await adopt(session.user)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The user closed the sign-in sheet: nothing to report.
            return
        } catch {
            throw friendlyError(error)
        }
    }

    /// Call from SignInWithAppleButton's onRequest to get the nonce to set on the request (the SHA-256 hash).
    func prepareAppleSignIn() -> String {
        let raw = Self.randomNonce()
        appleRawNonce = raw
        return Self.sha256Hex(raw)
    }

    /// Call from onCompletion with the credential's identityToken.
    func completeAppleSignIn(identityToken: Data, fullName: PersonNameComponents?) async throws {
        guard let client else {
            previewSignIn()
            return
        }
        guard let idToken = String(data: identityToken, encoding: .utf8), let nonce = appleRawNonce else {
            throw AuthServiceError.appleSignInFailed
        }
        appleRawNonce = nil

        // Apple shares the name only on the very first authorization. Keep it
        // before signing in: the SDK's sign-in event can route to onboarding
        // before this call returns, and onboarding prefills from it. A failed
        // attempt keeps it too, since Apple won't send it again.
        let appleName = Self.limited(Self.displayName(from: fullName), to: 50)
        if !appleName.isEmpty {
            pendingAppleDisplayName = appleName
        }

        let session: Session
        do {
            session = try await client.auth.signInWithIdToken(
                credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
            )
        } catch {
            throw friendlyError(error)
        }
        await adopt(session.user)

        // Save the name if the profile has none, so it's kept even if onboarding is left unfinished.
        if let name = pendingAppleDisplayName, let current = profile, current.id == session.user.id,
           current.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let changes = ProfileChanges(displayName: name)
            // A row saved before onboarding finished mustn't replace the onboarded profile.
            if let updated = try? await saveProfileChanges(changes, userID: current.id, client: client),
               userID == updated.id, updated.onboarded || profile?.onboarded != true {
                applyProfile(updated)
            }
        }
        if profile?.onboarded == true {
            pendingAppleDisplayName = nil
        }
    }

    func signUp(email: String, password: String) async throws -> EmailSignUpOutcome {
        let address = try Self.validatedEmail(email)
        guard let client else { return .confirmationEmailSent }
        pendingAppleDisplayName = nil
        do {
            let response = try await client.auth.signUp(
                email: address,
                password: password,
                redirectTo: BackendConfig.authCallbackURL
            )
            if let session = response.session {
                await adopt(session.user)
                return .signedIn
            }
            // With email confirmation on, an address that already has an account
            // gets a stand-in user without identities, and no email is sent.
            if response.user.identities?.isEmpty == true {
                throw AuthServiceError.accountExists
            }
            return .confirmationEmailSent
        } catch {
            throw friendlyError(error)
        }
    }

    func signIn(email: String, password: String) async throws {
        let address = try Self.validatedEmail(email)
        guard let client else {
            previewSignIn()
            return
        }
        pendingAppleDisplayName = nil
        let session: Session
        do {
            session = try await client.auth.signIn(email: address, password: password)
        } catch {
            throw friendlyError(error)
        }
        await adopt(session.user)
    }

    func resendConfirmation(email: String) async throws {
        let address = try Self.validatedEmail(email)
        guard let client else { return }
        do {
            try await client.auth.resend(email: address, type: .signup, emailRedirectTo: BackendConfig.authCallbackURL)
        } catch {
            throw friendlyError(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        let address = try Self.validatedEmail(email)
        guard let client else { return }
        do {
            try await client.auth.resetPasswordForEmail(address, redirectTo: BackendConfig.authCallbackURL)
        } catch {
            throw friendlyError(error)
        }
        // With PKCE the reset link comes back as a plain sign-in (no recovery
        // event), so remember the request to recognize the link when it's opened.
        Self.rememberPasswordResetRequest(for: address)
    }

    /// Handles haki://auth-callback links (email confirmation, password reset, OAuth).
    func handleOpenURL(_ url: URL) async {
        guard let client, Self.isAuthCallback(url) else { return }
        pendingAppleDisplayName = nil
        do {
            let session = try await client.auth.session(from: url)
            errorMessage = nil
            if Self.takePasswordResetRequest(matching: session.user) {
                isRecoveringPassword = true
            }
            await adopt(session.user)
        } catch {
            guard !Backend.isCancellation(error) else { return }
            errorMessage = friendlyError(error).localizedDescription
        }
    }

    /// Sets a new password for the signed-in user (after a password-reset link, or from Settings).
    func updatePassword(_ newPassword: String) async throws {
        guard newPassword.count >= Self.minimumPasswordLength else { throw AuthServiceError.weakPassword }
        guard let client else { return }
        guard userID != nil else { throw AuthServiceError.notSignedIn }
        do {
            try await client.auth.update(user: UserAttributes(password: newPassword))
        } catch {
            throw friendlyError(error)
        }
        Self.removePasswordResetRequest()
    }

    /// Stops asking for a new password: it was saved, or the user chose to keep the old one.
    func endPasswordRecovery() {
        isRecoveringPassword = false
    }

    // MARK: Profile

    /// Saves username/display name/sharing choice (and uploads an avatar if given) and sets onboarded = true.
    func completeOnboarding(username: String, displayName: String, sharePortfolio: Bool, avatarJPEG: Data?) async throws {
        let name = try Self.validatedUsername(username)
        let display = try Self.validatedDisplayName(displayName)

        guard let client else {
            if let current = profile {
                var updated = current
                updated.username = name
                updated.displayName = display
                updated.sharePortfolio = sharePortfolio
                updated.onboarded = true
                profile = updated
            }
            pendingAppleDisplayName = nil
            state = .signedIn
            return
        }
        guard let uid = userID else { throw AuthServiceError.notSignedIn }

        let changes = ProfileChanges(
            username: name,
            displayName: display,
            sharePortfolio: sharePortfolio,
            onboarded: true
        )
        let updated = try await saveProfile(changes: changes, avatarJPEG: avatarJPEG, userID: uid, client: client)
        applyProfile(updated)
        pendingAppleDisplayName = nil
        state = .signedIn
    }

    /// Updates the signed-in user's profile fields (nil = unchanged).
    func updateProfile(username: String?, displayName: String?, bio: String?, sharePortfolio: Bool?, avatarJPEG: Data?) async throws {
        var changes = ProfileChanges()
        if let username { changes.username = try Self.validatedUsername(username) }
        if let displayName { changes.displayName = try Self.validatedDisplayName(displayName) }
        if let bio { changes.bio = try Self.validatedBio(bio) }
        changes.sharePortfolio = sharePortfolio

        guard let client else {
            if var updated = profile {
                if let value = changes.username { updated.username = value }
                if let value = changes.displayName { updated.displayName = value }
                if let value = changes.bio { updated.bio = value }
                if let value = changes.sharePortfolio { updated.sharePortfolio = value }
                profile = updated
            }
            return
        }
        guard let uid = userID else { throw AuthServiceError.notSignedIn }
        guard !changes.isEmpty || avatarJPEG != nil else { return }

        let updated = try await saveProfile(changes: changes, avatarJPEG: avatarJPEG, userID: uid, client: client)
        applyProfile(updated)
    }

    func refreshProfile() async {
        guard client != nil, let uid = userID else { return }
        do {
            let record = try await fetchProfile(uid)
            guard userID == uid else { return }
            if let record {
                applyProfile(record)
                route(for: record)
            } else if state == .loading {
                // Retried from the launch screen: same outcome as the first load.
                if client?.auth.currentSession == nil {
                    resetToSignedOut()
                } else {
                    state = .needsOnboarding
                }
            }
            errorMessage = nil
        } catch {
            guard !Backend.isCancellation(error), userID == uid else { return }
            errorMessage = friendlyError(error).localizedDescription
        }
    }

    // MARK: Signing out

    func signOut() async {
        // A message about the account being left behind would only confuse the welcome screen.
        errorMessage = nil
        guard let client else {
            resetToSignedOut()
            return
        }
        let uid = userID
        // Removes the local session before calling the server, so this signs
        // out even when offline.
        try? await client.auth.signOut(scope: .local)
        if let uid { Self.removeCachedProfile(for: uid) }
        resetToSignedOut()
    }

    /// Calls the delete-account edge function, then signs out.
    ///
    /// For an account with a Sign in with Apple identity, first asks Apple for
    /// a fresh authorization code (the user confirms once more) so the server
    /// can revoke Haki's Apple tokens. If that's cancelled or fails, the
    /// account is still deleted: Apple never stands in the way.
    func deleteAccount() async throws {
        guard let client else {
            resetToSignedOut()
            return
        }
        guard userID != nil else { throw AuthServiceError.notSignedIn }
        var appleCode: String?
        if let user = client.auth.currentUser, Self.hasAppleIdentity(user) {
            appleCode = await Self.freshAppleAuthorizationCode()
        }
        do {
            try await client.functions.invoke(
                "delete-account",
                options: FunctionInvokeOptions(body: AuthDeleteAccountBody(appleAuthorizationCode: appleCode))
            )
        } catch {
            throw friendlyError(error)
        }
        await signOut()
    }

    // MARK: - State machine

    private func handleAuthChange(_ event: AuthChangeEvent, session: Session?) async {
        switch event {
        case .signedOut, .userDeleted:
            if let uid = userID {
                Self.removeCachedProfile(for: uid)
                // Stale messages about the signed-out account (e.g. a failed profile load).
                errorMessage = nil
            }
            resetToSignedOut()
        case .initialSession:
            if let session {
                await adopt(session.user)
            } else {
                resetToSignedOut()
            }
        case .passwordRecovery:
            // Only sent for implicit-flow links; PKCE reset links are recognized in `handleOpenURL`.
            if let session {
                isRecoveringPassword = true
                await adopt(session.user)
            }
        default:
            // signedIn, tokenRefreshed, userUpdated, mfaChallengeVerified
            if let session {
                await adopt(session.user)
            }
        }
    }

    /// Makes `user` the signed-in user and routes to onboarding or the app.
    /// Cheap to call again for the same user (token refreshes, duplicate events).
    private func adopt(_ user: User) async {
        let isSameUser = userID == user.id
        if let address = user.email, !address.isEmpty {
            email = address
        } else if !isSameUser {
            email = nil
        }
        signsInWithPassword = user.identities?.contains(where: { $0.provider == "email" }) ?? false
        if isSameUser, profile != nil, state == .signedIn || state == .needsOnboarding {
            return
        }
        if !isSameUser {
            profile = nil
        }
        userID = user.id
        await loadProfileAndRoute(user.id)
    }

    private func loadProfileAndRoute(_ uid: UUID) async {
        if profile == nil || state == .loading, let cached = Self.cachedProfile(for: uid) {
            // Go straight in with the last known profile (even on a slow or
            // offline network); the fetch below refreshes it.
            profile = cached
            route(for: cached)
        }
        var attempt = 0
        while true {
            do {
                let record = try await fetchProfile(uid)
                guard userID == uid else { return }
                if let record {
                    applyProfile(record)
                    route(for: record)
                } else if client?.auth.currentSession == nil {
                    // The session went away while loading (e.g. its refresh token was revoked).
                    resetToSignedOut()
                } else {
                    // Signed in, but no profile row could be read: let the user pick a username.
                    profile = nil
                    state = .needsOnboarding
                }
                errorMessage = nil
                return
            } catch {
                guard userID == uid, !Backend.isCancellation(error) else { return }
                if let cached = Self.cachedProfile(for: uid) {
                    // Offline: carry on with the last known profile (normally already shown above).
                    if profile == nil {
                        profile = cached
                        route(for: cached)
                    }
                    return
                }
                attempt += 1
                if attempt < 3, Self.isTransient(error) {
                    try? await Task.sleep(for: .seconds(Double(attempt) * 1.5))
                    guard userID == uid else { return }
                    continue
                }
                // Whether this account has finished onboarding (and chosen what to
                // share) is unknown, so don't let it into the app. The launch screen
                // shows this message with "Try again" and "Sign out".
                if state != .needsOnboarding {
                    state = .loading
                }
                errorMessage = "Couldn't load your profile. Check your connection and try again."
                return
            }
        }
    }

    /// Failures worth retrying: network trouble, or the database being briefly unavailable.
    private static func isTransient(_ error: any Error) -> Bool {
        if error is URLError { return true }
        if let httpError = error as? HTTPError {
            return httpError.response.statusCode >= 500
        }
        if let postgrestError = error as? PostgrestError, let code = postgrestError.code {
            return ["PGRST000", "PGRST001", "PGRST002", "PGRST003", "57014"].contains(code)
        }
        return false
    }

    private func route(for record: ProfileRecord) {
        state = record.onboarded ? .signedIn : .needsOnboarding
    }

    private func applyProfile(_ record: ProfileRecord) {
        profile = record
        Self.cacheProfile(record)
    }

    private func resetToSignedOut() {
        profileFetch?.cancel()
        profileFetch = nil
        profileFetchUserID = nil
        profile = nil
        userID = nil
        email = nil
        pendingAppleDisplayName = nil
        isRecoveringPassword = false
        signsInWithPassword = false
        state = .signedOut
    }

    private func previewSignIn() {
        let sample = SocialPreviewData.signedInProfile
        profile = sample
        userID = sample.id
        email = "you@example.com"
        state = sample.onboarded ? .signedIn : .needsOnboarding
    }

    // MARK: - Database

    private static let profileColumns = "id,username,display_name,bio,avatar_path,share_portfolio,onboarded"

    /// Loads the `profiles` row, sharing one request between concurrent callers.
    private func fetchProfile(_ uid: UUID) async throws -> ProfileRecord? {
        if let running = profileFetch, profileFetchUserID == uid {
            return try await running.value
        }
        guard let client else { return nil }
        let task = Task<ProfileRecord?, any Error> {
            let rows: [ProfileRecord] = try await client
                .from("profiles")
                .select(Self.profileColumns)
                .eq("id", value: uid)
                .limit(1)
                .execute()
                .value
            return rows.first
        }
        profileFetch = task
        profileFetchUserID = uid
        defer {
            if profileFetchUserID == uid {
                profileFetch = nil
                profileFetchUserID = nil
            }
        }
        return try await task.value
    }

    /// Uploads the avatar (if any), saves the changes, and cleans up the
    /// replaced (or, on failure, the new) photo.
    private func saveProfile(
        changes: ProfileChanges,
        avatarJPEG: Data?,
        userID uid: UUID,
        client: SupabaseClient
    ) async throws -> ProfileRecord {
        var changes = changes
        let previousAvatar = profile?.avatarPath
        var uploadedPath: String?
        if let avatarJPEG {
            let path = "\(uid.uuidString.lowercased())/\(UUID().uuidString.lowercased()).jpg"
            do {
                try await client.storage
                    .from(BackendConfig.avatarsBucket)
                    .upload(path, data: avatarJPEG, options: FileOptions(cacheControl: "31536000", contentType: "image/jpeg"))
            } catch {
                throw friendlyError(error)
            }
            uploadedPath = path
            changes.avatarPath = path
        }

        do {
            let updated = try await saveProfileChanges(changes, userID: uid, client: client)
            if let uploadedPath, let previousAvatar, previousAvatar != uploadedPath {
                _ = try? await client.storage.from(BackendConfig.avatarsBucket).remove(paths: [previousAvatar])
            }
            return updated
        } catch {
            if let uploadedPath {
                _ = try? await client.storage.from(BackendConfig.avatarsBucket).remove(paths: [uploadedPath])
            }
            throw friendlyError(error)
        }
    }

    private func saveProfileChanges(_ changes: ProfileChanges, userID uid: UUID, client: SupabaseClient) async throws -> ProfileRecord {
        try await client
            .from("profiles")
            .update(changes)
            .eq("id", value: uid)
            .select(Self.profileColumns)
            .single()
            .execute()
            .value
    }

    // MARK: - Errors

    private func friendlyError(_ error: any Error) -> any Error {
        if Backend.isCancellation(error) || error is AuthServiceError { return error }

        if let authError = error as? AuthError {
            if case .pkceGrantCodeExchange = authError { return AuthServiceError.linkExpired }
            if case .implicitGrantRedirect = authError { return AuthServiceError.linkExpired }
            if case .sessionMissing = authError { return AuthServiceError.notSignedIn }
            if case .weakPassword = authError { return AuthServiceError.weakPassword }
            switch authError.errorCode {
            case .invalidCredentials:
                return AuthServiceError.invalidCredentials
            case .emailNotConfirmed:
                return AuthServiceError.emailNotConfirmed
            case .userAlreadyExists, .emailExists, .identityAlreadyExists:
                return AuthServiceError.accountExists
            case .weakPassword:
                return AuthServiceError.weakPassword
            case .samePassword:
                return AuthServiceError.message("Choose a password that's different from your current one.")
            case .reauthenticationNeeded, .reauthenticationNotValid:
                return AuthServiceError.message("For your security, sign out and use “Forgot password?” on the sign-in screen to choose a new password.")
            case .overRequestRateLimit, .overEmailSendRateLimit:
                return AuthServiceError.rateLimited
            case .flowStateNotFound, .flowStateExpired, .badCodeVerifier, .otpExpired:
                return AuthServiceError.linkExpired
            case .signupDisabled:
                return AuthServiceError.message("New sign-ups are paused right now. Try again later.")
            case .providerDisabled, .emailProviderDisabled, .oauthProviderNotSupported:
                return AuthServiceError.unavailable
            case .sessionNotFound, .sessionExpired, .refreshTokenNotFound, .refreshTokenAlreadyUsed:
                return AuthServiceError.message("Your session has expired. Sign in again.")
            case .userBanned:
                return AuthServiceError.message("This account can't sign in right now.")
            case .emailAddressNotAuthorized:
                return AuthServiceError.message("Haki can't send email to that address yet.")
            default:
                let message = authError.message.trimmingCharacters(in: .whitespacesAndNewlines)
                return AuthServiceError.message(message.isEmpty ? "Couldn't sign you in. Try again." : message)
            }
        }

        if let postgrestError = error as? PostgrestError {
            let detail = postgrestError.message.lowercased()
            switch postgrestError.code {
            case "23505":
                return AuthServiceError.usernameTaken
            case "23514":
                if detail.contains("username") {
                    return AuthServiceError.invalidUsername(
                        "Use \(UsernameRules.lengthRange.lowerBound)–\(UsernameRules.lengthRange.upperBound) characters: \(UsernameRules.allowedCharacters)."
                    )
                }
                if detail.contains("bio") { return AuthServiceError.message("Your bio can be up to 160 characters.") }
                if detail.contains("display_name") { return AuthServiceError.message("Your name can be up to 50 characters.") }
            default:
                break
            }
        }

        let fallback = Backend.userFacingError(error, fallback: "Couldn't save your changes. Try again.")
        return AuthServiceError.message(fallback.localizedDescription)
    }

    // MARK: - Validation

    /// Matches the sign-up form's rule.
    static let minimumPasswordLength = 8

    /// Cuts `text` to at most `limit` Unicode scalars (how Postgres counts characters).
    private static func limited(_ text: String, to limit: Int) -> String {
        guard text.unicodeScalars.count > limit else { return text }
        var result = ""
        result.unicodeScalars.append(contentsOf: text.unicodeScalars.prefix(limit))
        return result
    }

    private static func validatedEmail(_ email: String) throws -> String {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !address.contains(" ") else {
            throw AuthServiceError.invalidEmail
        }
        return address
    }

    private static func validatedUsername(_ username: String) throws -> String {
        let candidate = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let problem = UsernameRules.problem(with: candidate) {
            throw AuthServiceError.invalidUsername(problem)
        }
        return candidate
    }

    private static func validatedDisplayName(_ displayName: String) throws -> String {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.unicodeScalars.count <= 50 else {
            throw AuthServiceError.message("Your name can be up to 50 characters.")
        }
        return name
    }

    private static func validatedBio(_ bio: String) throws -> String {
        let text = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.unicodeScalars.count <= 160 else {
            throw AuthServiceError.message("Your bio can be up to 160 characters.")
        }
        return text
    }

    private static func isAuthCallback(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == BackendConfig.authCallbackURL.scheme?.lowercased() else { return false }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var names = Set((components?.queryItems ?? []).map(\.name))
        for pair in (components?.fragment ?? "").split(separator: "&") {
            if let name = pair.split(separator: "=").first {
                names.insert(String(name))
            }
        }
        // Only links that carry a result: a code to exchange, tokens, or an error.
        return !names.isDisjoint(with: ["code", "access_token", "error", "error_description", "error_code"])
    }

    // MARK: - Sign in with Apple

    private static func randomNonce(length: Int = 32) -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters[Int.random(in: 0..<characters.count, using: &generator)] })
    }

    private static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { byte in
            let hex = String(byte, radix: 16)
            return byte < 16 ? "0" + hex : hex
        }
        .joined()
    }

    private static func displayName(from components: PersonNameComponents?) -> String {
        guard let components else { return "" }
        return [components.givenName, components.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Whether the account can sign in with Apple (as the delete-account function checks it).
    private static func hasAppleIdentity(_ user: User) -> Bool {
        if user.identities?.contains(where: { $0.provider == "apple" }) == true {
            return true
        }
        let providers = user.appMetadata["providers"]?.arrayValue ?? []
        return providers.contains(where: { $0.stringValue == "apple" })
    }

    /// Asks Apple for a fresh, single-use authorization code for the signed-in
    /// Apple ID (no name or email requested). `nil` if the user cancels, it
    /// fails, or there's no window to show Apple's sheet over.
    private static func freshAppleAuthorizationCode() async -> String? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        guard let anchor = windows.first(where: { $0.isKeyWindow }) ?? windows.first else { return nil }
        let request = ASAuthorizationAppleIDProvider().createRequest()
        let controller = ASAuthorizationController(authorizationRequests: [request])
        let reauthorization = AuthAppleReauthorization(anchor: anchor)
        return await reauthorization.run(controller)
    }

    // MARK: - Offline profile cache

    private static func cacheKey(for uid: UUID) -> String {
        "haki.auth.profile.\(uid.uuidString.lowercased())"
    }

    private static func cacheProfile(_ record: ProfileRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: cacheKey(for: record.id))
    }

    private static func cachedProfile(for uid: UUID) -> ProfileRecord? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey(for: uid)) else { return nil }
        return try? JSONDecoder().decode(ProfileRecord.self, from: data)
    }

    private static func removeCachedProfile(for uid: UUID) {
        UserDefaults.standard.removeObject(forKey: cacheKey(for: uid))
    }

    // MARK: - Password reset requests

    /// Stored (not in memory) because the app may be closed before the link is opened.
    private static let passwordResetKey = "haki.auth.passwordReset"
    /// How long a request is matched to a link. Reset links last an hour by
    /// default (a day at most); an expired one fails before it gets here.
    private static let passwordResetLifetime: TimeInterval = 24 * 60 * 60

    private static func rememberPasswordResetRequest(for email: String) {
        let request = AuthPasswordResetRequest(email: email.lowercased(), sentAt: .now)
        guard let data = try? JSONEncoder().encode(request) else { return }
        UserDefaults.standard.set(data, forKey: passwordResetKey)
    }

    /// Whether `user` just signed in through the reset link requested on this
    /// iPhone. Forgets the request when it matches or has expired.
    private static func takePasswordResetRequest(matching user: User) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: passwordResetKey),
              let request = try? JSONDecoder().decode(AuthPasswordResetRequest.self, from: data)
        else { return false }
        let age = Date.now.timeIntervalSince(request.sentAt)
        guard age > -300, age < passwordResetLifetime else {
            removePasswordResetRequest()
            return false
        }
        guard let address = user.email?.lowercased(), address == request.email else { return false }
        removePasswordResetRequest()
        return true
    }

    private static func removePasswordResetRequest() {
        UserDefaults.standard.removeObject(forKey: passwordResetKey)
    }
}

/// A "Forgot password?" request made on this device.
nonisolated private struct AuthPasswordResetRequest: Codable {
    let email: String
    let sentAt: Date
}

// MARK: - Request bodies

/// The columns of `profiles` a user may change; `nil` = unchanged (not sent).
nonisolated private struct ProfileChanges: Encodable {
    var username: String?
    var displayName: String?
    var bio: String?
    var avatarPath: String?
    var sharePortfolio: Bool?
    var onboarded: Bool?

    var isEmpty: Bool {
        username == nil && displayName == nil && bio == nil && avatarPath == nil && sharePortfolio == nil && onboarded == nil
    }

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case bio
        case avatarPath = "avatar_path"
        case sharePortfolio = "share_portfolio"
        case onboarded
    }
}

/// The delete-account request: `{}`, or `{"apple_authorization_code": ...}`
/// when Apple gave a fresh code (a `nil` code isn't sent).
nonisolated private struct AuthDeleteAccountBody: Encodable {
    var appleAuthorizationCode: String?

    enum CodingKeys: String, CodingKey {
        case appleAuthorizationCode = "apple_authorization_code"
    }
}

// MARK: - Apple re-authorization

/// Runs one Sign in with Apple request and hands back its authorization code.
/// Keeps the controller (which holds its delegate weakly) and itself alive
/// until Apple answers.
private final class AuthAppleReauthorization: NSObject, ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {
    private let anchor: ASPresentationAnchor
    private var controller: ASAuthorizationController?
    private var continuation: CheckedContinuation<String?, Never>?

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
        super.init()
    }

    /// The code as text (what the delete-account function expects), or `nil`.
    func run(_ controller: ASAuthorizationController) async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            self.continuation = continuation
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        let credential = authorization.credential as? ASAuthorizationAppleIDCredential
        let code = credential?.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
        finish(with: code)
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        // Cancelled or failed: the account is deleted without revoking Apple's tokens.
        finish(with: nil)
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor
    }

    /// Resumes the caller once (later calls do nothing). The controller is
    /// kept until this object goes away after `run` returns, so it isn't
    /// released while it's still calling its delegate.
    private func finish(with code: String?) {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.resume(returning: code)
    }
}
