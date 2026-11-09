//
//  SmokeTests.swift
//  HakiUITests
//
//  Every tab opens without crashing and shows its title.
//

import XCTest

final class SmokeTests: HakiUITestCase {
    func testEveryTabOpens() throws {
        launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)")
        snap("01 Home")

        for (index, tab) in ["Feed", "Invest", "Health", "Profile", "Home"].enumerated() {
            openTab(tab)
            sleep(2)
            expectStillRunning("opening \(tab)")
            snap(String(format: "%02d %@", index + 2, tab))
        }
    }
}
