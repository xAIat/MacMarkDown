import AppKit

// MARK: - Standard editing commands
//
// `interpretKeyEvents(_:)` maps the remaining macOS text-editing key
// bindings (⌥←/⌥→ word navigation, Home/End, ⌥⌫/⌘⌫ deletions, fn-arrow page
// scrolling, …) onto the `NSResponder` action selectors overridden here. Each
// movement goes through `NSTextSelectionNavigation` (same as the existing
// `moveLeft`/`moveUp`), and every deletion funnels through
// `replaceCharacters` so it registers an undo step like any other edit.

extension MarkdownTextView {

    // MARK: - Word navigation

    override func moveWordLeft(_ sender: Any?) {
        moveToWordBoundary(isForward: false, extending: false)
    }

    override func moveWordRight(_ sender: Any?) {
        moveToWordBoundary(isForward: true, extending: false)
    }

    override func moveWordLeftAndModifySelection(_ sender: Any?) {
        moveToWordBoundary(isForward: false, extending: true)
    }

    override func moveWordRightAndModifySelection(_ sender: Any?) {
        moveToWordBoundary(isForward: true, extending: true)
    }

    // MARK: - Paragraph navigation

    override func moveToBeginningOfParagraph(_ sender: Any?) {
        navigate(direction: .backward, destination: .paragraph, extending: false)
    }

    override func moveToEndOfParagraph(_ sender: Any?) {
        navigate(direction: .forward, destination: .paragraph, extending: false)
    }

    override func moveToBeginningOfParagraphAndModifySelection(_ sender: Any?) {
        navigate(direction: .backward, destination: .paragraph, extending: true)
    }

    override func moveToEndOfParagraphAndModifySelection(_ sender: Any?) {
        navigate(direction: .forward, destination: .paragraph, extending: true)
    }

    // MARK: - Line ends (Home / End)

    override func moveToLeftEndOfLine(_ sender: Any?) {
        navigate(direction: .backward, destination: .line, extending: false)
    }

    override func moveToRightEndOfLine(_ sender: Any?) {
        navigate(direction: .forward, destination: .line, extending: false)
    }

    override func moveToLeftEndOfLineAndModifySelection(_ sender: Any?) {
        navigate(direction: .backward, destination: .line, extending: true)
    }

    override func moveToRightEndOfLineAndModifySelection(_ sender: Any?) {
        navigate(direction: .forward, destination: .line, extending: true)
    }

    /// Shared keyboard-navigation primitive: moves the caret (or extends the
    /// selection) to the nearest boundary of `destination`, the same way the
    /// existing `moveLeft`/`moveUp` families use the text selection navigation.
    private func navigate(
        direction: NSTextSelectionNavigation.Direction,
        destination: NSTextSelectionNavigation.Destination,
        extending: Bool
    ) {
        guard let selection = textLayoutManager.textSelections.last,
              let next = textLayoutManager.textSelectionNavigation.destinationSelection(
                  for: selection,
                  direction: direction,
                  destination: destination,
                  extending: extending,
                  confined: false
              ) else { return }
        updateSelections([next])
    }

    // MARK: - Word navigation helper

    /// Moves the caret (or extends the selection) by one word, using
    /// whitespace-delimited word boundaries that match ⌥←/⌥→ in `NSTextView`.
    private func moveToWordBoundary(isForward: Bool, extending: Bool) {
        guard !textLayoutManager.textSelections.isEmpty else { return }
        let ns = string as NSString
        let length = ns.length
        let selection = selectedRange()
        let boundary = isForward
            ? nextWordStart(from: selection.location, in: ns, length: length)
            : previousWordStart(from: selection.location, in: ns)
        guard boundary != selection.location else { return }

        if extending {
            let start = min(selection.location, boundary)
            let end = max(selection.location + selection.length, boundary)
            selectAndScroll(to: NSRange(location: start, length: end - start))
        } else {
            selectAndScroll(to: NSRange(location: boundary, length: 0))
        }
    }

    static func isWordBoundaryUnit(_ unit: unichar) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D
    }

    private func nextWordStart(from offset: Int, in ns: NSString, length: Int) -> Int {
        var i = offset
        if i < length {
            if Self.isWordBoundaryUnit(ns.character(at: i)) {
                while i < length, Self.isWordBoundaryUnit(ns.character(at: i)) { i += 1 }
            } else {
                while i < length, !Self.isWordBoundaryUnit(ns.character(at: i)) { i += 1 }
                while i < length, Self.isWordBoundaryUnit(ns.character(at: i)) { i += 1 }
            }
        }
        return i
    }

    private func previousWordStart(from offset: Int, in ns: NSString) -> Int {
        var i = offset
        while i > 0, Self.isWordBoundaryUnit(ns.character(at: i - 1)) { i -= 1 }
        while i > 0, !Self.isWordBoundaryUnit(ns.character(at: i - 1)) { i -= 1 }
        return i
    }

    private func selectAndScroll(to range: NSRange) {
        setSelectedRange(range)
        scrollRangeToVisible(range)
    }

    // MARK: - Word / line deletion

    override func deleteWordBackward(_ sender: Any?) {
        deleteBeyondSelectionThen(direction: .backward, destination: .word)
    }

    override func deleteWordForward(_ sender: Any?) {
        deleteBeyondSelectionThen(direction: .forward, destination: .word)
    }

    override func deleteToBeginningOfLine(_ sender: Any?) {
        deleteBeyondSelectionThen(direction: .backward, destination: .line)
    }

    override func deleteToEndOfLine(_ sender: Any?) {
        deleteBeyondSelectionThen(direction: .forward, destination: .line)
    }

    /// Deletes an existing selection first (matching `deleteBackward`), else
    /// deletes the span between the caret and the nearby `destination`
    /// boundary. Registers a single undo step through `replaceCharacters`.
    private func deleteBeyondSelectionThen(
        direction: NSTextSelectionNavigation.Direction,
        destination: NSTextSelectionNavigation.Destination
    ) {
        guard isEditable else { return }

        let selected = selectedRange()
        if selected.length > 0 {
            if let textRange = textContentStorage.textRange(from: selected),
               shouldChangeText(in: [textRange], replacementString: "") {
                replaceCharacters(in: textRange, with: NSAttributedString(), allowsTypingCoalescing: true)
                updateTypingAttributes()
            }
            return
        }

        let navigation = textLayoutManager.textSelectionNavigation
        guard let selection = textLayoutManager.textSelections.last,
              let boundarySelection = navigation.destinationSelection(
                  for: selection,
                  direction: direction,
                  destination: destination,
                  extending: false,
                  confined: false
              ),
              let boundary = boundarySelection.textRanges.first?.location,
              let caret = selection.textRanges.first?.location
        else { return }

        let documentStart = textContentStorage.documentRange.location
        let boundaryOffset = textContentStorage.offset(from: documentStart, to: boundary)
        let caretOffset = textContentStorage.offset(from: documentStart, to: caret)
        guard boundaryOffset != NSNotFound, caretOffset != NSNotFound else { return }

        let start = min(boundaryOffset, caretOffset)
        let end = max(boundaryOffset, caretOffset)
        guard let deleteRange = textContentStorage.textRange(
            from: NSRange(location: start, length: end - start)
        ), !deleteRange.isEmpty else { return }

        if shouldChangeText(in: [deleteRange], replacementString: "") {
            replaceCharacters(in: deleteRange, with: NSAttributedString(), allowsTypingCoalescing: true)
            updateTypingAttributes()
        }
    }

    // MARK: - Page scrolling (fn + arrow)

    override func pageUp(_ sender: Any?) {
        scrollByPage(isUp: true)
    }

    override func pageDown(_ sender: Any?) {
        scrollByPage(isUp: false)
    }

    override func scrollPageUp(_ sender: Any?) {
        scrollByPage(isUp: true)
    }

    override func scrollPageDown(_ sender: Any?) {
        scrollByPage(isUp: false)
    }

    /// Scrolls the enclosing scroll view by one viewport (leaving a sliver of
    /// the previous content, like `NSTextView`) and parks the caret on the
    /// text that is now at the newly-visible edge.
    private func scrollByPage(isUp: Bool) {
        guard let scrollView = enclosingScrollView else { return }
        let clipBounds = scrollView.contentView.bounds
        let pageHeight = max(clipBounds.height - 8, 8)
        let minY: CGFloat = 0
        let maxY = max(0, frame.height - clipBounds.height)
        let targetY = min(maxY, max(minY, clipBounds.origin.y + (isUp ? -pageHeight : pageHeight)))

        let targetPoint = NSPoint(x: clipBounds.origin.x, y: targetY)
        scrollView.contentView.scroll(to: targetPoint)
        scrollView.reflectScrolledClipView(scrollView.contentView)

        let caretY = targetY + (isUp ? clipBounds.height - 4 : 4)
        let containerPoint = NSPoint(x: 2, y: caretY - textContainerOrigin.y)
        if let caret = caretSelection(at: containerPoint) {
            updateSelections([caret])
        }
    }
}