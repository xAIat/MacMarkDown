import AppKit

// MARK: - Mutation core
//
// Every user edit funnels through `replaceCharacters(in:with:)`. It performs
// the replacement inside `performEditingTransaction` so TextKit 2 (the layout
// manager, the viewport) and `textSelections` stay consistent, then registers
// an undo action that replays the same primitive.
//
// All writes go through the backing `NSTextStorage` rather than
// `replaceContents(in:with:)`: on the macOS 27 SDK that call is a no-op when
// the content storage is empty (verified with a standalone probe), and the
// storage primitive works uniformly for empty and non-empty documents.

extension MarkdownTextView {

    // MARK: - Responder gate

    override var acceptsFirstResponder: Bool { isSelectable }

    // MARK: - Text change signals

    /// Begins a coalesceable text-change session. No listeners yet (Milestone 4
    /// wires the editor host), but kept so the mutation contract reads like
    /// `NSTextView`'s.
    func textWillChange() {
        // Milestone 4 hooks `NSText.didBeginEditingNotification`-style signals here.
    }

    /// Concludes a text change, asks for relayout/redraw and keeps the caret
    /// visible.
    func didChangeText() {
        textMutationGeneration &+= 1
        if let caretRange = textLayoutManager.textSelections.last?.textRanges.last {
            scrollRangeToVisible(textContentStorage.range(from: caretRange))
        }
        updateInsertionPointStateAndRestartTimer()
        notifySelectionChange()
        needsLayout = true
        needsDisplay = true
    }

    /// Reports the current selection to `onSelectionChange`, if set.
    func notifySelectionChange() {
        onSelectionChange?(selectedRange())
    }

    /// Whether user-initiated edits are allowed. No delegate yet, so always
    /// accepts (Milestone 4 wires the editor host's "is editable" semantics).
    func shouldChangeText(in textRanges: [NSTextRange], replacementString: String?) -> Bool {
        true
    }

    // MARK: - EditorTextViewHost (NSRange-space entry points)

    /// Registration point for host-level edits. The smart-editing helpers call
    /// this before `replaceCharacters(in:with:)`; the handler verdict decides
    /// whether the subsequent replacement proceeds.
    func shouldChangeText(in range: NSRange, replacementString text: String?) -> Bool {
        shouldChangeTextHandler?(range, text) ?? true
    }

    /// `NSRange`-space replacement used by the host surface. Bridges into the
    /// `NSTextRange` core with the current typing attributes.
    func replaceCharacters(in range: NSRange, with string: String) {
        guard let replacement = textContentStorage.textRange(from: range) else { return }
        replaceCharacters(
            in: replacement,
            with: NSAttributedString(string: string),
            allowsTypingCoalescing: true
        )
    }

    // MARK: - Replacement core

    /// Replaces one text range. The workhorse of every edit.
    func replaceCharacters(
        in textRange: NSTextRange,
        with replacementString: NSAttributedString,
        allowsTypingCoalescing: Bool
    ) {
        let previousStringInRange = (textContentStorage.attributedString ?? NSAttributedString())
            .attributedSubstring(from: textContentStorage.range(from: textRange))

        if let shouldChangeTextHandler,
           !shouldChangeTextHandler(textContentStorage.range(from: textRange), replacementString.string) {
            return
        }

        textWillChange()

        textContentStorage.performEditingTransaction {
            textStorage?.replaceCharacters(
                in: textContentStorage.range(from: textRange),
                with: replacementString
            )
        }

        didChangeText()

        guard allowsUndo, let undoManager, undoManager.isUndoRegistrationEnabled else { return }
        registerUndo(for: textRange, replacementLength: replacementString.length, previousString: previousStringInRange)
    }

    /// String variant: the replacement is stamped with the current typing attributes.
    func replaceCharacters(
        in textRange: NSTextRange,
        with replacementString: String,
        useTypingAttributes: Bool,
        allowsTypingCoalescing: Bool
    ) {
        replaceCharacters(
            in: textRange,
            with: NSAttributedString(string: replacementString, attributes: useTypingAttributes ? typingAttributes : [:]),
            allowsTypingCoalescing: allowsTypingCoalescing
        )
    }

    /// Multi-range variant; edits apply back-to-front so offsets stay valid.
    func replaceCharacters(
        in textRanges: [NSTextRange],
        with replacementString: NSAttributedString,
        allowsTypingCoalescing: Bool
    ) {
        let documentStart = textContentStorage.documentRange.location
        for textRange in textRanges.sorted(by: { lhs, rhs in
            let l = textContentStorage.offset(from: documentStart, to: lhs.location)
            let r = textContentStorage.offset(from: documentStart, to: rhs.location)
            return l > r
        }) {
            replaceCharacters(
                in: textRange,
                with: replacementString,
                allowsTypingCoalescing: allowsTypingCoalescing
            )
        }
    }

    func replaceCharacters(
        in textRanges: [NSTextRange],
        with replacementString: String,
        useTypingAttributes: Bool,
        allowsTypingCoalescing: Bool
    ) {
        replaceCharacters(
            in: textRanges,
            with: NSAttributedString(string: replacementString, attributes: useTypingAttributes ? typingAttributes : [:]),
            allowsTypingCoalescing: allowsTypingCoalescing
        )
    }

    private func registerUndo(for textRange: NSTextRange, replacementLength: Int, previousString: NSAttributedString) {
        guard let undoManager else { return }
        let undoEnd = textContentStorage.location(textRange.location, offsetBy: replacementLength) ?? textRange.location
        let undoRange = NSTextRange(location: textRange.location, end: undoEnd) ?? textRange
        let previousInsertion = NSRange(location: textContentStorage.offset(from: textContentStorage.documentRange.location, to: textRange.location), length: 0)

        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { [previousString] (textView: MarkdownTextView) in
            textView.replaceCharacters(
                in: undoRange,
                with: previousString,
                allowsTypingCoalescing: false
            )
            textView.setSelectedRange(previousInsertion)
        }
        undoManager.endUndoGrouping()
    }

    /// Forces the next edit into its own undo group. The macOS 27 SDK removed
    /// `UndoManager.breakUndoGrouping`; automatic event-loop grouping already
    /// splits per-key edits, and explicit splits land with milestone 4's undo
    /// design. Kept as the call site for that.
    func breakUndoCoalescing() {}

    /// Runs `action` with undo registration temporarily disabled (used by the
    /// marked-text bookkeeping, which must not be undoable on its own).
    func withUndoRegistrationSuppressed(_ action: () -> Void) {
        guard let undoManager, undoManager.isUndoRegistrationEnabled else {
            action()
            return
        }
        undoManager.disableUndoRegistration()
        action()
        undoManager.enableUndoRegistration()
    }

    // MARK: - Model-driven application

    /// Applies a new model text (produced outside the editor — a Format-menu
    /// command, the formatting toolbar, find/replace, a Touch Bar button) as a
    /// *minimal* replacement computed against the current text, so the change
    /// is a single undoable edit instead of a whole-document `setString` that
    /// drops the undo history. The insertion uses the current typing
    /// attributes; the syntax highlighter repaints the document afterwards.
    func applyModelEdit(to newText: String, selection: NSRange) {
        let current = string
        guard current != newText else {
            setSelectedRange(selection)
            return
        }

        let currentNS = current as NSString
        let newNS = newText as NSString

        var first = 0
        let commonPrefixLength = min(currentNS.length, newNS.length)
        while first < commonPrefixLength,
              currentNS.character(at: first) == newNS.character(at: first) {
            first += 1
        }

        var currentEnd = currentNS.length
        var newEnd = newNS.length
        while currentEnd > first,
              newEnd > first,
              currentNS.character(at: currentEnd - 1) == newNS.character(at: newEnd - 1) {
            currentEnd -= 1
            newEnd -= 1
        }

        let removedRange = NSRange(location: first, length: currentEnd - first)
        let replacement = newNS.substring(
            with: NSRange(location: first, length: newEnd - first)
        )
        replaceCharacters(in: removedRange, with: replacement)
    }

    /// Clears the document's undo/redo stacks. Called when a whole document is
    /// replaced from disk (open/revert), so undo never rewinds across files.
    func resetUndoHistory() {
        undoManager?.removeAllActions()
    }

    // MARK: - Selection

    /// NSTextView-compatible single-range selection setter (character
    /// granularity, downstream affinity). Mouse selection and rich navigation
    /// land in Milestone 3.
    func setSelectedRange(_ range: NSRange) {
        let documentLength = textContentStorage.documentLength
        let location = max(0, min(documentLength, range.location))
        let length = max(0, min(range.length, documentLength - location))
        guard let textRange = textContentStorage.textRange(from: NSRange(location: location, length: length)) else { return }
        setSelectedTextRange(textRange)
    }

    /// Sets the selection from a TextKit range, refreshes typing attributes and
    /// the insertion point.
    func setSelectedTextRange(_ textRange: NSTextRange) {
        textLayoutManager.textSelections = [
            NSTextSelection(range: textRange, affinity: .downstream, granularity: .character)
        ]
        updateTypingAttributes()
        updateInsertionPointStateAndRestartTimer()
        notifySelectionChange()
        selectionView.updateHighlights()
        needsLayout = true
    }

    // MARK: - Scrolling

    /// Scrolls the enclosing clip view so the given (document-relative UTF-16)
    /// range is visible, like `NSTextView.scrollRangeToVisible`.
    func scrollRangeToVisible(_ range: NSRange) {
        guard let textRange = textContentStorage.textRange(from: range) else { return }
        textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: .rangeNotRequired) { _, segmentFrame, _, _ in
            let origin = textContainerOrigin
            scrollToVisible(segmentFrame.offsetBy(dx: origin.x, dy: origin.y))
            return false
        }
    }

    // MARK: - Typing attributes

    /// Refreshes `typingAttributes` from the attributes at the caret.
    func updateTypingAttributes() {
        let location = textLayoutManager.textSelections.last?.textRanges.last?.location
        updateTypingAttributes(at: location)
    }

    func updateTypingAttributes(at location: (any NSTextLocation)?) {
        guard let location else {
            _typingAttributes = [:]
            return
        }
        _typingAttributes = attributesForTyping(at: location)
    }

    private func attributesForTyping(at location: any NSTextLocation) -> [NSAttributedString.Key: Any] {
        guard let storage = textStorage, storage.length > 0 else { return _defaultTypingAttributes }
        let offset = textContentStorage.offset(from: textContentStorage.documentRange.location, to: location)
        guard offset != NSNotFound else { return _defaultTypingAttributes }
        let index = min(max(0, offset - 1), storage.length - 1)
        let base = storage.attributes(at: index, effectiveRange: nil)
        return base.merging(_defaultTypingAttributes) { current, _ in current }
    }

    // MARK: - Standard editing commands
    //
    // `interpretKeyEvents(_:)` dispatches the classic `insert*`/`delete*`/`move*`
    // selectors here. Minimal single-caret implementations; arrow-key navigation
    // is fully fleshed out alongside mouse selection in Milestone 3.

    override func insertText(_ insertString: Any) {
        insertText(insertString, replacementRange: .notFound)
    }

    override func insertNewline(_ sender: Any?) {
        breakUndoCoalescing()
        insertText("\n", replacementRange: .notFound)
        breakUndoCoalescing()
    }

    override func insertNewlineIgnoringFieldEditor(_ sender: Any?) {
        insertNewline(sender)
    }

    override func insertTab(_ sender: Any?) {
        insertText("\t", replacementRange: .notFound)
    }

    override func insertBacktab(_ sender: Any?) {
        insertText("\t", replacementRange: .notFound)
    }

    override func deleteBackward(_ sender: Any?) {
        deleteInDirection(-1)
    }

    override func deleteForward(_ sender: Any?) {
        deleteInDirection(1)
    }

    /// Deletes one unit before (`delta < 0`) or at (`delta > 0`) the caret.
    private func deleteInDirection(_ delta: Int) {
        let selected = selectedRange()
        let documentLength = textContentStorage.documentLength

        if selected.length > 0 {
            guard let textRange = textContentStorage.textRange(from: selected) else { return }
            if shouldChangeText(in: [textRange], replacementString: "") {
                replaceCharacters(in: textRange, with: NSAttributedString(), allowsTypingCoalescing: true)
                updateTypingAttributes()
            }
            return
        }

        let start = selected.location + (delta < 0 ? -1 : 0)
        let end = selected.location + (delta < 0 ? 0 : 1)
        guard start >= 0, end <= documentLength, end > start else { return }
        guard let textRange = textContentStorage.textRange(from: NSRange(location: start, length: end - start)) else { return }
        if shouldChangeText(in: [textRange], replacementString: "") {
            replaceCharacters(in: textRange, with: NSAttributedString(), allowsTypingCoalescing: true)
            updateTypingAttributes()
        }
    }

    override func moveLeft(_ sender: Any?) {
        moveCaret(by: -1)
    }

    override func moveRight(_ sender: Any?) {
        moveCaret(by: 1)
    }

    override func moveToBeginningOfDocument(_ sender: Any?) {
        setSelectedTextRange(NSTextRange(location: textContentStorage.documentRange.location))
    }

    override func moveToEndOfDocument(_ sender: Any?) {
        setSelectedTextRange(NSTextRange(location: textContentStorage.documentRange.endLocation))
    }

    override func moveToBeginningOfLine(_ sender: Any?) {
        moveToBoundary(isUpstream: true)
    }

    override func moveToEndOfLine(_ sender: Any?) {
        moveToBoundary(isUpstream: false)
    }

    private func moveCaret(by delta: Int) {
        guard let caretRange = textLayoutManager.textSelections.last?.textRanges.last, caretRange.isEmpty else { return }
        let offset = textContentStorage.offset(from: textContentStorage.documentRange.location, to: caretRange.location)
        guard offset != NSNotFound else { return }
        let target = max(0, min(textContentStorage.documentLength, offset + delta))
        setSelectedRange(NSRange(location: target, length: 0))
    }

    private func moveToBoundary(isUpstream: Bool) {
        let navigation = textLayoutManager.textSelectionNavigation
        guard let selection = textLayoutManager.textSelections.last,
              let destination = navigation.destinationSelection(
                  for: selection,
                  direction: isUpstream ? .backward : .forward,
                  destination: .line,
                  extending: false,
                  confined: false
              ) else { return }
        textLayoutManager.textSelections = [destination]
        updateInsertionPointStateAndRestartTimer()
    }
}