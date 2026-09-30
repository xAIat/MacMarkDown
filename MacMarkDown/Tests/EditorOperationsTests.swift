import XCTest
@testable import MacMarkDownKit

final class EditorOperationsTests: XCTestCase {

    func testToggleStrong() {
        // "world" is already wrapped in `**`, so toggling removes the markup.
        let text = "Hello **world**"
        let range = text.range(of: "world")!
        let (result, newRange) = EditorOperations.toggleMarkup(
            in: text, selectedRange: range, prefix: "**", suffix: "**"
        )
        XCTAssertEqual(result, "Hello world")
        XCTAssertEqual(String(result[newRange]), "world")
    }

    func testToggleStrongOnPlainText() {
        let text = "Hello world"
        let range = text.range(of: "world")!
        let (result, newRange) = EditorOperations.toggleMarkup(
            in: text, selectedRange: range, prefix: "**", suffix: "**"
        )
        XCTAssertEqual(result, "Hello **world**")
        XCTAssertEqual(String(result[newRange]), "world")
    }

    func testToggleMarkupOnEmptySelection() {
        let text = ""
        let range = text.startIndex..<text.startIndex
        let (result, newRange) = EditorOperations.toggleMarkup(
            in: text, selectedRange: range, prefix: "**", suffix: "**"
        )
        XCTAssertEqual(result, "****")
        XCTAssertEqual(result.distance(from: result.startIndex, to: newRange.lowerBound), 2)
        XCTAssertEqual(newRange.lowerBound, newRange.upperBound)
    }

    func testToggleBlockquote() {
        let text = "> quoted line\nnormal line"
        let range = text.startIndex..<text.index(text.startIndex, offsetBy: 13)
        let (result, _) = EditorOperations.toggleBlock(
            in: text, selectedRange: range, pattern: #"^> \S"#, prefix: "> "
        )
        // Removes prefix from the first line only
        XCTAssertTrue(result.contains("quoted line"))
    }

    func testIndentUnindent() {
        let text = "line1\nline2"
        let range = text.startIndex..<text.endIndex
        let (indented, _) = EditorOperations.indentLines(in: text, selectedRange: range, padding: "    ")
        XCTAssertEqual(indented, "    line1\n    line2")

        let (unindented, _) = EditorOperations.unindentLines(in: indented, selectedRange: range)
        XCTAssertEqual(unindented, "line1\nline2")
    }

    func testUnindentWithCaretInsideIndentation() {
        // Shift+Tab with the caret inside a line's leading spaces used to
        // produce `lowerBound > upperBound` and crash.
        let text = "    foo"
        let caret = text.index(text.startIndex, offsetBy: 4)
        let (result, newRange) = EditorOperations.unindentLines(in: text, selectedRange: caret..<caret)
        XCTAssertEqual(result, "foo")
        XCTAssertEqual(newRange.lowerBound, result.startIndex)
        XCTAssertEqual(newRange.upperBound, result.startIndex)
    }

    func testUnindentWithCaretInMiddleOfIndentation() {
        let text = "    foo"
        let caret = text.index(text.startIndex, offsetBy: 2)
        let (result, newRange) = EditorOperations.unindentLines(in: text, selectedRange: caret..<caret)
        XCTAssertEqual(result, "foo")
        XCTAssertEqual(newRange.lowerBound, result.startIndex)
        XCTAssertEqual(newRange.upperBound, result.startIndex)
    }

    func testUnindentWithTabIndentAndCaret() {
        let text = "\tfoo"
        let caret = text.index(text.startIndex, offsetBy: 1)
        let (result, newRange) = EditorOperations.unindentLines(in: text, selectedRange: caret..<caret)
        XCTAssertEqual(result, "foo")
        XCTAssertEqual(newRange.lowerBound, result.startIndex)
        XCTAssertEqual(newRange.upperBound, result.startIndex)
    }

    func testUnindentKeepsSelectionOnContent() {
        let text = "    foo"
        let lower = text.index(text.startIndex, offsetBy: 4)
        let upper = text.index(text.startIndex, offsetBy: 7)
        let (result, newRange) = EditorOperations.unindentLines(in: text, selectedRange: lower..<upper)
        XCTAssertEqual(result, "foo")
        XCTAssertEqual(String(result[newRange]), "foo")
    }

    func testUnindentMultilineSelectionRange() {
        let text = "    a\n    b"
        let lower = text.index(text.startIndex, offsetBy: 2)
        let upper = text.index(text.startIndex, offsetBy: 11)
        let (result, newRange) = EditorOperations.unindentLines(in: text, selectedRange: lower..<upper)
        XCTAssertEqual(result, "a\nb")
        XCTAssertEqual(String(result[newRange]), "a\nb")
    }

    func testUnindentWithoutIndentationIsNoOp() {
        let text = "foo"
        let caret = text.index(text.startIndex, offsetBy: 1)
        let (result, newRange) = EditorOperations.unindentLines(in: text, selectedRange: caret..<caret)
        XCTAssertEqual(result, "foo")
        XCTAssertEqual(newRange.lowerBound, result.index(result.startIndex, offsetBy: 1))
        XCTAssertEqual(newRange.upperBound, newRange.lowerBound)
    }

    func testSetHeaderLevel() {
        let text = "Hello World"
        let range = text.startIndex..<text.endIndex
        let (h1, _) = EditorOperations.setHeaderLevel(in: text, selectedRange: range, level: 1)
        XCTAssertEqual(h1, "# Hello World")

        let (h3, _) = EditorOperations.setHeaderLevel(in: h1, selectedRange: range, level: 3)
        XCTAssertEqual(h3, "### Hello World")
    }
}