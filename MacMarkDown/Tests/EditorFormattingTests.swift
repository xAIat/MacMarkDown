import XCTest

@testable import MacMarkDownKit

/// The Format menu and the toolbar share `EditorFormatting`; these tests pin
/// down the command semantics and the UTF-16 ↔ `String.Index` bridge.
final class EditorFormattingTests: XCTestCase {

    private func apply(
        _ command: EditorFormatCommand,
        text: String,
        selection: NSRange
    ) -> (text: String, selection: NSRange)? {
        EditorFormatting.apply(command, to: text, selection: selection)
    }

    func testStrongWrapsSelection() {
        let result = apply(.strong, text: "hello world", selection: NSRange(location: 6, length: 5))
        XCTAssertEqual(result?.text, "hello **world**")
        XCTAssertEqual(result?.selection, NSRange(location: 8, length: 5))
    }

    func testEmphasisWrapsSelectionWithSingleAsterisks() {
        let result = apply(.emphasis, text: "hello", selection: NSRange(location: 0, length: 5))
        XCTAssertEqual(result?.text, "*hello*")
        XCTAssertEqual(result?.selection, NSRange(location: 1, length: 5))
    }

    func testStrongWrapsSelectionWithDoubleAsterisks() {
        let result = apply(.strong, text: "hello", selection: NSRange(location: 0, length: 5))
        XCTAssertEqual(result?.text, "**hello**")
    }

    func testEmphasisTogglesOff() {
        let result = apply(.emphasis, text: "a *b* c", selection: NSRange(location: 3, length: 1))
        XCTAssertEqual(result?.text, "a b c")
    }

    func testInlineCode() {
        let result = apply(.inlineCode, text: "run it", selection: NSRange(location: 4, length: 2))
        XCTAssertEqual(result?.text, "run `it`")
    }

    func testUnderlineWrapsAndUnwraps() {
        let wrapped = apply(.underline, text: "hello world", selection: NSRange(location: 6, length: 5))
        XCTAssertEqual(wrapped?.text, "hello _world_")
        let unwrapped = apply(.underline, text: "hello _world_", selection: NSRange(location: 7, length: 5))
        XCTAssertEqual(unwrapped?.text, "hello world")
    }

    func testHighlightWrapsSelection() {
        let result = apply(.highlight, text: "mark this", selection: NSRange(location: 5, length: 4))
        XCTAssertEqual(result?.text, "mark ==this==")
    }

    func testCommentWrapsSelection() {
        let result = apply(.comment, text: "hide me", selection: NSRange(location: 0, length: 7))
        XCTAssertEqual(result?.text, "<!--hide me-->")
    }

    func testHeadingLevels() {
        let h1 = apply(.h1, text: "Title", selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(h1?.text, "# Title")
        let paragraph = apply(.paragraph, text: "## Title", selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(paragraph?.text, "Title")
    }

    func testBlockquoteToggles() {
        let quoted = apply(.blockquote, text: "line", selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(quoted?.text, "> line")
        let unquoted = apply(.blockquote, text: "> line", selection: NSRange(location: 2, length: 0))
        XCTAssertEqual(unquoted?.text, "line")
    }

    func testUnorderedListUsesConfiguredMarker() {
        let result = EditorFormatting.apply(
            .unorderedList,
            to: "item",
            selection: NSRange(location: 0, length: 0),
            listMarker: "+ "
        )
        XCTAssertEqual(result?.text, "+ item")
    }

    func testIndentUnindent() {
        let indented = apply(.indent, text: "a\nb", selection: NSRange(location: 0, length: 3))
        XCTAssertEqual(indented?.text, "    a\n    b")
        let unindented = apply(.unindent, text: "    a\n    b", selection: NSRange(location: 0, length: 11))
        XCTAssertEqual(unindented?.text, "a\nb")
    }

    func testNewParagraphInsertsBlankLine() {
        let result = apply(.newParagraph, text: "one", selection: NSRange(location: 3, length: 0))
        XCTAssertEqual(result?.text, "one\n\n")
        XCTAssertEqual(result?.selection, NSRange(location: 5, length: 0))
    }

    func testCJKSelectionUsesUTF16Offsets() {
        // Each character is one UTF-16 unit; the selection must survive.
        let result = apply(.strong, text: "你好 世界", selection: NSRange(location: 3, length: 2))
        XCTAssertEqual(result?.text, "你好 **世界**")
        XCTAssertEqual(result?.selection, NSRange(location: 5, length: 2))
    }

    func testEmojiSelectionUsesUTF16Offsets() {
        // "🙂" is two UTF-16 units; an NSRange selection from the editor is in
        // those units and must map to the right character range.
        let text = "a🙂b"
        let selection = NSRange(location: 1, length: 2)
        let result = apply(.strong, text: text, selection: selection)
        XCTAssertEqual(result?.text, "a**🙂**b")
    }

    func testInvalidSelectionReturnsNil() {
        XCTAssertNil(apply(.strong, text: "x", selection: NSRange(location: 99, length: 0)))
    }
}