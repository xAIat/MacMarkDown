import AppKit
import XCTest

@testable import MacMarkDownKit

/// Milestone 4 integration: the SwiftUI coordinator drives `MarkdownTextView`
/// directly. These tests exercise the wiring that `MarkdownEditorView` sets up
/// — text-change reporting (once per user edit, never for model echoes),
/// command routing into the smart-editing helpers, and highlighting — without
/// needing a hosted window.
final class MarkdownEditorCoordinatorTests: XCTestCase {

    @MainActor
    private func makeHost() -> MarkdownTextView {
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.string = ""
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return textView
    }

    @MainActor
    private func makeCoordinator(
        _ onChange: @escaping (String) -> Void = { _ in }
    ) -> MarkdownEditorView.Coordinator {
        MarkdownEditorView.Coordinator(onTextChange: onChange)
    }

    // MARK: - Text-change reporting

    @MainActor
    func testUserEditIsReportedOnce() {
        var changes: [String] = []
        let coordinator = makeCoordinator { changes.append($0) }
        let host = makeHost()
        coordinator.setUp(host: host)

        host.insertText("a", replacementRange: .notFound)
        XCTAssertEqual(changes, ["a"])

        host.insertText("b", replacementRange: .notFound)
        XCTAssertEqual(changes, ["a", "ab"])
    }

    @MainActor
    func testModelDrivenUpdateDoesNotEcho() {
        var changes: [String] = []
        let coordinator = makeCoordinator { changes.append($0) }
        let host = makeHost()
        coordinator.setUp(host: host)

        coordinator.isUpdatingFromModel = true
        host.string = "loaded from document"
        coordinator.isUpdatingFromModel = false

        XCTAssertTrue(changes.isEmpty)

        host.insertText("!", replacementRange: .notFound)
        XCTAssertEqual(changes, ["loaded from document!"])
    }

    // MARK: - Command routing

    @MainActor
    func testTabInsertsSpacesWhenConvertTabsToSpaces() {
        let coordinator = makeCoordinator()
        coordinator.convertTabsToSpaces = true
        let host = makeHost()
        coordinator.setUp(host: host)

        host.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(host.string, "    ")
    }

    @MainActor
    func testTabInsertsTabWhenConversionDisabled() {
        let coordinator = makeCoordinator()
        coordinator.convertTabsToSpaces = false
        let host = makeHost()
        coordinator.setUp(host: host)

        host.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(host.string, "\t")
    }

    @MainActor
    func testReturnContinuesUnorderedList() {
        let coordinator = makeCoordinator()
        coordinator.insertPrefixInBlock = true
        let host = makeHost()
        host.string = "- item"
        host.setSelectedRange(NSRange(location: 6, length: 0))
        coordinator.setUp(host: host)

        host.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(host.string, "- item\n- ")
    }

    @MainActor
    func testReturnContinuesOrderedListWithIncrement() {
        let coordinator = makeCoordinator()
        coordinator.insertPrefixInBlock = true
        coordinator.autoIncrementNumberedLists = true
        let host = makeHost()
        host.string = "1. item"
        host.setSelectedRange(NSRange(location: 7, length: 0))
        coordinator.setUp(host: host)

        host.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(host.string, "1. item\n2. ")
    }

    @MainActor
    func testBackspaceBetweenMatchingPairDeletesBoth() {
        let coordinator = makeCoordinator()
        coordinator.completeMatchingCharacters = true
        let host = makeHost()
        host.string = "()"
        host.setSelectedRange(NSRange(location: 1, length: 0))
        coordinator.setUp(host: host)

        host.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        XCTAssertEqual(host.string, "")
    }

    @MainActor
    func testBacktabUnindentsWithCaretInsideIndentation() {
        // Regression: Shift+Tab with the caret inside leading spaces used to
        // crash in `EditorOperations.unindentLines`.
        let coordinator = makeCoordinator()
        let host = makeHost()
        host.string = "    foo"
        host.setSelectedRange(NSRange(location: 4, length: 0))
        coordinator.setUp(host: host)

        host.doCommand(by: #selector(NSResponder.insertBacktab(_:)))

        XCTAssertEqual(host.string, "foo")
        XCTAssertEqual(host.selectedRange(), NSRange(location: 0, length: 0))
    }

    @MainActor
    func testSmartHomeMovesToFirstNonWhitespace() {
        let coordinator = makeCoordinator()
        coordinator.smartHome = true
        let host = makeHost()
        host.string = "    indented"
        host.setSelectedRange(NSRange(location: 12, length: 0))
        coordinator.setUp(host: host)

        host.doCommand(by: #selector(NSResponder.moveToLeftEndOfLine(_:)))
        XCTAssertEqual(host.selectedRange(), NSRange(location: 4, length: 0))
    }

    @MainActor
    func testAutoPairingIsRoutedThroughShouldChange() {
        let coordinator = makeCoordinator()
        coordinator.completeMatchingCharacters = true
        let host = makeHost()
        coordinator.setUp(host: host)

        // The coordinator performs the pairing edit itself during the
        // should-change consult and vetoes the raw keystroke.
        let veto = host.shouldChangeText(in: NSRange(location: 0, length: 0), replacementString: "(")
        XCTAssertFalse(veto)
        XCTAssertEqual(host.string, "()")
        XCTAssertEqual(host.selectedRange(), NSRange(location: 1, length: 0))
    }

    // MARK: - Highlighting

    @MainActor
    func testUserEditTriggersHighlighting() throws {
        let coordinator = makeCoordinator()
        let host = makeHost()
        coordinator.setUp(host: host)

        host.insertText("# Heading", replacementRange: .notFound)

        let storage = try XCTUnwrap(host.textStorage)
        let headingColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        XCTAssertEqual(headingColor, coordinator.editorTheme.nsHeadingColor)
    }

    /// Re-applying fonts/paragraph styles invalidates the TextKit layout, so the
    /// document height must be re-measured afterwards; otherwise the editor's
    /// scrollbar is too long until an unrelated live scroll corrects it.
    @MainActor
    func testHighlightMarksHeightForRemeasurement() {
        let coordinator = makeCoordinator()
        let host = makeHost()
        coordinator.setUp(host: host)

        host.insertText("# Heading\n\nbody", replacementRange: .notFound)
        host.needsFullHeightMeasurement = false
        host.needsLayout = false

        coordinator.applyHighlight()

        XCTAssertTrue(host.needsFullHeightMeasurement)
        XCTAssertTrue(host.needsLayout)
    }
}