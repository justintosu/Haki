//
//  AssistantFlowTests.swift
//  HakiUITests
//
//  "Ask Haki": opened from the Home tab's toolbar (the intro and starter
//  questions, typing and sending a question, the answer with its "Looked
//  at" row, chat history, opening a saved chat, New chat, Done) and from a
//  starter question on the You tab's Ask Haki card, which opens the chat
//  already asking it. Screenshots are named "A01 …".
//
//  Relies on the preview AI that `-HakiUITesting` uses
//  (HakiAIPreviewSamples in Haki/Services/HakiAIService.swift): it first
//  says "Let me look at your overview." and looks up the overview, then
//  answers "Here's what I found in Haki (sample answer in preview mode)…",
//  about a second per step. No consent prompt in preview mode. The sample
//  data has one saved chat, "Spending this month".
//

import XCTest

final class AssistantFlowTests: HakiUITestCase {
    /// How long a preview answer may take (two rounds of about a second each).
    private let answerTimeout: TimeInterval = 20

    // MARK: From the Home tab

    func testAskFromHomeHistoryAndNewChat() throws {
        launch()
        guard openHome() else { return }

        guard tapElement(app.navigationBars["Home"].buttons["Ask Haki"], "Ask Haki in the Home toolbar") else { return }
        let shown = expectScreen("Ask Haki")
        expectVisible(containing: "what would you like to know?")
        expectVisible("Try asking")
        XCTAssertTrue(app.buttons["How much have I spent this month, and on what?"].waitForExistence(timeout: 5), "No starter questions in the intro")
        XCTAssertTrue(app.navigationBars["Ask Haki"].buttons["History"].exists, "No History button")
        expectStillRunning("opening Ask Haki from Home")
        snap("A01 Ask Haki intro")
        guard shown else { return }

        // Type a question and send it.
        let question = "How am I doing this month?"
        let field = composerField()
        guard tapElement(field, "the Ask Haki text field") else { return }
        field.typeText(question)
        let send = app.buttons["Send"]
        XCTAssertTrue(send.waitForExistence(timeout: 5), "No Send button")
        XCTAssertTrue(send.isEnabled, "Send stays disabled after typing a question")
        expectStillRunning("typing a question")
        snap("A02 Question typed")
        send.tap()

        expectVisible("You: " + question)
        expectStillRunning("sending a question")
        snap("A03 Question sent")

        // The preview first looks at the overview, then answers.
        expectVisible(containing: "Let me look at your overview", timeout: answerTimeout)
        let answer = answerBubble(containing: "what I found in Haki")
        XCTAssertTrue(answer.waitForExistence(timeout: answerTimeout), "No answer from the preview assistant")
        if answer.exists {
            XCTAssertTrue(answer.label.contains("Looked at: Overview"), "The answer has no \"Looked at: Overview\" row (label: \(answer.label))")
        }
        XCTAssertTrue(waitUntil(timeout: 10) { !self.app.buttons["Cancel"].exists }, "The typing indicator didn't go away")
        expectStillRunning("getting an answer")
        snap("A04 Answer with Looked at")

        // History: the sample chat and the new one.
        guard tapElement(app.navigationBars["Ask Haki"].buttons["History"], "History in Ask Haki") else { return }
        let historyShown = expectScreen("Chat history")
        let sampleChat = historyRow("Spending this month")
        XCTAssertTrue(sampleChat.waitForExistence(timeout: 8), "The sample chat isn't in the history")
        XCTAssertTrue(historyRow(question).waitForExistence(timeout: 5), "The new chat isn't in the history")
        expectStillRunning("opening chat history")
        snap("A05 Chat history")
        guard historyShown else { return }

        // Opening a saved chat shows it in the chat screen.
        if tapElement(sampleChat, "the Spending this month chat") {
            expectScreen("Ask Haki")
            XCTAssertTrue(waitUntilGone(app.navigationBars["Chat history"]), "The history didn't close after opening a chat")
            expectVisible("You: How much have I spent on restaurants this month?")
            XCTAssertTrue(answerBubble(containing: "212.40").waitForExistence(timeout: 8), "The saved answer isn't shown")
            expectStillRunning("opening a saved chat")
            snap("A06 Saved chat")
        }

        // New chat: back to the intro.
        let newChat = app.navigationBars["Ask Haki"].buttons["New chat"]
        if tapElement(newChat, "New chat") {
            expectVisible(containing: "what would you like to know?")
            XCTAssertTrue(waitUntil(timeout: 5) { !newChat.isEnabled }, "New chat stays enabled on an empty chat")
            expectStillRunning("starting a new chat")
            snap("A07 New chat")
        }

        // Done closes the sheet.
        tapElement(app.navigationBars["Ask Haki"].buttons["Done"], "Done in Ask Haki")
        XCTAssertTrue(waitUntilGone(app.navigationBars["Ask Haki"]), "Ask Haki didn't close after Done")
        expectScreen("Home")
        expectStillRunning("closing Ask Haki")
        snap("A08 Home after Ask Haki")
    }

    // MARK: From the You tab

    func testAskFromYouCardSuggestion() throws {
        launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)")
        openTab("You")
        guard expectScreen("You") else { return }

        // The card shows three of the starter questions (a different set each day).
        let suggestion = app.buttons.matching(NSPredicate(format: "label IN %@", Self.suggestedQuestions)).firstMatch
        guard suggestion.waitForExistence(timeout: 8) else {
            XCTFail("The Ask Haki card shows no starter question")
            return
        }
        scrollTo(suggestion)
        let question = suggestion.label
        expectStillRunning("opening You")
        snap("A09 You, Ask Haki card")
        suggestion.tap()

        // The chat opens already asking it.
        guard expectScreen("Ask Haki") else { return }
        expectVisible("You: " + question)
        expectStillRunning("asking a starter question")
        snap("A10 Starter question asked")

        let answer = answerBubble(containing: "what I found in Haki")
        XCTAssertTrue(answer.waitForExistence(timeout: answerTimeout), "No answer to the starter question")
        if answer.exists {
            XCTAssertTrue(answer.label.contains("Looked at: Overview"), "The answer has no \"Looked at: Overview\" row (label: \(answer.label))")
        }
        expectStillRunning("answering a starter question")
        snap("A11 Starter question answered")

        tapElement(app.navigationBars["Ask Haki"].buttons["Done"], "Done in Ask Haki")
        XCTAssertTrue(waitUntilGone(app.navigationBars["Ask Haki"]), "Ask Haki didn't close after Done")
        expectScreen("You")
        expectStillRunning("closing Ask Haki")
    }

    // MARK: - Helpers

    /// The starter questions (AssistantSuggestedQuestions); the You card shows three.
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

    /// The composer's placeholder ("Ask Haki anything…").
    private static let composerPlaceholder = "Ask Haki anything\u{2026}"

    /// Opens the Home tab and waits for it.
    private func openHome(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)", file: file, line: line)
        openTab("Home", file: file, line: line)
        return expectScreen("Home", file: file, line: line)
    }

    /// The chat's text field (a vertical TextField, so a text field or a text view).
    private func composerField() -> XCUIElement {
        let predicate = NSPredicate(
            format: "label == %@ OR placeholderValue == %@ OR identifier == %@",
            Self.composerPlaceholder, Self.composerPlaceholder, Self.composerPlaceholder
        )
        let field = app.textFields.matching(predicate).firstMatch
        if field.waitForExistence(timeout: 5) { return field }
        let view = app.textViews.matching(predicate).firstMatch
        if view.waitForExistence(timeout: 2) { return view }
        if app.textViews.firstMatch.exists { return app.textViews.firstMatch }
        return app.textFields.firstMatch
    }

    /// Haki's answer bubble: one element labelled "Haki: <answer>. Looked at: …".
    private func answerBubble(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", "Haki: ", text
        )).firstMatch
    }

    /// A chat in the history ("Spending this month, <last answer>, <when>").
    private func historyRow(_ title: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", title)
        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: 3) { return button }
        let cell = app.cells.matching(predicate).firstMatch
        return cell.exists ? cell : button
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

    @discardableResult
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Polls `condition` until it holds or `timeout` passes.
    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline
        return condition()
    }
}
