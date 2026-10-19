import XCTest
@testable import TrueFocusKit

final class DefaultToneTests: XCTestCase {
    func testDefaultToneIsDirect() {
        XCTAssertEqual(TFSettings().tone, .direct)
        XCTAssertEqual(TFSettings.default.tone, .direct)
        XCTAssertEqual(NudgeContext(mode: .rest, modeStartedAt: nil, now: Date()).tone, .direct)
    }

    func testOldSettingsWithoutAToneGetDirect() throws {
        let old = try JSONDecoder().decode(TFSettings.self, from: Data(#"{"restBaseSeconds":30}"#.utf8))
        XCTAssertEqual(old.tone, .direct)
    }

    func testSavedToneIsKept() throws {
        for tone in NudgeTone.allCases {
            let saved = try JSONDecoder().decode(TFSettings.self, from: Data(#"{"tone":"\#(tone.rawValue)"}"#.utf8))
            XCTAssertEqual(saved.tone, tone)
        }
    }

    func testDefaultCopyIsClean() {
        let copy = Copy(tone: TFSettings().tone)
        for level in 1...3 {
            XCTAssertFalse(copy.restOver(level: level, next: "Deck").title.lowercased().contains("fuck"))
            XCTAssertFalse(copy.idle(level: level, next: "Deck", left: 2).title.lowercased().contains("fuck"))
        }
        XCTAssertFalse(copy.bootOut(site: "X", task: nil).title.lowercased().contains("fuck"))
    }

    func testSavageIsLabelledAsStrongLanguage() {
        XCTAssertEqual(NudgeTone.savage.fullLabel, "Savage · strong language")
        XCTAssertEqual(NudgeTone.direct.fullLabel, "Direct")
        XCTAssertEqual(NudgeTone.savage.note, "Strong language")
    }
}
