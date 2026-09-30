import AppKit

// MARK: - Selection
//
// Selection rendering (a highlight band under the text) and the pointer +
// keyboard interactions that drive `textSelections`. The rendered rects come
// from `.selection` segment frames — the macOS 27 SDK removed
// `NSTextSelectionNavigation.selectionRects(for:)`, so the layout manager
// supplies the segment frames directly.

extension MarkdownTextView {

    /// Rectangles (view coordinates) covering the current selection, offset by
    /// the container origin so they line up with the fragment views.
    /// Empty selections (carets) produce no fill.
    var textSelectionRects: [CGRect] {
        selectionRects(clampedTo: nil)
    }

    /// The selection rectangles that fall in the laid-out viewport. Used for
    /// the highlight bands: enumerating `textSelections` is expensive, and a
    /// whole-document selection (⌘A) would otherwise create one band per line
    /// in the entire document. The viewport has a prefetch margin, so slightly
    /// off-screen bands exist before they scroll in.
    var visibleTextSelectionRects: [CGRect] {
        selectionRects(clampedTo: textLayoutManager.textViewportLayoutController.viewportRange)
    }

    private func selectionRects(clampedTo viewportRange: NSTextRange?) -> [CGRect] {
        var frames: [CGRect] = []
        for selection in textLayoutManager.textSelections {
            for selectionRange in selection.textRanges where !selectionRange.isEmpty {
                let range = viewportRange.flatMap { selectionRange.clamped(to: $0) } ?? selectionRange
                guard !range.isEmpty else { continue }
                textLayoutManager.enumerateTextSegments(in: range, type: .selection, options: .rangeNotRequired) { _, segmentFrame, _, _ in
                    frames.append(segmentFrame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y))
                    return true
                }
            }
        }
        return frames
    }

    /// Single assignment point for selection changes, whether pointer-driven
    /// or from navigation. Keeps the insertion point views and the highlight
    /// bands in sync.
    func updateSelections(_ selections: [NSTextSelection]) {
        textLayoutManager.textSelections = selections
        updateInsertionPointStateAndRestartTimer()
        notifySelectionChange()
        selectionView.updateHighlights()
    }
}

// MARK: - Pointer selection

extension MarkdownTextView {

    private var selectionAnchor: NSTextSelection? {
        get { _selectionAnchor }
        set { _selectionAnchor = newValue }
    }

    /// Caret at the given content point (character granularity).
    func caretSelection(at point: NSPoint) -> NSTextSelection? {
        textLayoutManager.textSelectionNavigation.textSelections(
            interactingAt: point,
            inContainerAt: textLayoutManager.documentRange.location,
            anchors: [],
            modifiers: [],
            selecting: false,
            bounds: .zero
        ).first
    }

    /// Word/line/paragraph selection enclosing the given content point.
    func selectionForGranularity(_ granularity: NSTextSelection.Granularity, at point: NSPoint) -> NSTextSelection? {
        textLayoutManager.textSelectionNavigation.textSelection(
            for: granularity,
            enclosing: point,
            inContainerAt: textLayoutManager.documentRange.location
        )
    }

    /// The selection stretched between a content point and an anchor, used by
    /// drag-to-select and shift-click. The `.extend` modifier keeps the anchor
    /// fixed in place while the interaction end moves with the pointer.
    func marqueeSelection(from point: NSPoint, anchor: NSTextSelection) -> NSTextSelection? {
        textLayoutManager.textSelectionNavigation.textSelections(
            interactingAt: point,
            inContainerAt: textLayoutManager.documentRange.location,
            anchors: [anchor],
            modifiers: [.extend],
            selecting: true,
            bounds: .zero
        ).first
    }

    /// Converts a mouse event into the layout manager's container space
    /// (view point minus the content insets).
    func containerPoint(for event: NSEvent) -> NSPoint {
        let viewPoint = convert(event.locationInWindow, from: nil)
        return NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
    }

    override func mouseDown(with event: NSEvent) {        guard isSelectable else {
            super.mouseDown(with: event)
            return
        }
        window?.makeFirstResponder(self)
        let point = containerPoint(for: event)

        // A press inside the existing selection may start a drag-out gesture.
        // The selection is kept until the drag disambiguates: a quick drag
        // extends it from the press point, a held drag drags it out, and a
        // click collapses it to a caret (all resolved in mouseDragged/mouseUp).
        pendingDragOrigin = nil
        if event.clickCount == 1,
           !event.modifierFlags.contains(.shift),
           textLayoutManager.textSelections.flatMap(\.textRanges).contains(where: { !$0.isEmpty }),
           selectionContains(point) {
            pendingDragOrigin = point
            _pendingDragStartTime = event.timestamp
        }

        switch event.clickCount {
        case 1:
            if pendingDragOrigin != nil {
                // Keep the selection; wait for a drag/click to disambiguate.
            } else if event.modifierFlags.contains(.shift), let anchor = selectionAnchor,
               let extended = marqueeSelection(from: point, anchor: anchor) {
                _selectionAnchor = extended
                updateSelections([extended])
            } else if let caret = caretSelection(at: point) {
                selectionAnchor = caret
                updateSelections([caret])
            }
        case 2:
            if let word = selectionForGranularity(.word, at: point) {
                selectionAnchor = word
                updateSelections([word])
            }
        default:
            // Triple-click selects the enclosing paragraph.
            if let paragraph = selectionForGranularity(.paragraph, at: point) {
                selectionAnchor = paragraph
                updateSelections([paragraph])
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = containerPoint(for: event)

        // Dragging from inside the selection drags it out of the editor, but
        // only after a press-and-hold: an immediate drag is a normal
        // re-selection that starts over at the press point.
        if let origin = pendingDragOrigin {
            let dx = point.x - origin.x
            let dy = point.y - origin.y
            if dx * dx + dy * dy > 9 { // ~3pt threshold
                pendingDragOrigin = nil
                if event.timestamp - _pendingDragStartTime >= dragOutHoldDuration {
                    beginSelectionDrag(with: event, origin: origin)
                    return
                }
                if let caret = caretSelection(at: origin) {
                    selectionAnchor = caret
                    updateSelections([caret])
                }
            }
        }

        guard isSelectable, let anchor = selectionAnchor else { return }
        autoscroll(with: event)
        if let dragged = marqueeSelection(from: point, anchor: anchor) {
            updateSelections([dragged])
        }
    }

    override func mouseUp(with event: NSEvent) {
        // A click (no drag) that started inside the selection collapses it to
        // the click point, matching `NSTextView`.
        if let origin = pendingDragOrigin,
           let caret = caretSelection(at: containerPoint(for: event)) ?? caretSelection(at: origin) {
            selectionAnchor = caret
            updateSelections([caret])
        }
        pendingDragOrigin = nil
    }

    /// Whether `point` (content coordinates) falls inside a selected range.
    private func selectionContains(_ point: NSPoint) -> Bool {
        for selection in textLayoutManager.textSelections {
            for range in selection.textRanges where !range.isEmpty {
                var hit = false
                textLayoutManager.enumerateTextSegments(in: range, type: .selection, options: [.rangeNotRequired]) { _, frame, _, _ in
                    if frame.contains(point) { hit = true; return false }
                    return true
                }
                if hit { return true }
            }
        }
        return false
    }

    /// Starts a dragging session carrying the selected text (RTF + plain).
    private func beginSelectionDrag(with event: NSEvent, origin: NSPoint) {
        guard let attributed = textLayoutManager.textSelectionsAttributedString() else { return }
        let cleaned = Self.strippingViewDefaultColor(attributed, defaultColor: textColor)
        let item = NSPasteboardItem()
        if let rtf = try? cleaned.data(
            from: NSRange(location: 0, length: cleaned.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            item.setData(rtf, forType: .rtf)
        }
        item.setString(cleaned.string, forType: .string)

        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        let viewOrigin = NSPoint(x: origin.x + textContainerOrigin.x, y: origin.y + textContainerOrigin.y)
        draggingItem.setDraggingFrame(NSRect(origin: viewOrigin, size: NSSize(width: 24, height: 16)), contents: nil)

        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }
}

// MARK: - Keyboard selection extension

extension MarkdownTextView {

    override func moveLeftAndModifySelection(_ sender: Any?) {
        extendSelection(direction: .backward, destination: .character)
    }

    override func moveRightAndModifySelection(_ sender: Any?) {
        extendSelection(direction: .forward, destination: .character)
    }

    override func moveToBeginningOfLineAndModifySelection(_ sender: Any?) {
        extendSelection(direction: .backward, destination: .line)
    }

    override func moveToEndOfLineAndModifySelection(_ sender: Any?) {
        extendSelection(direction: .forward, destination: .line)
    }

    override func moveToBeginningOfDocumentAndModifySelection(_ sender: Any?) {
        extendSelection(direction: .backward, destination: .document)
    }

    override func moveToEndOfDocumentAndModifySelection(_ sender: Any?) {
        extendSelection(direction: .forward, destination: .document)
    }

    override func moveUp(_ sender: Any?) {
        moveVertically(.up, extending: false)
    }

    override func moveDown(_ sender: Any?) {
        moveVertically(.down, extending: false)
    }

    override func moveUpAndModifySelection(_ sender: Any?) {
        moveVertically(.up, extending: true)
    }

    override func moveDownAndModifySelection(_ sender: Any?) {
        moveVertically(.down, extending: true)
    }

    private func extendSelection(direction: NSTextSelectionNavigation.Direction, destination: NSTextSelectionNavigation.Destination) {
        guard let selection = textLayoutManager.textSelections.last,
              let extended = textLayoutManager.textSelectionNavigation.destinationSelection(
                  for: selection,
                  direction: direction,
                  destination: destination,
                  extending: true,
                  confined: false
              ) else { return }
        updateSelections([extended])
    }

    /// Moves the caret or extends the selection to the adjacent line. The
    /// navigation's `.up`/`.down` visual directions keep the anchor column
    /// across consecutive keystrokes, including across soft-wrapped lines.
    private func moveVertically(_ direction: NSTextSelectionNavigation.Direction, extending: Bool) {
        guard let selection = textLayoutManager.textSelections.last,
              let next = textLayoutManager.textSelectionNavigation.destinationSelection(
                  for: selection,
                  direction: direction,
                  destination: .character,
                  extending: extending,
                  confined: false
              ) else { return }
        updateSelections([next])
    }
}