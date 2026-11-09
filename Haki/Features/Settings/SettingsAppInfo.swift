//
//  SettingsAppInfo.swift
//  Haki
//
//  App-wide contact details and legal links shown in Settings.
//

import Foundation

nonisolated enum AppInfo {
    /// Where "Contact support" in Settings sends email. The row is hidden
    /// while this is empty.
    ///
    /// Set this to a monitored support address before submitting to the App
    /// Store: App Review expects a way to contact the developer, and an app
    /// with user-generated content (the Feed) needs one for reports.
    static let supportEmail = ""

    /// The hosted privacy policy, linked from Settings. The row is hidden
    /// while this is nil.
    ///
    /// Set this before submitting to the App Store: App Review requires the
    /// privacy policy to be easy to reach inside the app (guideline 5.1.1(i)),
    /// since Haki creates accounts, hosts posts, links brokerages through
    /// Plaid and sends meal photos to be analyzed.
    static let privacyPolicyURL: URL? = nil

    /// The hosted terms of use, linked from Settings. The row is hidden while
    /// this is nil.
    static let termsURL: URL? = nil
}
