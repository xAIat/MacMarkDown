import XCTest

@testable import MacMarkDownKit

@MainActor
final class FindControllerTests: XCTestCase {

    private func makeController(text: String, query: String) -> FindController {
        let find = FindController()
        find.updateText(text)
        find.query = query
        return find
    }

    func testFindsAllMatches() {
        let find = makeController(text: "one two one two one", query: "one")
        XCTAssertEqual(find.matches.count, 3)
        XCTAssertEqual(find.matches.first, NSRange(location: 0, length: 3))
    }

    func testCaseSensitivity() {
        let insensitive = makeController(text: "One ONE one", query: "one")
        XCTAssertEqual(insensitive.matches.count, 3)

        let sensitive = makeController(text: "One ONE one", query: "one")
        sensitive.caseSensitive = true
        XCTAssertEqual(sensitive.matches.count, 1)
        XCTAssertEqual(sensitive.matches.first, NSRange(location: 8, length: 3))
    }

    func testNextWrapsAround() {
        let find = makeController(text: "a a a", query: "a")
        XCTAssertEqual(find.nextMatch()?.location, 0)
        XCTAssertEqual(find.nextMatch()?.location, 2)
        XCTAssertEqual(find.nextMatch()?.location, 4)
        XCTAssertEqual(find.nextMatch()?.location, 0)
    }

    func testPreviousWrapsAround() {
        let find = makeController(text: "a a a", query: "a")
        XCTAssertEqual(find.previousMatch()?.location, 4)
        XCTAssertEqual(find.previousMatch()?.location, 2)
        XCTAssertEqual(find.previousMatch()?.location, 0)
        XCTAssertEqual(find.previousMatch()?.location, 4)
    }

    func testNextAfterCaret() {
        let find = makeController(text: "a a a", query: "a")
        XCTAssertEqual(find.nextMatch(after: 0)?.location, 2)
        XCTAssertEqual(find.nextMatch(after: 4)?.location, 0)
    }

    func testPreviousBeforeCaret() {
        let find = makeController(text: "a a a", query: "a")
        XCTAssertEqual(find.previousMatch(before: 4)?.location, 2)
        XCTAssertEqual(find.previousMatch(before: 0)?.location, 4)
    }

    func testMatchAtCaret() {
        let find = makeController(text: "hello world", query: "world")
        XCTAssertEqual(find.match(at: 7), NSRange(location: 6, length: 5))
        XCTAssertNil(find.match(at: 0))
    }

    func testNoMatches() {
        let find = makeController(text: "hello", query: "zzz")
        XCTAssertTrue(find.matches.isEmpty)
        XCTAssertNil(find.nextMatch())
    }

    func testEmptyQueryClearsMatches() {
        let find = makeController(text: "hello", query: "l")
        XCTAssertEqual(find.matches.count, 2)
        find.query = ""
        XCTAssertTrue(find.matches.isEmpty)
    }

    func testReplaceCurrent() {
        let find = makeController(text: "one two one", query: "one")
        find.replacement = "1"
        _ = find.nextMatch() // selects the first match
        let result = find.replaceCurrent(in: "one two one")
        XCTAssertEqual(result?.text, "1 two one")
        XCTAssertEqual(result?.selection, NSRange(location: 1, length: 0))
    }

    func testReplaceAll() {
        let find = makeController(text: "one two one", query: "one")
        find.replacement = "1"
        let result = find.replaceAll(in: "one two one")
        XCTAssertEqual(result?.text, "1 two 1")
        XCTAssertEqual(result?.count, 2)
    }

    func testReplaceAllWithoutMatchesReturnsNil() {
        let find = makeController(text: "hello", query: "zzz")
        XCTAssertNil(find.replaceAll(in: "hello"))
    }

    func testUpdateTextKeepsSelectionWithinBounds() {
        let find = makeController(text: "a a a", query: "a")
        _ = find.nextMatch()
        _ = find.nextMatch()
        _ = find.nextMatch() // index 2 (last)
        find.updateText("a")
        XCTAssertEqual(find.currentIndex, 0)
    }
}