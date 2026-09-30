import Foundation

/// Text-transformation helpers used by `ToolbarView` and key handlers.
/// These operate on plain strings, making them testable without a text view.
public enum EditorOperations {

    // MARK: - Markdown wrapping

    /// Toggles a Markdown prefix/suffix pair around the selected text.
    /// If the text is already wrapped, it removes the wrapper.
    /// If `text` is empty, inserts the wrapper with a placeholder.
    /// Returns `(result, selectedRangeAdjustment)`.
    public static func toggleMarkup(
        in text: String,
        selectedRange range: Range<String.Index>,
        prefix: String,
        suffix: String,
        placeholder: String = ""
    ) -> (text: String, newRange: Range<String.Index>) {
        let selection = String(text[range])

        // Selection is already marked up: remove the markup and keep the selection.
        if isSurrounded(byPrefix: prefix, suffix: suffix, at: range, in: text) {
            var result = text
            let contentStart = text.index(range.lowerBound, offsetBy: -prefix.count)
            let contentEnd = text.index(range.upperBound, offsetBy: suffix.count)
            result.replaceSubrange(contentStart..<contentEnd, with: selection)
            let newLower = result.index(result.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.lowerBound) - prefix.count)
            let newRange = newLower..<result.index(newLower, offsetBy: selection.count)
            return (result, newRange)
        }

        // Selection is empty: use the placeholder text (if any) so the user can
        // type over it; otherwise just insert prefix+suffix with the caret inside.
        let content = selection.isEmpty ? placeholder : selection
        var result = text
        result.replaceSubrange(range, with: prefix + content + suffix)
        let contentStart = text.distance(from: text.startIndex, to: range.lowerBound) + prefix.count
        let newLower = result.index(result.startIndex, offsetBy: contentStart)
        let newRange = newLower..<result.index(newLower, offsetBy: content.count)
        return (result, newRange)
    }

    // MARK: - Line block operations

    /// Toggles a block-level prefix (list, blockquote) based on a regex pattern.
    /// If the current line matches `pattern`, the prefix is removed.
    /// Otherwise the prefix is added.
    public static func toggleBlock(
        in text: String,
        selectedRange range: Range<String.Index>,
        pattern: String,
        prefix: String
    ) -> (text: String, newRange: Range<String.Index>) {
        let lineStart = text.startIndex..<range.lowerBound
        let startOfLine = findLineStart(in: text, range: lineStart)
        let lineEndRange = range.upperBound..<text.endIndex
        let endOfLine = findLineEnd(in: text, range: lineEndRange)
        let lineRange = startOfLine..<endOfLine
        let line = String(text[lineRange])

        let regex = try? NSRegularExpression(pattern: pattern)
        if let regex, regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {
            // Remove prefix
            if line.hasPrefix(prefix) {
                var result = text
                let removeRange = result.index(result.startIndex, offsetBy: text.distance(from: text.startIndex, to: startOfLine))..<result.index(result.startIndex, offsetBy: text.distance(from: text.startIndex, to: startOfLine) + prefix.count)
                result.removeSubrange(removeRange)
                let shift = -prefix.count
                let newLower = result.index(result.startIndex, offsetBy: max(0, text.distance(from: text.startIndex, to: range.lowerBound) + shift))
                let newUpper = result.index(result.startIndex, offsetBy: max(0, text.distance(from: text.startIndex, to: range.upperBound) + shift))
                return (result, newLower..<newUpper)
            }
        }

        // Add prefix
        var result = text
        let insertAt = result.index(result.startIndex, offsetBy: text.distance(from: text.startIndex, to: startOfLine))
        result.insert(contentsOf: prefix, at: insertAt)
        let newLower = result.index(result.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.lowerBound) + prefix.count)
        let newUpper = result.index(result.startIndex, offsetBy: text.distance(from: text.startIndex, to: range.upperBound) + prefix.count)
        return (result, newLower..<newUpper)
    }

    // MARK: - Header level

    /// Makes the selected lines into headers at the specified level (0 = paragraph).
    /// A caret (empty selection) applies to the line it sits on.
    public static func setHeaderLevel(
        in text: String,
        selectedRange range: Range<String.Index>,
        level: Int
    ) -> (text: String, newRange: Range<String.Index>) {
        let lines = text.components(separatedBy: "\n")
        let lowerOffset = range.lowerBound.utf16Offset(in: text)
        let upperOffset = range.upperBound.utf16Offset(in: text)

        // Line bounds in UTF-16 units, so the selection maps back exactly even
        // with CJK/emoji content.
        var lineStarts: [Int] = []
        var lineEnds: [Int] = []
        var cursor = 0
        for line in lines {
            let length = (line as NSString).length
            lineStarts.append(cursor)
            lineEnds.append(cursor + length)
            cursor += length + 1 // newline
        }

        // Which lines does the selection touch?
        var touched: Set<Int> = []
        if lowerOffset == upperOffset {
            if let index = lines.indices.first(where: {
                lowerOffset >= lineStarts[$0] && lowerOffset < lineEnds[$0]
            }) {
                touched.insert(index)
            } else if lowerOffset == (text as NSString).length, let last = lines.indices.last {
                touched.insert(last)
            }
        } else {
            for index in lines.indices {
                let lineRange = NSRange(
                    location: lineStarts[index],
                    length: lineEnds[index] - lineStarts[index]
                )
                if NSIntersectionRange(lineRange, NSRange(location: lowerOffset, length: upperOffset - lowerOffset)).length > 0
                    || (lowerOffset <= lineStarts[index] && upperOffset >= lineEnds[index]) {
                    touched.insert(index)
                }
            }
        }

        var newLines: [String] = []
        newLines.reserveCapacity(lines.count)
        var deltas: [Int] = []
        for (index, line) in lines.enumerated() {
            guard touched.contains(index) else {
                newLines.append(line)
                deltas.append(0)
                continue
            }
            let stripped = line.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            let newLine = level == 0
                ? stripped
                : String(repeating: "#", count: level) + " " + stripped
            newLines.append(newLine)
            deltas.append((newLine as NSString).length - (line as NSString).length)
        }

        let newText = newLines.joined(separator: "\n")
        let newLength = (newText as NSString).length

        func shifted(_ offset: Int) -> Int {
            var shift = 0
            for (index, start) in lineStarts.enumerated() {
                if offset <= start { break }
                shift += deltas[index]
            }
            return min(newLength, max(0, offset + shift))
        }

        let newLower = String.Index(utf16Offset: shifted(lowerOffset), in: newText)
        let newUpper = String.Index(utf16Offset: shifted(upperOffset), in: newText)
        return (newText, newLower..<newUpper)
    }

    // MARK: - Indent / Unindent

    public static func indentLines(
        in text: String,
        selectedRange range: Range<String.Index>,
        padding: String = "    "
    ) -> (text: String, newRange: Range<String.Index>) {
        var text = text

        // Expand selection to full lines
        let lineStart = findLineStart(in: text, range: text.startIndex..<range.lowerBound)
        let lineEnd = findLineEnd(in: text, range: range.upperBound..<text.endIndex)
        let fullLineRange = lineStart..<lineEnd
        let selectedLines = text[fullLineRange].components(separatedBy: "\n")

        let indented = selectedLines.map { padding + $0 }.joined(separator: "\n")
        text.replaceSubrange(fullLineRange, with: indented)

        let shift = padding.count * selectedLines.count
        let newLower = text.index(text.startIndex, offsetBy: min(text.count, text.distance(from: text.startIndex, to: range.lowerBound) + padding.count))
        let newUpper = text.index(text.startIndex, offsetBy: min(text.count, text.distance(from: text.startIndex, to: range.upperBound) + shift))
        return (text, newLower..<newUpper)
    }

    public static func unindentLines(
        in text: String,
        selectedRange range: Range<String.Index>
    ) -> (text: String, newRange: Range<String.Index>) {
        var text = text

        let lowerOffset = text.distance(from: text.startIndex, to: range.lowerBound)
        let upperOffset = text.distance(from: text.startIndex, to: range.upperBound)

        // Expand selection to full lines
        let lineStart = findLineStart(in: text, range: text.startIndex..<range.lowerBound)
        let lineEnd = findLineEnd(in: text, range: range.upperBound..<text.endIndex)
        let fullLineRange = lineStart..<lineEnd
        let selectedLines = text[fullLineRange].components(separatedBy: "\n")

        // Remove one indentation level per line, recording each line's original
        // start offset and how many characters it lost. The selection endpoints
        // are then shifted by exactly the characters removed before them, which
        // keeps the range valid for carets inside the indentation (previously
        // this produced `lowerBound > upperBound` and crashed).
        var lineStarts: [Int] = []
        var removals: [Int] = []
        var cursor = text.distance(from: text.startIndex, to: lineStart)
        let unindented = selectedLines.map { line -> String in
            lineStarts.append(cursor)
            cursor += line.count + 1 // + newline
            if line.hasPrefix("\t") {
                removals.append(1)
                return String(line.dropFirst())
            } else if line.hasPrefix("    ") {
                removals.append(4)
                return String(line.dropFirst(4))
            }
            removals.append(0)
            return line
        }.joined(separator: "\n")

        text.replaceSubrange(fullLineRange, with: unindented)

        func shiftedOffset(_ offset: Int) -> Int {
            var shift = 0
            for (index, start) in lineStarts.enumerated() {
                if offset <= start { break }
                shift += min(offset - start, removals[index])
            }
            return max(0, offset - shift)
        }

        let newLower = text.index(text.startIndex, offsetBy: min(text.count, shiftedOffset(lowerOffset)))
        let newUpper = text.index(text.startIndex, offsetBy: min(text.count, shiftedOffset(upperOffset)))
        return (text, newLower..<newUpper)
    }

    // MARK: - Helpers

    private static func isSurrounded(
        byPrefix prefix: String,
        suffix: String,
        at range: Range<String.Index>,
        in text: String
    ) -> Bool {
        guard let contentStart = text.index(range.lowerBound, offsetBy: -prefix.count, limitedBy: text.startIndex),
              let contentEnd = text.index(range.upperBound, offsetBy: suffix.count, limitedBy: text.endIndex)
        else { return false }
        return String(text[contentStart..<range.lowerBound]) == prefix
            && String(text[range.upperBound..<contentEnd]) == suffix
    }

    private static func findLineStart(in text: String, range: Range<String.Index>) -> String.Index {
        var idx = range.lowerBound
        while idx > text.startIndex {
            let prev = text.index(before: idx)
            if text[prev] == "\n" { return idx }
            idx = prev
        }
        return text.startIndex
    }

    private static func findLineEnd(in text: String, range: Range<String.Index>) -> String.Index {
        var idx = range.lowerBound
        while idx < text.endIndex {
            if text[idx] == "\n" { return text.index(after: idx) }
            idx = text.index(after: idx)
        }
        return text.endIndex
    }
}