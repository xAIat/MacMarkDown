import AppKit
import XCTest
@testable import MacMarkDownKit

/// Headless coverage for the standard macOS text-editing commands the custom
/// view maps onto `NSResponder` selectors (`⌥←/⌥→`, Home/End, `⌥⌫`/`⌘⌫` word
/// and line deletions, fn-arrow page scrolling) and for the undo semantics of
/// model-driven edits (format commands / find & replace applied from outside
/// the view).
@MainActor
final class MarkdownTextViewStandardEditingTests: XCTestCase {

    private func makeView(width: CGFloat = 600, text: String = "") -> MarkdownTextView {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        view.string = text
        view.performFullLayoutForTesting()
        view.textLayoutManager.ensureLayout(for: view.textContentStorage.documentRange)
        return view
    }

    private func makeHostedView(text: String = "hello world\nsecond line") -> MarkdownTextView {
        let textView = makeView(text: text)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        addTeardownBlock { @MainActor [weak window] in
            window?.contentView = nil
        }
        return textView
    }

    private func caretLocation(of view: MarkdownTextView) -> Int {
        view.selectedRange().location
    }

    // MARK: - Word navigation

    func testMoveWordLeftLandsOnPreviousWordStart() {
        let view = makeView(text: "the quick brown fox")
        view.setSelectedRange(NSRange(location: 13, length: 0))
        view.moveWordLeft(nil)
        XCTAssertEqual(caretLocation(of: view), 10)
    }

    func testMoveWordRightLandsOnNextWordStart() {
        let view = makeView(text: "the quick brown fox")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.moveWordRight(nil)
        XCTAssertEqual(caretLocation(of: view), 4)
    }

    func testMoveWordLeftAndModifySelectionExtendsRange() {
        let view = makeView(text: "the quick brown fox")
        view.setSelectedRange(NSRange(location: 13, length: 0))
        view.moveWordLeftAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 10, length: 3))
    }

    func testMoveWordRightAndModifySelectionExtendsRange() {
        let view = makeView(text: "the quick brown fox")
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.moveWordRightAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 4, length: 6))
    }

    // MARK: - Paragraph navigation

    func testMoveToBeginningOfParagraph() {
        let view = makeView(text: "first\nsecond line")
        view.setSelectedRange(NSRange(location: 8, length: 0))
        view.moveToBeginningOfParagraph(nil)
        XCTAssertEqual(caretLocation(of: view), 6)
    }

    func testMoveToEndOfParagraph() {
        let view = makeView(text: "first\nsecond line")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.moveToEndOfParagraph(nil)
        XCTAssertEqual(caretLocation(of: view), 5)
    }

    // MARK: - Home / End (line ends)

    func testMoveToLeftEndOfLine() {
        let view = makeView(text: "abc\ndefg")
        view.setSelectedRange(NSRange(location: 6, length: 0))
        view.moveToLeftEndOfLine(nil)
        XCTAssertEqual(caretLocation(of: view), 4)
    }

    func testMoveToRightEndOfLine() {
        let view = makeView(text: "abc\ndefg")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.moveToRightEndOfLine(nil)
        XCTAssertEqual(caretLocation(of: view), 3)
    }

    func testMoveToLeftEndOfLineAndModifySelectionExtends() {
        let view = makeView(text: "abcdef")
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.moveToLeftEndOfLineAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 4))
    }

    // MARK: - Word / line deletion

    func testDeleteWordBackwardDeletesPrecedingWord() {
        let view = makeView(text: "the quick brown")
        view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
        view.deleteWordBackward(nil)
        XCTAssertEqual(view.string, "the quick ")
    }

    func testDeleteWordForwardDeletesFollowingWord() {
        let view = makeView(text: "the quick brown")
        view.setSelectedRange(NSRange(location: 4, length: 0))
        view.deleteWordForward(nil)
        XCTAssertEqual(view.string, "the  brown")
    }

    func testDeleteToBeginningOfLine() {
        let view = makeView(text: "abc\ndefg")
        view.setSelectedRange(NSRange(location: 6, length: 0))
        view.deleteToBeginningOfLine(nil)
        XCTAssertEqual(view.string, "abc\nfg")
    }

    func testDeleteToEndOfLine() {
        let view = makeView(text: "abc\ndefg")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.deleteToEndOfLine(nil)
        XCTAssertEqual(view.string, "a\ndefg")
    }

    // MARK: - Undo across each edit primitive

    func testDeleteWordBackwardIsUndoableAndRedoable() {
        let view = makeHostedView()
        view.setSelectedRange(NSRange(location: 11, length: 0))
        view.deleteWordBackward(nil)
        XCTAssertEqual(view.string, "hello \nsecond line")

        view.undo(nil)
        XCTAssertEqual(view.string, "hello world\nsecond line")

        view.redo(nil)
        XCTAssertEqual(view.string, "hello \nsecond line")
    }

    func testDeleteToBeginningOfLineIsUndoable() {
        let view = makeHostedView()
        view.setSelectedRange(NSRange(location: 6, length: 0))
        view.deleteToBeginningOfLine(nil)
        XCTAssertEqual(view.string, "world\nsecond line")

        view.undo(nil)
        XCTAssertEqual(view.string, "hello world\nsecond line")
    }

    // MARK: - Model-driven edits (format commands, find & replace)

    func testFormatStyleEditIsAppliedAsMinimalUndoableDiff() {
        let view = makeHostedView()
        view.setSelectedRange(NSRange(location: 0, length: 5))

        view.applyModelEdit(to: "**hello** world\nsecond line", selection: NSRange(location: 0, length: 9))
        XCTAssertEqual(view.string, "**hello** world\nsecond line")

        view.undo(nil)
        XCTAssertEqual(view.string, "hello world\nsecond line")

        view.redo(nil)
        XCTAssertEqual(view.string, "**hello** world\nsecond line")
    }

    func testInsertionStyleEditBuildsPureInsertionDiff() {
        let view = makeHostedView()
        view.setSelectedRange(NSRange(location: 5, length: 0))

        // A `newParagraph`-style edit inserts "\n\n" at the caret.
        view.applyModelEdit(to: "hello\n\n world\nsecond line", selection: NSRange(location: 7, length: 0))
        XCTAssertEqual(view.string, "hello\n\n world\nsecond line")

        view.undo(nil)
        XCTAssertEqual(view.string, "hello world\nsecond line")
    }

    func testWholesaleDocumentEditReplacesText() {
        let view = makeHostedView(text: "old content")
        view.applyModelEdit(to: "brand new document", selection: NSRange(location: 0, length: 0))
        XCTAssertEqual(view.string, "brand new document")

        // Whole-document replacement still lands on the undo stack as one step.
        view.undo(nil)
        XCTAssertEqual(view.string, "old content")
    }

    // MARK: - Undo history reset on document load

    func testResetUndoHistoryClearsUndoAndRedoStacks() {
        let view = makeHostedView()
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.insertText("Y", replacementRange: .notFound)
        XCTAssertTrue(view.undoManager?.canUndo ?? false)

        view.resetUndoHistory()
        XCTAssertFalse(view.undoManager?.canUndo ?? true)
        XCTAssertFalse(view.undoManager?.canRedo ?? true)
    }

    // MARK: - Page scrolling

    func testPageDownScrollsAndMovesCaret() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        scrollView.documentView = view
        scrollView.hasVerticalScroller = true
        view.string = (1...120).map { "line \($0)" }.joined(separator: "\n") + "\n"
        view.performFullLayoutForTesting()

        view.setSelectedRange(NSRange(location: 0, length: 0))
        let before = scrollView.contentView.bounds.origin.y
        view.pageDown(nil)
        let after = scrollView.contentView.bounds.origin.y
        XCTAssertGreaterThan(after, before)
    }

    func testPageUpAtTopStaysPut() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 120))
        scrollView.documentView = view
        view.string = (1...120).map { "line \($0)" }.joined(separator: "\n") + "\n"
        view.performFullLayoutForTesting()

        view.pageUp(nil)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, 0, accuracy: 0.5)
    }
}