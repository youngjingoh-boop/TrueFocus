import XCTest
@testable import TrueFocusKit

/// Rest (a break you take yourself, as long as you like) and Stop (end the task, nothing held).
final class BreakAndStopTests: XCTestCase {
    let task = UUID()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testABreakIsARestWithNoPlannedEnd() {
        let onBreak = LiveSnapshot(mode: .rest, modeStartedAt: t0, nextTaskID: task)
        XCTAssertTrue(onBreak.isOnBreak)
        XCTAssertFalse(onBreak.mode.isWorking, "shields drop on a break")
        XCTAssertFalse(LiveSnapshot(mode: .rest, modeStartedAt: t0, plannedRestEnd: t0.addingTimeInterval(60)).isOnBreak)
    }

    func testNothingAsksYouBackFromABreak() {
        let nudges = NudgePlanner.plan(NudgeContext(mode: .rest, modeStartedAt: t0, plannedRestEnd: nil,
                                                    nextTaskTitle: "Pricing page", openTaskCount: 3, now: t0))
        XCTAssertTrue(nudges.isEmpty)
        // A micro-rest after Done still has its nudges.
        let rest = NudgePlanner.plan(NudgeContext(mode: .rest, modeStartedAt: t0, plannedRestEnd: t0.addingTimeInterval(60),
                                                  nextTaskTitle: "Pricing page", openTaskCount: 3, now: t0))
        XCTAssertFalse(rest.isEmpty)
    }

    func testAfterStopTheFirstNudgeWaitsHalfAnHour() {
        let stopped = NudgePlanner.plan(NudgeContext(mode: .idle, modeStartedAt: t0, nextTaskTitle: "Pricing page",
                                                     openTaskCount: 3, stopped: true, now: t0))
        XCTAssertEqual(stopped.first?.fireAt, t0.addingTimeInterval(1800))
        let idle = NudgePlanner.plan(NudgeContext(mode: .idle, modeStartedAt: t0, nextTaskTitle: "Pricing page",
                                                  openTaskCount: 3, now: t0))
        XCTAssertEqual(idle.first?.fireAt, t0.addingTimeInterval(180))
    }

    func testALongBreakIsNotARestOverrun() {
        let segments = [
            SegmentRecord(mode: .focus, taskID: task, start: t0, end: t0.addingTimeInterval(1200), outcome: .paused),
            SegmentRecord(mode: .rest, taskID: task, start: t0.addingTimeInterval(1200), end: t0.addingTimeInterval(3000),
                          outcome: .resumed, plannedSeconds: nil),
        ]
        let stats = DayStats.compute(segments: segments, boots: 0, now: t0.addingTimeInterval(3000))
        XCTAssertEqual(stats.restOverrunSeconds, 0)
        XCTAssertEqual(stats.restSeconds, 1800, accuracy: 0.5)
    }

    func testBreakAndStopSoundLikeAPause() {
        let focus = LiveSnapshot(mode: .focus, taskID: task, updatedAt: t0, originDevice: "Mac")
        let onBreak = LiveSnapshot(mode: .rest, modeStartedAt: t0, nextTaskID: task, updatedAt: t0, originDevice: "Mac")
        let microRest = LiveSnapshot(mode: .rest, modeStartedAt: t0, plannedRestEnd: t0.addingTimeInterval(60),
                                     updatedAt: t0, originDevice: "Mac")
        let stopped = LiveSnapshot(mode: .idle, stoppedAt: t0, updatedAt: t0, originDevice: "Mac")
        XCTAssertEqual(FlowCue.cue(from: focus, to: onBreak, device: "Mac"), .pause)
        XCTAssertEqual(FlowCue.cue(from: focus, to: microRest, device: "Mac"), .rest)
        XCTAssertEqual(FlowCue.cue(from: focus, to: stopped, device: "Mac"), .pause)
        XCTAssertEqual(FlowCue.cue(from: onBreak, to: focus, device: "Mac"), .go)
    }

    func testStopOutcomeAndStoppedAtRoundTrip() throws {
        XCTAssertEqual(SegmentOutcome(rawValue: "stopped"), .stopped)
        let encoded = try JSONEncoder().encode(LiveSnapshot(mode: .idle, stoppedAt: t0))
        XCTAssertEqual(try JSONDecoder().decode(LiveSnapshot.self, from: encoded).stoppedAt, t0)
        XCTAssertNil(try JSONDecoder().decode(LiveSnapshot.self, from: Data(#"{"mode":"idle"}"#.utf8)).stoppedAt)
    }
}
