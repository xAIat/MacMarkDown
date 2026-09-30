import XCTest
import AppKit
@testable import MacMarkDownKit

/// Headless coverage for the custom TextKit 2 editor stack (Phase 3,
/// Milestone 1). These tests drive `MarkdownTextView` without a window; every
/// code path exercised here is the same viewport/layout pipeline the app
/// renders with.
@MainActor
final class MarkdownTextViewTests: XCTestCase {

    private func makeView(width: CGFloat = 600, text: String = "") -> MarkdownTextView {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        view.string = text
        return view
    }

    // MARK: - Document surface

    func testStringRoundTrip() {
        let view = makeView(text: "Hello\nWorld")
        XCTAssertEqual(view.string, "Hello\nWorld")

        view.string = "bye"
        XCTAssertEqual(view.string, "bye")
    }

    func testSetStringStampsAttributes() {
        let view = makeView(text: "plain")
        view.font = NSFont(name: "Menlo", size: 18)
            ?? .monospacedSystemFont(ofSize: 18, weight: .regular)
        view.performFullLayoutForTesting()

        let attrs = view.textStorage?.attributes(at: 0, effectiveRange: nil)
        XCTAssertNotNil(attrs)
        XCTAssertEqual((attrs?[.font] as? NSFont)?.pointSize, 18)
    }

    func testExposesTextStorageForHighlighter() {
        let view = makeView(text: "# Heading")
        XCTAssertNotNil(view.textStorage)
        XCTAssertGreaterThan(view.textStorage?.length ?? 0, 0)
    }

    // MARK: - Layout & measurement

    func testEmptyDocumentLaysOut() {
        let view = makeView()
        view.performFullLayoutForTesting()
        XCTAssertTrue(view.textLayoutManager.documentRange.isEmpty)
    }

    func testDocumentMeasuresAndGrowsView() {
        let body = [
            "# Heading",
            "",
            "Some **bold** paragraph with a fairly long line that ought to wrap",
            "around onto a second row inside the width budget.",
            "",
            "| a | b |",
            "| - | - |",
            "| c | d |"
        ].joined(separator: "\n")

        let view = makeView(width: 500, text: body + "\n")
        view.performFullLayoutForTesting()

        XCTAssertEqual(view.string, body + "\n")
        XCTAssertGreaterThan(view.textLayoutManager.usageBoundsForTextContainer.height, 0)
        XCTAssertGreaterThan(view.frame.height, 0)
    }

    /// Replacing the document must grow the view immediately, without waiting
    /// for an explicit layout pass: a drag & drop can otherwise leave the
    /// editor at the previous (empty) height showing only the first line.
    func testSetStringGrowsViewWithoutExplicitLayout() {
        let view = makeView(width: 500, text: "")
        view.performFullLayoutForTesting()
        let emptyHeight = view.frame.height

        let body = (1...200).map { "line \($0)" }.joined(separator: "\n") + "\n"
        view.string = body

        XCTAssertGreaterThan(
            view.frame.height, emptyHeight,
            "setString must relayout so the document view grows to fit the text"
        )
    }

    func testWrappingHonorsContainerWidth() {
        // 40 'W' characters in a 200pt column must produce at least two text
        // layout fragments (a long line + the trailing empty line), proving
        // the container width reaches the layout manager.
        let view = makeView(width: 200, text: String(repeating: "W", count: 40) + "\n")
        view.performFullLayoutForTesting()

        XCTAssertGreaterThan(
            view.textLayoutManager.usageBoundsForTextContainer.width, 0
        )
    }

    func testViewportProducesFragmentViews() {
        let view = makeView(text: "line one\nline two\nline three\n")
        view.performFullLayoutForTesting()
        XCTAssertGreaterThan(view.renderedFragmentViews.count, 0)
    }
}

/// Phase 3, Milestone 2: the editing core (input client, insertion point,
/// standard editing commands). Most of these drive the NSTextInputClient entry
/// points directly; the insertion-point test needs a real window.
@MainActor
final class MarkdownTextViewEditingTests: XCTestCase {

    private func makeView(width: CGFloat = 600, text: String = "") -> MarkdownTextView {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        view.string = text
        return view
    }

    private func caretLocation(of view: MarkdownTextView) -> Int {
        view.selectedRange().location
    }

    // MARK: - Plain input

    func testInsertTextAppendsAndMovesCaret() {
        let view = makeView()
        view.insertText("H", replacementRange: .notFound)
        view.insertText("i", replacementRange: .notFound)
        XCTAssertEqual(view.string, "Hi")
        XCTAssertEqual(caretLocation(of: view), 2)
    }

    func testInsertTextRespectsCaretPosition() {
        let view = makeView(text: "ab")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.insertText("X", replacementRange: .notFound)
        XCTAssertEqual(view.string, "aXb")
        XCTAssertEqual(caretLocation(of: view), 2)
    }

    func testTypedTextCarriesTypingAttributes() {
        let view = makeView()
        view.insertText("x", replacementRange: .notFound)
        let font = view.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        XCTAssertEqual(font?.pointSize, 14)
    }

    func testInsertNewlineInsertsParagraph() {
        let view = makeView(text: "a")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.insertNewline(nil)
        XCTAssertEqual(view.string, "a\n")
        XCTAssertGreaterThan(caretLocation(of: view), 1)
    }

    func testInsertTabInsertsTab() {
        let view = makeView(text: "a")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.insertTab(nil)
        XCTAssertEqual(view.string, "a\t")
    }

    // MARK: - Deletion

    func testDeleteBackwardRemovesPrecedingCharacter() {
        let view = makeView(text: "Hi")
        view.setSelectedRange(NSRange(location: 2, length: 0))
        view.deleteBackward(nil)
        XCTAssertEqual(view.string, "H")
        XCTAssertEqual(caretLocation(of: view), 1)
    }

    func testDeleteForwardRemovesCharacterAfterCaret() {
        let view = makeView(text: "Hi")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.deleteForward(nil)
        XCTAssertEqual(view.string, "i")
        XCTAssertEqual(caretLocation(of: view), 0)
    }

    func testDeleteAtDocumentStartIsNoop() {
        let view = makeView(text: "Hi")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.deleteBackward(nil)
        XCTAssertEqual(view.string, "Hi")
    }

    // MARK: - Movement

    func testMoveRightAndLeft() {
        let view = makeView(text: "abc")
        view.moveLeft(nil)
        XCTAssertEqual(caretLocation(of: view), 2)
        view.moveRight(nil)
        XCTAssertEqual(caretLocation(of: view), 3)
        view.moveRight(nil)
        XCTAssertEqual(caretLocation(of: view), 3)
        view.moveToBeginningOfDocument(nil)
        XCTAssertEqual(caretLocation(of: view), 0)
    }

    func testMoveToEndOfLine() {
        let view = makeView(text: "foo bar\nbaz")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.moveToEndOfLine(nil)
        XCTAssertEqual(caretLocation(of: view), 7)
        view.insertText("X", replacementRange: .notFound)
        XCTAssertEqual(view.string, "foo barX\nbaz")
    }

    func testMoveToBeginningOfLine() {
        let view = makeView(text: "foo bar\nbaz")
        view.setSelectedRange(NSRange(location: 10, length: 0))
        view.moveToBeginningOfLine(nil)
        XCTAssertEqual(caretLocation(of: view), 8)
    }

    // MARK: - Marked text (IME)

    func testSetMarkedTextInsertsProvisionalText() {
        let view = makeView(text: "a")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 1, length: 0))
        XCTAssertEqual(view.string, "ani")
        XCTAssertTrue(view.hasMarkedText())
        XCTAssertEqual(view.markedRange(), NSRange(location: 1, length: 2))
    }

    func testSetMarkedTextReplacesReplacementRange() {
        let view = makeView(text: "abc")
        view.setMarkedText("XY", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 1, length: 1))
        XCTAssertEqual(view.string, "aXYc")
        XCTAssertEqual(view.markedRange(), NSRange(location: 1, length: 2))
    }

    func testMarkedTextUpdatesInPlace() {
        let view = makeView(text: "a")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 1, length: 0))
        view.setMarkedText("nichi", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 1, length: 2))
        XCTAssertEqual(view.string, "anichi")
        XCTAssertEqual(view.markedRange(), NSRange(location: 1, length: 5))
    }

    func testUnmarkThenInsertCommitsText() {
        let view = makeView(text: "q")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: 1, length: 0))
        XCTAssertTrue(view.hasMarkedText())
        // IME commits: it removes the provisional text and sinks the final string.
        view.unmarkText()
        XCTAssertFalse(view.hasMarkedText())
        view.insertText("你", replacementRange: .notFound)
        XCTAssertEqual(view.string, "q你")
    }

    // MARK: - Insertion point

    func testInsertionPointAppearsForFirstResponder() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.string = "hello"
        window.contentView = view
        window.makeKeyAndOrderFront(nil)

        guard window.makeFirstResponder(view) else {
            window.orderOut(nil)
            throw XCTSkip("No window server available in this test environment")
        }

        view.forcesInsertionPointDrawForTesting = true
        view.performFullLayoutForTesting()
        XCTAssertGreaterThan(view.insertionPointViews.count, 0)
        window.orderOut(nil)
    }

    func testInsertionPointHiddenWithoutResponder() {
        let view = makeView(text: "hello")
        view.performFullLayoutForTesting()
        view.updateInsertionPointStateAndRestartTimer()
        XCTAssertEqual(view.insertionPointViews.count, 0)
    }

    func testSelectedRangeClampsToDocument() {
        let view = makeView(text: "abc")
        view.setSelectedRange(NSRange(location: 99, length: 5))
        XCTAssertEqual(caretLocation(of: view), 3)
        view.setSelectedRange(NSRange(location: 1, length: 99))
        XCTAssertEqual(view.selectedRange(), NSRange(location: 1, length: 2))
    }
}

/// Headless coverage for Phase 3 Milestone 3: selection rendering rects and
/// the pointer/keyboard interactions that drive them.
@MainActor
final class MarkdownTextViewSelectionTests: XCTestCase {

    private func makeView(width: CGFloat = 600, text: String = "") -> MarkdownTextView {
        let view = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: width, height: 400))
        view.string = text
        view.performFullLayoutForTesting()
        view.textLayoutManager.ensureLayout(for: view.textContentStorage.documentRange)
        return view
    }

    /// Content-space point at the center of the character at `offset`.
    private func contentPoint(of offset: Int, in view: MarkdownTextView) -> NSPoint {
        var frame: CGRect = .zero
        if let range = view.textContentStorage.textRange(from: NSRange(location: offset, length: 1)) {
            view.textLayoutManager.enumerateTextSegments(in: range, type: .standard) { _, segmentFrame, _, _ in
                frame = segmentFrame
                return true
            }
        }
        return NSPoint(x: frame.midX, y: frame.midY)
    }

    private func caretLocation(of view: MarkdownTextView) -> Int {
        view.selectedRange().location
    }

    // MARK: - Selection rects

    func testCaretProducesNoSelectionRects() {
        let view = makeView(text: "hello")
        view.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertTrue(view.textSelectionRects.isEmpty)
    }

    func testSelectedRangeProducesSelectionRects() {
        let view = makeView(text: "hello world")
        view.setSelectedRange(NSRange(location: 0, length: 5))
        let rects = view.textSelectionRects
        XCTAssertFalse(rects.isEmpty)
        XCTAssertTrue(rects.allSatisfy { !$0.isNull && $0.width > 0 && $0.height > 0 })
    }

    // MARK: - Pointer helpers

    func testCaretSelectionAtPointLandsInsideCharacter() {
        let view = makeView(text: "hello world")
        let point = contentPoint(of: 4, in: view)
        let caret = try? XCTUnwrap(view.caretSelection(at: point))
        let offset = caret.map { view.textContentStorage.offset(from: view.textContentStorage.documentRange.location, to: $0.textRanges.first!.location) }
        XCTAssertNotNil(offset)
        XCTAssertTrue((2...5).contains(offset ?? -1), "caret offset \(String(describing: offset)) should land near character 4")
    }

    func testWordSelectionEnclosingPoint() {
        let view = makeView(text: "hello brave world")
        let point = contentPoint(of: 8, in: view)
        let selection = view.selectionForGranularity(.word, at: point)
        XCTAssertEqual(view.selectedRangeForTest(selection), NSRange(location: 6, length: 5))
    }

    func testParagraphSelectionEnclosingPoint() {
        let view = makeView(text: "hello brave world")
        let point = contentPoint(of: 3, in: view)
        let selection = view.selectionForGranularity(.paragraph, at: point)
        XCTAssertEqual(view.selectedRangeForTest(selection), NSRange(location: 0, length: 17))
    }

    func testMarqueeSelectionFromAnchor() {
        let view = makeView(text: "hello world")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        let anchor = try? XCTUnwrap(view.textLayoutManager.textSelections.first)
        let point = contentPoint(of: 6, in: view)
        let marquee = anchor.flatMap { view.marqueeSelection(from: point, anchor: $0) }
        XCTAssertEqual(view.selectedRangeForTest(marquee), NSRange(location: 0, length: 6))
    }

    // MARK: - Keyboard extension

    func testMoveLeftAndModifySelectionExtendsRange() {
        let view = makeView(text: "abcde")
        view.setSelectedRange(NSRange(location: 3, length: 0))
        view.moveLeftAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 2, length: 1))
    }

    func testMoveRightAndModifySelectionExtendsRange() {
        let view = makeView(text: "abcde")
        view.setSelectedRange(NSRange(location: 1, length: 0))
        view.moveRightAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 1, length: 1))
    }

    func testMoveToEndOfDocumentAndModifySelectionSelectsAll() {
        let view = makeView(text: "abc\ndef")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.moveToEndOfDocumentAndModifySelection(nil)
        XCTAssertEqual(view.selectedRange(), NSRange(location: 0, length: 7))
    }

    // MARK: - Vertical movement

    func testMoveDownThenUpKeepsColumn() {
        let view = makeView(text: "aaa\nbbb\nccc")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.moveDown(nil)
        let afterDown = caretLocation(of: view)
        XCTAssertTrue((2...4).contains(afterDown), "down offset \(afterDown)")
        view.moveUp(nil)
        XCTAssertEqual(caretLocation(of: view), 0)
    }

    func testMoveDownAtLastLineStaysPut() {
        let view = makeView(text: "aaa\nbbb")
        let end = view.textContentStorage.documentLength
        view.setSelectedRange(NSRange(location: end, length: 0))
        view.moveDown(nil)
        XCTAssertEqual(caretLocation(of: view), end)
    }

    // MARK: - Dropped image inlining

    func testBase64ImageMarkdownForPNG() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-test.png")
        // 1x1 transparent PNG.
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        try Data(base64Encoded: pngBase64)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let markdown = MarkdownTextView.base64ImageMarkdown(for: url)
        XCTAssertNotNil(markdown)
        XCTAssertTrue(markdown!.hasPrefix("![drop-test](data:image/"))
        XCTAssertTrue(markdown!.contains(";base64,"))
    }

    func testBase64ImageMarkdownRejectsNonImage() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("drop-test.txt")
        try Data("hello".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(MarkdownTextView.base64ImageMarkdown(for: url))
    }
}

/// Regression coverage for pointer selection dispatched through a real window:
/// a click lands on the fragment views, and the drag must extend the selection
/// even though the hit view is not the text view itself.
@MainActor
final class MarkdownTextViewPointerSelectionTests: XCTestCase {

    private func makeHost() -> (NSWindow, MarkdownTextView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.hasVerticalScroller = true
        let host = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = host
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        host.string = "hello world"
        host.performFullLayoutForTesting()
        host.textLayoutManager.ensureLayout(for: host.textContentStorage.documentRange)
        return (window, host)
    }

    /// Leading edge of the character at `offset`, so caret resolution is
    /// deterministic (a mid-glyph x can resolve to either side).
    private func contentPoint(of offset: Int, in host: MarkdownTextView) -> NSPoint {
        var frame: CGRect = .zero
        if let range = host.textContentStorage.textRange(from: NSRange(location: offset, length: 1)) {
            host.textLayoutManager.enumerateTextSegments(in: range, type: .standard) { _, segmentFrame, _, _ in
                frame = segmentFrame
                return true
            }
        }
        return NSPoint(x: frame.minX + 0.5, y: frame.midY)
    }

    private func send(
        _ type: NSEvent.EventType,
        at contentPoint: NSPoint,
        in host: MarkdownTextView,
        window: NSWindow,
        clickCount: Int = 1
    ) {
        let viewPoint = NSPoint(
            x: contentPoint.x + host.textContainerOrigin.x,
            y: contentPoint.y + host.textContainerOrigin.y
        )
        let windowPoint = host.convert(viewPoint, to: nil)
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: windowPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: clickCount,
            pressure: 1
        ) else {
            XCTFail("could not create \(type) event")
            return
        }
        // A headless test window never becomes key, so AppKit's own dispatch
        // swallows the click. Route it to the hit view the way the window
        // would: the default NSView forwarding carries it up to the text view.
        let hitView = host.hitTest(viewPoint) ?? host
        switch type {
        case .leftMouseDown: hitView.mouseDown(with: event)
        case .leftMouseDragged: hitView.mouseDragged(with: event)
        case .leftMouseUp: hitView.mouseUp(with: event)
        default: break
        }
    }

    func testDragSelectsContinuousText() {
        let (window, host) = makeHost()
        let start = contentPoint(of: 0, in: host)
        let end = contentPoint(of: 5, in: host)
        send(.leftMouseDown, at: start, in: host, window: window)
        send(.leftMouseDragged, at: end, in: host, window: window)
        send(.leftMouseUp, at: end, in: host, window: window)
        XCTAssertEqual(host.selectedRange(), NSRange(location: 0, length: 5))

        NSPasteboard.general.clearContents()
        host.copy(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello")
    }

    /// The highlight is made of small band views inside `selectionView` (not
    /// a full-size draw of the tiled `contentView`), so it updates on every
    /// selection change without a document-sized backing store.
    func testSelectionHighlightsFollowSelection() {
        let (_, host) = makeHost()
        let selectionColor = NSColor.systemRed
        host.selectionBackgroundColor = selectionColor
        host.setSelectedRange(NSRange(location: 0, length: 5))
        host.layoutSubtreeIfNeeded()

        let rects = host.textSelectionRects
        XCTAssertFalse(rects.isEmpty, "precondition: a selection rect exists")
        let bands = host.selectionView.highlightViews.filter { !$0.isHidden }
        XCTAssertEqual(bands.count, rects.count)
        XCTAssertEqual(bands.map(\.frame), rects)
        XCTAssertEqual(bands.first?.layer?.backgroundColor, selectionColor.cgColor)

        // A caret selection clears the bands.
        host.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertTrue(host.selectionView.highlightViews.allSatisfy(\.isHidden))
    }

    /// The highlight view must sit below the text fragments so glyphs render
    /// on top of the band.
    func testSelectionViewSitsBelowTextFragments() {
        let (_, host) = makeHost()
        host.setSelectedRange(NSRange(location: 0, length: 3))
        host.layoutSubtreeIfNeeded()
        guard let fragment = host.renderedFragmentViews.first,
              let viewport = fragment.superview,
              let selectionIndex = host.contentView.subviews.firstIndex(of: host.selectionView),
              let viewportIndex = host.contentView.subviews.firstIndex(of: viewport)
        else {
            XCTFail("missing views")
            return
        }
        XCTAssertLessThan(selectionIndex, viewportIndex)
    }

    /// Once a selection exists, an immediate drag starting inside it must
    /// start a new selection at the press point (a press-and-hold is what
    /// starts a drag-out instead).
    func testQuickDragInsideSelectionStartsNewSelection() {
        let (window, host) = makeHost()
        host.setSelectedRange(NSRange(location: 0, length: 5))
        let origin = contentPoint(of: 3, in: host)
        let destination = contentPoint(of: 8, in: host)
        send(.leftMouseDown, at: origin, in: host, window: window)
        send(.leftMouseDragged, at: destination, in: host, window: window)
        send(.leftMouseUp, at: destination, in: host, window: window)
        XCTAssertEqual(host.selectedRange(), NSRange(location: 3, length: 5))
    }

    /// A click (no drag) inside the selection collapses it to a caret.
    func testClickInsideSelectionCollapses() {
        let (window, host) = makeHost()
        host.setSelectedRange(NSRange(location: 0, length: 5))
        let point = contentPoint(of: 3, in: host)
        send(.leftMouseDown, at: point, in: host, window: window)
        send(.leftMouseUp, at: point, in: host, window: window)
        XCTAssertEqual(host.selectedRange().length, 0)
        XCTAssertEqual(host.selectedRange().location, 3)
    }

    func testDragSelectsBackwards() {
        let (window, host) = makeHost()
        send(.leftMouseDown, at: contentPoint(of: 8, in: host), in: host, window: window)
        send(.leftMouseDragged, at: contentPoint(of: 2, in: host), in: host, window: window)
        send(.leftMouseUp, at: contentPoint(of: 2, in: host), in: host, window: window)
        XCTAssertEqual(host.selectedRange(), NSRange(location: 2, length: 6))
    }
}

private extension MarkdownTextView {
    /// Converts a selection's first range to an `NSRange` for assertions.
    func selectedRangeForTest(_ selection: NSTextSelection?) -> NSRange? {
        guard let range = selection?.textRanges.first else { return nil }
        return textContentStorage.range(from: range)
    }
}