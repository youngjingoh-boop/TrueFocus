import XCTest
@testable import TrueFocusKit

final class FeedTimerTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testRemindsAtTheLimitOnce() {
        var timer = FeedTimer(now: t0)
        var asked: [Int] = []
        for s in stride(from: 3.0, through: 20 * 60, by: 3) {
            if let minutes = timer.add(3, to: "Instagram", limitMinutes: 15, now: t0 + s) { asked.append(minutes) }
        }
        XCTAssertEqual(asked, [15])
    }

    func testFiveMoreMinutes() {
        var timer = FeedTimer(now: t0)
        XCTAssertNotNil(timer.add(15 * 60, to: "Instagram", limitMinutes: 15, now: t0))
        timer.snooze("Instagram")
        XCTAssertNil(timer.add(4 * 60, to: "Instagram", limitMinutes: 15, now: t0))
        XCTAssertNotNil(timer.add(60, to: "Instagram", limitMinutes: 15, now: t0))
    }

    func testAppsCountSeparatelyAndDaysStartOver() {
        var timer = FeedTimer(now: t0)
        XCTAssertNotNil(timer.add(15 * 60, to: "Instagram", limitMinutes: 15, now: t0))
        XCTAssertNil(timer.add(60, to: "TikTok", limitMinutes: 15, now: t0))
        XCTAssertNil(timer.add(60, to: "Instagram", limitMinutes: 15, now: t0 + 86_400))
    }
}
