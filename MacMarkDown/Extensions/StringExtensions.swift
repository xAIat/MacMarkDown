import Foundation

// MARK: - String Extensions

extension String {

    /// Returns the range of the first newline character before `location`.
    public func locationOfFirstNewlineBefore(_ location: Int) -> Int {
        var i = min(location, count) - 1
        while i >= 0 {
            let charIndex = index(startIndex, offsetBy: i)
            if self[charIndex] == "\n" { return i }
            i -= 1
        }
        return 0
    }

    /// Returns the index of the first newline character after `location`
    /// (the newline of the line containing `location + 1`).
    public func locationOfFirstNewlineAfter(_ location: Int) -> Int {
        let loc = min(max(location, 0) + 1, count)
        var i = loc
        while i < count {
            let charIndex = index(startIndex, offsetBy: i)
            if self[charIndex] == "\n" { return i }
            i += 1
        }
        return count
    }

    /// Returns the location of the first non-whitespace character in the line
    /// containing `location`.
    public func locationOfFirstNonWhitespaceCharacterInLineBefore(_ location: Int) -> Int {
        let newlineBefore = locationOfFirstNewlineBefore(location)
        var i = newlineBefore
        while i < count {
            let charIndex = index(startIndex, offsetBy: i)
            let char = self[charIndex]
            if char.isNewline || (!char.isWhitespace && char != " " && char != "\t") {
                return i
            }
            i += 1
        }
        return newlineBefore
    }

    /// Extracts the highest-ranked heading text (used for auto-naming documents):
    /// tries `#` through `######` and returns the first match, or `nil` when the
    /// document has no heading.
    public var titleString: String? {
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            for line in linesForMatch {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard trimmed.hasPrefix(prefix) else { continue }
                let rest = trimmed.dropFirst(prefix.count)
                let content = rest.trimmingCharacters(in: .whitespaces)
                guard !content.isEmpty, !content.hasPrefix("#") else { continue }
                return content
            }
        }
        return nil
    }

    private var linesForMatch: [String] {
        components(separatedBy: .newlines)
    }

    /// Extracts the first heading text from Markdown.
    public var firstHeading: String? {
        let lines = components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("#") {
                return line.replacingOccurrences(of: #"^#+\s*"#, with: "", options: .regularExpression)
            }
        }
        return nil
    }

    /// Returns the number of words in the string.
    public var wordCount: Int {
        var count = 0
        enumerateSubstrings(
            in: startIndex..<endIndex,
            options: .byWords
        ) { _, _, _, _ in count += 1 }
        return count
    }

    /// Returns the number of characters (excluding spaces).
    public var characterCountNoSpaces: Int {
        reduce(0) { $1.isWhitespace ? $0 : $0 + 1 }
    }

    /// Trims trailing newline characters.
    public var trimmingTrailingNewlines: String {
        var s = self
        while s.hasSuffix("\n") { s.removeLast() }
        return s
    }

    /// Ensures the string ends with a single newline.
    public func ensuringTrailingNewline() -> String {
        if hasSuffix("\n") { return self }
        return self + "\n"
    }
}
