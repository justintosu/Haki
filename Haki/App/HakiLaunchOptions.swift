//
//  HakiLaunchOptions.swift
//  Haki
//
//  Launch arguments the UI tests pass (see HakiUITests/).
//

import Foundation

enum HakiLaunchOptions {
    /// `-HakiUITesting`: start signed in as a sample user with sample data in
    /// an in-memory database and preview services (no network, nothing saved).
    static let uiTestingArgument = "-HakiUITesting"

    static var isUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains(uiTestingArgument)
    }
}
