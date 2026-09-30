import Foundation

/// Find/replace state and matching logic for the editor. Pure value logic so
/// it can be unit-tested; the SwiftUI find bar only renders it.
@MainActor
@Observable
public final class FindController {

    public var query: String = "" {
        didSet { if query != oldValue { recomputeMatches() } }
    }
    public var replacement: String = ""
    public var caseSensitive = false {
        didSet { if caseSensitive != oldValue { recomputeMatches() } }
    }
    public var showsReplace = false

    /// All matches in the current document, in document order.
    public private(set) var matches: [NSRange] = []
    /// Index into `matches` of the currently selected match, if any.
    public private(set) var currentIndex: Int?

    private var text = ""

    public init() {}

    // MARK: - Document

    /// Updates the document text and recomputes matches (keeping the current
    /// match selected when possible).
    public func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        recomputeMatches()
    }

    // MARK: - Matching

    private func recomputeMatches() {
        guard !query.isEmpty else {
            matches = []
            currentIndex = nil
            return
        }
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        let ns = text as NSString
        var result: [NSRange] = []
        var searchStart = 0
        while searchStart <= ns.length {
            let range = ns.range(
                of: query,
                options: options,
                range: NSRange(location: searchStart, length: ns.length - searchStart)
            )
            guard range.location != NSNotFound else { break }
            result.append(range)
            searchStart = range.location + max(1, range.length)
        }
        matches = result
        if let currentIndex, currentIndex >= result.count {
            self.currentIndex = result.isEmpty ? nil : result.count - 1
        }
        // A fresh query has no presented match yet; the first `nextMatch()`
        // selects the first one.
    }

    // MARK: - Navigation

    /// The match selected next, if any. `from` is the editor caret; searching
    /// forward starts after it, backward before it.
    public func nextMatch(after location: Int? = nil) -> NSRange? {
        guard !matches.isEmpty else { return nil }
        guard let location else {
            currentIndex = ((currentIndex ?? -1) + 1) % matches.count
            return matches[currentIndex!]
        }
        if let index = matches.firstIndex(where: { $0.location > location }) {
            currentIndex = index
        } else {
            currentIndex = 0
        }
        return matches[currentIndex!]
    }

    public func previousMatch(before location: Int? = nil) -> NSRange? {
        guard !matches.isEmpty else { return nil }
        guard let location else {
            currentIndex = ((currentIndex ?? matches.count) - 1 + matches.count) % matches.count
            return matches[currentIndex!]
        }
        if let index = matches.lastIndex(where: { $0.location + $0.length < location }) {
            currentIndex = index
        } else {
            currentIndex = matches.count - 1
        }
        return matches[currentIndex!]
    }

    /// The match under/at the caret, if any.
    public func match(at location: Int) -> NSRange? {
        matches.first { $0.location <= location && location <= $0.location + $0.length }
    }

    // MARK: - Replace

    /// Replaces the current match. Returns the new text and the selection to
    /// restore (the start of the replacement), or `nil` when nothing matched.
    public func replaceCurrent(in text: String) -> (text: String, selection: NSRange)? {
        guard let currentIndex, matches.indices.contains(currentIndex) else { return nil }
        let range = matches[currentIndex]
        let newText = (text as NSString).replacingCharacters(in: range, with: replacement)
        let selection = NSRange(location: range.location + (replacement as NSString).length, length: 0)
        return (newText, selection)
    }

    /// Replaces every match. Returns the new text and the number of
    /// replacements, or `nil` when there was nothing to do.
    public func replaceAll(in text: String) -> (text: String, count: Int)? {
        guard !matches.isEmpty else { return nil }
        let result = NSMutableString(string: text)
        var applied = 0
        // Back to front so earlier ranges stay valid.
        for range in matches.reversed() {
            result.replaceCharacters(in: range, with: replacement)
            applied += 1
        }
        return (result as String, applied)
    }
}