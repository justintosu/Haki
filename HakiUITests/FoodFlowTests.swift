//
//  FoodFlowTests.swift
//  HakiUITests
//
//  The food side of the Health tab, walked through like a person would: the
//  dashboard, adding food by hand, "Snap a meal" with a description (the
//  simulator has no camera; the preview AI answers with a sample "Chicken
//  burrito bowl"), the food log (days, swipe actions, log again) and
//  nutrition goals. Sample data: three meals today, two yesterday.
//

import XCTest

final class FoodFlowTests: HakiUITestCase {
    // MARK: Dashboard

    func testHealthDashboard() throws {
        launch()
        openHealth()
        expectVisible(containing: "3 items logged today")
        for title in ["Snap a meal", "Add food", "Eat nearby"] {
            XCTAssertTrue(app.buttons[title].exists, "Missing the \"\(title)\" tile")
        }
        snap("F01 Health dashboard")

        app.swipeUp()
        for title in ["Food log", "Workouts", "Nutrition goals"] {
            XCTAssertTrue(app.buttons[title].waitForExistence(timeout: 5), "Missing the \"\(title)\" link")
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hevy")).firstMatch.exists, "Missing the Hevy row")
        expectStillRunning("scrolling the Health dashboard")
        snap("F02 Health dashboard, links")

        // The toolbar "+" opens the same capture sheet as "Snap a meal".
        app.swipeDown()
        let logMeal = app.navigationBars["Health"].buttons["Log a meal"]
        XCTAssertTrue(logMeal.waitForExistence(timeout: 5), "No \"Log a meal\" button in the toolbar")
        logMeal.tap()
        let captureBar = app.navigationBars["Snap a meal"]
        XCTAssertTrue(captureBar.waitForExistence(timeout: 8), "\"Log a meal\" didn't open the capture sheet")
        expectStillRunning("opening Log a meal")
        snap("F03 Log a meal sheet")
        captureBar.buttons["Cancel"].tap()
        waitUntilGone(captureBar)
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 5))
        expectStillRunning("cancelling the capture sheet")
    }

    // MARK: Add food by hand

    func testAddFoodManually() throws {
        launch()
        openHealth()

        let addFood = app.buttons["Add food"]
        XCTAssertTrue(addFood.waitForExistence(timeout: 8))
        addFood.tap()
        let formBar = app.navigationBars["Add food"]
        XCTAssertTrue(formBar.waitForExistence(timeout: 8), "\"Add food\" didn't open the form")
        expectStillRunning("opening Add food")
        snap("F04 Add food form")

        let save = formBar.buttons["Save"]
        XCTAssertFalse(save.isEnabled, "Save should wait for a name and calories")

        typeInto(app.textFields["Name, e.g. Chicken salad"], "Turkey sandwich UI test")
        typeInto(app.textFields["Calories in kilocalories"], "420")
        typeInto(app.textFields["Protein in grams"], "32")
        dismissKeyboard()
        expectStillRunning("typing a food")
        snap("F05 Add food filled in")

        XCTAssertTrue(save.isEnabled, "Save is still disabled with a name and calories")
        save.tap()
        XCTAssertTrue(waitUntilGone(formBar), "The form didn't close after Save")
        expectStillRunning("saving a food")
        expectVisible(containing: "4 items logged today")
        snap("F06 Today card after adding")

        openFoodLog()
        let row = element(containing: "Turkey sandwich UI test")
        scrollToElement(row)
        XCTAssertTrue(row.exists, "The new food isn't in the food log")
        if row.exists {
            XCTAssertTrue(row.label.contains("420 kcal"), "The new food's row doesn't show its calories: \(row.label)")
        }
        snap("F07 Food log with the new food")
    }

    // MARK: Snap a meal (description only)

    func testSnapMealWithDescription() throws {
        launch()
        openHealth()

        let snapMeal = app.buttons["Snap a meal"]
        XCTAssertTrue(snapMeal.waitForExistence(timeout: 8))
        snapMeal.tap()
        let captureBar = app.navigationBars["Snap a meal"]
        XCTAssertTrue(captureBar.waitForExistence(timeout: 8), "\"Snap a meal\" didn't open")
        expectVisible("Add a photo or a description to get an estimate.")
        expectStillRunning("opening Snap a meal")
        snap("F08 Snap a meal")

        // No camera in the simulator: describe the meal instead.
        let description = textInput("Meal description")
        XCTAssertTrue(description.exists, "No meal description field")
        description.tap()
        description.typeText("Chicken burrito bowl with rice, black beans and salsa")

        let estimate = app.buttons["Estimate calories & protein"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 5))
        bringAboveKeyboard(estimate)
        XCTAssertTrue(estimate.isEnabled, "The estimate button stays disabled with a description")
        snap("F09 Meal described")
        estimate.tap()

        if element(labeled: "Looking at your meal\u{2026}").waitForExistence(timeout: 3) {
            snap("F10 Estimating")
        }
        let reviewBar = app.navigationBars["Review"]
        XCTAssertTrue(reviewBar.waitForExistence(timeout: 20), "The estimate review never appeared")
        expectStillRunning("estimating a meal")

        let mealName = app.textFields["Meal name"]
        XCTAssertTrue(mealName.waitForExistence(timeout: 5))
        XCTAssertEqual(mealName.value as? String, "Chicken burrito bowl")
        XCTAssertTrue(textInput("Item name").exists, "The estimate has no items")
        snap("F11 Estimate review")

        let notes = element(labeled: "Assumed no sour cream or cheese.")
        scrollToElement(notes)
        XCTAssertTrue(notes.exists, "The estimate's notes aren't shown")
        expectStillRunning("scrolling the review")
        snap("F12 Estimate review, items and notes")

        let save = reviewBar.buttons["Save"]
        XCTAssertTrue(save.isEnabled, "Can't save the estimate")
        save.tap()
        XCTAssertTrue(waitUntilGone(reviewBar), "The review didn't close after Save")
        expectStillRunning("saving the estimate")
        expectVisible(containing: "4 items logged today")
        snap("F13 Today card after the estimate")

        openFoodLog()
        // The sample data already has a "Chicken burrito bowl"; the saved estimate
        // is the one listing its items as the portion.
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "Chicken burrito bowl", "Grilled chicken (4 oz)"
        )).firstMatch
        scrollToElement(row)
        XCTAssertTrue(row.exists, "The saved estimate isn't in the food log")
        snap("F14 Food log with the estimate")
    }

    // MARK: Food log

    func testFoodLogDaysAndSwipeActions() throws {
        launch()
        openHealth()
        openFoodLog()
        expectVisible("Today")
        XCTAssertTrue(app.buttons["Previous day"].exists)
        XCTAssertFalse(app.buttons["Next day"].isEnabled, "Next day should be disabled on today")
        expectVisible(containing: "Greek yogurt bowl")
        snap("F15 Food log today")

        // Yesterday and back.
        app.buttons["Previous day"].tap()
        let backToToday = app.buttons["Back to today"]
        XCTAssertTrue(backToToday.waitForExistence(timeout: 5), "No \"Back to today\" on yesterday")
        expectVisible("Yesterday")
        expectVisible(containing: "Salmon rice bowl")
        expectStillRunning("going to the previous day")
        snap("F16 Food log yesterday")
        backToToday.tap()
        XCTAssertTrue(waitUntilGone(backToToday), "Still not on today")
        expectVisible("Today")
        snap("F17 Food log back to today")

        // Swipe left: Delete. A short drag, so it shows the action instead of
        // doing a full swipe.
        let rowQuery = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Greek yogurt bowl"))
        let row = rowQuery.firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        drag(row, fromX: 0.8, toX: 0.5)
        let delete = app.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 3), "Swiping left didn't show Delete")
        expectStillRunning("swiping a food log row")
        snap("F18 Row swiped left")
        // A tap on the row closes the actions (or, if it lands, opens the editor).
        if row.exists {
            row.tap()
        }
        closeEditorIfOpen()
        waitUntilGone(delete, timeout: 3)

        // Swipe right: Log again (a full swipe logs it straight away, which is fine too).
        XCTAssertTrue(rowQuery.firstMatch.waitForExistence(timeout: 5), "The row is gone after swiping")
        drag(rowQuery.firstMatch, fromX: 0.15, toX: 0.45)
        let logAgain = app.buttons["Log again"]
        let toast = element(containing: "Added Greek yogurt bowl")
        if waitForAny([logAgain, toast], timeout: 3) == logAgain {
            snap("F19 Row swiped right")
            logAgain.tap()
        }
        XCTAssertTrue(toast.waitForExistence(timeout: 4), "No \"Added Greek yogurt bowl…\" confirmation")
        expectStillRunning("logging a food again")
        snap("F20 Logged again")

        // The toolbar menu and the "Log again…" sheet.
        let addMenu = app.navigationBars["Food log"].buttons["Add food"]
        XCTAssertTrue(addMenu.waitForExistence(timeout: 5))
        addMenu.tap()
        let logAgainItem = app.buttons["Log again\u{2026}"]
        XCTAssertTrue(logAgainItem.waitForExistence(timeout: 5), "The add menu has no \"Log again…\"")
        XCTAssertTrue(app.buttons["Add manually"].exists)
        snap("F21 Food log add menu")
        logAgainItem.tap()
        let logAgainBar = app.navigationBars["Log again"]
        XCTAssertTrue(logAgainBar.waitForExistence(timeout: 8), "\"Log again…\" didn't open its sheet")
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 3), "No search field for recent foods")
        expectStillRunning("opening Log again")
        snap("F22 Log again sheet")
        logAgainBar.buttons["Cancel"].tap()
        XCTAssertTrue(waitUntilGone(logAgainBar))
        expectStillRunning("closing Log again")
    }

    // MARK: Nutrition goals

    func testNutritionGoals() throws {
        launch()
        openHealth()

        let goalsLink = app.buttons.matching(identifier: "Nutrition goals").firstMatch
        XCTAssertTrue(goalsLink.waitForExistence(timeout: 8))
        scrollToElement(goalsLink)
        goalsLink.tap()
        XCTAssertTrue(app.navigationBars["Nutrition goals"].waitForExistence(timeout: 8), "Nutrition goals didn't open")
        expectStillRunning("opening Nutrition goals")
        snap("F23 Nutrition goals")

        // About you: pounds and feet/inches for en_US, kilograms and centimeters otherwise.
        let pounds = app.textFields["Weight in pounds"]
        let kilograms = app.textFields["Weight in kilograms"]
        XCTAssertNotNil(waitForAny([pounds, kilograms], timeout: 5), "No weight field")
        if pounds.exists {
            typeInto(pounds, "170")
        } else {
            typeInto(kilograms, "77")
        }
        let feet = app.textFields["Height, feet"]
        if feet.exists {
            typeInto(feet, "5")
            typeInto(app.textFields["Height, inches"], "10")
        } else {
            typeInto(app.textFields["Height in centimeters"], "178")
        }
        typeInto(app.textFields["Age in years"], "34")
        dismissKeyboard()
        expectStillRunning("filling in About you")
        snap("F24 About you filled in")

        // The suggestion sits below the activity levels, off screen, and the
        // form only creates rows as they scroll into view: scroll down to it.
        let useThese = app.buttons["Use these"]
        let usingThese = app.buttons["You're using these"]
        var suggestion = waitForAny([useThese, usingThese], timeout: 2)
        var swipes = 0
        while suggestion == nil && swipes < 6 {
            app.swipeUp()
            swipes += 1
            suggestion = waitForAny([useThese, usingThese], timeout: 1)
        }
        XCTAssertNotNil(suggestion, "No suggested targets after filling in About you")
        if let suggestion {
            scrollToElement(suggestion)
        }
        snap("F25 Suggested targets")
        if useThese.exists {
            useThese.tap()
            XCTAssertTrue(usingThese.waitForExistence(timeout: 5), "\"Use these\" didn't apply the targets")
            expectStillRunning("using the suggested targets")
        }

        let reset = app.buttons["Reset to standard"]
        scrollToElement(reset)
        snap("F26 Daily targets")

        // Put the targets and details back, so later runs start from the standard ones.
        if reset.exists, reset.isEnabled {
            reset.tap()
            if tapDialogButton("Reset to standard") {
                expectStillRunning("resetting the targets")
                snap("F27 Targets reset")
            }
        }
        let forget = app.buttons["Forget my details"]
        scrollToElement(forget, upward: true)
        if forget.exists {
            forget.tap()
            if tapDialogButton("Forget my details") {
                XCTAssertTrue(waitUntilGone(forget, timeout: 5), "The details weren't forgotten")
            }
        }
        expectStillRunning("cleaning up the goals")
    }

    // MARK: Navigation

    private func openHealth(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared", file: file, line: line)
        openTab("Health", file: file, line: line)
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 10), "The Health tab didn't open", file: file, line: line)
    }

    private func openFoodLog(file: StaticString = #filePath, line: UInt = #line) {
        let link = app.buttons.matching(identifier: "Food log").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 8), "No Food log link", file: file, line: line)
        scrollToElement(link)
        link.tap()
        XCTAssertTrue(app.navigationBars["Food log"].waitForExistence(timeout: 8), "The food log didn't open", file: file, line: line)
        expectStillRunning("opening the food log", file: file, line: line)
    }

    /// The food editor, if a tap meant to close swipe actions opened it instead.
    private func closeEditorIfOpen() {
        let editor = app.navigationBars["Edit food"]
        if editor.waitForExistence(timeout: 1) {
            editor.buttons["Cancel"].tap()
            waitUntilGone(editor)
        }
    }

    // MARK: Queries

    private func element(labeled label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// A text input by label; multi-line fields can show up as text views.
    private func textInput(_ label: String) -> XCUIElement {
        let field = app.textFields[label]
        let view = app.textViews[label]
        return waitForAny([field, view], timeout: 5) ?? field
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = elements.first(where: { $0.exists }) { return found }
            _ = elements.first?.waitForExistence(timeout: 0.5)
        } while Date() < deadline
        return elements.first(where: { $0.exists })
    }

    @discardableResult
    private func waitUntilGone(_ element: XCUIElement, timeout: TimeInterval = 8) -> Bool {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
    }

    // MARK: Gestures and typing

    /// Swipes up (or down) until `element` exists and can be tapped.
    @discardableResult
    private func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 6, upward: Bool = false) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            if upward {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
            swipes += 1
        }
        return element.exists && element.isHittable
    }

    /// A short horizontal drag across `element` (reveals swipe actions without a full swipe).
    private func drag(_ element: XCUIElement, fromX startX: CGFloat, toX endX: CGFloat) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end)
    }

    /// Replaces a field's text: closes the keyboard first (so the field isn't
    /// under it), taps the field's end and deletes what's there.
    private func typeInto(_ field: XCUIElement, _ text: String, file: StaticString = #filePath, line: UInt = #line) {
        guard field.waitForExistence(timeout: 5) else {
            XCTFail("No field to type \"\(text)\" into", file: file, line: line)
            return
        }
        dismissKeyboard()
        scrollToElement(field, maxSwipes: 3)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(text)
    }

    /// Taps the keyboard toolbar's "Done" (or the keyboard's own Done) when a keyboard is up.
    private func dismissKeyboard() {
        guard app.keyboards.firstMatch.exists else { return }
        let toolbarDone = app.toolbars.buttons["Done"]
        if toolbarDone.exists {
            toolbarDone.tap()
        } else if app.keyboards.buttons["Done"].exists {
            app.keyboards.buttons["Done"].tap()
        } else if app.buttons.matching(identifier: "Done").firstMatch.exists {
            app.buttons.matching(identifier: "Done").firstMatch.tap()
        }
        waitUntilGone(app.keyboards.firstMatch, timeout: 3)
    }

    /// Scrolls the screen's content until `element` sits above the keyboard.
    private func bringAboveKeyboard(_ element: XCUIElement) {
        for _ in 0..<4 {
            let keyboard = app.keyboards.firstMatch
            guard keyboard.exists, element.exists else { return }
            if element.frame.maxY < keyboard.frame.minY - 2 { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
    }

    /// Taps a confirmation dialog's button. The screen's own button with the
    /// same title stays behind it, so the dialog's copy is the last match.
    @discardableResult
    private func tapDialogButton(_ title: String) -> Bool {
        let inSheet = app.sheets.buttons[title]
        let inAlert = app.alerts.buttons[title]
        if let found = waitForAny([inSheet, inAlert], timeout: 3) {
            found.tap()
            return true
        }
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", title))
        guard matches.count > 1 else { return false }
        matches.element(boundBy: matches.count - 1).tap()
        return true
    }
}
