import AppKit

/// Colors Markdown source text inside the editor pane using an `EditorTheme`.
///
/// This is a lightweight, order-based tokenizer that maps Markdown token
/// categories (title, emphasis, strong, code, link, quote, list marker,
/// heading, bold, italic) onto AppKit text attributes.
///
/// Approach:
/// 1. A base attribute set is applied to the whole document.
/// 2. Fenced code blocks are colored as a single unit and excluded from the
///    inline passes (a line-based approximation of Markdown's "code spans
///    suppress inline markup" rule).
/// 3. Each remaining line gets block-level tokens (headings, blockquotes,
///    list markers) and then inline tokens (code, links, strong, emphasis,
///    strikethrough), with an "occupied ranges" set so a later pass never
///    re-colors inside an earlier token (e.g. `**bold**` inside a code span).
public struct MarkdownSyntaxHighlighter {

    public let theme: EditorTheme

    public init(theme: EditorTheme) {
        self.theme = theme
    }

    // MARK: - Public API

    /// Produces a fully-attributed copy of `text`.
    public func attributedString(
        for text: String,
        font: NSFont,
        paragraphStyle: NSParagraphStyle
    ) -> NSAttributedString {
        let storage = NSTextStorage(string: text)
        apply(to: storage, font: font, paragraphStyle: paragraphStyle)
        return storage
    }

    /// Applies base + token attributes to `storage` (typically the editor's
    /// text storage). Nested calls are safe: the storage is wrapped in
    /// `beginEditing()`/`endEditing()`.
    public func apply(to storage: NSTextStorage, font: NSFont, paragraphStyle: NSParagraphStyle) {
        let content = storage.string as NSString
        guard content.length > 0 else { return }

        storage.beginEditing()
        defer { storage.endEditing() }

        storage.setAttributes(
            baseAttributes(font: font, paragraphStyle: paragraphStyle),
            range: NSRange(location: 0, length: content.length)
        )

        let codeBlockRanges = Self.fencedCodeBlockRanges(in: content)
        for range in codeBlockRanges {
            storage.addAttributes(codeAttributes(inline: false), range: range)
        }
        for range in Self.indentedCodeLineRanges(in: content) {
            storage.addAttributes(codeAttributes(inline: false), range: range)
        }

        for lineRange in Self.lineRanges(in: content) {
            let inCodeBlock = codeBlockRanges.contains { range in
                range.intersection(lineRange)?.length ?? 0 > 0
            }
            if inCodeBlock { continue }
            highlightLine(content, lineRange: lineRange, storage: storage, font: font)
        }
    }

    // MARK: - Base / code attributes

    private func baseAttributes(font: NSFont, paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: theme.nsTextColor,
        ]
    }

    private func codeAttributes(inline: Bool) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: theme.nsCodeColor,
        ]
        if inline {
            attributes[.backgroundColor] = theme.nsCodeColor.withAlphaComponent(0.14)
        }
        return attributes
    }

    // MARK: - Line highlighting

    private func highlightLine(
        _ content: NSString,
        lineRange: NSRange,
        storage: NSTextStorage,
        font: NSFont
    ) {
        let line = content.substring(with: lineRange)
        let lineNS = line as NSString
        let base = lineRange.location

        // ATX headings: `#` … `######` followed by whitespace or end-of-line.
        if Self.headingRegex.firstMatch(in: line, range: fullRange(of: lineNS)) != nil {
            storage.addAttributes(
                Self.headingAttributes(theme: theme, font: font),
                range: NSRange(location: base, length: lineNS.length)
            )
            return
        }

        // Setext headings: a line of `=`/`-` underlines the previous line.
        if Self.setextUnderlineRegex.firstMatch(in: line, range: fullRange(of: lineNS)) != nil {
            let titleStart = Self.locationOfFirstNewlineBefore(max(lineRange.location - 1, 0), in: content) + 1
            let titleLength = lineRange.location - titleStart
            if titleLength > 0 {
                storage.addAttributes(
                    Self.headingAttributes(theme: theme, font: font),
                    range: NSRange(location: titleStart, length: titleLength)
                )
            }
            storage.addAttributes(
                Self.headingAttributes(theme: theme, font: font),
                range: NSRange(location: base, length: lineNS.length)
            )
            return
        }

        var inlineStart = 0

        // Blockquote markers: `>`, `> >`, …
        if let match = Self.blockquoteRegex.firstMatch(in: line, range: fullRange(of: lineNS)) {
            let markerRange = match.range(at: 1)
            guard markerRange.location != NSNotFound else { return }
            storage.addAttributes(
                [.foregroundColor: theme.nsQuoteColor],
                range: shifted(base, markerRange)
            )
            inlineStart = max(inlineStart, markerRange.location + markerRange.length)
        }

        // Unordered list markers: `- item`, `* item`, `+ item`
        // Ordered list markers: `1. item`, `12) item`
        if let match = (Self.unorderedListRegex.firstMatch(in: line, range: fullRange(of: lineNS))
                        ?? Self.orderedListRegex.firstMatch(in: line, range: fullRange(of: lineNS))) {
            let markerRange = match.range(at: 1)
            guard markerRange.location != NSNotFound else { return }
            let markerFont = Self.withTrait(.boldFontMask, on: font)
            storage.addAttributes(
                [.foregroundColor: theme.nsListMarkerColor, .font: markerFont],
                range: shifted(base, markerRange)
            )
            inlineStart = max(inlineStart, markerRange.location + markerRange.length)
        }

        // Indented code lines (4 spaces or a tab) are colored wholesale.
        if Self.indentedLineRegex.firstMatch(in: line, range: fullRange(of: lineNS)) != nil {
            storage.addAttributes(
                codeAttributes(inline: false),
                range: NSRange(location: base, length: lineNS.length)
            )
            return
        }

        highlightInline(lineNS, start: inlineStart, base: base, storage: storage, font: font)
    }

    // MARK: - Inline tokens

    /// Applies code, links, strong, emphasis and strikethrough on a single
    /// line. Each pass consults `occupied` so tokens never overlap.
    private func highlightInline(
        _ line: NSString,
        start: Int,
        base: Int,
        storage: NSTextStorage,
        font: NSFont
    ) {
        var occupied: [NSRange] = []

        // Inline code spans.
        for match in Self.inlineCodeRegex.matches(in: line as String, range: fullRange(of: line)) {
            let range = match.range
            guard range.location >= start, !overlaps(range, occupied) else { continue }
            storage.addAttributes(codeAttributes(inline: true), range: shifted(base, range))
            occupied.append(range)
        }

        // Links and images: `[text](url)` and `![alt](url)`.
        for match in Self.linkRegex.matches(in: line as String, range: fullRange(of: line)) {
            let range = match.range
            guard range.location >= start, !overlaps(range, occupied) else { continue }
            let textRange = match.range(at: 1)
            if textRange.location != NSNotFound {
                storage.addAttributes(
                    [.foregroundColor: theme.nsLinkColor],
                    range: shifted(base, textRange)
                )
            }
            let urlRange = match.range(at: 2)
            if urlRange.location != NSNotFound && urlRange.length > 0 {
                storage.addAttributes(
                    [.foregroundColor: theme.nsCodeColor],
                    range: shifted(base, urlRange)
                )
            }
            occupied.append(range)
        }

        // Strong: `**bold**` or `__bold__`.
        for match in Self.strongRegex.matches(in: line as String, range: fullRange(of: line)) {
            let range = match.range
            guard range.location >= start, !overlaps(range, occupied) else { continue }
            let boldFont = Self.withTrait(.boldFontMask, on: font)
            storage.addAttributes(
                [.foregroundColor: theme.nsStrongColor, .font: boldFont],
                range: shifted(base, range)
            )
            occupied.append(range)
        }

        // Emphasis: `*italic*` or `_italic_`.
        for match in Self.emphasisRegex.matches(in: line as String, range: fullRange(of: line)) {
            let range = match.range
            guard range.location >= start, !overlaps(range, occupied) else { continue }
            let italicFont = Self.withTrait(.italicFontMask, on: font)
            storage.addAttributes(
                [.foregroundColor: theme.nsEmphasisColor, .font: italicFont],
                range: shifted(base, range)
            )
            occupied.append(range)
        }

        // Strikethrough: `~~gone~~`.
        for match in Self.strikethroughRegex.matches(in: line as String, range: fullRange(of: line)) {
            let range = match.range
            guard range.location >= start, !overlaps(range, occupied) else { continue }
            storage.addAttributes(
                [
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: theme.nsQuoteColor,
                ],
                range: shifted(base, range)
            )
            occupied.append(range)
        }
    }

    // MARK: - Helpers

    private func fullRange(of ns: NSString) -> NSRange {
        NSRange(location: 0, length: ns.length)
    }

    private func shifted(_ base: Int, _ range: NSRange) -> NSRange {
        NSRange(location: base + range.location, length: range.length)
    }

    private func overlaps(_ range: NSRange, _ occupied: [NSRange]) -> Bool {
        occupied.contains { $0.intersection(range)?.length ?? 0 > 0 }
    }

    private static func withTrait(_ trait: NSFontTraitMask, on font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: trait)
    }

    private static func headingAttributes(theme: EditorTheme, font: NSFont) -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: theme.nsHeadingColor,
            .font: withTrait(.boldFontMask, on: font),
        ]
    }

    // MARK: - Line / block enumeration (internal for tests)

    /// Index of the newline before `location`, or `-1` when none exists.
    static func locationOfFirstNewlineBefore(_ location: Int, in content: NSString) -> Int {
        var i = min(location, content.length) - 1
        while i >= 0 {
            if content.character(at: i) == 10 { return i }
            i -= 1
        }
        return -1
    }

    static func lineRanges(in ns: NSString) -> [NSRange] {
        var ranges: [NSRange] = []
        var location = 0
        while location <= ns.length {
            let lineEnd = ns.range(
                of: "\n",
                options: [],
                range: NSRange(location: location, length: ns.length - location)
            ).location
            if lineEnd == NSNotFound {
                if location < ns.length {
                    ranges.append(NSRange(location: location, length: ns.length - location))
                }
                break
            }
            ranges.append(NSRange(location: location, length: lineEnd - location))
            location = lineEnd + 1
        }
        return ranges
    }

    /// Ranges of fenced code blocks (``` or ~~~), including their fences.
    static func fencedCodeBlockRanges(in ns: NSString) -> [NSRange] {
        let lines = lineRanges(in: ns)
        var result: [NSRange] = []
        var openIndex: Int?
        var openMarker: String?

        for (index, lineRange) in lines.enumerated() {
            let line = ns.substring(with: lineRange)
            if let oIndex = openIndex, let oMarker = openMarker {
                if closingFence(in: line, openMarker: oMarker) != nil {
                    result.append(NSRange(
                        location: lines[oIndex].location,
                        length: lineRange.location + lineRange.length - lines[oIndex].location
                    ))
                    openIndex = nil
                    openMarker = nil
                }
            } else if let marker = openingFence(in: line) {
                openIndex = index
                openMarker = marker
            }
        }
        if let openIndex {
            let start = lines[openIndex].location
            result.append(NSRange(location: start, length: ns.length - start))
        }
        return result
    }

    /// Ranges of indented code-block lines (leading tab, or 4+ spaces).
    static func indentedCodeLineRanges(in ns: NSString) -> [NSRange] {
        lineRanges(in: ns).filter { lineRange in
            let line = ns.substring(with: lineRange)
            return indentedLineRegex.firstMatch(
                in: line, range: NSRange(location: 0, length: (line as NSString).length)
            ) != nil
        }
    }

    private static func openingFence(in line: String) -> String? {
        guard let match = fenceRegex.firstMatch(
            in: line, range: NSRange(location: 0, length: (line as NSString).length)
        ) else { return nil }
        let marker = (line as NSString).substring(with: match.range(at: 1))
        return marker.isEmpty ? nil : marker
    }

    private static func closingFence(in line: String, openMarker: String) -> String? {
        guard let match = fenceRegex.firstMatch(
            in: line, range: NSRange(location: 0, length: (line as NSString).length)
        ) else { return nil }
        let marker = (line as NSString).substring(with: match.range(at: 1))
        guard !marker.isEmpty else { return nil }
        guard marker.last == openMarker.last, marker.count >= openMarker.count else { return nil }
        // A closing fence must have nothing but trailing whitespace after it.
        let rest = (line as NSString).substring(from: match.range.location + match.range.length)
        return rest.trimmingCharacters(in: .whitespaces).isEmpty ? marker : nil
    }

    // MARK: - Regular expressions

    private static let fenceRegex = try! NSRegularExpression(
        pattern: #"^ {0,3}(`{3,}|~{3,})"#
    )

    private static let headingRegex = try! NSRegularExpression(
        pattern: #"^ {0,3}(#{1,6})(?:[ \t]+.*|[ \t]*)$"#
    )

    private static let setextUnderlineRegex = try! NSRegularExpression(
        pattern: #"^ {0,3}(=+)[ \t]*$"#
    )

    private static let blockquoteRegex = try! NSRegularExpression(
        pattern: #"^ {0,3}((?:>[ \t]?)+)"#
    )

    private static let unorderedListRegex = try! NSRegularExpression(
        pattern: #"^ {0,3}((?:[-*+])(?:[ \t]+|$))"#
    )

    private static let orderedListRegex = try! NSRegularExpression(
        pattern: #"^ {0,3}((?:\d{1,9})(?:[.)])(?:[ \t]+|$))"#
    )

    private static let indentedLineRegex = try! NSRegularExpression(
        pattern: #"^(?: {4}|\t)"#
    )

    private static let inlineCodeRegex = try! NSRegularExpression(
        pattern: #"`+[^`\n]+`+"#
    )

    private static let linkRegex = try! NSRegularExpression(
        pattern: #"\!?\[([^\]\n]*)\]\(([^)\n]*)\)"#
    )

    private static let strongRegex = try! NSRegularExpression(
        pattern: #"(?:\*\*(.+?)\*\*|__(.+?)__)"#
    )

    private static let emphasisRegex = try! NSRegularExpression(
        pattern: #"(?<!\w)(\*|_)([^*_\n]+?)\1(?!\w)"#
    )

    private static let strikethroughRegex = try! NSRegularExpression(
        pattern: #"~~(.+?)~~"#
    )
}