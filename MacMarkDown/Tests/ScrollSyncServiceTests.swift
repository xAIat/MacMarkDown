import XCTest
@testable import MacMarkDownKit

@MainActor
final class ScrollSyncServiceTests: XCTestCase {

    private func makeService(editorAnchors: [CGFloat],
                             previewAnchors: [CGFloat]) -> ScrollSyncService {
        let service = ScrollSyncService()
        service.updateEditorAnchors(editorAnchors)
        service.updatePreviewAnchors(previewAnchors)
        return service
    }

    // MARK: - Proportional fallback (no anchors)

    func testProportionalSyncWithoutAnchors() {
        let service = ScrollSyncService()
        // Editor: content 1000, visible 200 -> max scroll 800.
        // Preview: content 800, visible 200 -> max scroll 600.
        // No anchors: interpolate from top to the true preview end. The taper
        // shifts the top segment by editorVisible/2 = 50, so offset 100
        // maps to 600 * (100 / (800 + 50)).
        let target = service.previewOffset(
            forEditorOffset: 100,
            editorContentHeight: 1000,
            editorVisibleHeight: 200,
            previewContentHeight: 800,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(target, 600 * 100 / 850, accuracy: 0.01)
    }

    func testProportionalSyncTopAndBottom() {
        let service = ScrollSyncService()
        let top = service.previewOffset(
            forEditorOffset: 0,
            editorContentHeight: 1000,
            editorVisibleHeight: 200,
            previewContentHeight: 800,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(top, 0, accuracy: 0.01)

        let bottom = service.previewOffset(
            forEditorOffset: 800,
            editorContentHeight: 1000,
            editorVisibleHeight: 200,
            previewContentHeight: 800,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(bottom, 600, accuracy: 0.01) // clamped to preview max scroll
    }

    func testClampsOutOfRangeOffsets() {
        let service = ScrollSyncService()
        let negative = service.previewOffset(
            forEditorOffset: -50,
            editorContentHeight: 1000,
            editorVisibleHeight: 200,
            previewContentHeight: 800,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(negative, 0, accuracy: 0.01)

        let beyond = service.previewOffset(
            forEditorOffset: 9999,
            editorContentHeight: 1000,
            editorVisibleHeight: 200,
            previewContentHeight: 800,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(beyond, 600, accuracy: 0.01) // clamped to preview max scroll
    }

    // MARK: - Anchor-based sync (segment interpolation)

    /// Editor anchors 0/40/80, preview anchors 0/500/1000.
    func testAnchorSyncMapsAnchorToPreview() {
        let service = makeService(editorAnchors: [0, 40, 80], previewAnchors: [0, 500, 1000])
        // Mid-pane: taper = visible/2 = 10, so editor 40 sits at 30 within the
        // [30, 70] bracket -> 25% of the way to the preview end bracket
        // [490, 990] -> 490 + 500 * 0.25 = 615.
        let target = service.previewOffset(
            forEditorOffset: 40,
            editorContentHeight: 100,
            editorVisibleHeight: 20,
            previewContentHeight: 1200,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(target, 615, accuracy: 0.01)
    }

    func testAnchorSyncInterpolatesBetweenAnchors() {
        let service = makeService(editorAnchors: [0, 40, 80], previewAnchors: [0, 500, 1000])
        // Top taper at offset 10 is 10/20 = 0.5 -> adjustment 5. Editor 10 lies
        // 15 into the [-5, 35] bracket -> 0.375 -> preview -5 + 500 * 0.375.
        let target = service.previewOffset(
            forEditorOffset: 10,
            editorContentHeight: 100,
            editorVisibleHeight: 20,
            previewContentHeight: 1200,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(target, 182.5, accuracy: 0.01)
    }

    func testAnchorSyncEndOfDocumentMapsToPreviewEnd() {
        let service = makeService(editorAnchors: [0, 40, 80], previewAnchors: [0, 500, 1000])
        // Offset 80 is in the last visible screen: bottom taper drops to 0 and
        // the last reference node is used, interpolating to the true preview
        // end (content 1200 - visible 200 = 1000).
        let target = service.previewOffset(
            forEditorOffset: 80,
            editorContentHeight: 100,
            editorVisibleHeight: 20,
            previewContentHeight: 1200,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(target, 1000, accuracy: 0.01)
    }

    /// All anchors participate (no truncation): anchors beyond the last visible
    /// screen are ignored as the *upper* bracket by the map itself.
    func testAnchorsBeyondLastScreenDoNotBracket() {
        let service = makeService(
            editorAnchors: [0, 40, 80, 200],
            previewAnchors: [0, 500, 1000, 1800]
        )
        let target = service.previewOffset(
            forEditorOffset: 60,
            editorContentHeight: 100,
            editorVisibleHeight: 20,
            previewContentHeight: 1200,
            previewVisibleHeight: 200
        )
        XCTAssertEqual(target, 865, accuracy: 0.01)
    }

    /// Dense anchors (list-item granularity) keep the mapping tight: a short
    /// editor gap between two adjacent anchors maps to the matching short
    /// preview gap instead of interpolating across a whole heading section.
    func testDenseAnchorsMapTightly() {
        // Editor anchors every 20pt; preview anchors compressed near the top.
        let service = makeService(
            editorAnchors: [0, 20, 40, 60, 80, 100],
            previewAnchors: [0, 90, 180, 270, 360, 450]
        )
        // Offset 20 sits at the second anchor; the taper (visible/2 = 10)
        // shifts it by 10, so it lies 20 into the [10, 30] bracket -> ratio 0.5
        // of the preview bracket [80, 170] -> 125.
        let target = service.previewOffset(
            forEditorOffset: 20,
            editorContentHeight: 140,
            editorVisibleHeight: 20,
            previewContentHeight: 500,
            previewVisibleHeight: 50
        )
        XCTAssertEqual(target, 125, accuracy: 0.01)
    }

    /// Unequal anchor counts fall back to the common prefix (1:1 pairing).
    func testUnequalAnchorCountsUseCommonPrefix() {
        let service = makeService(editorAnchors: [0, 40], previewAnchors: [0, 500, 1000])
        let target = service.previewOffset(
            forEditorOffset: 40,
            editorContentHeight: 100,
            editorVisibleHeight: 20,
            previewContentHeight: 1200,
            previewVisibleHeight: 200
        )
        // Only [0, 40] / [0, 500] participate; past the last anchor the map
        // interpolates to the preview end.
        XCTAssertGreaterThan(target, 0)
        XCTAssertLessThanOrEqual(target, 1000)
    }

    // MARK: - Reverse mapping (preview -> editor, bidirectional)

    func testInverseMapsPreviewOffsetToEditorOffset() {
        let service = makeService(editorAnchors: [0, 40, 80], previewAnchors: [0, 500, 1000])
        let editorOffset = service.editorOffset(
            forPreviewOffset: 250,
            previewContentHeight: 1200,
            previewVisibleHeight: 200,
            editorContentHeight: 100,
            editorVisibleHeight: 20
        )
        XCTAssertEqual(editorOffset, 13.7, accuracy: 0.5)
    }

    func testInverseRoundTripMatchesForward() {
        let service = makeService(editorAnchors: [0, 40, 80], previewAnchors: [0, 500, 1000])
        for editorOffset in [CGFloat(5), 15, 25, 45, 70] {
            let previewOffset = service.previewOffset(
                forEditorOffset: editorOffset,
                editorContentHeight: 100,
                editorVisibleHeight: 20,
                previewContentHeight: 1200,
                previewVisibleHeight: 200
            )
            let backToEditor = service.editorOffset(
                forPreviewOffset: previewOffset,
                previewContentHeight: 1200,
                previewVisibleHeight: 200,
                editorContentHeight: 100,
                editorVisibleHeight: 20
            )
            XCTAssertEqual(backToEditor, editorOffset, accuracy: 0.5,
                           "round trip failed for editor offset \(editorOffset)")
        }
    }

    func testInverseTopAndBottom() {
        let service = makeService(editorAnchors: [0, 40, 80], previewAnchors: [0, 500, 1000])
        let top = service.editorOffset(
            forPreviewOffset: 0,
            previewContentHeight: 1200,
            previewVisibleHeight: 200,
            editorContentHeight: 100,
            editorVisibleHeight: 20
        )
        XCTAssertEqual(top, 0, accuracy: 0.5)

        let bottom = service.editorOffset(
            forPreviewOffset: 1000,
            previewContentHeight: 1200,
            previewVisibleHeight: 200,
            editorContentHeight: 100,
            editorVisibleHeight: 20
        )
        XCTAssertEqual(bottom, 80, accuracy: 0.5)
    }

    func testDisabledServiceReturnsZero() {
        let service = makeService(editorAnchors: [0, 40], previewAnchors: [0, 100])
        service.isEnabled = false
        let target = service.previewOffset(
            forEditorOffset: 10,
            editorContentHeight: 100,
            editorVisibleHeight: 20,
            previewContentHeight: 120,
            previewVisibleHeight: 20
        )
        XCTAssertEqual(target, 0)
    }
}
