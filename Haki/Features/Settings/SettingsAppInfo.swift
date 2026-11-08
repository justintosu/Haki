//
//  SettingsAppInfo.swift
//  Haki
//
//  App-wide contact details shown in Settings.
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
}
