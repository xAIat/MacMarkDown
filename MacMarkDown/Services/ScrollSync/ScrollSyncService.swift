import Foundation
import Observation

/// Coordinates synchronized scrolling from the editor to the preview.
///
/// The mapping pairs *every* block and list item with an anchor (dense
/// anchors):
///
/// - The parser emits an ordered list of anchors (`DocumentAnchor`), one per
///   block / list item, in document order. Both panes measure a Y position for
///   the *same* ordered list, so the arrays are paired 1:1 by index.
/// - The scroll offset is expressed as a percentage between the two anchors
///   that bracket it, mapped onto the matching bracket in the preview pane.
///   Past the last in-range anchor the mapping interpolates to the true end of
///   the document.
/// - The documents are aligned in the middle of the screen with a smooth taper
///   near the top/bottom edges (`adjustmentForScroll`), so panes stay visually
///   locked while scrolling without clipping at the extremes.
///
/// Sync is one-way (editor → preview) by default. When the "Bidirectional
/// Sync" preference is enabled the reverse mapping
/// (`editorOffset(forPreviewOffset:)`) is used as well; it is the exact inverse
/// of the forward map, obtained by bisection, so the two panes never bounce.
@MainActor
@Observable
public final class ScrollSyncService {

    public var isEnabled = true

    /// Ordered anchor Y positions in the editor content space.
    private var editorAnchors: [CGFloat] = []
    /// Ordered anchor Y positions in the preview content space (same indices).
    private var previewAnchors: [CGFloat] = []

    public init() {}

    // MARK: - Anchor inputs

    /// Store the editor anchor positions, in the parser's anchor order.
    public func updateEditorAnchors(_ anchors: [CGFloat]) {
        self.editorAnchors = anchors
    }

    /// Store the preview anchor positions, in the parser's anchor order.
    public func updatePreviewAnchors(_ anchors: [CGFloat]) {
        self.previewAnchors = anchors
    }

    // MARK: - Editor → preview

    public func previewOffset(forEditorOffset editorY: CGFloat,
                              editorContentHeight: CGFloat,
                              editorVisibleHeight: CGFloat,
                              previewContentHeight: CGFloat,
                              previewVisibleHeight: CGFloat) -> CGFloat {
        guard isEnabled,
              editorVisibleHeight > 0, previewVisibleHeight > 0,
              editorContentHeight > editorVisibleHeight,
              previewContentHeight > previewVisibleHeight
        else { return 0 }

        let fromMax = editorContentHeight - editorVisibleHeight
        let toMax = previewContentHeight - previewVisibleHeight
        let clamped = min(max(0, editorY), fromMax)
        let count = Swift.min(editorAnchors.count, previewAnchors.count)
        let result = map(clamped,
                         from: Array(editorAnchors.prefix(count)),
                         fromContentHeight: editorContentHeight,
                         fromVisibleHeight: editorVisibleHeight,
                         to: Array(previewAnchors.prefix(count)),
                         toContentHeight: previewContentHeight,
                         toVisibleHeight: previewVisibleHeight)
        return min(max(0, result), toMax)
    }

    // MARK: - Preview → editor (exact inverse via bisection)

    /// The exact inverse of `previewOffset(forEditorOffset:...)`. `previewOffset`
    /// is monotonically non-decreasing in the editor offset, so the pre-image of
    /// `previewY` is found by bisection. Used only when bidirectional sync is
    /// enabled.
    public func editorOffset(forPreviewOffset previewY: CGFloat,
                             previewContentHeight: CGFloat,
                             previewVisibleHeight: CGFloat,
                             editorContentHeight: CGFloat,
                             editorVisibleHeight: CGFloat) -> CGFloat {
        guard isEnabled,
              editorVisibleHeight > 0, previewVisibleHeight > 0,
              editorContentHeight > editorVisibleHeight,
              previewContentHeight > previewVisibleHeight
        else { return 0 }

        let previewMax = max(0, previewContentHeight - previewVisibleHeight)
        let target = min(max(0, previewY), previewMax)

        let editorMax = max(0, editorContentHeight - editorVisibleHeight)
        guard editorMax > 0 else { return 0 }

        var lo: CGFloat = 0
        var hi: CGFloat = editorMax
        for _ in 0..<32 {
            let mid = (lo + hi) / 2
            let mapped = previewOffset(
                forEditorOffset: mid,
                editorContentHeight: editorContentHeight,
                editorVisibleHeight: editorVisibleHeight,
                previewContentHeight: previewContentHeight,
                previewVisibleHeight: previewVisibleHeight
            )
            if mapped < target {
                lo = mid
            } else {
                hi = mid
            }
        }
        return lo
    }

    // MARK: - Shared mapping

    private func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(0, value), 1)
    }

    /// Maps `currentOffset` (in the "from" pane) to the "to" pane offset that
    /// keeps matching content aligned:
    ///
    /// - `adjustmentForScroll` tapers so the documents align at mid-screen and
    ///   pin exactly at the top/bottom.
    /// - `minY`/`maxY` bracket `currentOffset` using the closest reference
    ///   nodes; the same brackets in the "to" pane are used for interpolation.
    /// - If there is no node after the current position, interpolate to the
    ///   true end of the document.
    private func map(_ currentOffset: CGFloat,
                     from fromAnchors: [CGFloat],
                     fromContentHeight: CGFloat,
                     fromVisibleHeight: CGFloat,
                     to toAnchors: [CGFloat],
                     toContentHeight: CGFloat,
                     toVisibleHeight: CGFloat) -> CGFloat {
        let fromMax = max(0, fromContentHeight - fromVisibleHeight)
        let toMax = max(0, toContentHeight - toVisibleHeight)

        // Align the documents in the middle of the screen, except at the
        // top/bottom of the document (the taper).
        let topTaper = clamp01(currentOffset / fromVisibleHeight)
        let bottomTaper = 1 - clamp01((currentOffset - fromContentHeight + 2 * fromVisibleHeight) / fromVisibleHeight)
        let adjustmentForScroll = topTaper * bottomTaper * fromVisibleHeight / 2

        // Find the closest reference node before the current position and the
        // first one after it (skipping any within the last visible screen, so
        // the final stretch interpolates to the end of the document).
        var relativeIndex = -1
        var minY: CGFloat = 0
        var maxY: CGFloat = 0
        for anchor in fromAnchors {
            let anchorY = anchor - adjustmentForScroll
            if anchorY < currentOffset {
                relativeIndex += 1
                minY = anchorY
            } else if maxY == 0 && anchorY < fromMax {
                maxY = anchorY
            }
        }

        var interpolateToEndOfDocument = false
        if maxY == 0 {
            maxY = fromMax + adjustmentForScroll
            interpolateToEndOfDocument = true
        }

        let scrolled = max(0, currentOffset - minY)
        let ratioBetween = maxY > minY ? clamp01(scrolled / (maxY - minY)) : 1

        var topY: CGFloat = 0
        var bottomY = toMax
        if relativeIndex >= 0, toAnchors.count > relativeIndex {
            topY = floor(toAnchors[relativeIndex]) - adjustmentForScroll
        }
        if !interpolateToEndOfDocument, toAnchors.count > relativeIndex + 1 {
            bottomY = ceil(toAnchors[relativeIndex + 1]) - adjustmentForScroll
        }

        return topY + (bottomY - topY) * ratioBetween
    }
}
