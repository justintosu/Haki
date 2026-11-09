//
//  WardrobeFlowTests.swift
//  HakiUITests
//
//  The wardrobe, from the You tab: the pieces grid and a category filter,
//  a piece's detail with "Wore it today", the outfits grid, an outfit board
//  (dragging a piece), AI outfit ideas (occasion chip, get ideas, save one)
//  and adding a piece. Screenshots are named "R01 …".
//
//  Sample data (Haki/Data/LifePreviewData.swift): ten pieces without
//  photos (the screens show category icons), newest first "Black leather
//  belt", oldest "White tee"; outfits "Easy weekend" and "Dinner out". The
//  preview AI (HakiAIPreviewSamples) suggests "Easy weekend", "Layered for a
//  cool day" and "Simple and sharp" after about 1.5 s.
//
//  Adding a piece doesn't need a photo when it has a name, so the add test
//  types one and saves without opening the photo picker (no camera in the
//  simulator; PhotosPicker would open the system picker).
//

import XCTest

final class WardrobeFlowTests: HakiUITestCase {
    // MARK: Pieces

    func testPiecesFilterAndWoreItToday() throws {
        launch()
        guard openWardrobe() else { return }
        // The section is remembered between launches.
        tapElement(app.segmentedControls.buttons["Pieces"], "the Pieces segment")

        let newest = pieceCard("Black leather belt")
        XCTAssertTrue(newest.waitForExistence(timeout: 8), "The newest sample piece isn't in the grid")
        XCTAssertTrue(app.buttons["All"].exists, "No All filter chip")
        XCTAssertTrue(app.navigationBars["Wardrobe"].buttons["Add piece"].exists, "No Add piece button in the toolbar")
        expectStillRunning("showing pieces")
        snap("R01 Wardrobe pieces")

        // Tops only.
        let tops = app.buttons["Tops"]
        guard tapElement(tops, "the Tops chip") else { return }
        XCTAssertTrue(wait(for: tops, toMatch: "isSelected == true", timeout: 3), "The Tops chip didn't turn on")
        XCTAssertTrue(waitUntilGone(pieceCard("Black leather belt"), timeout: 5), "The Tops filter still shows the belt")
        let whiteTee = pieceCard("White tee")
        scrollTo(whiteTee)
        XCTAssertTrue(whiteTee.exists, "The Tops filter doesn't show White tee")
        XCTAssertFalse(pieceCard("Slim dark jeans").exists, "The Tops filter shows jeans")
        expectStillRunning("filtering by Tops")
        snap("R02 Wardrobe tops")

        // A piece's detail: Wore it today.
        guard tapElement(whiteTee, "the White tee card") else { return }
        guard expectScreen("White tee") else { return }
        expectVisible(containing: "Times worn")
        let wore = app.buttons["Wore it today"]
        XCTAssertTrue(wore.waitForExistence(timeout: 5), "No Wore it today button (White tee was last worn two days ago)")
        expectStillRunning("opening a piece")
        snap("R03 Piece detail")

        if tapElement(wore, "Wore it today") {
            let worn = app.buttons["Worn today"]
            XCTAssertTrue(worn.waitForExistence(timeout: 5), "Wore it today didn't turn into Worn today")
            XCTAssertFalse(worn.isEnabled, "Worn today should be disabled")
            let timesWorn = app.descendants(matching: .any).matching(NSPredicate(
                format: "label BEGINSWITH %@ AND label CONTAINS %@", "Times worn", "15"
            )).firstMatch
            XCTAssertTrue(timesWorn.waitForExistence(timeout: 5), "Times worn didn't go from 14 to 15")
            expectStillRunning("marking a piece worn")
            snap("R04 Piece worn today")
        }

        goBack(from: "White tee")
        expectScreen("Wardrobe")
        if tapElement(app.buttons["All"], "the All chip") {
            XCTAssertTrue(pieceCard("Black leather belt").waitForExistence(timeout: 5), "All didn't bring every piece back")
        }
        expectStillRunning("going back to the wardrobe")
        snap("R05 Wardrobe all pieces again")
    }

    // MARK: Outfits

    func testOutfitBoardDrag() throws {
        launch()
        guard openWardrobe() else { return }
        guard tapElement(app.segmentedControls.buttons["Outfits"], "the Outfits segment") else { return }

        let easyWeekend = outfitCard("Easy weekend")
        XCTAssertTrue(easyWeekend.waitForExistence(timeout: 8), "No Easy weekend outfit")
        XCTAssertTrue(outfitCard("Dinner out").exists, "No Dinner out outfit")
        XCTAssertTrue(app.buttons["Outfit ideas"].exists, "No Outfit ideas button")
        expectStillRunning("showing outfits")
        snap("R06 Wardrobe outfits")

        guard tapElement(easyWeekend, "the Easy weekend outfit") else { return }
        guard expectScreen("Easy weekend") else { return }
        let piece = boardPiece("White tee")
        XCTAssertTrue(piece.waitForExistence(timeout: 8), "White tee isn't on the Easy weekend board")
        XCTAssertTrue(boardPiece("Slim dark jeans").exists, "Slim dark jeans isn't on the board")
        XCTAssertTrue(app.buttons["Add pieces"].exists, "No Add pieces button under the board")
        expectStillRunning("opening an outfit board")
        snap("R07 Outfit board")

        // Drag a piece a little to the right and down.
        if piece.exists {
            let start = piece.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            start.press(forDuration: 0.3, thenDragTo: start.withOffset(CGVector(dx: 40, dy: 50)))
            expectStillRunning("dragging a piece on the board")
            XCTAssertTrue(boardPiece("White tee").waitForExistence(timeout: 5), "The dragged piece went missing")
            snap("R08 Piece dragged")
            // Dragging selects the piece; Done deselects it.
            let done = app.buttons["Done"]
            if done.waitForExistence(timeout: 3) {
                done.tap()
                expectStillRunning("deselecting the piece")
            }
        }

        goBack(from: "Easy weekend")
        expectScreen("Wardrobe")
        XCTAssertTrue(outfitCard("Easy weekend").waitForExistence(timeout: 8), "Easy weekend is gone from the outfits")
        expectStillRunning("leaving the board (its snapshot is drawn)")
        snap("R09 Outfits after the board")
    }

    func testOutfitIdeasSaveOne() throws {
        launch()
        guard openWardrobe() else { return }
        guard tapElement(app.segmentedControls.buttons["Outfits"], "the Outfits segment") else { return }

        guard tapElement(app.buttons["Outfit ideas"], "the Outfit ideas button") else { return }
        guard expectScreen("Outfit ideas") else { return }
        expectVisible("What's it for?")
        let getIdeas = app.buttons["Get ideas"]
        XCTAssertTrue(getIdeas.waitForExistence(timeout: 5), "No Get ideas button")
        expectStillRunning("opening outfit ideas")
        snap("R10 Outfit ideas")

        // An occasion chip.
        let weekend = app.buttons["Weekend"]
        if tapElement(weekend, "the Weekend chip") {
            XCTAssertTrue(wait(for: weekend, toMatch: "isSelected == true", timeout: 3), "The Weekend chip didn't turn on")
            expectStillRunning("choosing an occasion")
            snap("R11 Weekend chosen")
        }

        // The preview AI answers after about 1.5 s.
        guard tapElement(getIdeas, "Get ideas") else { return }
        let sharp = ideaCard("Simple and sharp")
        XCTAssertTrue(sharp.waitForExistence(timeout: 20), "No \"Simple and sharp\" idea")
        XCTAssertTrue(ideaCard("Easy weekend").exists, "No \"Easy weekend\" idea")
        expectVisible("Ideas for weekend")
        XCTAssertTrue(app.buttons["Get new ideas"].waitForExistence(timeout: 5), "Get ideas didn't turn into Get new ideas")
        expectStillRunning("getting outfit ideas")
        snap("R12 Outfit ideas ready")

        // Save the last idea ("Simple and sharp").
        let saveButtons = app.buttons.matching(NSPredicate(format: "label == %@", "Save outfit"))
        let ideaCount = saveButtons.count
        XCTAssertEqual(ideaCount, 3, "Expected three ideas to save")
        if ideaCount > 0 {
            let save = saveButtons.element(boundBy: ideaCount - 1)
            scrollTo(save)
            save.tap()
            XCTAssertTrue(app.buttons["Open board"].waitForExistence(timeout: 5), "Saving an idea didn't offer Open board")
            XCTAssertEqual(saveButtons.count, ideaCount - 1, "The saved idea still shows Save outfit")
            expectStillRunning("saving an idea")
            snap("R13 Idea saved")
        }

        tapElement(app.navigationBars["Outfit ideas"].buttons["Done"], "Done in Outfit ideas")
        XCTAssertTrue(waitUntilGone(app.navigationBars["Outfit ideas"]), "Outfit ideas didn't close")
        expectScreen("Wardrobe")
        let saved = app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", "Simple and sharp,", "Suggested by Haki"
        )).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8), "The saved idea isn't in the outfits")
        expectStillRunning("closing outfit ideas")
        snap("R14 Outfits with the saved idea")
    }

    // MARK: Adding a piece

    func testAddPieceWithoutPhoto() throws {
        launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)")
        openTab("You")
        guard expectScreen("You") else { return }

        // From the You tab's card: open the editor and cancel.
        if tapElement(app.buttons["Add piece"], "Add piece on the wardrobe card") {
            if expectScreen("Add piece") {
                XCTAssertTrue(app.buttons["Choose photo"].waitForExistence(timeout: 5), "No Choose photo button")
                XCTAssertFalse(app.navigationBars["Add piece"].buttons["Add"].isEnabled, "Add is enabled with no photo and no name")
                expectStillRunning("opening Add piece from You")
                snap("R15 Add piece from You")
                tapElement(app.navigationBars["Add piece"].buttons["Cancel"], "Cancel in Add piece")
                XCTAssertTrue(waitUntilGone(app.navigationBars["Add piece"]), "Add piece didn't close after Cancel")
            }
            expectScreen("You")
            expectStillRunning("cancelling Add piece")
        }

        // From the wardrobe's toolbar: a piece with a name and no photo.
        guard openWardrobeCard() else { return }
        tapElement(app.segmentedControls.buttons["Pieces"], "the Pieces segment")
        guard tapElement(app.navigationBars["Wardrobe"].buttons["Add piece"], "Add piece in the Wardrobe toolbar") else { return }
        guard expectScreen("Add piece") else { return }

        let name = "Striped linen shirt"
        let nameField = textField(placeholder: "Name, e.g. Navy crew-neck sweater")
        guard tapElement(nameField, "the piece's name field") else { return }
        nameField.typeText(name)
        dismissKeyboard()
        let add = app.navigationBars["Add piece"].buttons["Add"]
        XCTAssertTrue(add.waitForExistence(timeout: 3), "No Add button")
        XCTAssertTrue(wait(for: add, toMatch: "isEnabled == true", timeout: 3), "Add stays disabled with a name")
        expectStillRunning("naming a new piece")
        snap("R16 New piece named")

        add.tap()
        XCTAssertTrue(waitUntilGone(app.navigationBars["Add piece"]), "Add piece didn't close after Add")
        expectScreen("Wardrobe")
        let card = pieceCard(name)
        XCTAssertTrue(card.waitForExistence(timeout: 8), "The new piece isn't in the grid")
        expectStillRunning("adding a piece")
        snap("R17 New piece in the wardrobe")
    }

    // MARK: - Helpers

    /// Opens the You tab, then the wardrobe from its card.
    private func openWardrobe(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)", file: file, line: line)
        openTab("You", file: file, line: line)
        guard expectScreen("You", file: file, line: line) else { return false }
        return openWardrobeCard(file: file, line: line)
    }

    /// On the You tab: taps the wardrobe card and waits for Wardrobe.
    private func openWardrobeCard(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        var link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Wardrobe")).firstMatch
        if !link.waitForExistence(timeout: 5) {
            link = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Wardrobe")).firstMatch
        }
        guard tapElement(link, "the wardrobe card on You", file: file, line: line) else { return false }
        let shown = expectScreen("Wardrobe", file: file, line: line)
        expectStillRunning("opening the wardrobe", file: file, line: line)
        return shown
    }

    /// A piece in the grid: "White tee, Top, Worn 14 times".
    private func pieceCard(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    /// An outfit in the grid: "Easy weekend, Weekend errands, 3 pieces, …".
    private func outfitCard(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
    }

    /// A piece on the outfit board (labelled with its name).
    private func boardPiece(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
    }

    /// An idea in Outfit ideas: its name and why it works ("Easy weekend, These colors…").
    private func ideaCard(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", name, "These colors work together"
        )).firstMatch
    }

    /// A text field by its placeholder (or label).
    private func textField(placeholder: String) -> XCUIElement {
        app.textFields.matching(NSPredicate(
            format: "placeholderValue == %@ OR label == %@ OR identifier == %@", placeholder, placeholder, placeholder
        )).firstMatch
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

    /// Taps the keyboard toolbar's "Done" when a keyboard is up.
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        let toolbarDone = app.toolbars.buttons["Done"]
        if toolbarDone.exists {
            toolbarDone.tap()
        } else if app.keyboards.buttons["Done"].exists {
            app.keyboards.buttons["Done"].tap()
        } else if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
        waitUntilGone(app.keyboards.firstMatch, timeout: 3)
    }
}
