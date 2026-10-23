import XCTest
@testable import TrueFocusKit

final class GuardTimingTests: XCTestCase {
    func testPassCannotBeUsedUpFasterThanTheClock() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(GuardTiming.passCouldBeUsedUp(startedAt: start, pass: 2, now: start))
        XCTAssertFalse(GuardTiming.passCouldBeUsedUp(startedAt: start, pass: 2, now: start.addingTimeInterval(60)))
        XCTAssertTrue(GuardTiming.passCouldBeUsedUp(startedAt: start, pass: 2, now: start.addingTimeInterval(120)))
        XCTAssertTrue(GuardTiming.passCouldBeUsedUp(startedAt: nil, pass: 2, now: start))
    }

    func testReplacedPassEndingDoesNotCloseTheNewOne() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        // A 2-minute pass runs on a 15-minute window.
        XCTAssertFalse(GuardTiming.passWindowOver(startedAt: start, pass: 2, now: start.addingTimeInterval(5)))
        XCTAssertFalse(GuardTiming.passWindowOver(startedAt: start, pass: 2, now: start.addingTimeInterval(10 * 60)))
        XCTAssertTrue(GuardTiming.passWindowOver(startedAt: start, pass: 2, now: start.addingTimeInterval(15 * 60)))
        XCTAssertTrue(GuardTiming.passWindowOver(startedAt: nil, pass: 2, now: start))
    }

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

    // MARK: Across midnight

    private var london: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int, second: Double = 0) -> Date {
        let date = london.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
        return date.addingTimeInterval(second)
    }

    /// Passes are counted per TruFocus day (4 am to 4 am). The Monitor used to zero them at
    /// midnight as well, which handed out a second day's worth between midnight and 4 am.
    func testPassesUsedBeforeMidnightStillCountUntilFourAM() {
        let cal = london
        let day = cal.tfDayStart(for: at(19, 23, 30))
        XCTAssertEqual(GuardTiming.passesUsed(8, countedOn: day, now: at(19, 23, 59), calendar: cal), 8)
        XCTAssertEqual(GuardTiming.passesUsed(8, countedOn: day, now: at(20, 0, 30), calendar: cal), 8)
        XCTAssertEqual(GuardTiming.passesUsed(8, countedOn: day, now: at(20, 3, 59), calendar: cal), 8)
        XCTAssertEqual(GuardTiming.passesUsed(8, countedOn: day, now: at(20, 4, 0), calendar: cal), 0)
        XCTAssertEqual(GuardTiming.passesUsed(3, countedOn: nil, now: at(20, 9, 0), calendar: cal), 0)
    }

    /// A boot-out that runs past midnight already has a fresh budget waiting: the daily
    /// monitor started over at 00:00. A second one-off monitor would warn and boot twice.
    func testABootOutAcrossMidnightDoesNotStartASecondBudget() {
        let cal = london
        XCTAssertTrue(GuardTiming.restartsBudget(bootedAt: at(19, 10, 0), cooldownEndedAt: at(19, 10, 15), calendar: cal))
        XCTAssertFalse(GuardTiming.restartsBudget(bootedAt: at(19, 23, 55), cooldownEndedAt: at(20, 0, 10), calendar: cal))
        // Saved before the boot time was kept: restart, as before.
        XCTAssertTrue(GuardTiming.restartsBudget(bootedAt: nil, cooldownEndedAt: at(20, 0, 10), calendar: cal))
    }

    /// Schedules are built from whole seconds. Truncating the end made an adult-filter
    /// cool-off's schedule end just before the cool-off did, so the Monitor found the filter
    /// still due and left it on.
    func testAScheduleNeverEndsBeforeTheMomentItStandsFor() {
        var settings = TFSettings()
        settings.adultFilterCoolOffHours = 24
        settings.adultFilterOffRequestedAt = at(19, 9, 0, second: 0.734)
        let due = settings.adultFilterOffEffectiveAt!
        let truncated = Date(timeIntervalSince1970: due.timeIntervalSince1970.rounded(.down))
        XCTAssertTrue(settings.adultFilterActive(now: truncated), "what the old schedule ended at")

        let end = GuardTiming.scheduleEnd(due)
        XCTAssertFalse(settings.adultFilterActive(now: end))
        XCTAssertEqual(end.timeIntervalSince1970, end.timeIntervalSince1970.rounded())
        XCTAssertLessThan(end.timeIntervalSince(due), 1)
        let whole = at(19, 9, 0)
        XCTAssertEqual(GuardTiming.scheduleEnd(whole), whole)
        XCTAssertEqual(london.component(.second, from: end), 1)
    }
}
