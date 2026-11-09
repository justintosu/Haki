//
//  StudyFlowTests.swift
//  HakiUITests
//
//  Notes & Flashcards, from the You tab: the notes list (pinned first), a
//  note with its Markdown preview, writing a new note, the decks, a study
//  session (flip a card, grade it Good, end the session), and "Make
//  flashcards with AI" from a note (four drafts, saved as a deck).
//  Screenshots are named "N01 …".
//
//  Sample data (Haki/Data/LifePreviewData.swift): notes "Cell biology"
//  (pinned), "Spanish verbs" and "Trip ideas"; decks "Cell biology" (one
//  card due) and "Spanish verbs" (four new cards). The preview AI
//  (HakiAIPreviewSamples.flashcards) writes four biology cards after about
//  1.5 s, whatever the note says.
//

import XCTest

final class StudyFlowTests: HakiUITestCase {
    // MARK: Notes

    func testNotesPreviewAndNewNote() throws {
        launch()
        guard openStudy() else { return }
        // The side is remembered between launches.
        tapElement(app.segmentedControls.buttons["Notes"], "the Notes segment")

        let cellBiology = listRow(containing: "Cell biology")
        XCTAssertTrue(cellBiology.waitForExistence(timeout: 8), "No Cell biology note")
        if cellBiology.exists {
            XCTAssertTrue(cellBiology.label.contains("Pinned"), "Cell biology isn't marked pinned (label: \(cellBiology.label))")
        }
        XCTAssertTrue(listRow(containing: "Spanish verbs").exists, "No Spanish verbs note")
        XCTAssertTrue(listRow(containing: "Trip ideas").exists, "No Trip ideas note")
        XCTAssertTrue(app.navigationBars["Notes & Flashcards"].buttons["New note"].exists, "No New note button")
        expectStillRunning("showing notes")
        snap("N01 Notes")

        // A note, then its preview.
        guard tapElement(cellBiology, "the Cell biology note") else { return }
        let bodyView = noteBody()
        XCTAssertTrue(bodyView.waitForExistence(timeout: 8), "The note editor didn't open")
        XCTAssertEqual(noteTitleField().value as? String, "Cell biology")
        expectStillRunning("opening a note")
        snap("N02 Note editor")

        if tapElement(app.navigationBars.buttons["Preview"], "Preview in the note editor") {
            expectScreen("Preview")
            expectVisible(containing: "make ATP")
            expectStillRunning("previewing a note")
            snap("N03 Note preview")
            tapElement(app.navigationBars["Preview"].buttons["Edit"], "Edit in the note preview")
            XCTAssertTrue(noteBody().waitForExistence(timeout: 5), "Edit didn't go back to writing")
            expectStillRunning("going back to writing")
        }
        backFromNote()
        guard expectScreen("Notes & Flashcards") else { return }

        // A new note.
        guard tapElement(app.navigationBars["Notes & Flashcards"].buttons["New note"], "New note") else { return }
        let title = noteTitleField()
        guard tapElement(title, "the new note's title field") else { return }
        title.typeText("UI test note")
        let newBody = noteBody()
        guard tapElement(newBody, "the new note's text") else { return }
        newBody.typeText("Written by the UI tests.\n- First point\n- **Second** point")
        dismissKeyboard()
        XCTAssertEqual(title.value as? String, "UI test note")
        expectVisible(containing: "words")
        expectStillRunning("writing a note")
        snap("N04 New note written")

        backFromNote()
        expectScreen("Notes & Flashcards")
        let newRow = listRow(containing: "UI test note")
        XCTAssertTrue(newRow.waitForExistence(timeout: 8), "The new note isn't listed")
        expectStillRunning("saving a new note")
        snap("N05 Notes with the new one")
    }

    // MARK: Flashcards

    func testDeckStudySession() throws {
        launch()
        guard openStudy() else { return }
        guard tapElement(app.segmentedControls.buttons["Flashcards"], "the Flashcards segment") else { return }

        expectVisible(containing: "due today")
        let spanish = deckRow("Spanish verbs")
        XCTAssertTrue(spanish.waitForExistence(timeout: 8), "No Spanish verbs deck")
        XCTAssertTrue(deckRow("Cell biology").exists, "No Cell biology deck")
        expectStillRunning("showing decks")
        snap("N06 Flashcard decks")

        guard tapElement(spanish, "the Spanish verbs deck") else { return }
        guard expectScreen("Spanish verbs") else { return }
        let studyNow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Study now")).firstMatch
        XCTAssertTrue(studyNow.waitForExistence(timeout: 5), "No Study now button (four new cards)")
        XCTAssertTrue(statTile("Cards", value: "4").exists, "The deck doesn't show 4 cards")
        expectStillRunning("opening a deck")
        snap("N07 Deck detail")

        // The session opens full screen on its setup: pick flip cards.
        guard tapElement(studyNow, "Study now") else { return }
        let start = app.buttons["Start"]
        XCTAssertTrue(start.waitForExistence(timeout: 8), "The study session didn't open")
        let flip = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Flip cards")).firstMatch
        if tapElement(flip, "the Flip cards mode") {
            XCTAssertTrue(wait(for: flip, toMatch: "isSelected == true", timeout: 3), "Flip cards didn't get selected")
        }
        expectStillRunning("opening a study session")
        snap("N08 Study session setup")
        guard tapElement(start, "Start") else { return }

        // Flip the first card and grade it.
        let question = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Question: ")).firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: 8), "No question card")
        XCTAssertTrue(progress("Card 1 of 4").exists, "The session isn't on card 1 of 4")
        expectStillRunning("starting the session")
        snap("N09 Question")

        guard tapElement(app.buttons["Show answer"], "Show answer") else { return }
        let good = app.buttons["Good"]
        XCTAssertTrue(good.waitForExistence(timeout: 5), "No grade buttons after flipping")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Answer: ")).firstMatch.exists, "The card didn't flip to its answer")
        XCTAssertTrue(app.buttons["Again"].exists && app.buttons["Hard"].exists && app.buttons["Easy"].exists, "Missing grade buttons")
        expectStillRunning("flipping a card")
        snap("N10 Answer and grades")

        good.tap()
        XCTAssertTrue(progress("Card 2 of 4").waitForExistence(timeout: 5), "Grading didn't move to card 2 of 4")
        expectStillRunning("grading a card Good")
        snap("N11 Next card")

        // Close mid-session: it asks first.
        guard tapElement(app.buttons["Close"], "Close in the session") else { return }
        let end = app.buttons["End session"]
        if end.waitForExistence(timeout: 5) {
            snap("N12 End session confirmation")
            end.tap()
        } else {
            XCTFail("Closing mid-session didn't ask to end it")
        }
        XCTAssertTrue(waitUntilGone(app.buttons["Close"]), "The session didn't close")
        XCTAssertTrue(app.buttons["Cram all cards"].waitForExistence(timeout: 8), "Didn't return to the deck")
        XCTAssertTrue(statTile("Learned", value: "1").waitForExistence(timeout: 5), "The graded card doesn't count as learned")
        expectStillRunning("ending the session")
        snap("N13 Deck after studying")
    }

    // MARK: AI flashcards

    func testMakeFlashcardsWithAI() throws {
        launch()
        guard openStudy() else { return }
        tapElement(app.segmentedControls.buttons["Notes"], "the Notes segment")

        // "Trip ideas" has no deck yet, so the new one is easy to find.
        guard tapElement(listRow(containing: "Trip ideas"), "the Trip ideas note") else { return }
        XCTAssertTrue(noteBody().waitForExistence(timeout: 8), "The note editor didn't open")
        guard tapElement(app.navigationBars.buttons["More"], "More in the note editor") else { return }
        let makeWithAI = app.buttons["Make flashcards with AI"]
        XCTAssertTrue(makeWithAI.waitForExistence(timeout: 5), "The note menu has no Make flashcards with AI")
        snap("N14 Note menu")
        guard tapElement(makeWithAI, "Make flashcards with AI") else { return }

        guard expectScreen("AI flashcards") else { return }
        expectVisible(containing: "into flashcards")
        let make = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "Make ", "flashcards")).firstMatch
        XCTAssertTrue(make.waitForExistence(timeout: 5), "No Make flashcards button")
        expectStillRunning("opening AI flashcards")
        snap("N15 AI flashcards setup")
        guard tapElement(make, "Make flashcards") else { return }

        // The preview AI writes four cards.
        guard expectScreen("Review cards", timeout: 20) else { return }
        let keeps = app.buttons.matching(NSPredicate(format: "label == %@", "Keep this card"))
        XCTAssertTrue(waitUntil(timeout: 5) { keeps.count == 4 }, "Expected 4 drafts, found \(keeps.count)")
        expectVisible(containing: "4 kept")
        let firstDraft = app.descendants(matching: .any).matching(NSPredicate(
            format: "label == %@ OR value == %@", "What does the mitochondria produce?", "What does the mitochondria produce?"
        )).firstMatch
        XCTAssertTrue(firstDraft.exists, "The first draft's question isn't shown")
        expectStillRunning("making flashcards")
        snap("N16 Drafts to review")

        guard tapElement(app.navigationBars["Review cards"].buttons["Save deck"], "Save deck") else { return }
        XCTAssertTrue(waitUntilGone(app.navigationBars["Review cards"]), "The flashcard sheet didn't close")
        // The note opens the new deck once the sheet is gone.
        guard expectScreen("Trip ideas") else { return }
        XCTAssertTrue(statTile("Cards", value: "4").waitForExistence(timeout: 5), "The new deck doesn't have 4 cards")
        expectVisible(containing: "Made from")
        expectStillRunning("saving the deck")
        snap("N17 New deck")

        goBack(from: "Trip ideas")
        XCTAssertTrue(noteBody().waitForExistence(timeout: 8), "Didn't go back to the note")
        backFromNote()
        guard expectScreen("Notes & Flashcards") else { return }
        guard tapElement(app.segmentedControls.buttons["Flashcards"], "the Flashcards segment") else { return }
        let newDeck = deckRow("Trip ideas")
        scrollTo(newDeck)
        XCTAssertTrue(newDeck.exists, "The new deck isn't listed")
        expectStillRunning("listing the new deck")
        snap("N18 Decks with the new one")
    }

    // MARK: - Helpers

    /// Opens the You tab, then Notes & Flashcards from its card.
    private func openStudy(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)", file: file, line: line)
        openTab("You", file: file, line: line)
        guard expectScreen("You", file: file, line: line) else { return false }
        var link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Notes & Flashcards")).firstMatch
        if !link.waitForExistence(timeout: 5) {
            link = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Notes & Flashcards")).firstMatch
        }
        guard tapElement(link, "the notes and flashcards card on You", file: file, line: line) else { return false }
        let shown = expectScreen("Notes & Flashcards", file: file, line: line)
        expectStillRunning("opening Notes & Flashcards", file: file, line: line)
        return shown
    }

    /// A note row ("Pinned, Cell biology, Yesterday, …"), as a button or a cell.
    private func listRow(containing text: String, timeout: TimeInterval = 8) -> XCUIElement {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: timeout) { return button }
        let cell = app.cells.matching(predicate).firstMatch
        return cell.exists ? cell : button
    }

    /// A deck row ("Spanish verbs, 4 new · 4 cards, …"), as a button or a cell.
    private func deckRow(_ name: String) -> XCUIElement {
        let predicate = NSPredicate(format: "label BEGINSWITH %@", name + ",")
        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: 5) { return button }
        let cell = app.cells.matching(predicate).firstMatch
        return cell.exists ? cell : button
    }

    /// The note editor's title field.
    private func noteTitleField() -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "placeholderValue == %@ OR label == %@", "Title", "Title")).firstMatch
    }

    /// The note editor's text ("Note text").
    private func noteBody() -> XCUIElement {
        app.textViews["Note text"]
    }

    /// A deck's number ("Cards" / "4").
    private func statTile(_ title: String, value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", title, value)).firstMatch
    }

    /// The study session's progress ("Card 2 of 4").
    private func progress(_ value: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@ AND value == %@", "Progress", value)).firstMatch
    }

    /// Back from the note editor, whose bar has no title.
    private func backFromNote() {
        dismissKeyboard()
        let named = app.navigationBars.buttons["Notes & Flashcards"]
        if named.exists {
            named.tap()
        } else if app.navigationBars.buttons["Back"].exists {
            app.navigationBars.buttons["Back"].tap()
        } else {
            goBack()
        }
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

    /// Waits until `element` matches `predicate` (e.g. "isSelected == true").
    private func wait(for element: XCUIElement, toMatch predicate: String, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    @discardableResult
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        wait(for: element, toMatch: "exists == false", timeout: timeout)
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

    /// Taps the keyboard toolbar's "Done" when a keyboard is up.
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        let toolbarDone = app.toolbars.buttons["Done"]
        if toolbarDone.exists {
            toolbarDone.tap()
        } else if app.keyboards.buttons["Done"].exists {
            app.keyboards.buttons["Done"].tap()
        }
        waitUntilGone(app.keyboards.firstMatch, timeout: 3)
    }
}
