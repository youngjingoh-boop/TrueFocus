import XCTest
@testable import TrueFocusKit

final class JuggleTests: XCTestCase {
    let a = LiveSnapshot.Item(id: UUID(), title: "Submit the job application")
    let b = LiveSnapshot.Item(id: UUID(), title: "Fix the PDF", waitingSince: Date())
    let c = LiveSnapshot.Item(id: UUID(), title: "Reply to Ben")

    func testNextSkipsWaitingAndWrapsAround() {
        XCTAssertEqual(Juggle.next(after: a.id, in: [a, b, c])?.id, c.id)
        XCTAssertEqual(Juggle.next(after: c.id, in: [a, b, c])?.id, a.id)
        XCTAssertNil(Juggle.next(after: a.id, in: [a, b]))
        XCTAssertEqual(Juggle.next(after: nil, in: [b, c])?.id, c.id)
        XCTAssertNil(Juggle.next(after: nil, in: []))
    }

    func testSummaryNamesTheOthers() {
        XCTAssertEqual(Juggle.summary([a, b, c], excluding: a.id), "Juggling ⏳ Fix the PDF · Reply to Ben")
        XCTAssertNil(Juggle.summary([a], excluding: a.id))
    }

    func testSnapshotKnowsWhatsJuggled() throws {
        var snapshot = LiveSnapshot(taskID: a.id, inPlay: [a, b])
        XCTAssertTrue(snapshot.isJuggling)
        XCTAssertEqual(snapshot.juggledOthers.map(\.id), [b.id])
        snapshot.inPlay = [a]
        XCTAssertFalse(snapshot.isJuggling)

        // Items written before waiting existed still decode.
        let old = #"{"id":"\#(a.id.uuidString)","title":"A"}"#
        XCTAssertNil(try JSONDecoder().decode(LiveSnapshot.Item.self, from: Data(old.utf8)).waitingSince)
    }

    func testJuggleLimitDefaultsToCurrentPlusThree() throws {
        XCTAssertEqual(TFSettings().juggleLimit, 4)
        let old = try JSONDecoder().decode(TFSettings.self, from: Data(#"{"maxInPlay":3}"#.utf8))
        XCTAssertEqual(old.juggleLimit, 4)
        var wild = TFSettings()
        wild.juggleLimit = 40
        wild.normalize()
        XCTAssertEqual(wild.juggleLimit, Juggle.maxLimit)
    }

    func testSwitchCommandsCarryTheirTask() throws {
        let command = RemoteCommand(kind: .switchTo, taskID: c.id)
        let back = try JSONDecoder().decode(RemoteCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(back.taskID, c.id)
        let old = try JSONDecoder().decode(RemoteCommand.self, from: Data(#"{"kind":"complete","at":0}"#.utf8))
        XCTAssertNil(old.taskID)
    }
}
