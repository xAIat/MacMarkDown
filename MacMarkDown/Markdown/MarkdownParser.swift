import Foundation
import Markdown

/// Parses Markdown source text into `[MarkdownElement]` using Apple's
/// `swift-markdown` package. This is the single entry point for all parsing
/// in the app — both the native preview (`MarkdownView`) and the HTML
/// exporter (`Renderer`) consume its output.
///
/// The parser walks the `swift-markdown` `Document` node tree and produces a
/// lightweight, `Sendable` element representation that is easy to render.
@MainActor
public final class MarkdownParser: @unchecked Sendable {

    // MARK: Public

    public init() {}

    /// The options for the parse currently in flight. `parse` is synchronous
    /// and the parser is main-actor bound, so this cannot be observed mid-parse.
    private var options = MarkdownParseOptions()

    /// Parse Markdown text into elements (no scroll anchors).
    public func parse(_ text: String, options: MarkdownParseOptions = MarkdownParseOptions()) -> [MarkdownElement] {
        parseDocument(text, options: options).elements
    }

    /// Parse Markdown text into the render tree plus the ordered scroll
    /// anchors (pre-order) shared by the editor and the preview.
    ///
    /// Every rewrite is line-preserving so `DocumentAnchor.line` refers to a
    /// line in the *original* document text: front matter and footnote
    /// definitions are blanked (not removed), and inline math records a line
    /// map. This lets the editor resolve each anchor line to a layout position.
    public func parseDocument(_ text: String, options: MarkdownParseOptions = MarkdownParseOptions()) -> ParsedDocument {
        self.options = options
        var elements: [MarkdownElement] = []
        var anchors: [DocumentAnchor] = []

        // Front matter detection. The block is replaced with blank lines so
        // parser line numbers stay aligned with the original document.
        var body = text
        var frontMatterTitle: String?
        var frontMatterEntries: [FrontMatterEntry] = []
        if options.enableFrontMatter, let fm = FrontMatter.extract(from: text) {
            let lines = text.components(separatedBy: "\n")
            let consumed = min(fm.consumedLineCount, lines.count)
            body = String(repeating: "\n", count: consumed)
                + lines[consumed...].joined(separator: "\n")
            frontMatterTitle = fm.title
            frontMatterEntries = fm.entries
        }

        // Footnotes are not part of swift-markdown; blank the definitions
        // (line-preserving) and rewrite `[^id]` references to anchor links.
        var footnotes: [FootnoteItem] = []
        if options.enableFootnotes {
            let extracted = Self.extractFootnoteDefinitions(from: body)
            var referenceNumbers: [String: Int] = [:]
            body = Self.rewriteFootnoteReferences(in: extracted.body) { id, number in
                referenceNumbers[id] = number
                return "[\(number)](#fn-\(id))"
            }
            footnotes = extracted.items.sorted {
                (referenceNumbers[$0.id] ?? Int.max) < (referenceNumbers[$1.id] ?? Int.max)
            }
        }

        // `NO_INTRA_EMPHASIS`: escape word-internal `*`/`_` so they are not
        // parsed as emphasis (swift-markdown has no such option).
        if !options.enableIntraEmphasis {
            body = Self.transformOutsideFencedCode(body) { Self.escapeIntraWordEmphasis(in: $0) }
        }

        // swift-markdown has no dedicated bare-URL autolink option; wrap bare
        // URLs in angle brackets so its built-in autolink recognizes them.
        if options.enableAutolink {
            body = Self.transformOutsideFencedCode(body) { Self.applyAutolinks(to: $0) }
        }

        // Math spans are rewritten to fenced blocks, which changes the line
        // count; keep a map from parsed lines back to original lines.
        var lineMap: [Int]?
        if options.enableMath || options.enableInlineMath {
            let result = Self.applyMath(
                body,
                enableMath: options.enableMath,
                enableInlineDollar: options.enableInlineMath
            )
            body = result.body
            lineMap = result.lineMap
        }

        // Underline/highlight/superscript/quote are not part of swift-markdown;
        // mark them with sentinels so the inline converter can wrap them.
        body = Self.applyInlineExtensionMarkers(to: body, options: options)

        // swift-markdown applies smart punctuation (curly quotes, dashes) by
        // default; the SmartyPants preference opts out of it.
        let parseOptions: ParseOptions = options.enableSmartyPants ? [] : [.disableSmartOpts]
        let document = Document(parsing: body, options: parseOptions)

        func originalLine(_ parsedLine: Int) -> Int {
            guard let lineMap, parsedLine >= 1, parsedLine <= lineMap.count else {
                return parsedLine
            }
            return lineMap[parsedLine - 1] + 1
        }

        for block in document.blockChildren {
            let path = [elements.count]
            if let element = convertBlock(
                block, text: body, path: path, anchors: &anchors, originalLine: originalLine
            ) {
                elements.append(element)
            }
        }

        // Replace a `[toc]` paragraph with a table of contents built from the
        // document's headings.
        if options.enableTOC, elements.contains(where: isTOCPlaceholder) {
            let toc = TOCItem.make(from: elements)
            elements = elements.map { element in
                isTOCPlaceholder(element) ? .tableOfContents(toc) : element
            }
        }

        if !footnotes.isEmpty {
            elements.append(.footnotes(footnotes))
        }

        if !frontMatterEntries.isEmpty {
            elements.insert(.frontMatter(title: frontMatterTitle, entries: frontMatterEntries), at: 0)
            // Shift top-level anchor paths right by one for the inserted node.
            anchors = anchors.map { anchor in
                var path = anchor.path
                if let first = path.first { path[0] = first + 1 }
                return DocumentAnchor(path: path, line: anchor.line)
            }
        }
        return ParsedDocument(elements: elements, anchors: anchors)
    }

    // MARK: - Footnotes

    /// Pulls `[^id]: definition` lines out of the body. Definitions are
    /// single-line (indented continuations are not supported yet).
    private static func extractFootnoteDefinitions(
        from body: String
    ) -> (body: String, items: [FootnoteItem]) {
        var definitions: [String: String] = [:]
        var order: [String] = []
        var keptLines: [String] = []

        let pattern = #"^\[\^([^\]]+)\]:\s*(.*)$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        for line in body.components(separatedBy: "\n") {
            let range = NSRange(location: 0, length: (line as NSString).length)
            if let match = regex?.firstMatch(in: line, range: range),
               let idRange = Range(match.range(at: 1), in: line),
               let textRange = Range(match.range(at: 2), in: line) {
                let id = String(line[idRange])
                if definitions[id] == nil { order.append(id) }
                definitions[id] = String(line[textRange])
                // Blank (rather than drop) the line so parser line numbers stay
                // aligned with the original document.
                keptLines.append("")
            } else {
                keptLines.append(line)
            }
        }

        let items = order.compactMap { id in
            definitions[id].map { FootnoteItem(id: id, text: $0) }
        }
        return (keptLines.joined(separator: "\n"), items)
    }

    /// Replaces `[^id]` references with the string produced by `replacement`,
    /// numbering them in order of first appearance.
    private static func rewriteFootnoteReferences(
        in body: String,
        replacement: (String, Int) -> String
    ) -> String {
        let pattern = #"\[\^([^\]]+)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return body }
        var numbers: [String: Int] = [:]
        var next = 1
        var result = ""
        var cursor = 0
        let ns = body as NSString
        for match in regex.matches(in: body, range: NSRange(location: 0, length: ns.length)) {
            guard let idRange = Range(match.range(at: 1), in: body) else { continue }
            let id = String(body[idRange])
            let number = numbers[id] ?? {
                defer { next += 1 }
                numbers[id] = next
                return next
            }()
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += replacement(id, number)
            cursor = NSMaxRange(match.range)
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// A paragraph whose only content is `[toc]`/`[TOC]`.
    private func isTOCPlaceholder(_ element: MarkdownElement) -> Bool {
        guard case let .paragraph(inlines) = element else { return false }
        let text = inlines.compactMap { inline -> String? in
            if case .text(let value) = inline { return value }
            return nil
        }.joined().trimmingCharacters(in: .whitespaces)
        return text.caseInsensitiveCompare("[toc]") == .orderedSame
    }

    // MARK: Block conversion

    private func convertBlock(
        _ block: Markup,
        text: String,
        path: AnchorPath,
        anchors: inout [DocumentAnchor],
        originalLine: (Int) -> Int
    ) -> MarkdownElement? {
        func record(_ node: Markup) {
            if let line = node.range?.lowerBound.line {
                anchors.append(DocumentAnchor(path: path, line: originalLine(line)))
            }
        }

        switch block {
        case let heading as Heading:
            record(heading)
            return .heading(level: heading.level, text: inlineText(of: heading))
        case let paragraph as Paragraph:
            record(paragraph)
            return .paragraph(convertInlines(paragraph.inlineChildren))
        case let codeBlock as CodeBlock:
            record(codeBlock)
            if !options.enableFencedCode, isFencedCodeBlock(codeBlock, in: text) {
                return .paragraph([.text(codeBlock.format())])
            }
            let language = codeBlock.language
            let code = codeBlock.code
            return .codeBlock(language: language, code: code)
        case let ordered as OrderedList:
            record(ordered)
            let items = convertListItems(
                Array(ordered.listItems), parentPath: path, text: text,
                anchors: &anchors, originalLine: originalLine
            )
            return listElement(items: items, ordered: true)
        case let unordered as UnorderedList:
            record(unordered)
            let items = convertListItems(
                Array(unordered.listItems), parentPath: path, text: text,
                anchors: &anchors, originalLine: originalLine
            )
            return listElement(items: items, ordered: false)
        case let blockQuote as BlockQuote:
            record(blockQuote)
            var children: [MarkdownElement] = []
            for child in blockQuote.blockChildren {
                let childPath = path + [children.count]
                if let element = convertBlock(
                    child, text: text, path: childPath,
                    anchors: &anchors, originalLine: originalLine
                ) {
                    children.append(element)
                }
            }
            return .blockQuote(children)
        case let table as Table:
            record(table)
            guard options.enableTables else {
                return .paragraph([.text(table.format())])
            }
            return .table(convertTable(table))
        case is ThematicBreak:
            record(block)
            return .thematicBreak
        case let html as HTMLBlock:
            return .rawHTML(html.rawHTML)
        default:
            return nil
        }
    }

    /// Emits a task list when checkbox items are present and the extension is
    /// enabled; otherwise a regular list.
    private func listElement(items: [ListItem], ordered: Bool) -> MarkdownElement {
        if options.enableTaskList, items.contains(where: { $0.isChecked != nil }) {
            return .taskList(items)
        }
        return ordered ? .orderedList(items) : .unorderedList(items)
    }

    /// Whether a code block was written with a fence (```` ``` ````/`~~~`),
    /// versus a four-space indent. Used to honor the fenced-code preference.
    private func isFencedCodeBlock(_ block: CodeBlock, in text: String) -> Bool {
        guard let range = block.range else { return true }
        let lines = text.components(separatedBy: "\n")
        let lineIndex = range.lowerBound.line - 1
        guard lines.indices.contains(lineIndex) else { return true }
        let trimmed = lines[lineIndex].trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    private func convertListItems(
        _ rawItems: [Markdown.ListItem],
        parentPath: AnchorPath,
        text: String,
        anchors: inout [DocumentAnchor],
        originalLine: (Int) -> Int
    ) -> [ListItem] {
        var items: [ListItem] = []
        for rawItem in rawItems {
            let itemPath = parentPath + [items.count]
            if let line = rawItem.range?.lowerBound.line {
                anchors.append(DocumentAnchor(path: itemPath, line: originalLine(line)))
            }
            var children: [MarkdownElement] = []
            for child in rawItem.blockChildren {
                let childPath = itemPath + [children.count]
                if let element = convertBlock(
                    child, text: text, path: childPath,
                    anchors: &anchors, originalLine: originalLine
                ) {
                    children.append(element)
                }
            }
            let checked: Bool? = switch rawItem.checkbox {
            case .checked?: true
            case .unchecked?: false
            case .none: nil
            }
            items.append(ListItem(children: children, isChecked: checked))
        }
        return items
    }

    private func convertTable(_ table: Table) -> TableData {
        let headers = Array(table.head.cells).map {
            Self.strippingExtensionMarkers($0.plainText)
        }
        let rows = Array(table.body.rows).map { row in
            Array(row.cells).map { Self.strippingExtensionMarkers($0.plainText) }
        }
        let alignments = table.columnAlignments.map { alignment -> TableColumnAlignment in
            switch alignment {
            case .center: return .center
            case .right: return .right
            default: return .left
            }
        }
        return TableData(headers: headers, rows: rows, alignments: alignments)
    }

    // MARK: Inline conversion

    /// Converts a run of inline markup, resolving the private-use markers
    /// written by `applyInlineExtensionMarkers`.
    ///
    /// The markers are tracked across the whole run instead of per `Text` node
    /// so an underline pair can straddle a line break (the editor's Underline
    /// command wraps multi-line selections, which swift-markdown represents as
    /// a `SoftBreak` between two text nodes). Markers that never pair up are
    /// dropped rather than leaking private-use characters into the output.
    private func convertInlines(_ inlines: some Sequence<InlineMarkup>) -> [InlineElement] {
        var result: [InlineElement] = []
        var active: InlineExtensionMarker?
        var inner: [InlineElement] = []
        var plain = ""
        var innerPlain = ""

        func flushPlain() {
            guard !plain.isEmpty else { return }
            result.append(.text(plain))
            plain = ""
        }

        func flushInnerPlain() {
            guard !innerPlain.isEmpty else { return }
            inner.append(.text(innerPlain))
            innerPlain = ""
        }

        func emit(_ element: InlineElement) {
            if active != nil {
                flushInnerPlain()
                inner.append(element)
            } else {
                flushPlain()
                result.append(element)
            }
        }

        for inline in inlines {
            guard let text = inline as? Text else {
                emit(convertInlineNode(inline))
                continue
            }
            for character in text.string {
                if let current = active {
                    if character == current.close {
                        flushInnerPlain()
                        result.append(current.make(inner))
                        active = nil
                        inner = []
                    } else if !Self.allExtensionMarkers.contains(character) {
                        innerPlain.append(character)
                    }
                    continue
                }
                if let marker = Self.extensionMarkers[character] {
                    flushPlain()
                    active = marker
                } else if Self.allExtensionMarkers.contains(character) {
                    // Unpaired marker: drop it so it cannot show up as text.
                    continue
                } else {
                    plain.append(character)
                }
            }
        }

        if active != nil {
            // Unterminated pair: keep the content without the markers.
            flushInnerPlain()
            result.append(contentsOf: inner)
        }
        flushPlain()
        return result
    }

    /// Converts one inline node that is not a `Text` run.
    private func convertInlineNode(_ inline: some InlineMarkup) -> InlineElement {
        switch inline {
        case let emphasis as Emphasis:
            return .emphasis(convertInlines(emphasis.inlineChildren))
        case let strong as Strong:
            return .strong(convertInlines(strong.inlineChildren))
        case let code as InlineCode:
            return .code(code.code)
        case let link as Link:
            return .link(url: link.destination, children: convertInlines(link.inlineChildren))
        case let strike as Strikethrough:
            guard options.enableStrikethrough else {
                return .text(Self.strippingExtensionMarkers(strike.plainText))
            }
            return .strikethrough(convertInlines(strike.inlineChildren))
        case let image as Image:
            return .image(url: image.source, alt: Self.strippingExtensionMarkers(image.plainText))
        case is LineBreak:
            return .lineBreak
        case is SoftBreak:
            return options.enableHardWrap ? .lineBreak : .text(" ")
        case let html as InlineHTML:
            return .inlineHTML(html.rawHTML)
        default:
            return .text(Self.strippingExtensionMarkers(inline.plainText))
        }
    }

    // MARK: - Inline extensions (underline / highlight / superscript / quote)

    private static let underlineOpen: Character = "\u{E000}"
    private static let underlineClose: Character = "\u{E001}"
    private static let highlightOpen: Character = "\u{E002}"
    private static let highlightClose: Character = "\u{E003}"
    private static let superscriptOpen: Character = "\u{E004}"
    private static let superscriptClose: Character = "\u{E005}"
    private static let quoteOpen: Character = "\u{E006}"
    private static let quoteClose: Character = "\u{E007}"

    /// A sentinel pair emitted by `applyInlineExtensionMarkers`.
    private struct InlineExtensionMarker {
        let close: Character
        let make: ([InlineElement]) -> InlineElement
    }

    /// Open sentinel → the inline element the pair wraps.
    private static let extensionMarkers: [Character: InlineExtensionMarker] = [
        underlineOpen: InlineExtensionMarker(close: underlineClose, make: InlineElement.underline),
        highlightOpen: InlineExtensionMarker(close: highlightClose, make: InlineElement.highlight),
        superscriptOpen: InlineExtensionMarker(close: superscriptClose, make: InlineElement.superscript),
        quoteOpen: InlineExtensionMarker(close: quoteClose, make: InlineElement.quote),
    ]

    /// Every sentinel, open or close. Unpaired ones are dropped instead of
    /// leaking private-use characters into the rendered output.
    private static let allExtensionMarkers: Set<Character> = [
        underlineOpen, underlineClose,
        highlightOpen, highlightClose,
        superscriptOpen, superscriptClose,
        quoteOpen, quoteClose,
    ]

    /// Removes leftover sentinels from text consumed as plain text (headings,
    /// table cells, image alt text), where no inline conversion happens.
    private static func strippingExtensionMarkers(_ text: String) -> String {
        text.filter { !allExtensionMarkers.contains($0) }
    }

    /// Rewrites `_text_`, `==text==`, `^text^` and `"text"` into
    /// sentinel-delimited runs before parsing (single level). Fenced code
    /// blocks are left untouched so code is never rewritten.
    ///
    /// Underline uses a *single* underscore pair, so `__text__` keeps its
    /// standard meaning (strong emphasis). Escaped underscores and intra-word
    /// `_` are left alone because that escape pass runs before this one. A
    /// pair may span the line breaks inside a paragraph (the editor's
    /// Underline command wraps a multi-line selection) but never a blank line.
    private static func applyInlineExtensionMarkers(
        to body: String,
        options: MarkdownParseOptions
    ) -> String {
        transformOutsideFencedCode(body) { segment in
            var result = segment
            // Inline HTML tags and autolinks are passed through verbatim, so
            // extension markup inside `<…>` must not be rewritten.
            let protected = angleSpans(in: segment)
            if options.enableUnderline {
                result = replace(
                    #"(?<![\\_])_(?!_)((?:[^\n]|\n(?![ \t]*\n))+?)(?<![\\_])_(?!_)"#,
                    in: result,
                    open: underlineOpen,
                    close: underlineClose,
                    protected: protected
                )
            }
            if options.enableHighlight {
                result = replace(
                    #"==(.+?)=="#,
                    in: result,
                    open: highlightOpen,
                    close: highlightClose,
                    protected: protected
                )
            }
            if options.enableSuperscript {
                result = replace(
                    #"\^(.+?)\^"#,
                    in: result,
                    open: superscriptOpen,
                    close: superscriptClose,
                    protected: protected
                )
            }
            if options.enableQuote {
                result = replace(
                    #""([^"\n]+)""#,
                    in: result,
                    open: quoteOpen,
                    close: quoteClose,
                    protected: protected
                )
            }
            return result
        }
    }

    /// The ranges of single-line `<…>` spans (inline HTML tags and
    /// autolinks). Markdown is not parsed inside them, so the extension
    /// rewrites skip these.
    private static func angleSpans(in text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: #"<[^<>\n]*>"#) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
    }

    // MARK: - Preprocessing helpers

    /// Applies `transform` to the document outside fenced code blocks
    /// (```` ``` ````/`~~~`), so extension preprocessing never rewrites code.
    static func transformOutsideFencedCode(
        _ body: String,
        _ transform: (String) -> String
    ) -> String {
        var output: [String] = []
        var buffer: [String] = []
        var fenceMarker: Character?

        func flush() {
            guard !buffer.isEmpty else { return }
            output.append(transform(buffer.joined(separator: "\n")))
            buffer.removeAll()
        }

        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fenceMarker {
                output.append(line)
                if trimmed.hasPrefix(String(repeating: String(marker), count: 3)) {
                    fenceMarker = nil
                }
                continue
            }
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                fenceMarker = trimmed.first
                output.append(line)
                continue
            }
            buffer.append(line)
        }
        flush()
        return output.joined(separator: "\n")
    }

    /// Escapes `*`/`_` that sit between word characters so swift-markdown does
    /// not treat them as emphasis (the intra-word emphasis toggle).
    static func escapeIntraWordEmphasis(in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<=\w)([*_])(?=\w)"#) else {
            return text
        }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += "\\" + ns.substring(with: match.range)
            cursor = NSMaxRange(match.range)
        }
        result += ns.substring(from: cursor)
        return result
    }

    // MARK: - Math

    /// One opening delimiter of a TeX math span.
    private struct MathDelimiter {
        let open: [Character]
        /// Closing sequences, longest first (`\\]` wins over `\]`).
        let closes: [[Character]]
        /// Fence language of the rewritten block (`math` / `math-inline`).
        let language: String
        /// Whether the span may close on a later line. Display math does;
        /// `$…$` stays on one line so prose dollars cannot swallow a paragraph.
        let allowsLineBreak: Bool
    }

    /// A located math span: its TeX content plus everything needed to rebuild
    /// the surrounding text and to map the rewritten lines back to the source.
    private struct MathSpan {
        var content: String
        /// 0-based source line of the content's first line.
        var contentStartLine: Int
        /// 0-based source line the closing delimiter sits on.
        var closerLine: Int
        /// Index just past the closer within its line.
        var closeEnd: Int
        /// Text after the closer on its line.
        var rest: String
    }

    /// The delimiter pairs enabled by the parse options, in match order.
    ///
    /// TeX-like spans are written with double backslashes (`\\[ … \\]`,
    /// `\\( … \\)`) by some generators and with the single-backslash forms by
    /// MathJax and most editors; both are accepted, as are `$$ … $$`.
    /// A bare `$ … $` is the inline-dollar opt-in.
    private static func mathDelimiters(enableMath: Bool, enableInlineDollar: Bool) -> [MathDelimiter] {
        var delimiters: [MathDelimiter] = []
        if enableMath {
            let displayCloses: [[Character]] = [Array("\\\\]"), Array("\\]")]
            let inlineCloses: [[Character]] = [Array("\\\\)"), Array("\\)")]
            delimiters.append(MathDelimiter(
                open: Array("\\\\["), closes: displayCloses, language: "math", allowsLineBreak: true
            ))
            delimiters.append(MathDelimiter(
                open: Array("\\\\("), closes: inlineCloses, language: "math-inline", allowsLineBreak: true
            ))
            delimiters.append(MathDelimiter(
                open: Array("\\["), closes: displayCloses, language: "math", allowsLineBreak: true
            ))
            delimiters.append(MathDelimiter(
                open: Array("\\("), closes: inlineCloses, language: "math-inline", allowsLineBreak: true
            ))
            delimiters.append(MathDelimiter(
                open: Array("$$"), closes: [Array("$$")], language: "math", allowsLineBreak: true
            ))
        }
        if enableInlineDollar {
            delimiters.append(MathDelimiter(
                open: ["$"], closes: [["$"]], language: "math-inline", allowsLineBreak: false
            ))
        }
        return delimiters
    }

    /// Rewrites TeX math spans into fenced `math`/`math-inline` blocks,
    /// returning a map from each parsed line (0-based) back to its original
    /// line. Fenced code blocks and inline code spans are skipped, and a span
    /// that is never closed is left as written.
    ///
    /// MathJax cannot run inside the native preview, so the spans are handed
    /// to the web block pipeline. Every supported delimiter is recognized:
    /// `\\[ … \\]`, `\\( … \\)`, `\[ … \]`, `\( … \)`, `$$ … $$` and (when
    /// the inline-dollar option is on) `$ … $`.
    static func applyMath(
        _ body: String,
        enableMath: Bool,
        enableInlineDollar: Bool
    ) -> (body: String, lineMap: [Int]) {
        let lines = body.components(separatedBy: "\n")
        // Most prose has no math characters at all; skip the rewrite (and the
        // whole-document line copy) without scanning.
        guard enableMath || enableInlineDollar,
              body.contains(where: { $0 == "\\" || $0 == "$" })
        else {
            return (body, Array(lines.indices))
        }

        let delimiters = Self.mathDelimiters(enableMath: enableMath, enableInlineDollar: enableInlineDollar)
        var output: [String] = []
        var map: [Int] = []
        var fenceMarker: Character?
        var lineIndex = 0
        /// Text after a closer that lives on an already-consumed source line.
        var remainder: (text: String, source: Int)?

        func emit(_ text: String, source: Int) {
            output.append(text)
            map.append(source)
        }

        while lineIndex < lines.count || remainder != nil {
            let current: String
            let source: Int
            var isRemainder = false
            if let rest = remainder {
                remainder = nil
                current = rest.text
                source = rest.source
                isRemainder = true
            } else {
                current = lines[lineIndex]
                source = lineIndex
                lineIndex += 1
            }

            let trimmed = current.trimmingCharacters(in: .whitespaces)
            if !isRemainder, let marker = fenceMarker {
                emit(current, source: source)
                if trimmed.hasPrefix(String(repeating: String(marker), count: 3)) {
                    fenceMarker = nil
                }
                continue
            }
            if !isRemainder, trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                emit(current, source: source)
                fenceMarker = trimmed.first
                continue
            }
            if trimmed.hasPrefix("|") {
                // A table row (or its separator). A fence cannot live in a
                // row, so rewriting here would tear the table apart; leave the
                // cell text as written.
                emit(current, source: source)
                continue
            }
            if !current.contains(where: { $0 == "\\" || $0 == "$" }) {
                // No delimiter can appear on this line.
                emit(current, source: source)
                continue
            }

            let chars = Array(current)
            var plainStart = 0
            var cursor = 0
            var sawSpan = false
            while cursor < chars.count {
                if chars[cursor] == "`" {
                    // Inline code never rewrites, so a `$HOME` span in prose
                    // is not mistaken for math.
                    if let end = Self.inlineCodeEnd(in: chars, from: cursor) {
                        cursor = end
                        continue
                    }
                }
                guard let opener = Self.matchMathOpener(in: chars, at: cursor, delimiters: delimiters) else {
                    cursor += 1
                    continue
                }
                guard let span = Self.locateMathSpan(
                    opener: opener,
                    chars: chars,
                    contentStart: cursor + opener.open.count,
                    sourceLine: source,
                    nextLineIndex: lineIndex,
                    lines: lines
                ) else {
                    cursor += opener.open.count
                    continue
                }

                // The fence must start at the beginning of a line, so any prose
                // before the span becomes its own line. Indentation (a list
                // item's continuation indent) is kept on the fence so the
                // block stays inside its list item.
                let prefix = String(chars[plainStart..<cursor])
                let indent = prefix.allSatisfy { $0 == " " || $0 == "\t" } ? prefix : ""
                if !prefix.isEmpty && indent.isEmpty {
                    emit(prefix, source: source)
                }

                var contentLines = span.content.components(separatedBy: "\n")
                var contentSource = span.contentStartLine
                while contentLines.count > 1, contentLines.first?.isEmpty == true {
                    contentLines.removeFirst()
                    contentSource += 1
                }
                while contentLines.count > 1, contentLines.last?.isEmpty == true {
                    contentLines.removeLast()
                }

                let fence = String(
                    repeating: "`",
                    count: max(3, Self.longestBacktickRun(in: span.content) + 1)
                )
                emit(indent + fence + opener.language, source: source)
                for (offset, contentLine) in contentLines.enumerated() {
                    emit(contentLine, source: contentSource + offset)
                }
                emit(indent + fence, source: span.closerLine)

                sawSpan = true
                if span.closerLine == source {
                    cursor = span.closeEnd
                    plainStart = cursor
                } else {
                    lineIndex = max(lineIndex, span.closerLine + 1)
                    if !span.rest.isEmpty {
                        remainder = (span.rest, span.closerLine)
                    }
                    plainStart = chars.count
                    cursor = chars.count
                }
            }
            // A line with no span is copied verbatim (blank lines included); a
            // line a span consumed contributes no separate output.
            let tail = String(chars[plainStart...])
            if !sawSpan || !tail.isEmpty {
                emit(tail, source: source)
            }
        }
        return (output.joined(separator: "\n"), map)
    }

    /// The first math opener at or after `index`, or `nil`.
    private static func matchMathOpener(
        in chars: [Character],
        at index: Int,
        delimiters: [MathDelimiter]
    ) -> MathDelimiter? {
        for delimiter in delimiters {
            guard Self.matches(chars, at: index, text: delimiter.open) else { continue }
            // An escaped backslash or dollar cannot open a span.
            if Self.isEscaped(chars, at: index) { continue }
            // A single `$` must not be the first half of `$$`.
            if delimiter.open == ["$"], index + 1 < chars.count, chars[index + 1] == "$" { continue }
            return delimiter
        }
        return nil
    }

    /// The first unescaped closing sequence at or after `start`, or `nil`.
    private static func matchMathCloser(
        in chars: [Character],
        from start: Int,
        closes: [[Character]]
    ) -> (start: Int, end: Int)? {
        var index = max(0, start)
        while index < chars.count {
            for close in closes where Self.matches(chars, at: index, text: close) {
                if close.first == "$", Self.isEscaped(chars, at: index) { continue }
                return (index, index + close.count)
            }
            index += 1
        }
        return nil
    }

    /// Whether `text` occurs at `index`. Compares in place: the scanner probes
    /// every character, and slicing a new array per probe would allocate on
    /// every keystroke's parse.
    private static func matches(_ chars: [Character], at index: Int, text: [Character]) -> Bool {
        guard index + text.count <= chars.count else { return false }
        for (offset, character) in text.enumerated() where chars[index + offset] != character {
            return false
        }
        return true
    }

    /// Locates the closer for an opener, on the same line or — for display
    /// math — on a following line, stopping at a blank line (a paragraph
    /// break) or a fenced code block.
    private static func locateMathSpan(
        opener: MathDelimiter,
        chars: [Character],
        contentStart: Int,
        sourceLine: Int,
        nextLineIndex: Int,
        lines: [String]
    ) -> MathSpan? {
        if let hit = Self.matchMathCloser(in: chars, from: contentStart, closes: opener.closes) {
            return MathSpan(
                content: String(chars[contentStart..<hit.start]),
                contentStartLine: sourceLine,
                closerLine: sourceLine,
                closeEnd: hit.end,
                rest: String(chars[hit.end...])
            )
        }
        guard opener.allowsLineBreak else { return nil }

        var searchLine = nextLineIndex
        while searchLine < lines.count {
            let line = lines[searchLine]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") || trimmed.hasPrefix("|") {
                break
            }
            let lineChars = Array(line)
            guard let hit = Self.matchMathCloser(in: lineChars, from: 0, closes: opener.closes) else {
                searchLine += 1
                continue
            }
            var content = String(chars[contentStart...])
            if searchLine > nextLineIndex {
                content += "\n" + lines[nextLineIndex..<searchLine].joined(separator: "\n")
            }
            content += "\n" + String(lineChars[..<hit.start])
            return MathSpan(
                content: content,
                contentStartLine: sourceLine,
                closerLine: searchLine,
                closeEnd: hit.end,
                rest: String(lineChars[hit.end...])
            )
        }
        return nil
    }

    /// Whether the character at `index` is escaped by an odd run of
    /// backslashes immediately before it.
    private static func isEscaped(_ chars: [Character], at index: Int) -> Bool {
        var count = 0
        var probe = index - 1
        while probe >= 0, chars[probe] == "\\" {
            count += 1
            probe -= 1
        }
        return count % 2 == 1
    }

    /// The end (exclusive) of an inline code span starting at `index`, or `nil`
    /// when the backtick run never closes on the line.
    private static func inlineCodeEnd(in chars: [Character], from index: Int) -> Int? {
        var openRun = 0
        while index + openRun < chars.count, chars[index + openRun] == "`" { openRun += 1 }
        var probe = index + openRun
        while probe < chars.count {
            guard chars[probe] == "`" else {
                probe += 1
                continue
            }
            var closeRun = 0
            while probe + closeRun < chars.count, chars[probe + closeRun] == "`" { closeRun += 1 }
            if closeRun == openRun { return probe + closeRun }
            probe += closeRun
        }
        return nil
    }

    /// The longest backtick run in `text`; the fence has to be longer so it is
    /// never closed by the content itself.
    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var run = 0
        for character in text {
            if character == "`" {
                run += 1
                longest = max(longest, run)
            } else {
                run = 0
            }
        }
        return longest
    }

    /// Wraps bare `http(s)://…` URLs in angle brackets so swift-markdown's
    /// built-in autolink recognizes them. URLs already inside a link/image
    /// destination or an existing autolink are left alone.
    static func applyAutolinks(to text: String) -> String {
        let pattern = #"(?<![\w\(<"'])(https?://[^\s<>\(\)\[\]"']+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var url = ns.substring(with: match.range)
            // Don't swallow trailing sentence punctuation.
            while let last = url.last, ".,;:!?".contains(last) {
                url.removeLast()
            }
            guard !url.isEmpty else { continue }
            let consumed = match.range.location + url.utf16.count
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += "<\(url)>"
            cursor = consumed
        }
        result += ns.substring(from: cursor)
        return result
    }

    private static func replace(
        _ pattern: String,
        in text: String,
        open: Character,
        close: Character,
        protected: [NSRange] = []
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 1 else { continue }
            guard !protected.contains(where: {
                NSIntersectionRange($0, match.range).length > 0
            }) else { continue }
            let content = ns.substring(with: match.range(at: 1))
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += "\(open)\(content)\(close)"
            cursor = NSMaxRange(match.range)
        }
        result += ns.substring(from: cursor)
        return result
    }

    private func inlineText(of markup: Markup) -> String {
        let text: String
        if let convertible = markup as? PlainTextConvertibleMarkup {
            text = convertible.plainText
        } else {
            text = markup.format()
        }
        return Self.strippingExtensionMarkers(text)
    }
}

extension TOCItem {
    /// Collects the document's headings (including those nested in quotes and
    /// list items) in document order.
    static func make(from elements: [MarkdownElement]) -> [TOCItem] {
        var items: [TOCItem] = []
        func walk(_ elements: [MarkdownElement]) {
            for element in elements {
                switch element {
                case .heading(let level, let text):
                    items.append(TOCItem(level: level, text: text))
                case .blockQuote(let children):
                    walk(children)
                case .unorderedList(let listItems), .orderedList(let listItems), .taskList(let listItems):
                    for item in listItems {
                        walk(item.children)
                    }
                default:
                    break
                }
            }
        }
        walk(elements)
        return items
    }
}