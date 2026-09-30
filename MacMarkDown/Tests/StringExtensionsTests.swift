import XCTest
@testable import MacMarkDownKit

final class StringExtensionsTests: XCTestCase {

    func testWordCount() {
        XCTAssertEqual("hello world".wordCount, 2)
        XCTAssertEqual("".wordCount, 0)
        XCTAssertEqual("one  two   three".wordCount, 3)
    }

    func testCharacterCountNoSpaces() {
        XCTAssertEqual("ab cd".characterCountNoSpaces, 4)
        XCTAssertEqual("  ".characterCountNoSpaces, 0)
    }

    func testLocationOfFirstNewline() {
        let text = "line1\nline2\nline3"
        XCTAssertEqual(text.locationOfFirstNewlineBefore(7), 5)
        XCTAssertEqual(text.locationOfFirstNewlineAfter(6), 11)
        XCTAssertEqual(text.locationOfFirstNewlineAfter(4), 5)
    }

    func testTitleString() {
        XCTAssertEqual("# Title\nBody".titleString, "Title")
        XCTAssertEqual("   \n# Title".titleString, "Title")
        // Highest-ranked heading wins: `# Shallow` outranks `### Deep`.
        XCTAssertEqual("### Deep\n# Shallow".titleString, "Shallow")
        XCTAssertEqual("### Only".titleString, "Only")
        XCTAssertNil("Hello\nWorld".titleString)
    }

    func testFirstHeading() {
        XCTAssertEqual("# Title\nbody".firstHeading, "Title")
        XCTAssertNil("body only".firstHeading)
    }
}