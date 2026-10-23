import XCTest
@testable import TrueFocusKit

final class ScrollCheckInTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    /// Strokes every `every` seconds for `seconds`, ticking every 3 s. Returns when it asked.
    private func scroll(_ c: inout ScrollCheckIn, from start: TimeInterval, for seconds: TimeInterval,
                        every: TimeInterval = 4) -> TimeInterval? {
        var t = start
        var nextStroke = start
        var askedAt: TimeInterval?
        while t <= start + seconds {
            if t >= nextStroke { c.stroke(at: t0 + t); nextStroke += every }
            if c.tick(at: t0 + t), askedAt == nil { askedAt = t }
            t += 1
        }
        return askedAt
    }

    func testAsksAfterTwoMinutesOfScrolling() throws {
        var c = ScrollCheckIn()
        let asked = try XCTUnwrap(scroll(&c, from: 0, for: 200))
        XCTAssertEqual(asked, 120, accuracy: 2)
        XCTAssertTrue(c.asking)
        XCTAssertEqual(c.minutes, 2)
    }

    func testReadingWithoutScrollingDoesNotCount() {
        var c = ScrollCheckIn()
        // One stroke, then four minutes of reading.
        c.stroke(at: t0)
        for s in stride(from: 0.0, through: 240, by: 3) { XCTAssertFalse(c.tick(at: t0 + s)) }
        XCTAssertEqual(c.scrolled, ScrollCheckIn.activeWindow, accuracy: 0.01)
    }

    func testWorkingQuietsItForFiveMoreMinutes() throws {
        var c = ScrollCheckIn()
        _ = scroll(&c, from: 0, for: 125)
        c.working()
        XCTAssertFalse(c.asking)
        let asked = try XCTUnwrap(scroll(&c, from: 130, for: 400))
        XCTAssertEqual(asked - 130, 300, accuracy: 4)
        XCTAssertEqual(c.minutes, 5)
    }

    func testAsksOnlyOnceUntilAnswered() {
        var c = ScrollCheckIn()
        _ = scroll(&c, from: 0, for: 125)
        XCTAssertNil(scroll(&c, from: 126, for: 300))
    }

    func testTenQuietMinutesStartOver() {
        var c = ScrollCheckIn()
        _ = scroll(&c, from: 0, for: 100)
        c.stroke(at: t0 + 100 + ScrollCheckIn.idleReset + 1)
        XCTAssertEqual(c.scrolled, 0)
    }
}
