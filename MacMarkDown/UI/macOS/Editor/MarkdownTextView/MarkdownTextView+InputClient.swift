import AppKit

// MARK: - NSTextInputClient
//
// The input context routes keyboard events and IME operations here. The
// protocol is legacy (non-actor-isolated) AppKit, so the conformance itself is
// declared `@MainActor`-isolated (SE-0466) to keep strict concurrency happy;
// the input context only ever calls in on the main thread.

extension MarkdownTextView: @MainActor NSTextInputClient {

    @objc
    func selectedRange() -> NSRange {
        guard let selection = textLayoutManager.textSelections.last?.textRanges.last else { return .notFound }
        return textContentStorage.range(from: selection)
    }

    @objc
    func setMarkedText(_ string: Any, selectedRange markedTextSelectedRange: NSRange, replacementRange: NSRange) {
        let attributedMarkedString: NSAttributedString
        switch string {
        case let attributedString as NSAttributedString:
            let mutable = NSMutableAttributedString(attributedString: attributedString)
            // IMEs often attach a clear underline color that renders invisibly.
            mutable.removeAttribute(.underlineColor, range: NSRange(location: 0, length: mutable.length))
            let attrs = typingAttributes.merging(markedTextAttributes) { _, new in new }
            mutable.addAttributes(attrs, range: NSRange(location: 0, length: mutable.length))
            attributedMarkedString = mutable
        case let string as String:
            let attrs = typingAttributes.merging(markedTextAttributes) { _, new in new }
            attributedMarkedString = NSAttributedString(string: string, attributes: attrs)
        default:
            assertionFailure()
            return
        }

        if replacementRange.location != NSNotFound {
            if markedText == nil {
                markedText = MarkdownTextMarking(
                    markedText: attributedMarkedString,
                    markedRange: NSRange(location: replacementRange.location, length: attributedMarkedString.length)
                )
            } else {
                markedText?.markedText = attributedMarkedString
                markedText?.markedRange = NSRange(location: replacementRange.location, length: attributedMarkedString.length)
            }
        } else if let currentMarkedText = markedText {
            // Delete the previous provisional text, then replace it in place.
            withUndoRegistrationSuppressed { [self] in
                if let textRange = textContentStorage.textRange(from: currentMarkedText.markedRange) {
                    replaceCharacters(in: textRange, with: NSAttributedString(), allowsTypingCoalescing: false)
                }
            }
            currentMarkedText.markedText = attributedMarkedString
            currentMarkedText.markedRange = NSRange(
                location: currentMarkedText.markedRange.location,
                length: attributedMarkedString.length
            )
        } else {
            markedText = MarkdownTextMarking(
                markedText: attributedMarkedString,
                markedRange: NSRange(location: selectedRange().location, length: attributedMarkedString.length)
            )
        }

        let insertionLength = replacementRange.location == NSNotFound ? 0 : replacementRange.length
        let insertionRange = NSRange(
            location: markedText?.markedRange.location ?? 0,
            length: insertionLength
        )
        withUndoRegistrationSuppressed { [self] in
            if let insertionNSTextRange = textContentStorage.textRange(from: insertionRange) {
                replaceCharacters(
                    in: insertionNSTextRange,
                    with: markedText?.markedText ?? NSAttributedString(),
                    allowsTypingCoalescing: false
                )
            }
        }
        updateInsertionPointStateAndRestartTimer()
        needsLayout = true
    }

    @objc
    func unmarkText() {
        if hasMarkedText() {
            withUndoRegistrationSuppressed { [self] in
                let markedRange = markedText?.markedRange
                if let textRange = markedRange.flatMap({ textContentStorage.textRange(from: $0) }) {
                    replaceCharacters(in: textRange, with: NSAttributedString(), allowsTypingCoalescing: false)
                }
            }
        }
        markedText = nil
        updateInsertionPointStateAndRestartTimer()
        needsLayout = true
    }

    @objc
    func markedRange() -> NSRange {
        markedText?.markedRange ?? .notFound
    }

    @objc
    func hasMarkedText() -> Bool {
        markedText != nil
    }

    @objc
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        // Callers may pass out-of-bounds ranges; clamp to document edges.
        let clamped = clampToDocument(range)
        guard let textRange = textContentStorage.textRange(from: clamped), !textRange.isEmpty else { return nil }
        actualRange?.pointee = textContentStorage.range(from: textRange)
        return textStorage?.attributedSubstring(from: textContentStorage.range(from: textRange))
    }

    @objc
    func attributedString() -> NSAttributedString {
        textContentStorage.attributedString ?? NSAttributedString()
    }

    @objc
    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [
            .underlineStyle,
            .underlineColor,
            .markedClauseSegment,
            NSAttributedString.Key("NSTextInputReplacementRangeAttributeName")
        ]
    }

    @objc
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let window else { return .zero }
        guard let textRange = textContentStorage.textRange(from: clampToDocument(range)) else { return .zero }
        var rect: NSRect = .zero
        textLayoutManager.enumerateTextSegments(in: textRange, type: .standard, options: .rangeNotRequired) { _, segmentFrame, _, _ in
            let frameInContent = segmentFrame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            rect = window.convertToScreen(contentView.convert(frameInContent, to: nil))
            return false
        }
        return rect
    }

    @objc
    func characterIndex(for point: NSPoint) -> Int {
        guard let window else { return NSNotFound }
        let viewPoint = contentView.convert(window.convertPoint(fromScreen: point), from: nil)
        let containerPoint = NSPoint(
            x: viewPoint.x - textContainerOrigin.x,
            y: viewPoint.y - textContainerOrigin.y
        )
        let navigation = textLayoutManager.textSelectionNavigation
        let selection = navigation.textSelections(
            interactingAt: containerPoint,
            inContainerAt: textLayoutManager.documentRange.location,
            anchors: [],
            modifiers: [],
            selecting: false,
            bounds: .zero
        )
        guard let location = selection.first?.textRanges.first?.location else { return NSNotFound }
        return textContentStorage.offset(from: textLayoutManager.documentRange.location, to: location)
    }

    @objc
    func insertText(_ string: Any, replacementRange: NSRange) {
        unmarkText()

        var textRanges: [NSTextRange] = []
        if replacementRange == .notFound {
            textRanges = textLayoutManager.textSelections.flatMap(\.textRanges)
            assert(!textRanges.isEmpty, "Unknown selection range to insert")
        } else if let replacementTextRange = textContentStorage.textRange(from: replacementRange),
                  !textRanges.contains(where: { $0 == replacementTextRange }) {
            textRanges.append(replacementTextRange)
        }

        switch string {
        case let input as String:
            if shouldChangeText(in: textRanges, replacementString: input) {
                replaceCharacters(in: textRanges, with: input, useTypingAttributes: true, allowsTypingCoalescing: true)
                updateTypingAttributes()
            }
        case let input as NSAttributedString:
            if shouldChangeText(in: textRanges, replacementString: input.string) {
                replaceCharacters(in: textRanges, with: input, allowsTypingCoalescing: true)
                updateTypingAttributes()
            }
        default:
            assertionFailure()
        }
    }

    private func clampToDocument(_ range: NSRange) -> NSRange {
        let documentLength = textContentStorage.documentLength
        let location = max(0, min(documentLength, range.location))
        let length = max(0, min(range.length, documentLength - location))
        return NSRange(location: location, length: length)
    }
}

// MARK: - Marked-text bookkeeping

/// Provisional (in-progress IME) text currently displayed in the document.
/// Distinct from `textSelections`, which always reflects the committed text.
final class MarkdownTextMarking {
    var markedText: NSAttributedString
    var markedRange: NSRange

    init(markedText: NSAttributedString, markedRange: NSRange) {
        self.markedText = markedText
        self.markedRange = markedRange
    }
}