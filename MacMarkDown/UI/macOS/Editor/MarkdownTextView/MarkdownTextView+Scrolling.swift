import AppKit

// MARK: - Scrolling & viewport
//
// O(1) jumps to a location (instead of laying out everything in between),
// centering, and deferring expensive content-size measurement while the user
// is actively scrolling or live-resizing.

extension MarkdownTextView {

    /// Scrolls the given range into view, relocating the TextKit viewport
    /// directly when the target is far away.
    func scrollToVisible(_ textRange: NSTextRange, type: NSTextLayoutManager.SegmentType = .standard) {
        let controller = textLayoutManager.textViewportLayoutController

        if let viewportRange = controller.viewportRange {
            let inViewport = textRange.isEmpty
                ? viewportRange.contains(textRange.location)
                : viewportRange.intersects(textRange)
            if !inViewport {
                relocateViewport(to: textRange.location)
                layoutSubtreeIfNeeded()
            }
        }

        guard let segmentFrame = textLayoutManager.textSegmentFrame(in: textRange, type: type) else { return }
        let origin = textContainerOrigin
        scrollToVisible(segmentFrame.offsetBy(dx: origin.x, dy: origin.y))
    }

    /// Moves the TextKit viewport anchor to `location` in O(1).
    func relocateViewport(to location: any NSTextLocation) {
        textLayoutManager.textViewportLayoutController.relocateViewport(to: location)
    }

    /// Centers the current selection in the visible area (Find/Go-to behavior).
    override func centerSelectionInVisibleArea(_ sender: Any?) {
        guard let selectionRange = textLayoutManager.textSelections.last?.textRanges.last,
              let segmentFrame = textLayoutManager.textSegmentFrame(in: selectionRange, type: .selection)
        else { return }
        let origin = textContainerOrigin
        guard let clipView = enclosingScrollView?.contentView else { return }
        let targetY = segmentFrame.midY + origin.y - clipView.bounds.height / 2
        clipView.scroll(to: NSPoint(x: clipView.bounds.origin.x, y: max(0, targetY)))
        enclosingScrollView?.reflectScrolledClipView(clipView)
    }

    // MARK: - Deferred measurement

    /// Whether a full content-size measurement should be deferred (the user is
    /// live-scrolling or live-resizing, where a frame change would jitter).
    var shouldDeferContentSizeUpdate: Bool {
        isLiveScrolling || isLiveResizing
    }

    @objc func liveScrollWillStart(_ note: Notification) {
        isLiveScrolling = true
    }

    @objc func liveScrollDidEnd(_ note: Notification) {
        isLiveScrolling = false
        needsFullHeightMeasurement = true
        needsLayout = true
    }

    override func viewWillStartLiveResize() {
        super.viewWillStartLiveResize()
        isLiveResizing = true
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        isLiveResizing = false
        needsFullHeightMeasurement = true
        needsLayout = true
    }
}
