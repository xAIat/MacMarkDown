import XCTest
@testable import MacMarkDownKit

@MainActor
final class ScrollSyncCoordinatorTests: XCTestCase {

    /// Builds a one-way (editor → preview) coordinator. The editor anchor
    /// measurement is faked: source line `n` maps to `(n - 1) * 10`.
    private func makeCoordinator() -> (ScrollSyncCoordinator,
                                       () -> CGFloat?,     // last preview target
                                       () -> [CGFloat]) {  // editor commands
        let coordinator = ScrollSyncCoordinator()
        var lastPreviewTarget: CGFloat?
        var editorCommands: [CGFloat] = []

        coordinator.editor.measureAnchors = { _, lines, _, _, _ in
            lines.map { CGFloat($0 - 1) * 10 }
        }
        coordinator.editor.applyOffsetY = { editorCommands.append($0) }
        coordinator.preview.applyOffsetY = { lastPreviewTarget = $0 }
        coordinator.install()

        // Three anchors at source lines 1, 5, 9 -> editor Y 0, 40, 80.
        coordinator.anchorsDidChange(lines: [1, 5, 9])
        coordinator.previewAnchorsDidChange([0, 500, 1000])
        return (coordinator, { lastPreviewTarget }, { editorCommands })
    }

    func testEditorScrollDrivesPreview() {
        let (coordinator, previewTarget, editorCommands) = makeCoordinator()
        coordinator.previewDidScroll(offsetY: 0, contentHeight: 1200, visibleHeight: 200)

        coordinator.editorDidScroll(offsetY: 40, contentHeight: 100, visibleHeight: 20)
        let expected = coordinator.service.previewOffset(
            forEditorOffset: 40,
            editorContentHeight: 100,
            editorVisibleHeight: 20,
            previewContentHeight: 1200,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(previewTarget() ?? -1, expected, accuracy: 0.01)
        XCTAssertTrue(editorCommands().isEmpty, "one-way sync must not command the editor")
    }

    func testPreviewScrollDoesNotDriveEditorByDefault() {
        let (coordinator, _, editorCommands) = makeCoordinator()
        coordinator.editorDidScroll(offsetY: 0, contentHeight: 100, visibleHeight: 20)

        // Default (one-way): a genuine preview scroll must not move the editor.
        coordinator.previewDidScroll(offsetY: 500, contentHeight: 1200, visibleHeight: 200)
        XCTAssertTrue(editorCommands().isEmpty)
    }

    func testBidirectionalPreviewScrollDrivesEditor() {
        let (coordinator, _, editorCommands) = makeCoordinator()
        coordinator.isBidirectional = true
        coordinator.editorDidScroll(offsetY: 0, contentHeight: 100, visibleHeight: 20)

        // Only a genuine user gesture on the preview drives the editor.
        coordinator.preview.onLiveScrollBegan?()
        coordinator.previewDidScroll(offsetY: 500, contentHeight: 1200, visibleHeight: 200)
        let expected = coordinator.service.editorOffset(
            forPreviewOffset: 500,
            previewContentHeight: 1200,
            previewVisibleHeight: 200,
            editorContentHeight: 100,
            editorVisibleHeight: 20
        )
        XCTAssertEqual(editorCommands().last ?? -1, expected, accuracy: 0.5)
        XCTAssertGreaterThan(editorCommands().last ?? 0, 0)
    }

    /// A preview scroll that is *not* part of a user gesture (e.g. the echo of
    /// the editor's own command) must never drive the editor, even with
    /// bidirectional sync on.
    func testBidirectionalProgrammaticPreviewScrollDoesNotDriveEditor() {
        let (coordinator, _, editorCommands) = makeCoordinator()
        coordinator.isBidirectional = true
        coordinator.editorDidScroll(offsetY: 0, contentHeight: 100, visibleHeight: 20)

        // No `onLiveScrollBegan` -> not a user gesture.
        coordinator.previewDidScroll(offsetY: 500, contentHeight: 1200, visibleHeight: 200)
        XCTAssertTrue(editorCommands().isEmpty)
    }

    /// While the editor drives the preview, the preview's echoed scroll must be
    /// swallowed even when a preview gesture is active.
    func testPreviewEchoDoesNotDriveEditor() {
        let (coordinator, _, editorCommands) = makeCoordinator()
        coordinator.isBidirectional = true
        coordinator.previewDidScroll(offsetY: 0, contentHeight: 1200, visibleHeight: 200)
        coordinator.preview.onLiveScrollBegan?()

        // The editor drives the preview; the preview echoes the commanded offset.
        coordinator.editorDidScroll(offsetY: 40, contentHeight: 100, visibleHeight: 20)
        let target = coordinator.service.previewOffset(
            forEditorOffset: 40,
            editorContentHeight: 100,
            editorVisibleHeight: 20,
            previewContentHeight: 1200,
            previewVisibleHeight: 200
        )
        coordinator.previewDidScroll(offsetY: target, contentHeight: 1200, visibleHeight: 200)
        XCTAssertTrue(editorCommands().isEmpty, "the preview echo must not drive the editor")
    }

    /// Content heights captured at gesture start are frozen for the duration, so
    /// a document height that settles mid-scroll cannot move the target.
    func testGestureFreezesContentHeights() {
        let (coordinator, previewTarget, _) = makeCoordinator()
        coordinator.editorDidScroll(offsetY: 0, contentHeight: 100, visibleHeight: 20)
        coordinator.previewDidScroll(offsetY: 0, contentHeight: 1200, visibleHeight: 200)

        coordinator.editor.onLiveScrollBegan?()
        // Offset 90 is past the frozen editor's max scroll (100 - 20 = 80) but
        // inside the settled one (260 - 20 = 240), so the two mappings differ.
        coordinator.editorDidScroll(offsetY: 90, contentHeight: 100, visibleHeight: 20)
        let frozen = previewTarget()

        // A lazy height correction mid-gesture must not change the mapping.
        coordinator.editorDidScroll(offsetY: 90, contentHeight: 260, visibleHeight: 20)
        XCTAssertEqual(previewTarget() ?? -1, frozen ?? -2, accuracy: 0.01)

        // Once the gesture ends the settled height is used again.
        coordinator.editor.onLiveScrollEnded?()
        XCTAssertNotEqual(previewTarget() ?? -1, frozen ?? -2)
    }

    /// A user gesture on the preview must not snap the preview back to the
    /// editor when the mouse is released (one-way sync).
    func testPreviewGestureEndDoesNotResnapPreview() {
        let coordinator = ScrollSyncCoordinator()
        var previewCommands: [CGFloat] = []
        coordinator.editor.measureAnchors = { _, lines, _, _, _ in
            lines.map { CGFloat($0 - 1) * 10 }
        }
        coordinator.preview.applyOffsetY = { previewCommands.append($0) }
        coordinator.install()
        coordinator.anchorsDidChange(lines: [1, 5, 9])
        coordinator.previewAnchorsDidChange([0, 500, 1000])
        coordinator.editorDidScroll(offsetY: 0, contentHeight: 100, visibleHeight: 20)
        coordinator.previewDidScroll(offsetY: 0, contentHeight: 1200, visibleHeight: 200)
        coordinator.editorDidScroll(offsetY: 40, contentHeight: 100, visibleHeight: 20)

        let commandsBefore = previewCommands.count
        coordinator.preview.onLiveScrollBegan?()
        coordinator.previewDidScroll(offsetY: 700, contentHeight: 1200, visibleHeight: 200)
        coordinator.preview.onLiveScrollEnded?()

        XCTAssertEqual(previewCommands.count, commandsBefore,
                       "releasing the preview scrollbar must not re-command the preview")
    }

    /// Anchor updates that arrive mid-gesture are ignored so the frozen mapping
    /// stays consistent.
    func testPreviewAnchorUpdatesIgnoredDuringGesture() {
        let (coordinator, previewTarget, _) = makeCoordinator()
        coordinator.editorDidScroll(offsetY: 0, contentHeight: 100, visibleHeight: 20)
        coordinator.previewDidScroll(offsetY: 0, contentHeight: 1200, visibleHeight: 200)

        coordinator.editor.onLiveScrollBegan?()
        coordinator.editorDidScroll(offsetY: 40, contentHeight: 100, visibleHeight: 20)
        let frozen = previewTarget()

        coordinator.previewAnchorsDidChange([0, 9999, 99999])
        XCTAssertEqual(previewTarget() ?? -1, frozen ?? -2, accuracy: 0.01)
    }

    /// The editor's synchronous echo of a preview-driven command must not
    /// bounce back and re-command the preview.
    func testBidirectionalEditorEchoDoesNotRecommandPreview() {
        let coordinator = ScrollSyncCoordinator()
        var previewCommands: [CGFloat] = []
        coordinator.editor.measureAnchors = { _, lines, _, _, _ in
            lines.map { CGFloat($0 - 1) * 10 }
        }
        coordinator.preview.applyOffsetY = { previewCommands.append($0) }
        // The editor pane echoes synchronously inside `apply`.
        coordinator.editor.applyOffsetY = { target in
            coordinator.editorDidScroll(offsetY: target, contentHeight: 100, visibleHeight: 20)
        }
        coordinator.isBidirectional = true
        coordinator.anchorsDidChange(lines: [1, 5, 9])
        coordinator.previewAnchorsDidChange([0, 500, 1000])
        coordinator.editorDidScroll(offsetY: 0, contentHeight: 100, visibleHeight: 20)
        previewCommands.removeAll()

        coordinator.previewDidScroll(offsetY: 500, contentHeight: 1200, visibleHeight: 200)
        XCTAssertTrue(previewCommands.isEmpty, "editor echo must not re-command the preview")
    }

    func testEditorScrollBurstOnlyCommandsPreview() {
        let (coordinator, previewTarget, editorCommands) = makeCoordinator()
        coordinator.previewDidScroll(offsetY: 0, contentHeight: 1200, visibleHeight: 200)

        for offset in stride(from: CGFloat(5), through: 80, by: 5) {
            coordinator.editorDidScroll(offsetY: offset, contentHeight: 100, visibleHeight: 20)
        }
        let final = coordinator.service.previewOffset(
            forEditorOffset: 80,
            editorContentHeight: 100,
            editorVisibleHeight: 20,
            previewContentHeight: 1200,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(previewTarget() ?? -1, final, accuracy: 0.01)
        XCTAssertTrue(editorCommands().isEmpty)
    }

    /// A layout change (resize) produces new anchor positions; re-measuring via
    /// `anchorsDidChange` must re-sync the preview to the new mapping.
    func testAnchorsDidChangeRemeasuresAndResyncs() {
        let coordinator = ScrollSyncCoordinator()
        var lastPreviewTarget: CGFloat?
        var stretch: CGFloat = 1
        coordinator.editor.measureAnchors = { _, lines, _, _, _ in
            lines.map { CGFloat($0 - 1) * 10 * stretch }
        }
        coordinator.preview.applyOffsetY = { lastPreviewTarget = $0 }
        coordinator.anchorsDidChange(lines: [1, 5, 9])
        coordinator.previewAnchorsDidChange([0, 500, 1000])
        coordinator.previewDidScroll(offsetY: 0, contentHeight: 1200, visibleHeight: 200)
        coordinator.editorDidScroll(offsetY: 40, contentHeight: 100, visibleHeight: 20)
        let before = lastPreviewTarget

        // Simulate a resize that doubles the editor's anchor spacing, then
        // re-push the anchors.
        stretch = 2
        coordinator.anchorsDidChange(lines: [1, 5, 9])
        coordinator.editorDidScroll(offsetY: 40, contentHeight: 100, visibleHeight: 20)
        XCTAssertNotEqual(lastPreviewTarget, before, "resize must change the mapping")
    }

    func testEmptyAnchorsFallsBackToProportional() {
        let coordinator = ScrollSyncCoordinator()
        var lastPreviewTarget: CGFloat?
        coordinator.preview.applyOffsetY = { lastPreviewTarget = $0 }
        coordinator.previewDidScroll(offsetY: 0, contentHeight: 1200, visibleHeight: 200)
        coordinator.editorDidScroll(offsetY: 40, contentHeight: 100, visibleHeight: 20)
        XCTAssertNotNil(lastPreviewTarget)
    }
}
