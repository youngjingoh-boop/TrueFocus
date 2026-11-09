import XCTest
@testable import TrueFocusKit

final class PlanTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Ho_Chi_Minh")!
        return calendar
    }

    /// 9pm on a Monday, then a time on later days.
    private func date(day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))!
    }

    private func dayStart(_ day: Int) -> Date { date(day: day, hour: 4) }

    // MARK: Buckets

    func testBucketsFollowThePlannedDay() {
        let now = date(day: 9, hour: 21)
        func bucket(_ planned: Date?) -> PlanBucket {
            PlanSchedule.bucket(plannedFor: planned, now: now, calendar: calendar)
        }
        XCTAssertEqual(bucket(nil), .today)
        XCTAssertEqual(bucket(dayStart(9)), .today)
        XCTAssertEqual(bucket(dayStart(1)), .today, "A day that has passed is still on today's plan")
        XCTAssertEqual(bucket(dayStart(10)), .tomorrow)
        XCTAssertEqual(bucket(dayStart(11)), .later)
        XCTAssertEqual(bucket(PlanSchedule.someday), .later)
    }

    func testTomorrowBecomesTodayWhenTheDayTurnsOver() {
        let planned = PlanSchedule.plannedFor(.tomorrow, now: date(day: 9, hour: 21), calendar: calendar)
        XCTAssertEqual(PlanSchedule.bucket(plannedFor: planned, now: date(day: 10, hour: 3), calendar: calendar), .tomorrow,
                       "Working past midnight is still the same day")
        XCTAssertEqual(PlanSchedule.bucket(plannedFor: planned, now: date(day: 10, hour: 5), calendar: calendar), .today)
    }

    func testMovingToABucketLandsInThatBucket() {
        let now = date(day: 9, hour: 2) // Before the rollover: still the 8th's day.
        for bucket in PlanBucket.allCases {
            let planned = PlanSchedule.plannedFor(bucket, now: now, calendar: calendar)
            XCTAssertEqual(PlanSchedule.bucket(plannedFor: planned, now: now, calendar: calendar), bucket)
        }
    }

    // MARK: Old dividers

    func testRecognisesDividersTypedAsTasks() {
        let now = date(day: 9, hour: 21)
        XCTAssertEqual(PlanSchedule.divider(in: "----- TOMORROW -----", now: now, calendar: calendar)?.plannedFor, dayStart(10))
        XCTAssertEqual(PlanSchedule.divider(in: "----- THE DAY AFTER TOMORROW ------", now: now, calendar: calendar)?.plannedFor, dayStart(11))
        XCTAssertEqual(PlanSchedule.divider(in: "=== later ===", now: now, calendar: calendar)?.plannedFor, PlanSchedule.someday)
    }

    func testRealTasksAreNeverDividers() {
        let now = date(day: 9, hour: 21)
        for title in ["Tomorrow", "- tomorrow", "Call Sam tomorrow", "--- call the signage owners ---",
                      "8-10 As soon as wake up, Call 100 signage owners + record", "---", "----- -----"] {
            XCTAssertNil(PlanSchedule.divider(in: title, now: now, calendar: calendar), title)
        }
    }

    func testConvertingDividersPlansTheTasksUnderThem() {
        let now = date(day: 9, hour: 21)
        let ids = (0..<6).map { _ in UUID() }
        let tasks = [(ids[0], "Tonight"), (ids[1], "----- TOMORROW -----"), (ids[2], "Calls"), (ids[3], "Ads"),
                     (ids[4], "----- THE DAY AFTER TOMORROW ------"), (ids[5], "Follow up")]
            .map { (id: $0.0, title: $0.1) }
        let converted = PlanSchedule.convertDividers(tasks, now: now, calendar: calendar)
        XCTAssertEqual(converted.dividers, [ids[1], ids[4]])
        XCTAssertNil(converted.plannedFor[ids[0]] as Date??, "Tasks above the first divider stay as they are")
        XCTAssertEqual(converted.plannedFor[ids[2]], .some(dayStart(10)))
        XCTAssertEqual(converted.plannedFor[ids[3]], .some(dayStart(10)))
        XCTAssertEqual(converted.plannedFor[ids[5]], .some(dayStart(11)))
    }

    // MARK: Layout

    func testRowsPutEachBucketUnderItsHeading() {
        let a = UUID(), b = UUID(), c = UUID()
        let rows = PlanLayout.rows([(a, .today), (b, .later), (c, .tomorrow)])
        XCTAssertEqual(rows, [.task(a), .newTask(.today),
                              .heading(.tomorrow), .task(c), .newTask(.tomorrow),
                              .heading(.later), .task(b), .newTask(.later)])
    }

    func testDraggingAcrossAHeadingChangesTheBucket() {
        let a = UUID(), b = UUID(), c = UUID()
        let rows = PlanLayout.rows([(a, .today), (b, .today), (c, .tomorrow)])
        // a, b, new, [Tomorrow], c, new, [Later], new: drop a just under the Tomorrow heading.
        let moved = PlanLayout.move(rows, fromOffsets: [0], toOffset: 4)
        XCTAssertEqual(moved.map(\.id), [b, a, c])
        XCTAssertEqual(moved.map(\.bucket), [.today, .tomorrow, .tomorrow])
    }

    func testDraggingToTheTopReturnsATaskToToday() {
        let a = UUID(), c = UUID()
        let rows = PlanLayout.rows([(a, .today), (c, .later)])
        let index = rows.firstIndex(of: .task(c))!
        let moved = PlanLayout.move(rows, fromOffsets: [index], toOffset: 0)
        XCTAssertEqual(moved.map(\.id), [c, a])
        XCTAssertEqual(moved.map(\.bucket), [.today, .today])
    }

    func testHeadingsCannotBeMoved() {
        let a = UUID()
        let rows = PlanLayout.rows([(a, .today)])
        let index = rows.firstIndex(of: .heading(.tomorrow))!
        let moved = PlanLayout.move(rows, fromOffsets: [index], toOffset: 0)
        XCTAssertEqual(moved.map(\.id), [a])
        XCTAssertEqual(moved.map(\.bucket), [.today])
    }

    // MARK: Priority

    func testUnknownStoredPriorityReadsAsNone() {
        XCTAssertEqual(TaskPriority(stored: 2), .top)
        XCTAssertEqual(TaskPriority(stored: 99), .none)
    }

    // MARK: Sync

    func testNewTaskFieldsSurviveSync() throws {
        let plan = Date(timeIntervalSince1970: 1_800_000_000)
        let payload = TaskPayload(title: "T", isDone: false, doneAt: nil, createdAt: plan, order: 1, focusSeconds: 0,
                                  breadcrumb: "", inPlay: false, inPlayAt: nil, priority: 2, plannedFor: plan)
        let back = try PayloadCoding.decode(TaskPayload.self, from: PayloadCoding.encode(payload))
        XCTAssertEqual(back.priority, 2)
        XCTAssertEqual(back.plannedFor, plan)
    }

    /// Payload bytes are how changes are found: a task using none of this must encode exactly as
    /// before, or every device would upload its whole plan after updating.
    func testTasksWithoutNewFieldsEncodeAsBefore() throws {
        let payload = TaskPayload(title: "T", isDone: false, doneAt: nil, createdAt: Date(timeIntervalSince1970: 1), order: 1,
                                  focusSeconds: 0, breadcrumb: "", inPlay: false, inPlayAt: nil)
        let text = String(decoding: try PayloadCoding.encode(payload), as: UTF8.self)
        XCTAssertFalse(text.contains("priority"))
        XCTAssertFalse(text.contains("plannedFor"))

        let note = NotePayload(body: "x", createdAt: Date(timeIntervalSince1970: 1), updatedAt: Date(timeIntervalSince1970: 1), isPinned: false)
        XCTAssertFalse(String(decoding: try PayloadCoding.encode(note), as: UTF8.self).contains("taskID"))
    }
}

final class NoteInlineTests: XCTestCase {
    func testSplitsBoldRuns() {
        XCTAssertEqual(NoteInline.spans(in: "a **b** c"),
                       [.init("a "), .init("b", bold: true), .init(" c")])
        XCTAssertEqual(NoteInline.spans(in: "**all**"), [.init("all", bold: true)])
    }

    func testUnpairedMarkersAreJustText() {
        XCTAssertEqual(NoteInline.spans(in: "2 ** 3"), [.init("2 ** 3")])
        XCTAssertEqual(NoteInline.spans(in: "****"), [.init("****")])
        XCTAssertEqual(NoteInline.plain("2 ** 3"), "2 ** 3")
        XCTAssertEqual(NoteInline.spans(in: ""), [])
    }

    func testRoundTrips() {
        for line in ["plain", "a **b** c", "**x** and **y**", "2 ** 3", ""] {
            XCTAssertEqual(NoteInline.markup(from: NoteInline.spans(in: line)), line)
        }
    }

    func testNeighbouringRunsOfOneWeightJoin() {
        XCTAssertEqual(NoteInline.markup(from: [.init("a", bold: true), .init("b", bold: true), .init("c")]), "**ab**c")
    }

    func testPlainStripsMarkersForEverythingThatReadsTheText() {
        let document = NoteDocument(markup: "**Title**\n**Body** text\n- [ ] Call **Sam**")
        XCTAssertEqual(document.title, "Title")
        XCTAssertEqual(document.preview, "Body text")
        XCTAssertEqual(document.openChecklistItems, ["Call Sam"])
    }
}

final class NoteHistoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testEditsInOneSittingShareAVersion() {
        var history = NoteHistory()
        history.record("a", at: start)
        history.record("ab", at: start.addingTimeInterval(10))
        history.record("abc", at: start.addingTimeInterval(20))
        XCTAssertEqual(history.versions.map(\.markup), ["abc"])
    }

    func testANewVersionStartsAfterAMinute() {
        var history = NoteHistory()
        history.record("a", at: start)
        history.record("ab", at: start.addingTimeInterval(61))
        XCTAssertEqual(history.versions.map(\.markup), ["a", "ab"])
    }

    func testALargeDeletionKeepsTheTextFromBeforeIt() {
        let text = String(repeating: "important words ", count: 3)
        var history = NoteHistory()
        history.record(text, at: start)
        history.record("", at: start.addingTimeInterval(1))
        XCTAssertEqual(history.versions.map(\.markup), [text, ""])
    }

    func testTheSameTextAddsNothing() {
        var history = NoteHistory()
        history.record("a", at: start)
        history.record("a", at: start.addingTimeInterval(500))
        XCTAssertEqual(history.versions.count, 1)
    }

    func testTypingOverARestoredVersionKeepsEverything() {
        var history = NoteHistory()
        history.record("first", at: start)
        history.record("second", at: start.addingTimeInterval(100))
        // Restored "first", then typed, moments after "second" began.
        history.record("first and more", at: start.addingTimeInterval(101), sealing: true)
        XCTAssertEqual(history.versions.map(\.markup), ["first", "second", "first and more"])
    }

    func testKeepsTheNewestVersionsOnly() {
        var history = NoteHistory()
        for index in 0..<(NoteHistory.limit + 5) {
            history.record("v\(index)", at: start.addingTimeInterval(Double(index) * 100))
        }
        XCTAssertEqual(history.versions.count, NoteHistory.limit)
        XCTAssertEqual(history.versions.last?.markup, "v\(NoteHistory.limit + 4)")
        XCTAssertEqual(history.versions.first?.markup, "v5")
    }
}
