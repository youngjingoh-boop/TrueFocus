import XCTest
@testable import TrueFocusKit

final class SoundTests: XCTestCase {
    let a = UUID(), b = UUID()

    func snap(_ mode: FlowMode, task: UUID? = nil, done: Int = 0, boots: Int = 0, ended: Bool = false,
              device: String = "Mac") -> LiveSnapshot {
        LiveSnapshot(mode: mode, taskID: task, doneToday: done, bootsToday: boots, dayEnded: ended,
                     updatedAt: Date(timeIntervalSince1970: 1_800_000_000), originDevice: device)
    }

    func testEachMomentHasItsCue() {
        XCTAssertEqual(FlowCue.cue(from: snap(.focus, task: a), to: snap(.rest, done: 1), device: "Mac"), .complete)
        XCTAssertEqual(FlowCue.cue(from: snap(.focus, task: a), to: snap(.think, task: a), device: "Mac"), .think)
        XCTAssertEqual(FlowCue.cue(from: snap(.rest), to: snap(.focus, task: b), device: "Mac"), .go)
        XCTAssertEqual(FlowCue.cue(from: snap(.focus, task: a), to: snap(.focus, task: b), device: "Mac"), .switchTask)
        XCTAssertEqual(FlowCue.cue(from: snap(.focus, task: a), to: snap(.focus, task: a, boots: 1), device: "Mac"), .boot)
        XCTAssertEqual(FlowCue.cue(from: snap(.idle), to: snap(.idle, ended: true), device: "Mac"), .shutdown)
        XCTAssertNil(FlowCue.cue(from: snap(.focus, task: a), to: snap(.focus, task: a), device: "Mac"))
    }

    func testOtherDevicesStayQuietAndFirstLoadIsSilent() {
        XCTAssertNil(FlowCue.cue(from: snap(.focus, task: a, device: "Mac"), to: snap(.rest, done: 1, device: "Mac"),
                                 device: "iPhone"))
        XCTAssertNil(FlowCue.cue(from: nil, to: snap(.focus, task: a), device: "Mac"))
        XCTAssertNil(FlowCue.cue(from: .idle, to: snap(.focus, task: a), device: "Mac"))
    }

    func testMusicSettingsDecodeAndCycle() throws {
        XCTAssertEqual(TFSettings().focusMusic, .off)
        XCTAssertTrue(TFSettings().soundEffects)
        let old = try JSONDecoder().decode(TFSettings.self, from: Data(#"{"tone":"calm"}"#.utf8))
        XCTAssertEqual(old.focusMusic, .off)
        let future = try JSONDecoder().decode(TFSettings.self, from: Data(#"{"focusMusic":"spotify"}"#.utf8))
        XCTAssertEqual(future.focusMusic, .off, "an unknown choice from a newer build falls back to off")
        XCTAssertEqual(FocusMusic.off.next, .drive)
        XCTAssertEqual(FocusMusic.flow.next, .off)
        XCTAssertEqual(FocusMusic.appleMusic.bundledTrack, "tf_music_drive")
    }
}
