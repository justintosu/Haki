//
//  WorkoutFlowTests.swift
//  HakiUITests
//
//  Workouts and Hevy from the Health tab: the Workouts screen, logging an
//  empty workout (exercise picker, a set, the rest timer, finishing), a
//  workout from the "Push day" routine (exercise history, minimize and
//  resume), a past workout's detail, the exercise library, the routine
//  editor and the Hevy settings (preview service: connected, no network).
//  Sample data: five finished workouts, the latest "Push day" yesterday.
//

import XCTest

final class WorkoutFlowTests: HakiUITestCase {
    // MARK: Workouts screen

    func testWorkoutsScreen() throws {
        launch()
        openWorkouts()
        XCTAssertTrue(app.buttons["Start workout"].exists, "No Start workout button")
        XCTAssertTrue(routineRow("Push day").waitForExistence(timeout: 5), "No Push day routine")
        snap("W01 Workouts")

        let exercises = app.buttons.matching(identifier: "Exercises").firstMatch
        scrollToElement(exercises)
        XCTAssertTrue(exercises.exists, "No link to the exercise library")
        expectStillRunning("scrolling Workouts")
        snap("W02 Workouts, library and progress")

        let history = historyRow(title: "Push day", containing: "Bench Press")
        scrollToElement(history, maxSwipes: 8)
        XCTAssertTrue(history.exists, "No Push day in the history")
        expectStillRunning("scrolling to the history")
        snap("W03 Workouts, history")

        // The Hevy row in "Library and sync".
        let hevy = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hevy")).firstMatch
        scrollToElement(hevy, upward: true)
        XCTAssertTrue(hevy.exists, "No Hevy row on Workouts")
        hevy.tap()
        XCTAssertTrue(app.navigationBars["Hevy"].waitForExistence(timeout: 8), "The Hevy row didn't open Hevy settings")
        expectStillRunning("opening Hevy from Workouts")
        snap("W04 Hevy from Workouts")
        goBack()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 8))
    }

    // MARK: An empty workout

    func testLogEmptyWorkoutWithBenchPress() throws {
        launch()
        openWorkouts()

        app.buttons["Start workout"].tap()
        let empty = app.buttons["Empty workout"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "The start menu didn't open")
        snap("W05 Start menu")
        empty.tap()
        let nameField = app.textFields["Workout name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "The workout didn't open")
        expectStillRunning("starting an empty workout")
        snap("W06 Empty workout")

        // Add Bench Press (Dumbbell): no history, so one empty set.
        addExercise(search: "bench", named: "Bench Press (Dumbbell)", screenshot: "W07 Exercise picker, bench")
        expectVisible(containing: "Bench Press (Dumbbell)")

        let weight = app.textFields.matching(NSPredicate(format: "label BEGINSWITH %@", "Set 1 weight")).firstMatch
        XCTAssertTrue(weight.waitForExistence(timeout: 8), "No weight field for set 1")
        scrollToElement(weight, maxSwipes: 3)
        weight.tap()
        weight.typeText("50")
        let reps = app.textFields["Set 1 reps"]
        XCTAssertTrue(reps.exists, "No reps field for set 1")
        reps.tap()
        reps.typeText("10")
        dismissKeyboard()
        XCTAssertEqual(weight.value as? String, "50")
        XCTAssertEqual(reps.value as? String, "10")
        expectStillRunning("entering a set")
        snap("W08 Set entered")

        // Tick the set: the rest timer starts.
        let notDone = setCheckButton("Set 1", done: false)
        XCTAssertTrue(notDone.waitForExistence(timeout: 5), "No done button for set 1")
        notDone.tap()
        let skipRest = app.buttons["Skip rest"]
        XCTAssertTrue(skipRest.waitForExistence(timeout: 5), "The rest timer didn't appear")
        expectVisible("Rest timer")
        XCTAssertTrue(setCheckButton("Set 1", done: true).exists, "Set 1 isn't marked done")
        expectStillRunning("ticking a set")
        snap("W09 Set done, rest timer")
        skipRest.tap()
        XCTAssertTrue(waitUntilGone(skipRest, timeout: 5), "Skip didn't stop the rest timer")

        // Finish: confirmation, then the summary.
        finishWorkout(confirmation: "W10 Finish confirmation", summary: "W11 Workout saved")
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 8), "Didn't return to Workouts")
        let logged = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ AND label CONTAINS %@", "Today", "Bench Press (Dumbbell)"
        )).firstMatch
        scrollToElement(logged, maxSwipes: 8)
        XCTAssertTrue(logged.exists, "The finished workout isn't in the history")
        expectStillRunning("returning to Workouts")
        snap("W12 History with the new workout")
    }

    // MARK: A workout from a routine

    func testRoutineWorkoutHistoryMinimizeAndFinish() throws {
        launch()
        openWorkouts()

        app.buttons["Start workout"].tap()
        let pushDay = app.buttons.matching(NSPredicate(format: "label == %@", "Push day")).firstMatch
        XCTAssertTrue(pushDay.waitForExistence(timeout: 5), "The start menu has no Push day routine")
        pushDay.tap()
        let nameField = app.textFields["Workout name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10), "The routine workout didn't open")
        XCTAssertEqual(nameField.value as? String, "Push day")
        expectVisible(containing: "Bench Press (Barbell)")
        expectStillRunning("starting Push day")
        snap("W13 Push day workout")

        // The exercise's history, pushed inside the workout.
        let exerciseHeader = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bench Press (Barbell)")).firstMatch
        XCTAssertTrue(exerciseHeader.waitForExistence(timeout: 5))
        exerciseHeader.tap()
        XCTAssertTrue(app.navigationBars["Bench Press (Barbell)"].waitForExistence(timeout: 8), "The exercise history didn't open")
        expectVisible("Personal records")
        expectStillRunning("opening an exercise's history from a workout")
        snap("W14 Exercise history from the workout")
        goBack()
        XCTAssertTrue(nameField.waitForExistence(timeout: 8), "Didn't go back to the workout")

        // Set 1 is filled in from last time; tick it.
        let notDone = setCheckButton("Set 1", done: false)
        XCTAssertTrue(notDone.waitForExistence(timeout: 5))
        notDone.tap()
        XCTAssertTrue(app.buttons["Skip rest"].waitForExistence(timeout: 5), "The rest timer didn't appear")
        expectStillRunning("ticking a routine set")
        snap("W15 Routine set done")

        // Minimize, then resume from Workouts.
        app.buttons["Minimize"].tap()
        let resume = app.buttons["Resume Push day"]
        XCTAssertTrue(resume.waitForExistence(timeout: 8), "No resume banner after minimizing")
        expectStillRunning("minimizing the workout")
        snap("W16 Workout minimized")
        resume.tap()
        XCTAssertTrue(nameField.waitForExistence(timeout: 8), "Resume didn't reopen the workout")

        finishWorkout(confirmation: "W17 Finish routine workout", summary: "W18 Routine workout saved")
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 8), "Didn't return to Workouts")
        XCTAssertTrue(app.buttons["Start workout"].waitForExistence(timeout: 5), "Still shows a workout in progress")
    }

    // MARK: A past workout

    func testPastWorkoutDetailAndExerciseHistory() throws {
        launch()
        openWorkouts()

        let row = historyRow(title: "Push day", containing: "Bench Press")
        scrollToElement(row, maxSwipes: 8)
        XCTAssertTrue(row.exists, "No Push day in the history")
        row.tap()
        XCTAssertTrue(app.navigationBars["Push day"].waitForExistence(timeout: 8), "The workout's detail didn't open")
        expectVisible("Duration")
        expectVisible("Volume")
        XCTAssertTrue(app.buttons["Workout options"].exists, "No workout options menu")
        expectStillRunning("opening a past workout")
        snap("W19 Workout detail")

        let header = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bench Press (Barbell)")).firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "No Bench Press card")
        scrollToElement(header, maxSwipes: 3)
        header.tap()
        XCTAssertTrue(app.navigationBars["Bench Press (Barbell)"].waitForExistence(timeout: 8), "The exercise history didn't open")
        expectVisible("Personal records")
        expectStillRunning("opening an exercise's history")
        snap("W20 Exercise history")
        app.swipeUp()
        expectVisible("Sessions")
        snap("W21 Exercise history, sessions")
        goBack()
        XCTAssertTrue(app.navigationBars["Push day"].waitForExistence(timeout: 8))
    }

    // MARK: The exercise library

    func testExerciseLibrary() throws {
        launch()
        openWorkouts()

        let exercises = app.buttons.matching(identifier: "Exercises").firstMatch
        scrollToElement(exercises)
        exercises.tap()
        XCTAssertTrue(app.navigationBars["Exercises"].waitForExistence(timeout: 8), "The exercise library didn't open")
        expectStillRunning("opening the exercise library")
        snap("W22 Exercise library")

        let chest = app.buttons["Chest"]
        if chest.waitForExistence(timeout: 3) {
            chest.tap()
            XCTAssertTrue(wait(for: chest, toMatch: "isSelected == true", timeout: 3), "The Chest chip didn't turn on")
            snap("W23 Chest exercises")
            app.buttons["All"].tap()
        }

        let search = app.searchFields.firstMatch
        if !search.waitForExistence(timeout: 3) {
            app.swipeDown()
        }
        XCTAssertTrue(search.waitForExistence(timeout: 3), "No exercise search field")
        search.tap()
        search.typeText("bench\n")
        let bench = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bench Press (Barbell)")).firstMatch
        XCTAssertTrue(bench.waitForExistence(timeout: 5), "Searching \"bench\" didn't find Bench Press (Barbell)")
        snap("W24 Exercise search")
        bench.tap()
        XCTAssertTrue(app.navigationBars["Bench Press (Barbell)"].waitForExistence(timeout: 8), "The exercise history didn't open")
        expectVisible("Personal records")
        expectStillRunning("opening an exercise from the library")
        snap("W25 Exercise from the library")
    }

    // MARK: Routines

    func testRoutineEditor() throws {
        launch()
        openWorkouts()

        // Edit "Push day": one more set of its first exercise.
        let pushDay = routineRow("Push day")
        XCTAssertTrue(pushDay.waitForExistence(timeout: 5), "No Push day routine")
        pushDay.tap()
        let edit = app.buttons["Edit routine"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "The routine's actions didn't show")
        snap("W26 Routine actions")
        edit.tap()
        let editBar = app.navigationBars["Edit routine"]
        XCTAssertTrue(editBar.waitForExistence(timeout: 8), "The routine editor didn't open")
        expectVisible(containing: "Bench Press (Barbell)")
        expectStillRunning("opening the routine editor")
        snap("W27 Routine editor")

        let setsStepper = app.steppers.firstMatch
        if setsStepper.waitForExistence(timeout: 3) {
            setsStepper.buttons["Increment"].tap()
            expectVisible("4 sets")
            snap("W28 Routine, 4 sets")
        }
        editBar.buttons["Done"].tap()
        XCTAssertTrue(waitUntilGone(editBar), "The routine editor didn't close")
        expectStillRunning("saving the routine")

        // A new routine with one exercise.
        app.buttons.matching(identifier: "New routine").firstMatch.tap()
        let newBar = app.navigationBars["New routine"]
        XCTAssertTrue(newBar.waitForExistence(timeout: 8), "The new routine editor didn't open")
        let name = app.textFields["Routine name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Leg day UI test")
        dismissKeyboard()
        snap("W29 New routine")
        // "squat barbell" lists Front Squat and Squat (Barbell), so the row sits
        // near the top. With "squat" it was 5th, under where the search keyboard
        // had just been, and that tap never reached it (the picker stayed open).
        addExercise(search: "squat barbell", named: "Squat (Barbell)", screenshot: "W30 Exercise picker, squat")
        expectVisible(containing: "Squat (Barbell)")
        snap("W31 New routine with an exercise")
        newBar.buttons["Save"].tap()
        XCTAssertTrue(waitUntilGone(newBar), "The new routine editor didn't close")
        XCTAssertTrue(routineRow("Leg day UI test").waitForExistence(timeout: 5), "The new routine isn't listed")
        expectStillRunning("saving a new routine")
        snap("W32 Routines with the new one")
    }

    // MARK: Hevy

    func testHevySettings() throws {
        launch()
        openHealth()

        let hevyRow = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Hevy")).firstMatch
        XCTAssertTrue(hevyRow.waitForExistence(timeout: 8), "No Hevy row on Health")
        scrollToElement(hevyRow)
        hevyRow.tap()
        XCTAssertTrue(app.navigationBars["Hevy"].waitForExistence(timeout: 8), "Hevy settings didn't open")
        expectVisible(containing: "Sync with Hevy")
        expectStillRunning("opening Hevy settings")
        snap("W33 Hevy settings")

        // The preview service is connected and syncs without the network.
        let syncNow = app.buttons["Sync now"]
        XCTAssertTrue(syncNow.waitForExistence(timeout: 5), "No Sync now (the preview should be connected)")
        syncNow.tap()
        XCTAssertTrue(syncNow.waitForExistence(timeout: 8), "Sync didn't finish")
        expectStillRunning("syncing with Hevy")
        snap("W34 Hevy synced")

        let postToggle = app.switches["Post workouts logged in Haki to Hevy"]
        scrollToElement(postToggle)
        XCTAssertTrue(postToggle.exists, "No posting toggle")
        XCTAssertTrue(app.buttons["Disconnect Hevy"].exists, "No Disconnect button")
        expectStillRunning("scrolling Hevy settings")
        snap("W35 Hevy settings, posting")
    }

    // MARK: Steps

    private func openHealth(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 20), "The tab bar never appeared", file: file, line: line)
        openTab("Health", file: file, line: line)
        XCTAssertTrue(app.navigationBars["Health"].waitForExistence(timeout: 10), "The Health tab didn't open", file: file, line: line)
    }

    private func openWorkouts(file: StaticString = #filePath, line: UInt = #line) {
        openHealth(file: file, line: line)
        let link = app.buttons.matching(identifier: "Workouts").firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10), "No Workouts link on Health", file: file, line: line)
        scrollToElement(link)
        link.tap()
        XCTAssertTrue(app.navigationBars["Workouts"].waitForExistence(timeout: 10), "Workouts didn't open", file: file, line: line)
        expectStillRunning("opening Workouts", file: file, line: line)
    }

    /// "Add exercise" → search → pick `named` in the exercise picker.
    private func addExercise(search text: String, named name: String, screenshot: String, file: StaticString = #filePath, line: UInt = #line) {
        let add = app.buttons.matching(identifier: "Add exercise").firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5), "No Add exercise button", file: file, line: line)
        scrollToElement(add, maxSwipes: 3)
        add.tap()
        let pickerBar = app.navigationBars["Add exercise"]
        XCTAssertTrue(pickerBar.waitForExistence(timeout: 8), "The exercise picker didn't open", file: file, line: line)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "No exercise search field", file: file, line: line)
        search.tap()
        search.typeText(text + "\n")
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "Searching \"\(text)\" didn't find \(name)", file: file, line: line)
        snap(screenshot)
        row.tap()
        XCTAssertTrue(waitUntilGone(pickerBar), "The exercise picker didn't close", file: file, line: line)
        expectStillRunning("adding \(name)", file: file, line: line)
    }

    /// "Finish" → confirm → the summary → "Done".
    private func finishWorkout(confirmation: String, summary: String, file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["Finish"].tap()
        let confirm = app.buttons["Finish workout"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "No finish confirmation", file: file, line: line)
        snap(confirmation)
        confirm.tap()
        expectVisible(containing: "Nice work!", timeout: 10, file: file, line: line)
        expectVisible("Sets", file: file, line: line)
        expectStillRunning("finishing the workout", file: file, line: line)
        snap(summary)
        let done = app.buttons.matching(identifier: "Done").firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "No Done on the summary", file: file, line: line)
        done.tap()
    }

    // MARK: Queries

    /// A routine row: "Push day, 3 exercises · …".
    private func routineRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", name, "exercise"
        )).firstMatch
    }

    /// A finished workout in the history: "Push day, Yesterday, Bench Press (Barbell), …".
    private func historyRow(title: String, containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(
            format: "label BEGINSWITH %@ AND label CONTAINS %@", title, text
        )).firstMatch
    }

    /// A set's done button ("Set 1", "Not done" / "Done"); the set-type menu shares its label.
    private func setCheckButton(_ set: String, done: Bool) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND value == %@", set, done ? "Done" : "Not done")).firstMatch
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

    // MARK: Gestures

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

    /// Taps the keyboard toolbar's "Done" when a keyboard is up.
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
}
