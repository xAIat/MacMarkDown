import AppKit

// MARK: - Shared tables

/// Regexes, character sets and lookup tables the smart-editing helpers use.
/// Kept above the `EditorTextViewHost` extension because Swift forbids static
/// stored properties in protocol (and generic type) extensions.
fileprivate enum SmartEditingTables {
    struct Regexes {
        static let listLineHead = try! NSRegularExpression(
            pattern: #"^(\s*)((?:(?:\*|\+|-|)\s+)?)((?:\d+\.\s+)?)(\S)?"#
        )
        static let blockquoteLine = try! NSRegularExpression(
            pattern: #"^((?:\> ?)+).*$"#
        )
    }

    static let listLineHeadRegex = Regexes.listLineHead
    static let blockquoteLineRegex = Regexes.blockquoteLine

    /// Character pairs that auto-complete (ASCII brackets and quotes plus the
    /// common CJK pairs).
    static let matchingCharacterPairs: [(unichar, unichar)] = [
        (0x28, 0x29),         // ( )
        (0x5B, 0x5D),         // [ ]
        (0x7B, 0x7D),         // { }
        (0x3C, 0x3E),         // < >
        (0x27, 0x27),         // ' '
        (0x22, 0x22),         // " "
        (0xFF08, 0xFF09),     // （ ）
        (0x300C, 0x300D),     // 「 」
        (0x300E, 0x300F),     // 『 』
        (0x2018, 0x2019),     // ‘ ’
        (0x201C, 0x201D),     // “ ”
        (0x2039, 0x203A),     // ‹ ›
        (0x00AB, 0x00BB),     // « »
        (0x3008, 0x3009),     // 〈 〉
        (0x300A, 0x300B),     // 《 》
    ]

    /// Characters used to wrap a selection (`*bold*`, `` `code` ``, etc.).
    static let markupCharacters: [unichar] = [
        0x2A, // *
        0x5F, // _
        0x60, // `
        0x3D, // =
    ]

    static var whitespaceSet: NSCharacterSet { CharacterSet.whitespaces as NSCharacterSet }
    static var boundarySet: NSCharacterSet {
        CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters) as NSCharacterSet
    }

    static func isWhitespace(_ character: unichar) -> Bool {
        whitespaceSet.characterIsMember(character)
    }

    static func isBoundary(_ character: unichar) -> Bool {
        boundarySet.characterIsMember(character)
    }

    /// Index of the newline before `location`, or `-1` when none exists.
    static func locationOfFirstNewlineBefore(_ location: Int, in content: NSString) -> Int {
        var i = min(location, content.length) - 1
        while i >= 0 {
            if content.character(at: i) == 10 { return i }
            i -= 1
        }
        return -1
    }
}

// MARK: - Smart editing

/// Auto-complete and smart-editing helpers, written against the
/// `EditorTextViewHost` protocol so they work with any conforming text view;
/// the editor's coordinator routes `shouldChangeText` and `doCommandBy`
/// through them.
extension EditorTextViewHost {

    // MARK: - Matching-character autocomplete

    /// Auto-pairs or wraps the character being inserted.
    /// - Returns: `true` when the insert was handled entirely by this method.
    func completeMatchingCharacters(
        forRange range: NSRange,
        replacementString text: String,
        strikethroughEnabled: Bool
    ) -> Bool {
        let length = (text as NSString).length
        if range.length == 0 && length == 1 {
            return completeMatchingCharacter(text, atLocation: range.location)
        } else if range.length > 0 && length == 1 {
            let character = (text as NSString).character(at: 0)
            return wrapMatchingCharacters(
                of: character, around: range, strikethroughEnabled: strikethroughEnabled
            )
        }
        return false
    }

    private func completeMatchingCharacter(_ text: String, atLocation location: Int) -> Bool {
        let content = string as NSString
        let contentLength = content.length
        let c = (text as NSString).character(at: 0)

        var next: unichar = 32
        var previous: unichar = 32
        if location < contentLength { next = content.character(at: location) }
        if location > 0 && location <= contentLength { previous = content.character(at: location - 1) }

        for pair in SmartEditingTables.matchingCharacterPairs {
            let (open, close) = pair

            // Auto-open: type `(` when surrounded by boundary characters.
            if SmartEditingTables.isBoundary(next) && c == open
                && (SmartEditingTables.isBoundary(previous) || open != close) {
                var completion = String(Character(UnicodeScalar(open)!))
                    + String(Character(UnicodeScalar(close)!))
                if isAutomaticQuoteSubstitutionEnabled {
                    switch open {
                    case 0x22: completion = "\u{201C}"
                    case 0x27: completion = "\u{2018}"
                    default: break
                    }
                }
                insertText(completion, replacementRange: NSRange(location: location, length: 0))
                setSelectedRange(NSRange(location: location + 1, length: 0))
                return true
            }

            // Shift over: typing the closing char moves the caret past it.
            if c == close && next == close {
                setSelectedRange(NSRange(location: location + 1, length: 0))
                return true
            }
        }
        return false
    }

    private func wrapMatchingCharacters(
        of character: unichar,
        around range: NSRange,
        strikethroughEnabled: Bool
    ) -> Bool {
        if let pair = SmartEditingTables.matchingCharacterPairs.first(where: { $0.0 == character }) {
            wrapText(in: range, withPrefix: pair.0, suffix: pair.1)
            return true
        }
        for markup in SmartEditingTables.markupCharacters where character == markup {
            wrapText(in: range, withPrefix: markup, suffix: markup)
            return true
        }
        if strikethroughEnabled && character == 0x7E {
            wrapText(in: range, withPrefix: 0x7E, suffix: 0x7E)
            return true
        }
        return false
    }

    private func wrapText(in range: NSRange, withPrefix prefix: unichar, suffix: unichar) {
        let prefixString = String(Character(UnicodeScalar(prefix)!))
        let suffixString = String(Character(UnicodeScalar(suffix)!))
        let content = (string as NSString).substring(with: range)
        let replacement = prefixString + content + suffixString
        _ = shouldChangeText(in: range, replacementString: replacement)
        replaceCharacters(in: range, with: replacement)
        setSelectedRange(NSRange(location: range.location + 1, length: range.length))
    }

    /// Backspacing between a matched pair (e.g. `(|)` with cursor between)
    /// deletes both characters at once.
    func deleteMatchingCharactersAround(_ location: Int) -> Bool {
        let content = string as NSString
        guard location > 0, location < content.length else { return false }
        let front = content.character(at: location - 1)
        let back = content.character(at: location)
        for pair in SmartEditingTables.matchingCharacterPairs where front == pair.0 && back == pair.1 {
            let range = NSRange(location: location - 1, length: 2)
            _ = shouldChangeText(in: range, replacementString: "")
            replaceCharacters(in: range, with: "")
            return true
        }
        return false
    }

    // MARK: - Tab / indentation

    /// Inserts spaces aligned to a 4-column tab stop.
    func insertSpacesForTab() {
        let currentLocation = selectedRange().location
        let lineStart = SmartEditingTables.locationOfFirstNewlineBefore(currentLocation, in: string as NSString) + 1
        let offset = (currentLocation - lineStart) % 4
        let count = offset == 0 ? 4 : 4 - offset
        guard count > 0 else { return }
        insertText(String(repeating: " ", count: count), replacementRange: selectedRange())
    }

    /// Backspacing a whole 4-space tab step (when `editorConvertTabs` is on).
    func unindentForSpacesBefore(_ location: Int) -> Bool {
        let content = string as NSString
        guard location > 0 else { return false }

        var whitespaceCount = 0
        var cursor = location
        while cursor > 0, whitespaceCount < 4, content.character(at: cursor - 1) == 32 {
            whitespaceCount += 1
            cursor -= 1
        }
        if whitespaceCount < 2 { return false }

        let lineStart = SmartEditingTables.locationOfFirstNewlineBefore(location, in: content) + 1
        if location <= lineStart { return false }

        var offset = (location - lineStart) % 4
        if offset == 0 { offset = 4 }
        if whitespaceCount < offset { offset = whitespaceCount }

        let range = NSRange(location: location - offset, length: offset)
        _ = shouldChangeText(in: range, replacementString: "")
        replaceCharacters(in: range, with: "")
        return true
    }

    /// Indents the (expanded-to-full-lines) selection with `padding`.
    func indentSelectedLines(padding: String = "    ") {
        applyToExpandedLines { text, range in
            EditorOperations.indentLines(in: text, selectedRange: range, padding: padding)
        }
    }

    /// Removes one indentation level from each selected line.
    func unindentSelectedLines() {
        applyToExpandedLines { text, range in
            EditorOperations.unindentLines(in: text, selectedRange: range)
        }
    }

    private func applyToExpandedLines(
        _ transform: (String, Range<String.Index>) -> (String, Range<String.Index>)
    ) {
        let ns = string as NSString
        let selection = selectedRange()
        guard ns.length > 0 else { return }
        let source = string

        let start = min(max(selection.location, 0), ns.length)
        let end = min(max(selection.location + selection.length, 0), ns.length)
        let lower = String.Index(utf16Offset: start, in: source)
        let upper = String.Index(utf16Offset: end, in: source)

        let (newText, newRange) = transform(source, lower..<upper)
        let newLower = newRange.lowerBound.utf16Offset(in: newText)
        let newUpper = newRange.upperBound.utf16Offset(in: newText)

        _ = shouldChangeText(in: NSRange(location: 0, length: ns.length), replacementString: newText)
        replaceCharacters(in: NSRange(location: 0, length: ns.length), with: newText)
        setSelectedRange(NSRange(location: newLower, length: max(0, newUpper - newLower)))
    }

    // MARK: - Return-key list / blockquote / indent continuation

    /// Pressing Return in a list item continues the marker (or exits the list
    /// when the item is empty). `autoIncrement` renumbers ordered lists.
    func completeNextListItem(autoIncrement: Bool) -> Bool {
        let selection = selectedRange()
        let location = selection.location
        let content = string as NSString
        guard selection.length == 0, content.length > 0 else { return false }

        let lineStart = SmartEditingTables.locationOfFirstNewlineBefore(location, in: content) + 1
        let nonWhitespace = locationOfFirstNonWhitespaceCharacterInLineBefore(
            location, in: content
        )
        guard nonWhitespace != location else { return false }

        let line = content.substring(with: NSRange(location: lineStart, length: location - lineStart))
        let lineNS = line as NSString
        guard lineNS.length > 0,
              let result = SmartEditingTables.listLineHeadRegex.firstMatch(
                  in: line, range: NSRange(location: 0, length: lineNS.length)
              )
        else { return false }

        let isUnordered = result.range(at: 2).length != 0
        let isOrdered = result.range(at: 3).length != 0
        let previousLineEmpty = result.range(at: 4).length == 0

        var marker: String?
        if previousLineEmpty {
            var replaceRange = isUnordered ? result.range(at: 2) : result.range(at: 3)
            if replaceRange.length > 0 {
                replaceRange.location += lineStart
                _ = shouldChangeText(in: replaceRange, replacementString: "")
                replaceCharacters(in: replaceRange, with: "")
            }
            marker = ""
        } else if isUnordered {
            var range = result.range(at: 2)
            range.length -= 1 // exclude trailing space
            marker = lineNS.substring(with: range)
        } else if isOrdered {
            var range = result.range(at: 3)
            range.length -= 1 // exclude trailing space
            let captured = lineNS.substring(with: range)
            let digits = captured.prefix(while: { $0.isNumber })
            let number = (Int(digits) ?? 0) + (autoIncrement ? 1 : 0)
            marker = "\(number)."
        }
        guard let marker else { return false }

        insertNewline(nil)
        let nextLocation = location + 1

        let indent = lineNS.substring(with: result.range(at: 1))
        let contentLength = content.length

        // The next line already carries exactly this marker → accept (dedup).
        let markerNS = marker as NSString
        let markerRange = NSRange(location: nextLocation, length: markerNS.length)
        if contentLength > nextLocation + markerNS.length,
           content.substring(with: markerRange) == marker {
            insertText(indent, replacementRange: selectedRange())
            return true
        }

        // …or the indent + marker together.
        let prefixed = indent + marker
        let prefixedNS = prefixed as NSString
        let prefixedRange = NSRange(location: nextLocation, length: prefixedNS.length)
        if contentLength > nextLocation + prefixedNS.length,
           content.substring(with: prefixedRange) == prefixed {
            return true
        }

        let insertion = marker.isEmpty ? prefixed : prefixed + " "
        insertText(insertion, replacementRange: selectedRange())
        return true
    }

    /// Pressing Return in a blockquote line continues the `> ` marker.
    func completeNextBlockquoteLine() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let content = string as NSString
        let contentLength = content.length
        guard contentLength > 0 else { return false }

        let location = selection.location
        let lineStart = SmartEditingTables.locationOfFirstNewlineBefore(location, in: content) + 1
        var lineEnd = lineStart
        while lineEnd < contentLength && content.character(at: lineEnd) != 10 {
            lineEnd += 1
        }
        let line = content.substring(with: NSRange(location: lineStart, length: lineEnd - lineStart))
        guard let result = SmartEditingTables.blockquoteLineRegex.firstMatch(
            in: line, range: NSRange(location: 0, length: (line as NSString).length)
        ) else { return false }

        insertNewline(nil)

        let markersRange = result.range(at: 1)
        let markers = (line as NSString).substring(with: markersRange)
        let nextLineStart = location + 1
        if contentLength > nextLineStart + markersRange.length {
            let nextMarkers = content.substring(with: NSRange(location: nextLineStart, length: markersRange.length))
            if nextMarkers == markers { return true }
        }
        insertText(markers, replacementRange: selectedRange())
        return true
    }

    /// Pressing Return in an indented line preserves the leading whitespace.
    func completeNextIndentedLine() -> Bool {
        let selection = selectedRange()
        guard selection.length == 0 else { return false }
        let content = string as NSString
        let contentLength = content.length
        guard contentLength > 0 else { return false }

        let location = selection.location
        let lineStart = SmartEditingTables.locationOfFirstNewlineBefore(location, in: content) + 1
        let nonWhitespace = locationOfFirstNonWhitespaceCharacterInLineBefore(location, in: content)
        if nonWhitespace <= lineStart { return false }

        insertNewline(nil)
        let indentRange = NSRange(location: lineStart, length: nonWhitespace - lineStart)
        insertText(content.substring(with: indentRange), replacementRange: selectedRange())
        return true
    }

    // MARK: - Smart home

    /// The location the caret should move to when Home is pressed, per the
    /// "Smart Home" preference. Returns `nil` when the default Home behavior
    /// should kick in instead (already at the first non-whitespace, at text
    /// start, or when the target sits on a different visual line).
    func smartHomeLocation() -> Int? {
        let content = string as NSString
        let cursor = selectedRange().location
        guard cursor > 0, content.length > 0 else { return nil }

        let location = locationOfFirstNonWhitespaceCharacterInLineBefore(cursor, in: content)
        if location == cursor { return nil }

        // Don't jump between visual rows when the line is wrapped (#103).
        // TextKit 2 port: resolve both offsets to their `NSTextLineFragment`
        // and bail out when they differ. (The layout-manager-level API this
        // replaced was `textLineFragment(for:in:)`; this SDK exposes the
        // equivalent on the owning layout fragment, so both offsets are first
        // resolved to their `NSTextLayoutFragment`.)
        if let textLayoutManager = layoutManagerForGeometry() {
            guard let target = textLayoutManager.location(atCharacter: location),
                  let current = textLayoutManager.location(atCharacter: cursor - 1),
                  let targetFragment = textLayoutManager.textLayoutFragment(for: target),
                  let currentFragment = textLayoutManager.textLayoutFragment(for: current),
                  let targetLine = targetFragment.textLineFragment(for: target, isUpstreamAffinity: true),
                  let currentLine = currentFragment.textLineFragment(for: current, isUpstreamAffinity: true)
            else { return location }
            if targetLine !== currentLine { return nil }
        }
        return location
    }

    // MARK: - Location helpers

    /// First non-whitespace character in the line before `location`.
    func locationOfFirstNonWhitespaceCharacterInLineBefore(_ location: Int, in content: NSString) -> Int {
        let clamped = min(location, content.length)
        let lineStart = SmartEditingTables.locationOfFirstNewlineBefore(clamped, in: content) + 1
        var i = lineStart
        while i < clamped {
            if !SmartEditingTables.isWhitespace(content.character(at: i)) { return i }
            i += 1
        }
        return clamped
    }

    }