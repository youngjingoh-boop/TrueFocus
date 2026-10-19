import XCTest
@testable import TrueFocusKit

final class GuardTimingTests: XCTestCase {
    func testBudgetWarnsTwoMinutesBeforeTheShield() {
        XCTAssertEqual(GuardTiming.budgetWarningMinute(budget: 5), 3)
        XCTAssertEqual(GuardTiming.budgetWarningMinute(budget: 3), 1)
        XCTAssertEqual(GuardTiming.budgetWarningMinute(budget: 60), 58)
        XCTAssertEqual(GuardTiming.budgetWarningMinute(budget: 2), 1)
        XCTAssertNil(GuardTiming.budgetWarningMinute(budget: 1))
    }

    func testPassWarnsAMinuteBeforeItCloses() {
        XCTAssertEqual(GuardTiming.passWarningMinute(pass: 5), 4)
        XCTAssertEqual(GuardTiming.passWarningMinute(pass: 2), 1)
        XCTAssertNil(GuardTiming.passWarningMinute(pass: 1))
    }

    func testPassWindowMeetsTheFifteenMinuteMinimum() {
        XCTAssertEqual(GuardTiming.passWindow(pass: 2), 15 * 60)
        XCTAssertEqual(GuardTiming.passWindow(pass: 10), 15 * 60)
        XCTAssertEqual(GuardTiming.passWindow(pass: 15), 20 * 60)
    }

    func testWarningCopyNamesTheTimeLeftAndTheTask() {
        let line = Copy(tone: .savage).budgetWarning(minutesLeft: 2, task: "Ship the deck")
        XCTAssertEqual(line.title, "Still scrolling?")
        XCTAssertTrue(line.body.contains("2 minutes left"))
        XCTAssertTrue(line.body.contains("“Ship the deck”"))
        XCTAssertTrue(Copy(tone: .calm).budgetWarning(minutesLeft: 1, task: nil).body.hasPrefix("1 minute left"))
        for tone in [NudgeTone.calm, .direct, .savage] {
            XCTAssertFalse(Copy(tone: tone).passEnding.title.isEmpty)
        }
    }

    func testPassIsLongEnoughToPostByDefaultAndCapsAtFifteen() {
        XCTAssertEqual(TFSettings().respondPassMinutes, 5)
        var s = TFSettings()
        s.respondPassMinutes = 40
        s.normalize()
        XCTAssertEqual(s.respondPassMinutes, 15)
    }
}
