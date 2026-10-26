import XCTest
@testable import TrueFocusKit

final class PauseTests: XCTestCase {
    let task = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testPauseIsIdleWithAHeldTask() {
        let paused = LiveSnapshot(mode: .idle, nextTaskID: task, pausedAt: t0)
        XCTAssertTrue(paused.isPaused)
        XCTAssertFalse(paused.mode.isWorking, "shields drop while paused")
        XCTAssertFalse(LiveSnapshot(mode: .idle, nextTaskID: task).isPaused)
        XCTAssertFalse(LiveSnapshot(mode: .idle, dayEnded: true, pausedAt: t0).isPaused, "shutting down ends the pause")
    }

    func testPauseAndResumeCues() {
        let focus = LiveSnapshot(mode: .focus, taskID: task, updatedAt: t0, originDevice: "Mac")
        let paused = LiveSnapshot(mode: .idle, nextTaskID: task, pausedAt: t0, updatedAt: t0, originDevice: "Mac")
        XCTAssertEqual(FlowCue.cue(from: focus, to: paused, device: "Mac"), .pause)
        XCTAssertEqual(FlowCue.cue(from: paused, to: focus, device: "Mac"), .go)
        let stopped = LiveSnapshot(mode: .idle, updatedAt: t0, originDevice: "Mac")
        XCTAssertNil(FlowCue.cue(from: focus, to: stopped, device: "Mac"))
    }

    func testOlderSnapshotsDecodeUnpausedAndNewOnesRoundTrip() throws {
        let old = try JSONDecoder().decode(LiveSnapshot.self, from: Data(#"{"mode":"idle"}"#.utf8))
        XCTAssertNil(old.pausedAt)
        let encoded = try JSONEncoder().encode(LiveSnapshot(mode: .idle, pausedAt: t0))
        XCTAssertEqual(try JSONDecoder().decode(LiveSnapshot.self, from: encoded).pausedAt, t0)
        XCTAssertEqual(SegmentOutcome(rawValue: "paused"), .paused)
    }

    func testAPauseGetsRoomThenAGentleCallBack() {
        let nudges = NudgePlanner.plan(NudgeContext(mode: .idle, modeStartedAt: t0, nextTaskTitle: "Pricing page",
                                                    openTaskCount: 3, paused: true, tone: .calm, now: t0))
        XCTAssertEqual(nudges.map(\.id), ["paused.0", "paused.1", "paused.2"])
        XCTAssertEqual(nudges.first?.fireAt, t0.addingTimeInterval(600), "no nudge in the first ten minutes")
        XCTAssertTrue(nudges.first?.body.contains("Pricing page") ?? false)
        XCTAssertTrue(NudgePlanner.plan(NudgeContext(mode: .idle, modeStartedAt: t0, openTaskCount: 3, dayEnded: true,
                                                     paused: true, now: t0)).isEmpty)
    }

    func testPausedSinceCopy() {
        XCTAssertEqual(TFFormat.pausedSince(t0, now: t0.addingTimeInterval(20)), "Paused just now")
        XCTAssertEqual(TFFormat.pausedSince(t0, now: t0.addingTimeInterval(12 * 60 + 5)), "Paused 12m ago")
    }

    func testPausedFocusCountsAsFocusNotACompletion() {
        let segments = [
            SegmentRecord(mode: .focus, taskID: task, start: t0, end: t0.addingTimeInterval(600), outcome: .paused),
        ]
        let stats = DayStats.compute(segments: segments, boots: 0, now: t0.addingTimeInterval(700))
        XCTAssertEqual(stats.focusSeconds, 600, accuracy: 0.5)
        XCTAssertEqual(stats.completed, 0)
    }
}
