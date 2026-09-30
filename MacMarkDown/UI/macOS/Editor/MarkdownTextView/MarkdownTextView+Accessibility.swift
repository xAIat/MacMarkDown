import AppKit

// MARK: - Accessibility
//
// `MarkdownTextView` is a plain `NSView`, so VoiceOver sees nothing useful by
// default. These overrides expose it as a text area with the standard
// character/range/line geometry.

extension MarkdownTextView {

    override func accessibilitySharedCharacterRange() -> NSRange {
        NSRange(location: 0, length: textContentStorage.documentLength)
    }

    override func isAccessibilityElement() -> Bool { true }

    override func isAccessibilityEnabled() -> Bool { isEditable || isSelectable }

    override func accessibilityRole() -> NSAccessibility.Role? { .textArea }

    override func accessibilityRoleDescription() -> String? {
        NSAccessibility.Role.description(for: self)
    }

    override func accessibilityLabel() -> String? {
        NSLocalizedString("Text Editor", comment: "Accessibility label for the Markdown editor")
    }

    override func accessibilityNumberOfCharacters() -> Int {
        textContentStorage.documentLength
    }

    override func accessibilityValue() -> Any? { string }

    override func setAccessibilityValue(_ accessibilityValue: Any?) {
        guard isEditable, let newValue = accessibilityValue as? String else { return }
        setString(newValue)
    }

    override func accessibilitySelectedText() -> String? {
        textLayoutManager.textSelectionsString()
    }

    override func setAccessibilitySelectedText(_ accessibilitySelectedText: String?) {
        guard isEditable else { return }
        replaceCharacters(in: selectedRange(), with: accessibilitySelectedText ?? "")
    }

    override func accessibilitySelectedTextRange() -> NSRange {
        selectedRange()
    }

    override func setAccessibilitySelectedTextRange(_ accessibilitySelectedTextRange: NSRange) {
        setSelectedRange(accessibilitySelectedTextRange)
    }

    override func accessibilitySelectedTextRanges() -> [NSValue]? {
        textLayoutManager.textSelections
            .flatMap(\.textRanges)
            .map { NSRange($0, in: textContentStorage) }
            .map { NSValue(range: $0) }
    }

    override func accessibilityVisibleCharacterRange() -> NSRange {
        let viewport = textLayoutManager.textViewportLayoutController.viewportRange
            ?? textLayoutManager.documentRange
        return NSRange(viewport, in: textContentStorage)
    }

    override func accessibilityAttributedString(for range: NSRange) -> NSAttributedString? {
        guard let textRange = textContentStorage.textRange(from: range) else { return nil }
        return textContentStorage.attributedString(in: textRange)
    }

    override func accessibilityString(for range: NSRange) -> String? {
        guard let textRange = textContentStorage.textRange(from: range) else { return nil }
        return textContentStorage.attributedString(in: textRange)?.string
    }

    override func accessibilityInsertionPointLineNumber() -> Int {
        guard let location = textLayoutManager.insertionPointLocations.first else { return 0 }
        return accessibilityLine(for: textContentStorage.offset(from: textContentStorage.documentRange.location, to: location))
    }

    override func setAccessibilityInsertionPointLineNumber(_ line: Int) {
        guard isEditable else { return }
        let range = accessibilityRange(forLine: line)
        setSelectedRange(NSRange(location: range.location, length: 0))
    }

    override func accessibilityLine(for index: Int) -> Int {
        let text = string as NSString
        guard index >= 0, index <= text.length else { return -1 }
        var line = 0
        var cursor = 0
        while cursor < index {
            if text.character(at: cursor) == 0x0A { line += 1 }
            cursor += 1
        }
        return line
    }

    override func accessibilityRange(forLine line: Int) -> NSRange {
        let text = string as NSString
        var currentLine = 0
        var start = 0
        var cursor = 0
        while cursor < text.length, currentLine < line {
            if text.character(at: cursor) == 0x0A {
                currentLine += 1
                start = cursor + 1
            }
            cursor += 1
        }
        guard currentLine == line else { return NSRange(location: text.length, length: 0) }
        var end = start
        while end < text.length, text.character(at: end) != 0x0A { end += 1 }
        // Include the trailing newline so ranges tile the document.
        if end < text.length { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    override func accessibilityFrame(for range: NSRange) -> NSRect {
        guard let textRange = textContentStorage.textRange(from: range),
              let frame = textLayoutManager.typographicBounds(in: textRange)
        else { return .zero }
        let inView = frame.offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        guard let window else { return inView }
        let inWindow = convert(inView, to: nil)
        return window.convertToScreen(inWindow)
    }

    override func accessibilityRange(for point: NSPoint) -> NSRange {
        let inView = convert(point, from: nil)
        let contentPoint = NSPoint(x: inView.x - textContainerOrigin.x, y: inView.y - textContainerOrigin.y)
        guard let location = textLayoutManager.caretLocation(
            interactingAt: contentPoint,
            options: .allowOutside,
            inContainerAt: textLayoutManager.documentRange.location
        ) else { return NSRange(location: 0, length: 0) }
        let offset = textContentStorage.offset(from: textContentStorage.documentRange.location, to: location)
        return NSRange(location: offset == NSNotFound ? 0 : offset, length: 1)
    }
}
