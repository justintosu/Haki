//
//  HakiUITestCase.swift
//  HakiUITests
//
//  Base class for Haki's UI tests: launches the app in UI-testing mode
//  (signed in as a sample user, sample data in memory, no network) and
//  saves named screenshots into the test results.
//

import XCTest

@MainActor
class HakiUITestCase: XCTestCase {
    private(set) var app = XCUIApplication()

    /// Launches Haki in UI-testing mode. Call first in every test.
    func launch() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-HakiUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        // Location, camera and similar system prompts: allow, so tests can carry on.
        addUIInterruptionMonitor(withDescription: "System alert") { alert in
            for label in ["Allow While Using App", "Allow Once", "Allow", "OK"] {
                let button = alert.buttons[label]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
        app.launch()
    }

    /// Attaches a screenshot of the whole screen, kept even when the test passes.
    func snap(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Taps a tab bar item by its title, failing the test if it isn't there.
    func openTab(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        let tab = app.tabBars.buttons[title]
        guard tab.waitForExistence(timeout: 10) else {
            XCTFail("No tab named \(title)", file: file, line: line)
            return
        }
        tab.tap()
    }

    /// Waits for any element whose label is `label` (static text, button, cell...).
    @discardableResult
    func expectVisible(_ label: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
        if !element.waitForExistence(timeout: timeout) {
            XCTFail("Expected to see \"\(label)\"", file: file, line: line)
        }
        return element
    }

    /// Waits for an element whose label contains `text`.
    @discardableResult
    func expectVisible(containing text: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
        if !element.waitForExistence(timeout: timeout) {
            XCTFail("Expected to see something containing \"\(text)\"", file: file, line: line)
        }
        return element
    }

    /// The app is still running (didn't crash) after an action.
    func expectStillRunning(_ step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(app.state, .runningForeground, "App stopped running after: \(step)", file: file, line: line)
    }

    /// Goes back one screen in the current navigation stack.
    func goBack() {
        let back = app.navigationBars.buttons.element(boundBy: 0)
        if back.exists { back.tap() }
    }
}
