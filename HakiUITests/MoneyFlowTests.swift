//
//  MoneyFlowTests.swift
//  HakiUITests
//
//  Walks through the money screens like a person would: the Home dashboard,
//  Transactions (detail, search, adding one by hand), Budgets, Recurring,
//  Accounts and the Settings sheet. Every step checks the screen appeared and
//  the app is still running, and saves a screenshot ("M01 Home"...).
//
//  Relies on the sample data `-HakiUITesting` loads (Haki/Core/SampleLedger.swift):
//  a monthly Netflix charge and bill, the "Everyday Checking" account and a
//  suggested Groceries budget.
//

import XCTest

final class MoneyFlowTests: HakiUITestCase {

    // MARK: Home

    func test01HomeDashboard() throws {
        launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)")
        expectScreen("Home")
        for title in ["Transactions", "Budgets", "Recurring", "Accounts"] {
            expectVisible("Open \(title)")
        }
        expectVisible("Settings")
        expectStillRunning("opening Home")
        snap("M01 Home")

        app.swipeUp()
        expectStillRunning("scrolling Home")
        snap("M02 Home scrolled")
    }

    // MARK: Transactions

    func test02TransactionsDetailAndSearch() throws {
        launch()
        guard openHomeShortcut("Transactions") else { return }
        let shown = expectScreen("Transactions")
        // Rows read "Merchant, Category · Account, $amount"; the review prompt above them has no "·".
        let firstRow = control("label CONTAINS %@", " · ")
        XCTAssertTrue(firstRow.exists, "No transactions listed")
        expectStillRunning("opening Transactions")
        snap("M03 Transactions")
        guard shown else { return }

        // A transaction's detail, then back.
        if tapElement(firstRow, "the first transaction") {
            expectScreen("Transaction")
            expectStillRunning("opening a transaction")
            snap("M04 Transaction detail")
            goBack(from: "Transaction")
            expectScreen("Transactions")
        }

        // Search for a merchant from the sample data (charged every month).
        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) || !search.isHittable {
            app.swipeDown()
        }
        guard tapElement(search, "the transactions search field") else { return }
        search.typeText("Netflix")
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", " · "))
        let others = rows.matching(NSPredicate(format: "NOT (label CONTAINS[c] %@)", "Netflix"))
        let filtered = waitUntil(timeout: 8) { rows.count > 0 && others.count == 0 }
        XCTAssertTrue(filtered, "Searching \"Netflix\" didn't narrow the list to Netflix transactions")
        expectStillRunning("searching transactions")
        snap("M05 Transactions search Netflix")

        let result = control("label CONTAINS[c] %@", "Netflix")
        if tapElement(result, "a Netflix search result") {
            expectScreen("Transaction")
            expectVisible("Netflix")
            expectStillRunning("opening a search result")
            snap("M06 Netflix transaction detail")
            goBack(from: "Transaction")
            expectScreen("Transactions")
        }
    }

    func test03AddManualTransaction() throws {
        launch()
        guard openHomeShortcut("Transactions"), expectScreen("Transactions") else { return }

        guard tapElement(app.buttons["Add transaction"], "the Add transaction (+) button in the Transactions toolbar") else { return }
        let editorShown = expectScreen("New Expense")
        expectStillRunning("opening New Expense")
        snap("M07 New expense")
        guard editorShown else { return }

        let amount = app.textFields["Amount"]
        if tapElement(amount, "the amount field") {
            amount.typeText("12.34")
        }
        let merchantName = "Haki Test Kitchen"
        let merchant = textField("Where did you spend it?")
        if tapElement(merchant, "the merchant field") {
            merchant.typeText(merchantName)
        }
        expectVisible(containing: "12.34 going out")
        snap("M08 New expense filled in")

        guard tapElement(barButton("Save", in: "New Expense"), "the Save button") else { return }
        XCTAssertTrue(waitUntil(timeout: 5) { !app.navigationBars["New Expense"].exists }, "The New Expense sheet didn't close after Save")
        expectScreen("Transactions")
        let added = control("label CONTAINS %@", merchantName)
        XCTAssertTrue(added.exists, "The new transaction isn't in the list")
        expectStillRunning("saving a transaction")
        snap("M09 Transactions with new expense")
    }

    // MARK: Budgets

    func test04Budgets() throws {
        launch()
        guard openHomeShortcut("Budgets") else { return }
        let shown = expectScreen("Budgets")
        expectStillRunning("opening Budgets")
        snap("M10 Budgets")
        guard shown else { return }

        // Last month, then back to this one.
        if tapElement(app.buttons["Previous month"], "the Previous month button") {
            expectStillRunning("showing last month's budgets")
            snap("M11 Budgets last month")
            tapElement(app.buttons["Next month"], "the Next month button")
        }

        // A category's detail (Groceries gets a suggested budget with the sample data).
        let groceries = control("label BEGINSWITH %@", "Groceries")
        if tapElement(groceries, "the Groceries budget") {
            expectScreen("Groceries")
            expectStillRunning("opening a budget category")
            snap("M12 Groceries category")
            goBack(from: "Groceries")
            expectScreen("Budgets")
        }
    }

    // MARK: Recurring

    func test05Recurring() throws {
        launch()
        guard openHomeShortcut("Recurring") else { return }
        let shown = expectScreen("Recurring")
        expectVisible(containing: "Monthly recurring")
        expectStillRunning("opening Recurring")
        snap("M13 Recurring")
        guard shown else { return }

        // A tracked bill opens its editor; cancel without changes.
        let netflix = control("label CONTAINS %@", "Netflix")
        if tapElement(netflix, "the Netflix bill") {
            expectScreen("Edit Bill")
            expectStillRunning("opening a bill")
            snap("M14 Edit bill")
            tapElement(barButton("Cancel", in: "Edit Bill"), "Cancel in Edit Bill")
            XCTAssertTrue(waitUntil(timeout: 5) { !app.navigationBars["Edit Bill"].exists }, "Edit Bill didn't close")
            expectScreen("Recurring")
        }

        app.swipeUp()
        expectStillRunning("scrolling Recurring")
        snap("M15 Recurring scrolled")
    }

    // MARK: Accounts

    func test06Accounts() throws {
        launch()
        guard openHomeShortcut("Accounts") else { return }
        let shown = expectScreen("Accounts")
        expectStillRunning("opening Accounts")
        snap("M16 Accounts")
        guard shown else { return }

        // Rows read "Everyday Checking, Checking, Harborline Bank, Balance ...".
        let checking = control("label BEGINSWITH %@", "Everyday Checking,")
        if tapElement(checking, "the Everyday Checking account") {
            expectScreen("Everyday Checking")
            expectStillRunning("opening an account")
            snap("M17 Account detail")
            app.swipeUp()
            expectStillRunning("scrolling an account")
            snap("M18 Account detail scrolled")
            goBack(from: "Everyday Checking")
            expectScreen("Accounts")
        }
    }

    // MARK: Settings

    func test07SettingsSheet() throws {
        launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)")
        expectScreen("Home")

        guard tapElement(app.buttons["Settings"].firstMatch, "the Settings button on Home") else { return }
        let shown = expectScreen("Settings")
        expectStillRunning("opening Settings")
        snap("M19 Settings")
        guard shown else { return }

        // Settings opens on the profile, Account, Privacy and Delete account
        // sections; Categories (under Organize) is further down, and the list
        // only creates rows as they scroll on screen, so scroll to it first.
        let categories = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Categories")).firstMatch
        scrollTo(categories)
        if tapElement(categories, "Categories in Settings") {
            expectScreen("Categories")
            expectStillRunning("opening Categories")
            snap("M20 Settings categories")
            goBack(from: "Categories")
            expectScreen("Settings")
        }

        tapElement(barButton("Done", in: "Settings"), "Done in Settings")
        XCTAssertTrue(waitUntil(timeout: 5) { !app.navigationBars["Settings"].exists }, "The Settings sheet didn't close")
        expectScreen("Home")
        expectStillRunning("closing Settings")
        snap("M21 Home after Settings")
    }

    // MARK: - Helpers

    /// Opens one of Home's shortcut tiles ("Open Transactions", ...).
    private func openHomeShortcut(_ title: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)", file: file, line: line)
        expectScreen("Home", file: file, line: line)
        return tapElement(app.buttons["Open \(title)"], "the \(title) shortcut on Home", file: file, line: line)
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

    /// The first button (or, failing that, list cell) whose label matches
    /// `format` (one `%@`, filled with `text`). Waits for it to appear.
    private func control(_ format: String, _ text: String, timeout: TimeInterval = 8) -> XCUIElement {
        let predicate = NSPredicate(format: format, text)
        let button = app.buttons.matching(predicate).firstMatch
        if button.waitForExistence(timeout: timeout) { return button }
        let cell = app.cells.matching(predicate).firstMatch
        return cell.exists ? cell : button
    }

    /// A text field by its label or placeholder.
    private func textField(_ text: String) -> XCUIElement {
        app.textFields.matching(NSPredicate(format: "label == %@ OR placeholderValue == %@", text, text)).firstMatch
    }

    /// A button in the navigation bar titled `title`, else anywhere on screen.
    private func barButton(_ label: String, in title: String) -> XCUIElement {
        let inBar = app.navigationBars[title].buttons[label]
        return inBar.exists ? inBar : app.buttons[label].firstMatch
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
