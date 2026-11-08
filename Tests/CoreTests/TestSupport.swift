//
//  TestSupport.swift
//  Haki core tests
//
//  A tiny assertion harness so the pure-Foundation core can be tested with
//  plain `swiftc` on Linux or macOS (no Xcode project needed). Run with
//  scripts/test-core.sh.
//

import Foundation

var checkCount = 0
var failureCount = 0
var currentSuite = ""

func suite(_ name: String, _ body: () throws -> Void) {
    currentSuite = name
    do {
        try body()
    } catch {
        failureCount += 1
        print("FAIL [\(name)] threw \(error)")
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "", line: Int = #line) {
    checkCount += 1
    if !condition() {
        failureCount += 1
        print("FAIL [\(currentSuite)] line \(line): \(message)")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", line: Int = #line) {
    checkCount += 1
    if actual != expected {
        failureCount += 1
        print("FAIL [\(currentSuite)] line \(line): \(message) got \(actual), expected \(expected)")
    }
}

/// Gregorian calendar in a fixed zone so tests don't depend on the machine.
let testCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}()

let usLocale = Locale(identifier: "en_US")

func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    testCalendar.noon(year: year, month: month, day: day)!
}

nonisolated struct Entry: LedgerEntry {
    var ledgerDate: Date
    var ledgerAmountCents: Int
    var ledgerFlow: LedgerFlow = .spending
    var ledgerCategoryID: String? = nil
    var ledgerMerchant: String = "Test Merchant"
    var ledgerMerchantKey: String { MerchantNormalizer.key(for: ledgerMerchant) }
}
