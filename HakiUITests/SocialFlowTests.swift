//
//  SocialFlowTests.swift
//  HakiUITests
//
//  Walks through the social and investing screens like a person would: the
//  Feed (Following / Explore, liking, a post's detail and comments, a ticker
//  feed, Activity), composing a post, finding people, the Invest tab and your
//  own profile. Every step checks the screen appeared and the app is still
//  running, and saves a screenshot ("S01 Feed following"...).
//
//  Relies on the preview services `-HakiUITesting` uses (SocialPreviewData in
//  Haki/Services/SocialService.swift, PortfolioPreviewSamples in
//  PortfolioService.swift): signed in as @maya.invests, following Dan and
//  Priya, with a VTI holding and Sam Rivera (@sam_saves) to find.
//

import XCTest

final class SocialFlowTests: HakiUITestCase {
    /// The signed-in sample user (`SocialPreviewData.signedInProfile`).
    private var myUsername: String { "maya.invests" }

    // MARK: Feed

    func test01FeedScopesAndLike() throws {
        launch()
        guard openFeed() else { return }

        // The scope is remembered between launches, so pick Following first.
        tapElement(app.segmentedControls.buttons["Following"], "the Following segment")
        XCTAssertTrue(button("Comments").waitForExistence(timeout: 10), "No posts in Following")
        expectStillRunning("showing Following")
        snap("S01 Feed following")

        if tapElement(app.segmentedControls.buttons["Explore"], "the Explore segment") {
            XCTAssertTrue(button("Comments").waitForExistence(timeout: 10), "No posts in Explore")
            expectStillRunning("showing Explore")
            snap("S02 Feed explore")
            tapElement(app.segmentedControls.buttons["Following"], "the Following segment")
        }

        // Like the first post that isn't liked yet: its button turns into "Unlike".
        let like = button("Like")
        if like.waitForExistence(timeout: 8) {
            scrollTo(like)
            let unlikes = app.buttons.matching(NSPredicate(format: "label == %@", "Unlike"))
            let before = unlikes.count
            like.tap()
            XCTAssertTrue(waitUntil(timeout: 5) { unlikes.count > before }, "Liking a post didn't turn its button into Unlike")
        } else {
            XCTFail("No post to like in the feed")
        }
        expectStillRunning("liking a post")
        snap("S03 Feed post liked")
    }

    func test02PostDetailCommentTickerAndActivity() throws {
        launch()
        guard openFeed() else { return }
        tapElement(app.segmentedControls.buttons["Following"], "the Following segment")

        // A post's detail, with a new comment.
        if tapElement(button("Comments"), "a post's Comments button", timeout: 10) {
            expectScreen("Post")
            let addComment = button("Add a comment")
            XCTAssertTrue(addComment.waitForExistence(timeout: 8), "The post detail has no comment button")
            expectStillRunning("opening a post")
            snap("S04 Post detail")

            let comment = "Great call, from the UI tests"
            if tapElement(addComment, "Add a comment") {
                _ = app.keyboards.firstMatch.waitForExistence(timeout: 5)
                app.typeText(comment)
                tapElement(button("Send comment"), "Send comment")
                expectVisible(containing: comment)
                expectStillRunning("sending a comment")
                snap("S05 Post comment sent")
            }
            goBack(from: "Post")
            expectScreen("Feed")
        }

        // A trade's "Bought $KO" badge opens that ticker's feed ("$KO").
        let trade = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Bought $", "Sold $")).firstMatch
        if trade.waitForExistence(timeout: 8) {
            let cashtag = "$" + (trade.label.components(separatedBy: "$").last ?? "")
            if tapElement(trade, "a trade badge") {
                expectScreen(cashtag)
                expectStillRunning("opening the \(cashtag) feed")
                snap("S06 Ticker feed")
                goBack(from: cashtag)
                expectScreen("Feed")
            }
        } else {
            XCTFail("No trade post in the feed")
        }

        // Activity (likes, comments and follows on your posts).
        if tapElement(button("Activity"), "the Activity button in the Feed toolbar") {
            expectScreen("Activity")
            expectStillRunning("opening Activity")
            snap("S07 Activity")
            goBack(from: "Activity")
            expectScreen("Feed")
        }
    }

    // MARK: Compose

    func test03ComposeScreen() throws {
        launch()
        guard openFeed() else { return }

        guard tapElement(button("New post"), "the New post button in the Feed toolbar") else { return }
        let shown = expectScreen("New post")
        expectStillRunning("opening New post")
        snap("S08 Compose post")
        guard shown else { return }

        if tapElement(app.segmentedControls.buttons["Trade"], "the Trade segment") {
            XCTAssertTrue(app.textFields["Ticker"].waitForExistence(timeout: 5), "The trade form has no ticker field")
            expectStillRunning("switching to a trade post")
            snap("S09 Compose trade")
        }
        if tapElement(app.segmentedControls.buttons["Portfolio"], "the Portfolio segment") {
            expectVisible("Show how your portfolio is split, in percentages.")
            expectStillRunning("switching to a portfolio post")
            snap("S10 Compose portfolio")
        }

        // Nothing written, so Cancel closes without asking.
        tapElement(barButton("Cancel", in: "New post"), "Cancel in New post")
        XCTAssertTrue(waitUntil(timeout: 5) { !app.navigationBars["New post"].exists }, "New post didn't close after Cancel")
        expectScreen("Feed")
        expectStillRunning("cancelling a post")
    }

    // MARK: People

    func test04PeopleSearchAndFollow() throws {
        launch()
        guard openFeed() else { return }

        guard tapElement(button("Search people"), "the Search people button in the Feed toolbar") else { return }
        let shown = expectScreen("Find people")
        expectVisible("Suggested for you")
        expectStillRunning("opening Find people")
        snap("S11 Find people")
        guard shown else { return }

        let search = app.searchFields.firstMatch
        guard tapElement(search, "the people search field") else { return }
        search.typeText("Sam")
        expectVisible("People")
        let sam = control("label BEGINSWITH %@", "Sam Rivera")
        XCTAssertTrue(sam.exists, "Searching \"Sam\" didn't find Sam Rivera")
        expectStillRunning("searching people")
        snap("S12 People search results")

        if tapElement(sam, "Sam Rivera's row") {
            expectScreen("sam_saves")
            expectStillRunning("opening someone's profile")
            snap("S13 Other profile")

            if tapElement(button("Follow Sam Rivera"), "Follow on Sam's profile") {
                XCTAssertTrue(button("Following Sam Rivera").waitForExistence(timeout: 5), "Following Sam didn't update the button")
                expectStillRunning("following someone")
                snap("S14 Other profile followed")
            }
            goBack(from: "sam_saves")
            expectScreen("Find people")
        }
    }

    // MARK: Invest

    func test05InvestPortfolioAndHolding() throws {
        launch()
        openTab("Invest")
        let shown = expectScreen("Invest")
        let vti = button("VTI, Vanguard Total Stock Market ETF")
        XCTAssertTrue(vti.waitForExistence(timeout: 10), "The sample VTI position isn't listed")
        expectStillRunning("opening Invest")
        snap("S15 Invest")
        guard shown else { return }

        app.swipeUp()
        expectStillRunning("scrolling Invest")
        snap("S16 Invest scrolled")

        if tapElement(vti, "the VTI position") {
            expectScreen("VTI")
            expectStillRunning("opening a holding")
            snap("S17 Holding detail")
            goBack(from: "VTI")
            expectScreen("Invest")
        }

        if tapElement(button("See all investment activity"), "See all investment activity") {
            expectScreen("Investment activity")
            expectStillRunning("opening investment activity")
            snap("S18 Investment activity")
            goBack(from: "Investment activity")
            expectScreen("Invest")
        }

        // Sharing the portfolio opens the composer with a portfolio post.
        if tapElement(button("Share my portfolio"), "Share my portfolio in the Invest toolbar") {
            expectScreen("New post")
            expectStillRunning("sharing the portfolio")
            snap("S19 Share portfolio")
            tapElement(barButton("Cancel", in: "New post"), "Cancel in New post")
            XCTAssertTrue(waitUntil(timeout: 5) { !app.navigationBars["New post"].exists }, "New post didn't close after Cancel")
            expectScreen("Invest")
        }
    }

    // MARK: Profile

    func test06OwnProfile() throws {
        launch()
        openTab("Profile")
        let shown = expectScreen(myUsername)
        expectStillRunning("opening Profile")
        snap("S20 Profile")
        guard shown else { return }

        // The header's counts open the follower lists ("128 followers", "2 following").
        if tapElement(control("label ENDSWITH %@", " followers"), "the followers count") {
            expectScreen("Followers")
            expectStillRunning("opening followers")
            snap("S21 Followers")
            goBack(from: "Followers")
            expectScreen(myUsername)
        }
        if tapElement(control("label ENDSWITH %@", " following"), "the following count") {
            expectScreen("Following")
            expectStillRunning("opening following")
            snap("S22 Following")
            goBack(from: "Following")
            expectScreen(myUsername)
        }

        // Edit profile, then cancel without changes.
        if tapElement(button("Edit profile"), "the Edit profile button") {
            expectScreen("Edit profile")
            XCTAssertTrue(app.textFields["Display name"].waitForExistence(timeout: 8), "Edit profile has no Display name field")
            expectStillRunning("opening Edit profile")
            snap("S23 Edit profile")
            tapElement(barButton("Cancel", in: "Edit profile"), "Cancel in Edit profile")
            XCTAssertTrue(waitUntil(timeout: 5) { !app.navigationBars["Edit profile"].exists }, "Edit profile didn't close after Cancel")
            expectScreen(myUsername)
        }

        // The shared portfolio, as percentages.
        if tapElement(app.segmentedControls.buttons["Portfolio"], "the Portfolio segment") {
            expectVisible(containing: "Percentages only")
            expectStillRunning("showing my portfolio")
            snap("S24 Profile portfolio")
            tapElement(app.segmentedControls.buttons["Posts"], "the Posts segment")
        }

        // One of my posts from the grid.
        let tile = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@ OR label BEGINSWITH %@",
            "Portfolio post", "Post, ", "Photo post", "Bought ", "Sold "
        )).firstMatch
        if tapElement(tile, "a post in my profile grid") {
            expectScreen("Post")
            expectStillRunning("opening my post")
            snap("S25 Own post detail")
            goBack(from: "Post")
            expectScreen(myUsername)
        }
    }

    // MARK: - Helpers

    /// Opens the Feed tab and waits for it.
    private func openFeed(file: StaticString = #filePath, line: UInt = #line) -> Bool {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared (signed-in sample user)", file: file, line: line)
        openTab("Feed", file: file, line: line)
        return expectScreen("Feed", file: file, line: line)
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

    /// The first button whose accessibility label is exactly `label`.
    private func button(_ label: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// The first button (or, failing that, list cell) whose label matches
    /// `format` (one `%@`, filled with `text`). Waits for it to appear.
    private func control(_ format: String, _ text: String, timeout: TimeInterval = 8) -> XCUIElement {
        let predicate = NSPredicate(format: format, text)
        let match = app.buttons.matching(predicate).firstMatch
        if match.waitForExistence(timeout: timeout) { return match }
        let cell = app.cells.matching(predicate).firstMatch
        return cell.exists ? cell : match
    }

    /// A button in the navigation bar titled `title`, else anywhere on screen.
    private func barButton(_ label: String, in title: String) -> XCUIElement {
        let inBar = app.navigationBars[title].buttons[label]
        return inBar.exists ? inBar : app.buttons[label].firstMatch
    }

    /// Swipes up until `element` can be tapped, at most `maxSwipes` times.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            app.swipeUp()
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
