import AppKit
import XCTest
@testable import MacMarkDownKit

/// Exercises the smart-editing helpers on a real `NSTextView`. Delegation
/// (typing `(` auto-closes, Return continues a list, …) is wired in
/// `MarkdownEditorView.Coordinator`, so these tests drive the helpers directly.
@MainActor
final class EditorSmartEditingTests: XCTestCase {

    private func makeTextView(_ text: String = "", selection: NSRange? = nil) -> NSTextView {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.string = text
        if let selection {
            textView.setSelectedRange(selection)
        }
        return textView
    }

    // MARK: - Matching characters

    func testAutoPairParens() {
        let textView = makeTextView(selection: NSRange(location: 0, length: 0))
        let handled = textView.completeMatchingCharacters(
            forRange: NSRange(location: 0, length: 0),
            replacementString: "(",
            strikethroughEnabled: true
        )
        XCTAssertTrue(handled)
        XCTAssertEqual(textView.string, "()")
        XCTAssertEqual(textView.selectedRange().location, 1)
    }

    func testShiftOverClosingParens() {
        let textView = makeTextView("()", selection: NSRange(location: 1, length: 0))
        let handled = textView.completeMatchingCharacters(
            forRange: NSRange(location: 1, length: 0),
            replacementString: ")",
            strikethroughEnabled: true
        )
        XCTAssertTrue(handled)
        XCTAssertEqual(textView.string, "()")
        XCTAssertEqual(textView.selectedRange().location, 2)
    }

    func testWrapSelection() {
        let textView = makeTextView("ab", selection: NSRange(location: 0, length: 2))
        let handled = textView.completeMatchingCharacters(
            forRange: NSRange(location: 0, length: 2),
            replacementString: "*",
            strikethroughEnabled: true
        )
        XCTAssertTrue(handled)
        XCTAssertEqual(textView.string, "*ab*")
    }

    func testDeleteMatchingCharacters() {
        let textView = makeTextView("()", selection: NSRange(location: 1, length: 0))
        XCTAssertTrue(textView.deleteMatchingCharactersAround(1))
        XCTAssertEqual(textView.string, "")
    }

    // MARK: - Tab / indentation

    func testInsertSpacesForTabAlignsToTabStop() {
        let textView = makeTextView("ab", selection: NSRange(location: 2, length: 0))
        textView.insertSpacesForTab()
        XCTAssertEqual(textView.string, "ab  ")
        XCTAssertEqual(textView.selectedRange().location, 4)
    }

    func testUnindentForSpacesBefore() {
        let textView = makeTextView("    foo", selection: NSRange(location: 4, length: 0))
        XCTAssertTrue(textView.unindentForSpacesBefore(4))
        XCTAssertEqual(textView.string, "foo")
    }

    // MARK: - Return-key continuation

    func testCompleteNextListItemContinues() {
        let textView = makeTextView("1. foo", selection: NSRange(location: 6, length: 0))
        XCTAssertTrue(textView.completeNextListItem(autoIncrement: true))
        XCTAssertEqual(textView.string, "1. foo\n2. ")
    }

    func testCompleteNextListItemWithoutIncrement() {
        let textView = makeTextView("1. foo", selection: NSRange(location: 6, length: 0))
        XCTAssertTrue(textView.completeNextListItem(autoIncrement: false))
        XCTAssertEqual(textView.string, "1. foo\n1. ")
    }

    func testCompleteNextUnorderedItem() {
        let textView = makeTextView("- foo", selection: NSRange(location: 5, length: 0))
        XCTAssertTrue(textView.completeNextListItem(autoIncrement: false))
        XCTAssertEqual(textView.string, "- foo\n- ")
    }

    func testCompleteNextItemExitsEmptyList() {
        let textView = makeTextView("- ", selection: NSRange(location: 2, length: 0))
        XCTAssertTrue(textView.completeNextListItem(autoIncrement: false))
        XCTAssertEqual(textView.string, "\n")
    }

    func testCompleteNextBlockquoteLine() {
        let textView = makeTextView("> foo", selection: NSRange(location: 5, length: 0))
        XCTAssertTrue(textView.completeNextBlockquoteLine())
        XCTAssertEqual(textView.string, "> foo\n> ")
    }

    func testCompleteNextIndentedLine() {
        let textView = makeTextView("    foo", selection: NSRange(location: 7, length: 0))
        XCTAssertTrue(textView.completeNextIndentedLine())
        XCTAssertEqual(textView.string, "    foo\n    ")
    }

    // MARK: - Smart home

    func testSmartHomeMovesToFirstNonWhitespace() {
        let textView = makeTextView("    foo", selection: NSRange(location: 7, length: 0))
        XCTAssertEqual(textView.smartHomeLocation(), 4)
    }

    func testSmartHomeReturnsNilWhenAlreadyThere() {
        let textView = makeTextView("foo", selection: NSRange(location: 0, length: 0))
        XCTAssertNil(textView.smartHomeLocation())
    }
}