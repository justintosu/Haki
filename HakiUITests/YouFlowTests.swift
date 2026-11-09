//
//  YouFlowTests.swift
//  HakiUITests
//
//  The You tab: the profile card (name, @username, counts, View profile and
//  Edit profile), the Ask Haki card (starter questions, Open chat), the
//  wardrobe card and the notes and flashcards card; View profile pushed and
//  back; Activity and Settings from the toolbar. Every step checks the
//  screen appeared and the app is still running, and saves a screenshot
//  ("Y01 You, profile card"...).
//
//  Relies on `-HakiUITesting`: signed in as Maya Chen (@maya.invests,
//  SocialPreviewData) with the sample wardrobe, notes and decks from
//  Haki/Data/LifePreviewData.swift.
//

import XCTest

final class YouFlowTests: HakiUITestCase {
    // MARK: The cards

    func testYouTabCards() throws {
        launch()
        guard openYou() else { return }

        // Profile card.
        expectVisible("Maya Chen")
        expectVisible("Username maya.invests")
        XCTAssertTrue(app.buttons["View profile"].waitForExistence(timeout: 5), "No View profile button on the profile card")
        XCTAssertTrue(app.buttons["Edit profile"].exists, "No Edit profile button on the profile card")
        XCTAssertTrue(app.navigationBars["You"].buttons["Ask Haki"].exists, "No Ask Haki button in the You toolbar")
        expectStillRunning("opening You")
        snap("Y01 You, profile card")

        // Ask Haki card: what it's for, today's starter questions, Open chat.
        let askIntro = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@", "Ask about your spending, meals, workouts, wardrobe and notes."
        )).firstMatch
        XCTAssertTrue(askIntro.waitForExistence(timeout: 5), "No Ask Haki card")
        let openChat = app.buttons["Open chat"]
        scrollTo(openChat)
        XCTAssertTrue(openChat.exists, "No Open chat button on the Ask Haki card")
        XCTAssertTrue(suggestionButton().exists, "The Ask Haki card shows no starter question")
        expectStillRunning("scrolling to the Ask Haki card")
        snap("Y02 You, Ask Haki card")

        // Wardrobe card: counts, newest pieces, Add piece.
        let wardrobe = cardLink("Wardrobe")
        scrollTo(wardrobe)
        XCTAssertTrue(wardrobe.exists, "No wardrobe card")
        XCTAssertTrue(app.buttons["Add piece"].exists, "No Add piece button on the wardrobe card")
        expectVisible(containing: "Newest:")
        expectStillRunning("scrolling to the wardrobe card")
        snap("Y03 You, wardrobe card")

        // Notes and flashcards card: what's due, Study now, recent notes.
        let study = cardLink("Notes & Flashcards")
        scrollTo(study)
        XCTAssertTrue(study.exists, "No notes and flashcards card")
        let studyNow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Study now")).firstMatch
        scrollTo(studyNow)
        XCTAssertTrue(studyNow.exists, "No Study now button (a sample deck has cards due)")
        let recentNotes = app.staticTexts["Recent notes"]
        scrollTo(recentNotes)
        XCTAssertTrue(recentNotes.exists, "No recent notes on the study card")
        expectStillRunning("scrolling to the study card")
        snap("Y04 You, notes and flashcards card")
    }

    func testOpenChatFromAskHakiCard() throws {
        launch()
        guard openYou() else { return }

        guard tapElement(app.buttons["Open chat"], "Open chat on the Ask Haki card") else { return }
        let shown = expectScreen("Ask Haki")
        expectVisible(containing: "what would you like to know?")
        expectStillRunning("opening a blank chat from the You tab")
        snap("Y05 Ask Haki from Open chat")
        guard shown else { return }

        tapElement(app.navigationBars["Ask Haki"].buttons["Done"], "Done in Ask Haki")
        XCTAssertTrue(waitUntilGone(app.navigationBars["Ask Haki"]), "Ask Haki didn't close")
        expectScreen("You")
        expectStillRunning("closing Ask Haki")
    }

    // MARK: Profile

    func testViewProfileAndBack() throws {
        launch()
        guard openYou() else { return }

        guard tapElement(app.buttons["View profile"], "View profile") else { return }
        let shown = expectScreen("maya.invests")
        expectStillRunning("opening my profile from You")
        snap("Y06 Profile from You")
        guard shown else { return }

        goBack(from: "maya.invests")
        expectScreen("You")
        XCTAssertTrue(app.buttons["View profile"].waitForExistence(timeout: 5), "Didn't return to the You tab")
        expectStillRunning("going back to You")
        snap("Y07 Back on You")
    }

    // MARK: Toolbar

    func testActivityAndSettingsFromToolbar() throws {
        launch()
        guard openYou() else { return }

        // Activity is pushed.
        if tapElement(app.navigationBars["You"].buttons["Activity"], "Activity in the You toolbar") {
            expectScreen("Activity")
            expectStillRunning("opening Activity")
            snap("Y08 Activity")
            goBack(from: "Activity")
            expectScreen("You")
            expectStillRunning("closing Activity")
        }

        // Settings is a sheet with Done.
        if tapElement(app.navigationBars["You"].buttons["Settings"], "Settings in the You toolbar") {
            let shown = expectScreen("Settings")
            expectStillRunning("opening Settings")
            snap("Y09 Settings")
            if shown {
                tapElement(app.navigationBars["Settings"].buttons["Done"], "Done in Settings")
                XCTAssertTrue(waitUntilGone(app.navigationBars["Settings"]), "Settings didn't close")
            }
            expectScreen("You")
            expectStillRunning("closing Settings")
            snap("Y10 You after Settings")
        }
    }

    // MARK: - Helpers

    /// The starter questions the Ask Haki card picks from (AssistantSuggestedQuestions).
    private static let suggestedQuestions = [
        "How much have I spent this month, and on what?",
        "How's my protein this week compared with my goal?",
        "What should I wear to a casual dinner this weekend?",
        "Am I on track with my budgets?",
        "How have my workouts been going lately?",
        "Which flashcards should I study today?",
        "What bills are coming up in the next two weeks?",
        "Where could I cut back to save more next month?",
        "What did I write about in my recent notes?",
        "How are my investments doing?",
    ]

    /// Opens the You tab and waits for it.
    private func openYou(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)", file: file, line: line)
        openTab("You", file: file, line: line)
        return expectScreen("You", file: file, line: line)
    }

    /// One of the Ask Haki card's starter questions.
    private func suggestionButton() -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", argumentArray: [Self.suggestedQuestions])).firstMatch
    }

    /// A card's linked top part, whose label starts with its title
    /// ("Wardrobe, 10 pieces…"); else the title itself.
    private func cardLink(_ title: String) -> XCUIElement {
        let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        if link.waitForExistence(timeout: 5) { return link }
        return app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    /// Waits for the navigation bar titled `title`, i.e. for that screen.
    @discardableResult
    private func expectScreen(_ title: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let shown = app.navigationBars[title].waitForExistence(timeout: timeout)
        if !shown {
            XCTFail("Expected the \"\(title)\" screen", file: file, line: line)
        }
        return shown
    }

    /// Swipes until `element` can be tapped, at most `maxSwipes` times: down
    /// when it's above the middle of the screen (scrolled past), else up.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            if element.exists && element.frame.maxY < app.frame.midY {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /// Waits for `element`, scrolls to it if needed and taps it. Fails the
    /// test (and returns false) when it never appears.
    @discardableResult
    private func tapElement(_ element: XCUIElement, _ what: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard element.waitForExistence(timeout: timeout) else {
            XCTFail("Couldn't find \(what)", file: file, line: line)
            return false
        }
        if !element.isHittable {
            scrollTo(element)
        }
        element.tap()
        return true
    }

    /// Taps the back button of the navigation bar titled `title`.
    private func goBack(from title: String) {
        let back = app.navigationBars[title].buttons.element(boundBy: 0)
        if back.waitForExistence(timeout: 3) {
            back.tap()
        } else {
            goBack()
        }
    }

    @discardableResult
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }
}
