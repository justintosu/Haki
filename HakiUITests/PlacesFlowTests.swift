//
//  PlacesFlowTests.swift
//  HakiUITests
//
//  "Eat nearby" from the Health tab: the map and list of places from Apple
//  Maps, search shortcuts and typed searches, then a place's menu (the
//  preview AI answers with the sample "Green Fork Kitchen" menu): best picks,
//  a filter, a sort, a dish sheet and logging the dish. Apple Maps results
//  need the network, so the menu test is skipped when no place comes back.
//

import XCTest

final class PlacesFlowTests: HakiUITestCase {
    // MARK: Searching

    func testEatNearbySearchAndMap() throws {
        launch()
        openEatNearby()
        snap("P01 Eat nearby")

        // A shortcut chip toggles on and off.
        let healthy = app.buttons["Healthy"]
        XCTAssertTrue(healthy.waitForExistence(timeout: 5), "No \"Healthy\" shortcut")
        healthy.tap()
        XCTAssertTrue(wait(for: healthy, toMatch: "isSelected == true", timeout: 3), "The Healthy chip didn't turn on")
        let healthyOutcome = waitForSearchOutcome(resultsTitle: "Healthy food nearby", timeout: 20)
        expectStillRunning("searching with the Healthy shortcut")
        snap("P02 Healthy shortcut (\(healthyOutcome))")
        healthy.tap()
        XCTAssertTrue(wait(for: healthy, toMatch: "isSelected == false", timeout: 3), "The Healthy chip didn't turn off")

        // A typed search replaces the shortcut.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "No search field")
        search.tap()
        search.typeText("salad\n")
        let typedOutcome = waitForSearchOutcome(resultsTitle: "Results for", timeout: 20)
        expectStillRunning("typing a search")
        snap("P03 Typed search (\(typedOutcome))")

        // The full map and back to the list.
        let mapSegment = app.segmentedControls.buttons["Map"]
        XCTAssertTrue(mapSegment.waitForExistence(timeout: 5), "No List/Map switch")
        mapSegment.tap()
        XCTAssertTrue(wait(for: app.buttons["Show full map"], toMatch: "exists == false", timeout: 5), "The full map didn't open")
        // With results the map says to tap a pin; it may offer "Search this area".
        _ = waitForAny([element(labeled: "Tap a pin to see that place's menu"), app.buttons["Search this area"]], timeout: 5)
        expectStillRunning("showing the full map")
        snap("P04 Full map")
        app.segmentedControls.buttons["List"].tap()
        XCTAssertTrue(app.buttons["Show full map"].waitForExistence(timeout: 5), "Didn't go back to the list")
        expectStillRunning("going back to the list")
        snap("P05 Back to the list")
    }

    // MARK: A place's menu

    func testPlaceMenuPicksFilterSortAndLog() throws {
        launch()
        openEatNearby()

        let salads = app.buttons["Salads"]
        XCTAssertTrue(salads.waitForExistence(timeout: 5), "No \"Salads\" shortcut")
        salads.tap()
        var outcome = waitForSearchOutcome(resultsTitle: "Salads nearby", timeout: 25)
        if outcome != "results" {
            // Try a typed search before giving up.
            let search = app.searchFields.firstMatch
            if search.waitForExistence(timeout: 5) {
                search.tap()
                search.typeText("salad\n")
                outcome = waitForSearchOutcome(resultsTitle: "Results for", timeout: 25)
            }
        }
        expectStillRunning("searching for salads")
        snap("P06 Salad places (\(outcome))")

        guard outcome == "results", let place = firstResultRow() else {
            throw XCTSkip("Apple Maps returned no places (\(outcome)); the menu steps need a search result.")
        }

        // Open the place: its menu loads (sample menu after about 2 s).
        scrollToElement(place)
        place.tap()
        if element(containing: "reading this place").waitForExistence(timeout: 3) {
            snap("P07 Menu loading")
        }
        let picks = element(labeled: "Best picks for you")
        XCTAssertTrue(picks.waitForExistence(timeout: 20), "The menu never loaded")
        expectStillRunning("loading the menu")
        expectVisible(containing: "Chicken Power Bowl")
        snap("P08 Best picks")

        // A filter chip: "High protein" keeps the 4 dishes with 30 g or more.
        let highProtein = app.buttons["High protein"]
        XCTAssertTrue(highProtein.waitForExistence(timeout: 5), "No \"High protein\" filter")
        scrollToElement(highProtein)
        expectVisible("6 dishes")
        highProtein.tap()
        expectVisible("4 dishes")
        XCTAssertTrue(highProtein.isSelected, "The High protein chip doesn't show as selected")
        expectStillRunning("filtering the menu")
        snap("P09 High protein filter")

        // The sort menu.
        let sortPicker = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label == %@ OR value == %@", "Sort by", "Healthiest", "Healthiest"
        )).firstMatch
        XCTAssertTrue(sortPicker.waitForExistence(timeout: 5), "No sort menu")
        scrollToElement(sortPicker)
        sortPicker.tap()
        let mostProtein = app.buttons["Most protein"]
        XCTAssertTrue(mostProtein.waitForExistence(timeout: 5), "The sort menu didn't open")
        snap("P10 Sort options")
        mostProtein.tap()
        expectVisible("Sorted by most protein")
        expectStillRunning("sorting the menu")
        snap("P11 Sorted by most protein")

        // A dish sheet, with 1.5 servings, logged. The last match is the row in
        // the sorted list (the best picks card above may list the dish too).
        let dishes = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Chicken Power Bowl"))
        XCTAssertTrue(dishes.firstMatch.waitForExistence(timeout: 5))
        let dish = dishes.element(boundBy: max(dishes.count - 1, 0))
        scrollToElement(dish)
        dish.tap()
        let dishBar = app.navigationBars["Dish"]
        XCTAssertTrue(dishBar.waitForExistence(timeout: 8), "The dish sheet didn't open")
        expectVisible("Chicken Power Bowl")
        expectStillRunning("opening a dish")
        snap("P12 Dish sheet")

        // Pull the sheet up to its large size to reach the servings stepper.
        dishBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        let stepper = app.steppers.firstMatch
        if stepper.waitForExistence(timeout: 3) {
            scrollToElement(stepper, maxSwipes: 2)
            stepper.buttons["Increment"].tap()
            expectVisible(containing: "1.5 servings")
            snap("P13 Dish, 1.5 servings")
        }

        dishBar.buttons["Log it"].tap()
        // The confirmation only shows for 2.5 s, so look for it first.
        XCTAssertTrue(element(containing: "Logged Chicken Power Bowl").waitForExistence(timeout: 4), "No \"Logged…\" confirmation")
        XCTAssertTrue(waitUntilGone(dishBar), "The dish sheet didn't close after Log it")
        expectStillRunning("logging a dish")
        snap("P14 Dish logged")

        // The dish is in today's food log, from the menu.
        goBack()
        XCTAssertTrue(app.navigationBars["Eat nearby"].waitForExistence(timeout: 8), "Didn't go back to Eat nearby")
        goBack()
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 8), "Didn't go back to Health")
        let foodLog = app.buttons.matching(identifier: "Food log").firstMatch
        scrollToElement(foodLog)
        foodLog.tap()
        XCTAssertTrue(app.navigationBars["Food log"].waitForExistence(timeout: 8))
        let row = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "Chicken Power Bowl", "Menu"
        )).firstMatch
        scrollToElement(row)
        XCTAssertTrue(row.exists, "The logged dish isn't in the food log")
        expectStillRunning("opening the food log")
        snap("P15 Food log with the dish")
    }

    // MARK: Navigation

    private func openEatNearby(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared", file: file, line: line)
        openTab("Health", file: file, line: line)
        let tile = app.buttons["Eat nearby"]
        XCTAssertTrue(tile.waitForExistence(timeout: 10), "No \"Eat nearby\" tile", file: file, line: line)
        tile.tap()
        XCTAssertTrue(app.navigationBars["Eat nearby"].waitForExistence(timeout: 10), "Eat nearby didn't open", file: file, line: line)
        // A harmless tap, so the interruption monitor answers a location prompt if one is up.
        let listSegment = app.segmentedControls.buttons["List"]
        if listSegment.waitForExistence(timeout: 5) {
            listSegment.tap()
        }
        expectStillRunning("opening Eat nearby", file: file, line: line)
    }

    // MARK: Search results

    /// "results" once places for `resultsTitle` show (a title or its start),
    /// "no places", "search failed", or "timed out".
    private func waitForSearchOutcome(resultsTitle: String, timeout: TimeInterval) -> String {
        let title = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", resultsTitle)).firstMatch
        let noPlaces = element(labeled: "No places found")
        let failed = element(containing: "search right now")
        guard let found = waitForAny([title, noPlaces, failed], timeout: timeout) else { return "timed out" }
        if found == title { return "results" }
        if found == noPlaces { return "no places" }
        return "search failed"
    }

    /// The first place in the results list. Rows read "Name, Restaurant · 0.3 mi,
    /// address"; failing that, the first button below the "N places" line.
    private func firstResultRow() -> XCUIElement? {
        let countPattern = "^[0-9]+ places?( \u{00B7} nearest first)?$"
        let countText = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", countPattern)).firstMatch
        guard countText.waitForExistence(timeout: 5) else { return nil }
        let list = app.scrollViews.containing(NSPredicate(format: "label MATCHES %@", countPattern)).firstMatch
        let scope = list.exists ? list : app
        let typical = scope.buttons.matching(NSPredicate(format: "label CONTAINS %@", " \u{00B7} ")).firstMatch
        if typical.exists, typical.frame.minY >= countText.frame.minY {
            return typical
        }
        let bottom = countText.frame.maxY
        return scope.buttons.allElementsBoundByIndex.first { button in
            !button.label.isEmpty && button.frame.minY >= bottom - 1
        }
    }

    // MARK: Queries

    private func element(labeled label: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func waitForAny(_ elements: [XCUIElement], timeout: TimeInterval) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if let found = elements.first(where: { $0.exists }) { return found }
            _ = elements.first?.waitForExistence(timeout: 0.5)
        } while Date() < deadline
        return elements.first(where: { $0.exists })
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

    /// Swipes up until `element` exists and can be tapped.
    @discardableResult
    private func scrollToElement(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists && element.isHittable
    }
}
