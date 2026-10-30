import XCTest
@testable import TrueFocusKit

final class NoteFormattingTests: XCTestCase {
    func testEveryStyleRoundTrips() {
        let markup = """
        Plan
        ## Heading
        ### Subheading
        plain
        ` let x = 1
        - bullet
        – dashed
        1. first
        2. second
        > quoted
        - [ ] open
        - [x] done
        """
        let document = NoteDocument(markup: markup)
        XCTAssertEqual(document.lines.map(\.kind), [.title, .heading, .subheading, .text, .mono, .bullet, .dashed,
                                                    .numbered, .numbered, .quote,
                                                    .checklist(done: false), .checklist(done: true)])
        XCTAssertEqual(document.lines[4].text, "let x = 1")
        XCTAssertEqual(document.lines[8].text, "second")
        XCTAssertEqual(document.markup, markup)
    }

    func testIndentIsTabsAndRoundTrips() {
        let markup = "Trip\n- pack\n\t- passport\n\t\t- [ ] visa\n\tback to one"
        let document = NoteDocument(markup: markup)
        XCTAssertEqual(document.lines.map(\.indent), [0, 0, 1, 2, 1])
        XCTAssertEqual(document.lines[3].kind, .checklist(done: false))
        XCTAssertEqual(document.markup, markup)
    }

    func testNumbersCountPerIndentAndRestartAfterABreak() {
        let document = NoteDocument(lines: [
            NoteLine(.title, "T"),
            NoteLine(.numbered, "a"),
            NoteLine(.numbered, "a.1", indent: 1),
            NoteLine(.numbered, "a.2", indent: 1),
            NoteLine(.numbered, "b"),
            NoteLine(.text, "break"),
            NoteLine(.numbered, "again"),
        ])
        XCTAssertEqual(document.listNumbers, [1, 1, 1, 2, 2, 1, 1])
        XCTAssertEqual(document.markup, "T\n1. a\n\t1. a.1\n\t2. a.2\n2. b\nbreak\n1. again")
    }

    func testOldNotesReadTheSame() {
        let markup = "Groceries\n## Today\n- milk\n- [ ] eggs\n- [x] bread\nnotes"
        XCTAssertEqual(NoteDocument(markup: markup).markup, markup)
        XCTAssertEqual(NoteDocument(markup: markup).openChecklistItems, ["eggs"])
    }

    func testIndentIsClamped() {
        XCTAssertEqual(NoteLine(.bullet, "x", indent: 9).indent, NoteLine.maxIndent)
        XCTAssertEqual(NoteLine(.bullet, "x", indent: -2).indent, 0)
    }
}
