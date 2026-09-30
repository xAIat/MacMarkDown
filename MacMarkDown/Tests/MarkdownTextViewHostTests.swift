import AppKit
import SwiftUI
import XCTest

@testable import MacMarkDownKit

/// Milestone 4: once `MarkdownEditorView` hosts the custom text view, the
/// coordinator drives it through the `EditorTextViewHost` surface and the
/// drop/command hooks replace the old `NSTextView` delegation. These tests
/// lock that contract down on the custom host.
final class MarkdownTextViewHostTests: XCTestCase {

    @MainActor
    private func makeTextView() -> MarkdownTextView {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.string = "hello world\nsecond line"
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return textView
    }

    /// Replacing a long document with a short one shrinks the document view;
    /// the scroll origin must be pulled back inside the new range instead of
    /// leaving the viewport past the content (a large blank area).
    @MainActor
    func testShrinkingContentClampsScrollOrigin() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scroll.hasVerticalScroller = true
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor
        ]
        let long = Array(repeating: "line of text", count: 200).joined(separator: "\n")
        textView.setAttributedContent(NSAttributedString(string: long, attributes: attributes))
        textView.layoutSubtreeIfNeeded()
        let tall = textView.frame.height
        XCTAssertGreaterThan(tall, 300)

        scroll.contentView.scroll(to: NSPoint(x: 0, y: tall - 300))
        XCTAssertGreaterThan(scroll.contentView.bounds.origin.y, 0)

        textView.setAttributedContent(NSAttributedString(string: "short", attributes: attributes))
        textView.layoutSubtreeIfNeeded()

        let maxY = max(0, textView.frame.height - scroll.contentView.bounds.height)
        XCTAssertLessThanOrEqual(
            scroll.contentView.bounds.origin.y, maxY + 0.5,
            "the viewport must be clamped after the document shrinks"
        )
    }

    // MARK: - EditorTextViewHost surface

    @MainActor
    func testHostSurfaceReadsWritesThroughContentStorage() {        let textView = makeTextView()
        let host: any EditorTextViewHost = textView
        XCTAssertEqual(host.string, "hello world\nsecond line")
        XCTAssertEqual(host.selectedRange(), NSRange(location: 0, length: 0))

        host.setSelectedRange(NSRange(location: 5, length: 1))
        host.insertText("x", replacementRange: .notFound)
        XCTAssertEqual(host.string, "helloxworld\nsecond line")
        XCTAssertEqual(host.selectedRange(), NSRange(location: 6, length: 0))
    }

    @MainActor
    func testHostReplaceCharactersInRangeSpace() {
        let textView = makeTextView()
        let host: any EditorTextViewHost = textView
        host.replaceCharacters(in: NSRange(location: 0, length: 5), with: "HELLO")
        XCTAssertEqual(host.string, "HELLO world\nsecond line")
    }

    @MainActor
    func testHostShouldChangeTextConsultsHandler() {
        let textView = makeTextView()
        var consulted = false
        textView.shouldChangeTextHandler = { _, _ in
            consulted = true
            return true
        }
        _ = textView.shouldChangeText(in: NSRange(location: 0, length: 0), replacementString: "z")
        XCTAssertTrue(consulted)
    }

    @MainActor
    func testShouldChangeHandlerVetoesReplacement() {
        let textView = makeTextView()
        textView.shouldChangeTextHandler = { _, _ in false }
        textView.replaceCharacters(in: NSRange(location: 0, length: 0), with: "blocked")
        XCTAssertEqual(textView.string, "hello world\nsecond line")
    }

    // MARK: - CommandInterceptingTextView

    @MainActor
    func testDoCommandHandlerIsConsultedAndCanConsume() {
        let textView = makeTextView()
        var seen: [Selector] = []
        textView.doCommandHandler = { selector in
            seen.append(selector)
            return true
        }
        let selector = #selector(NSResponder.moveLeft(_:))
        textView.doCommand(by: selector)
        XCTAssertEqual(seen, [selector])
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    @MainActor
    func testDoCommandHandlerReturnsDroppedThroughToResponder() {
        let textView = makeTextView()
        var consulted = false
        textView.doCommandHandler = { _ in
            consulted = true
            return false
        }
        textView.doCommand(by: #selector(NSResponder.moveRight(_:)))
        XCTAssertTrue(consulted)
    }

    // MARK: - Drag and drop

    @MainActor
    func testFileDropOpensURLInsteadOfInserting() {
        let textView = makeTextView()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropped-doc.md")
        FileManager.default.createFile(atPath: url.path, contents: Data("file body".utf8))

        var opened: URL?
        var targeting: [Bool] = []
        textView.onOpenFile = { opened = $0 }
        textView.onDragTargetingChanged = { targeting.append($0) }

        let pasteboard = NSPasteboard(name: .init("com.xaiat.MacMarkDown.test.file-drop"))
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        let info = MockDraggingInfo(pasteboard: pasteboard, location: NSPoint(x: 20, y: 30))
        textView.draggingEntered(info)
        textView.performDragOperation(info)

        XCTAssertEqual(opened, url)
        XCTAssertEqual(targeting, [true, false])
        XCTAssertEqual(textView.string, "hello world\nsecond line")
    }

    @MainActor
    func testTextDropInsertsAtDropLocation() {
        let textView = makeTextView()
        let pasteboard = NSPasteboard(name: .init("com.xaiat.MacMarkDown.test.string-drop"))
        pasteboard.clearContents()
        pasteboard.setString("pasted", forType: .string)
        let info = MockDraggingInfo(pasteboard: pasteboard, location: NSPoint(x: 20, y: 30))
        let opened = textView.performDragOperation(info)
        XCTAssertTrue(opened)
        XCTAssertTrue(textView.string.contains("pasted"))
    }

    /// The preview surface is a read-only `MarkdownTextView` and covers the
    /// whole pane once the document has content, so it must forward file drops
    /// to its open handler. Image drops specifically must not fall into the
    /// editor's base64-inlining path and mutate the preview's text storage.
    @MainActor
    func testReadOnlySurfaceForwardsFileDropsInsteadOfInserting() {
        let textView = makeTextView()
        textView.isEditable = false
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropped-image.png")
        FileManager.default.createFile(atPath: url.path, contents: Data("not really a png".utf8))

        var opened: URL?
        var targeting: [Bool] = []
        textView.onOpenFile = { opened = $0 }
        textView.onDragTargetingChanged = { targeting.append($0) }

        let pasteboard = NSPasteboard(name: .init("com.xaiat.MacMarkDown.test.readonly-file-drop"))
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        let info = MockDraggingInfo(pasteboard: pasteboard, location: NSPoint(x: 20, y: 30))

        XCTAssertEqual(textView.draggingEntered(info), .copy)
        XCTAssertTrue(textView.performDragOperation(info))

        XCTAssertEqual(opened, url)
        XCTAssertEqual(targeting, [true, false])
        XCTAssertEqual(
            textView.string, "hello world\nsecond line",
            "the read-only preview must not inline the dropped image"
        )
    }

    /// A read-only surface with no file handler declines file drags, so the
    /// window can fall through to the SwiftUI drop destination instead of
    /// silently swallowing the drop.
    @MainActor
    func testReadOnlySurfaceWithoutFileHandlerDeclinesFileDrag() {
        let textView = makeTextView()
        textView.isEditable = false
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropped-doc.md")
        FileManager.default.createFile(atPath: url.path, contents: Data("file body".utf8))

        let pasteboard = NSPasteboard(name: .init("com.xaiat.MacMarkDown.test.declined-file-drop"))
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        let info = MockDraggingInfo(pasteboard: pasteboard, location: NSPoint(x: 20, y: 30))

        XCTAssertEqual(textView.draggingEntered(info), [])
    }

    // MARK: - Scroll sync anchor snapshot

    @MainActor
    func testTextAnchorHostSnapshotsBothHostClasses() throws {
        let textView = makeTextView()
        let host = try XCTUnwrap(ScrollSyncPane<EmptyView>.Coordinator.textAnchorHost(from: textView))
        XCTAssertEqual(host.string, "hello world\nsecond line")

        let legacy = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 50))
        legacy.string = "legacy"
        let legacyHost = try XCTUnwrap(ScrollSyncPane<EmptyView>.Coordinator.textAnchorHost(from: legacy))
        XCTAssertEqual(legacyHost.string, "legacy")
    }

    // MARK: - Scroll view integration

    @MainActor
    func testDocumentViewGrowsWithContentInsideScrollView() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 120))
        scrollView.documentView = textView
        textView.string = Array(repeating: "a line of text", count: 120).joined(separator: "\n")

        textView.performFullLayoutForTesting()

        XCTAssertGreaterThan(textView.frame.height, 120)
    }

    // MARK: - Smart editing through the host protocol

    @MainActor
    func testSmartEditingHelpersWorkOnCustomHost() {
        let textView = makeTextView()
        textView.string = ""
        let host: any EditorTextViewHost = textView

        _ = host.completeMatchingCharacters(
            forRange: NSRange(location: 0, length: 0),
            replacementString: "(",
            strikethroughEnabled: false
        )
        XCTAssertEqual(host.string, "()")
        XCTAssertEqual(host.selectedRange(), NSRange(location: 1, length: 0))
    }

    // MARK: - Standard editing commands (P0)

    @MainActor
    func testCopyPutsSelectionOnPasteboard() {
        let textView = makeTextView()
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        textView.copy(nil)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello")
    }

    @MainActor
    func testCutRemovesSelectionAndCopies() {
        let textView = makeTextView()
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        textView.cut(nil)
        XCTAssertEqual(textView.string, " world\nsecond line")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }

    @MainActor
    func testPasteInsertsClipboardAtSelection() {
        let textView = makeTextView()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("PASTED", forType: .string)
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        textView.paste(nil)
        XCTAssertEqual(textView.string, "PASTED world\nsecond line")
    }

    @MainActor
    func testDeleteRemovesSelection() {
        let textView = makeTextView()
        textView.setSelectedRange(NSRange(location: 0, length: 6))
        textView.delete(nil)
        XCTAssertEqual(textView.string, "world\nsecond line")
    }

    @MainActor
    func testSelectAll() {
        let textView = makeTextView()
        textView.selectAll(nil)
        XCTAssertEqual(textView.selectedRange().length, (textView.string as NSString).length)
    }

    @MainActor
    func testUndoRedo() {
        // Undo registration resolves through the window's undo manager, so the
        // view must be hosted for this test.
        let textView = makeTextView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = textView
        defer { window.contentView = nil }

        textView.setSelectedRange(NSRange(location: 5, length: 0))
        textView.insertText("X", replacementRange: .notFound)
        XCTAssertEqual(textView.string, "helloX world\nsecond line")

        textView.undo(nil)
        XCTAssertEqual(textView.string, "hello world\nsecond line")

        textView.redo(nil)
        XCTAssertEqual(textView.string, "helloX world\nsecond line")
    }

    @MainActor
    func testSelectionChangeCallbackFiresOnEditsAndSelection() {
        let textView = makeTextView()
        var reported: [NSRange] = []
        textView.onSelectionChange = { reported.append($0) }

        textView.setSelectedRange(NSRange(location: 3, length: 2))
        textView.insertText("y", replacementRange: .notFound)

        XCTAssertEqual(reported.first, NSRange(location: 3, length: 2))
        XCTAssertEqual(reported.last, NSRange(location: 4, length: 0))
    }

    // MARK: - Editor geometry (P5)

    @MainActor
    func testContentInsetsOffsetContainerOrigin() {
        let textView = makeTextView()
        XCTAssertEqual(textView.textContainerOrigin, .zero)
        textView.contentInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        XCTAssertEqual(textView.textContainerOrigin, NSPoint(x: 20, y: 10))
    }

    @MainActor
    func testScrollsPastEndGrowsDocumentView() {
        let textView = makeTextView()
        textView.frame = NSRect(x: 0, y: 0, width: 320, height: 120)
        textView.string = "one line"
        textView.performFullLayoutForTesting()
        let without = textView.frame.height

        textView.scrollsPastEnd = true
        textView.performFullLayoutForTesting()
        XCTAssertGreaterThan(textView.frame.height, without)
    }

    @MainActor
    func testSelectionRectsOffsetByInsets() {
        let textView = makeTextView()
        textView.setSelectedRange(NSRange(location: 0, length: 5))
        textView.performFullLayoutForTesting()
        let plain = textView.textSelectionRects.first

        textView.contentInsets = NSEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        textView.performFullLayoutForTesting()
        let inset = textView.textSelectionRects.first

        XCTAssertNotNil(plain)
        XCTAssertNotNil(inset)
        XCTAssertEqual((inset?.origin.x ?? 0) - (plain?.origin.x ?? 0), 20, accuracy: 0.5)
        XCTAssertEqual((inset?.origin.y ?? 0) - (plain?.origin.y ?? 0), 10, accuracy: 0.5)
    }

    /// The line-number gutter draws its labels into the document view's
    /// coordinate space, but `visibleLineNumberFrames()` reports fragment
    /// frames in the text container's coordinate space. When the editor has a
    /// vertical inset, labels must be shifted down by `textContainerOrigin.y`
    /// or the first number floats a whole line-height above its text (the
    /// reported symptom: line 1 looks empty and the heading reads as line 2).
    @MainActor
    func testGutterLineNumbersAlignWithTheirLinesAcrossTopInset() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scroll.hasVerticalScroller = true
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        textView.autoresizingMask = [.width]
        scroll.documentView = textView
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        textView.contentInsets = NSEdgeInsets(top: 16, left: 0, bottom: 16, right: 0)
        textView.showsLineNumbers = true
        textView.string = "# Heading\n\nSome body text\n"
        textView.performFullLayoutForTesting()

        guard let gutter = textView.gutterView else { return XCTFail("gutter missing") }

        let sourceFrames = textView.visibleLineNumberFrames()
        let labelFrames = gutter.lineNumberLabelFrames()
        XCTAssertEqual(
            labelFrames.map(\.line),
            sourceFrames.map(\.line),
            "gutter labels must map to the same visible lines as their fragments"
        )

        let insetY = textView.textContainerOrigin.y
        XCTAssertGreaterThan(insetY, 0, "this test needs a nonzero top inset to be meaningful")
        XCTAssertEqual(sourceFrames.first?.line, 1, "the heading must be the first visible line")
        for (source, label) in zip(sourceFrames, labelFrames) {
            XCTAssertEqual(
                label.frame.midY, source.frame.midY + insetY, accuracy: 0.5,
                "line \(source.line)'s number must be vertically centered on its text fragment, offset by the top inset"
            )
        }

        // Without the inset offset the first label would sit at the very top of
        // the view, half a line-height above the heading text it labels.
        XCTAssertGreaterThan(labelFrames[0].frame.midY, sourceFrames[0].frame.midY + insetY - 1)
    }
}

/// A minimal `NSDraggingInfo` producing the pasteboard/location the drop path
/// reads; everything else returns inert defaults.
private final class MockDraggingInfo: NSObject, NSDraggingInfo {
    let pasteboard: NSPasteboard
    let location: NSPoint

    init(pasteboard: NSPasteboard, location: NSPoint) {
        self.pasteboard = pasteboard
        self.location = location
    }

    var draggingDestinationWindow: NSWindow? { nil }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingSource: Any? { self }
    var draggingSequenceNumber: Int { 1 }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { pasteboard }
    var draggingItem: NSDraggingItem? { nil }
    var draggingFormation: NSDraggingFormation {
        get { .none }
        set {}
    }
    var animatesToDestination: Bool {
        get { false }
        set {}
    }
    var numberOfValidItemsForDrop: Int {
        get { 1 }
        set {}
    }
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }

    func sourceOperationMask(for context: NSDraggingContext) -> NSDragOperation { .copy }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    func resetSpringLoading() {}
    func setSpringLoading(_ springLoading: Bool, for context: NSDraggingContext) {}

    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions,
        for view: NSView?,
        classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: @escaping (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}
// MARK: - Spell checking (P5)

@MainActor
final class MarkdownTextViewSpellingTests: XCTestCase {

    private func makeTextView() -> MarkdownTextView {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.string = "This sentence has a misspeled word."
        return textView
    }

    func testSpellingMarksMisspelledWord() {
        let textView = makeTextView()
        textView.isContinuousSpellCheckingEnabled = true
        XCTAssertFalse(textView.spellingRanges.isEmpty)
        let flagged = textView.spellingRanges.contains { range in
            (textView.string as NSString).substring(with: range) == "misspeled"
        }
        XCTAssertTrue(flagged)
    }

    func testDisablingSpellCheckingClearsMarks() {
        let textView = makeTextView()
        textView.isContinuousSpellCheckingEnabled = true
        XCTAssertFalse(textView.spellingRanges.isEmpty)

        textView.isContinuousSpellCheckingEnabled = false
        XCTAssertTrue(textView.spellingRanges.isEmpty)
        let attributes = textView.textStorage?.attribute(.underlineStyle, at: 0, effectiveRange: nil)
        XCTAssertNil(attributes)
    }

    func testCorrectTextHasNoMarks() {
        let textView = makeTextView()
        textView.string = "This sentence is spelled correctly."
        textView.isContinuousSpellCheckingEnabled = true
        XCTAssertTrue(textView.spellingRanges.isEmpty)
    }
}
