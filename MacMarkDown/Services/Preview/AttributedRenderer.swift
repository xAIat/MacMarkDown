import AppKit
import SwiftUI

/// Renders parsed Markdown elements into a single `NSAttributedString`, so the
/// preview can be shown in a read-only TextKit 2 surface (whole-document
/// selection, ⌘A and copy-with-HTML).
///
/// Images are embedded as `NSTextAttachment`s; block-level content (headings,
/// paragraphs, lists, quotes, code, rules, tables) becomes attributed text with
/// paragraph styles. Tables and math formulas cannot be laid out by TextKit
/// (a text grid drifts, and TeX needs MathJax), so they become sized
/// placeholders that `MarkdownPreviewSurface` covers with a `WKWebView` block;
/// diagram fences still render as code.
@MainActor
struct AttributedRenderer {

    let theme: Theme
    var zoom: CGFloat = 1
    var baseURL: URL?
    /// The preview's font family (see `Preferences.previewFontFamily`). The
    /// empty string means the system font; fixed-width runs (code, tables,
    /// front matter) always stay monospaced.
    var fontName: String = ""

    private var baseFontSize: CGFloat { 14 * zoom }

    static func resolvedFont(named name: String, size: CGFloat) -> NSFont? {
        FontResolver.font(named: name, size: size)
    }

    /// The preview's text font: the chosen family when it resolves, otherwise
    /// the system font — the proportional face the bundled preview stylesheets
    /// use. Any non-regular weight asks the family for its bold face, which is
    /// the closest most families expose.
    private func textFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        FontResolver.previewFont(named: fontName, size: size, weight: weight)
    }

    /// Last height WebKit measured for each table, used to reserve the right
    /// amount of space for its placeholder, so a re-render does not jump the
    /// layout back to an estimate.
    var tableHeights: [AnchorPath: CGFloat] = [:]

    /// Last height WebKit measured for each math block, same purpose as
    /// `tableHeights`.
    var mathHeights: [AnchorPath: CGFloat] = [:]

    /// Whether math fences render through MathJax (a web block) instead of
    /// staying code text. Mirrors `Preferences.htmlMathJax`.
    var rendersMath = true

    /// Collects the table blocks the render produces. A reference type so the
    /// recursive `append` chain can report them without threading another
    /// parameter through every block element.
    private final class TableCollector {
        var blocks: [RenderedPreview.TableBlock] = []
    }

    /// Collects the math blocks the render produces (see `TableCollector`).
    private final class MathCollector {
        var blocks: [RenderedPreview.MathBlock] = []
    }

    private let collectedTables = TableCollector()
    private let collectedMath = MathCollector()

    /// Placeholder paragraph font: small enough that the line box is the
    /// attachment's own height instead of adding a text line on top of it.
    private static let placeholderFont = NSFont.systemFont(ofSize: 2)

    /// SwiftUI `Color` -> AppKit `NSColor` (TextKit drawing calls `set`).
    private func ns(_ color: Color) -> NSColor { NSColor(color) }

    /// The rendered preview plus the character ranges needed to locate
    /// scroll-sync anchors in the text layout.
    struct RenderedPreview {
        var attributed: NSAttributedString
        /// The range occupied by each top-level element, in element order.
        var ranges: [NSRange?]
        /// The range occupied by each *anchor path* (nested list items, quote
        /// children, … included), so every parser anchor can be measured at its
        /// own position instead of collapsing to its parent block's top.
        var pathRanges: [AnchorPath: NSRange]
        /// The tables whose rendered HTML belongs to WebKit, with the
        /// placeholder the text layout reserved for each.
        var tables: [TableBlock] = []
        /// The math formulas MathJax renders through WebKit, with their
        /// placeholders.
        var mathBlocks: [MathBlock] = []

        /// One table handed to the WebKit block view.
        struct TableBlock {
            var path: AnchorPath
            /// Range of the placeholder attachment character.
            var range: NSRange
            var table: TableData
            /// The attachment the placeholder uses; its `bounds` height is the
            /// space the table reserves, so the host updates it once WebKit has
            /// measured the real height.
            var attachment: NSTextAttachment
        }

        /// One math formula handed to the WebKit block view.
        struct MathBlock {
            var path: AnchorPath
            /// Range of the placeholder attachment character.
            var range: NSRange
            /// The TeX source, without delimiters.
            var tex: String
            /// Display math (`\[…\]`) or inline math (`\(…\)`).
            var isDisplay: Bool
            var attachment: NSTextAttachment
        }

        /// Ranges aligned 1:1 with `paths` (the parser's anchors, in order).
        func anchorRanges(for paths: [AnchorPath]) -> [NSRange?] {
            paths.map { pathRanges[$0] }
        }
    }

    /// Renders `elements` and returns the character range each top-level element
    /// and each anchor path occupies in the output (used to locate scroll-sync
    /// anchors).
    func render(_ elements: [MarkdownElement]) -> RenderedPreview {
        let result = NSMutableAttributedString()
        var ranges: [NSRange?] = []
        var pathRanges: [AnchorPath: NSRange] = [:]
        collectedTables.blocks = []
        collectedMath.blocks = []
        for (index, element) in elements.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            let start = result.length
            append(element, path: [index], to: result, pathRanges: &pathRanges)
            ranges.append(NSRange(location: start, length: result.length - start))
        }
        return RenderedPreview(
            attributed: result,
            ranges: ranges,
            pathRanges: pathRanges,
            tables: collectedTables.blocks,
            mathBlocks: collectedMath.blocks
        )
    }

    // MARK: - Block elements

    private func append(
        _ element: MarkdownElement,
        path: AnchorPath,
        to result: NSMutableAttributedString,
        pathRanges: inout [AnchorPath: NSRange]
    ) {
        let start = result.length
        defer {
            pathRanges[path] = NSRange(location: start, length: result.length - start)
        }
        switch element {
        case .heading(let level, let text):
            result.append(NSAttributedString(
                string: text + "\n",
                attributes: [
                    .font: headingFont(level),
                    .foregroundColor: ns(theme.headingColor),
                    .paragraphStyle: paragraph(spacingBefore: level == 1 ? 16 : 12, spacingAfter: 6)
                ]
            ))

        case .paragraph(let inlines):
            let text = NSMutableAttributedString()
            appendInlines(inlines, to: text)
            text.append(NSAttributedString(string: "\n"))
            text.addAttributes(
                [.paragraphStyle: paragraph(spacingBefore: 4, spacingAfter: 4)],
                range: NSRange(location: 0, length: text.length)
            )
            result.append(text)

        case .codeBlock(let language, let code):
            if rendersMath, let isDisplay = Self.mathKind(for: language) {
                appendMathBlock(
                    tex: code.trimmingCharacters(in: .whitespacesAndNewlines),
                    isDisplay: isDisplay,
                    path: path,
                    to: result
                )
            } else {
                appendCodeBlock(language: language, code: code, to: result)
            }

        case .blockQuote(let children):
            // Append the children straight into `result` so every nested anchor
            // range stays in the final document's coordinate space (building a
            // separate `inner` string and appending it later would record the
            // children's offsets relative to `inner`).
            let quoteStart = result.length
            for (index, child) in children.enumerated() {
                if index > 0 { result.append(NSAttributedString(string: "\n")) }
                append(child, path: path + [index], to: result, pathRanges: &pathRanges)
            }
            let style = NSMutableParagraphStyle()
            style.headIndent = 16
            style.firstLineHeadIndent = 16
            result.addAttributes(
                [.foregroundColor: ns(theme.blockquoteColor), .paragraphStyle: style],
                range: NSRange(location: quoteStart, length: result.length - quoteStart)
            )

        case .unorderedList(let items):
            appendList(items, ordered: false, path: path, to: result, pathRanges: &pathRanges)

        case .orderedList(let items):
            appendList(items, ordered: true, path: path, to: result, pathRanges: &pathRanges)

        case .taskList(let items):
            appendTaskList(items, path: path, to: result, pathRanges: &pathRanges)

        case .table(let table):
            appendTable(table, path: path, to: result)

        case .thematicBreak:
            result.append(NSAttributedString(
                string: "────────────────\n",
                attributes: [
                    .foregroundColor: ns(theme.dividerColor),
                    .font: textFont(size: baseFontSize)
                ]
            ))

        case .rawHTML(let html):
            result.append(NSAttributedString(
                string: html + "\n",
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular),
                    .foregroundColor: ns(theme.secondaryTextColor)
                ]
            ))

        case .image(let url, let alt):
            appendImage(url: url, alt: alt, to: result)

        case .tableOfContents(let items):
            for item in items {
                let indent = String(repeating: "  ", count: max(0, item.level - 1))
                result.append(NSAttributedString(
                    string: indent + "• " + item.text + "\n",
                    attributes: [
                        .font: textFont(size: baseFontSize),
                        .foregroundColor: ns(theme.linkColor)
                    ]
                ))
            }

        case .footnotes(let items):
            for (index, item) in items.enumerated() {
                result.append(NSAttributedString(
                    string: "[\(index + 1)] \(item.text)\n",
                    attributes: [
                        .font: textFont(size: baseFontSize * 0.9),
                        .foregroundColor: ns(theme.secondaryTextColor)
                    ]
                ))
            }

        case .frontMatter(_, let entries):
            for entry in entries {
                result.append(NSAttributedString(
                    string: "\(entry.key): \(entry.value)\n",
                    attributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular),
                        .foregroundColor: ns(theme.secondaryTextColor)
                    ]
                ))
            }
        }
    }

    // MARK: - Inline elements

    private func appendInlines(_ inlines: [InlineElement], to result: NSMutableAttributedString) {
        for inline in inlines { appendInline(inline, to: result) }
    }

    private func appendInline(_ inline: InlineElement, to result: NSMutableAttributedString) {
        switch inline {
        case .text(let text):
            result.append(NSAttributedString(string: text, attributes: bodyAttributes()))

        case .emphasis(let children):
            appendStyled(children, traits: [.italic], to: result)

        case .strong(let children):
            appendStyled(children, traits: [.bold], to: result)

        case .strikethrough(let children):
            appendStyled(children, traits: [.strikethrough], to: result)

        case .underline(let children):
            appendStyled(children, traits: [.underline], to: result)

        case .highlight(let children):
            let start = result.length
            appendInlines(children, to: result)
            result.addAttribute(
                .backgroundColor,
                value: ns(theme.codeBackgroundColor),
                range: NSRange(location: start, length: result.length - start)
            )

        case .superscript(let children):
            let start = result.length
            appendInlines(children, to: result)
            result.addAttribute(
                .baselineOffset,
                value: baseFontSize * 0.4,
                range: NSRange(location: start, length: result.length - start)
            )

        case .code(let code):
            result.append(NSAttributedString(
                string: code,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular),
                    .foregroundColor: ns(theme.codeTextColor),
                    .backgroundColor: ns(theme.codeBackgroundColor)
                ]
            ))

        case .link(let url, let children):
            let start = result.length
            appendInlines(children, to: result)
            var attributes: [NSAttributedString.Key: Any] = [.foregroundColor: ns(theme.linkColor)]
            if let url, let linkURL = URL(string: url) { attributes[.link] = linkURL }
            result.addAttributes(attributes, range: NSRange(location: start, length: result.length - start))

        case .image(let url, let alt):
            appendImage(url: url, alt: alt, to: result)

        case .quote(let children):
            appendInlines(children, to: result)

        case .lineBreak:
            result.append(NSAttributedString(string: "\n"))

        case .inlineHTML(let html):
            result.append(NSAttributedString(
                string: html,
                attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular),
                    .foregroundColor: ns(theme.secondaryTextColor)
                ]
            ))
        }
    }

    private enum Trait { case italic, bold, strikethrough, underline }

    private func appendStyled(_ children: [InlineElement], traits: Set<Trait>, to result: NSMutableAttributedString) {
        let start = result.length
        appendInlines(children, to: result)
        let range = NSRange(location: start, length: result.length - start)

        var font = textFont(size: baseFontSize)
        var attributes: [NSAttributedString.Key: Any] = [:]
        if traits.contains(.italic) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }
        if traits.contains(.bold) {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        attributes[.font] = font
        if traits.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        if traits.contains(.underline) { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        result.addAttributes(attributes, range: range)

        if traits.contains(.italic) {
            applySyntheticItalicFallback(to: result, in: range, italicFont: font)
        }
    }

    // MARK: - Synthetic italic

    /// CoreText's fallback faces for Chinese (PingFang SC, Hiragino, …) have no
    /// italic member, so the converted italic font above covers Latin only:
    /// the fallback glyphs would stay upright while the Latin beside them
    /// slants — the "English italicizes, Chinese does not" bug. A family with
    /// no italic face at all (e.g. a CJK monospaced family) renders every
    /// script upright the same way. For those characters this substitutes
    /// `FontResolver.syntheticItalic` — the same synthetic oblique the SwiftUI
    /// preview (`InlineRenderer`) and browsers apply.
    private func applySyntheticItalicFallback(
        to result: NSMutableAttributedString,
        in range: NSRange,
        italicFont: NSFont
    ) {
        guard range.length > 0 else { return }
        let string = result.string as NSString
        let isRealItalic = italicFont.fontDescriptor.symbolicTraits.contains(.italic)
        let coverage = CTFontCopyCharacterSet(italicFont as CTFont) as CharacterSet

        // Fast path: the family's real italic face draws the whole run.
        if isRealItalic,
           string.substring(with: range).unicodeScalars.allSatisfy({ coverage.contains($0) }) {
            return
        }

        // Consecutive glyphs that need the same substitute share one
        // attributed run, so a Chinese sentence does not fragment into one
        // font run per character.
        var pendingStart: Int?
        var pendingFace: NSFont?

        func flush(upTo end: Int) {
            if let start = pendingStart, let face = pendingFace, end > start {
                result.addAttribute(
                    .font,
                    value: FontResolver.syntheticItalic(face),
                    range: NSRange(location: start, length: end - start)
                )
            }
            pendingStart = nil
            pendingFace = nil
        }

        var index = range.location
        while index < NSMaxRange(range) {
            let sequence = NSIntersectionRange(
                string.rangeOfComposedCharacterSequence(at: index),
                range
            )
            guard sequence.length > 0 else { break }
            defer { index = NSMaxRange(sequence) }

            // Images, tables and other attachments are not glyphs; never slant them.
            if result.attribute(.attachment, at: index, effectiveRange: nil) != nil {
                flush(upTo: index)
                continue
            }

            let text = string.substring(with: sequence)
            let isCovered = text.unicodeScalars.allSatisfy { coverage.contains($0) }
            if isRealItalic, isCovered {
                flush(upTo: index)
                continue
            }

            let face: NSFont
            if isCovered {
                face = italicFont
            } else {
                // The face CoreText would substitute for this glyph; it needs
                // the shear because the italic font cannot draw it.
                face = CTFontCreateForString(
                    italicFont as CTFont,
                    text as CFString,
                    CFRange(location: 0, length: (text as NSString).length)
                ) as NSFont
            }
            if pendingFace?.fontName == face.fontName { continue }
            flush(upTo: index)
            pendingStart = index
            pendingFace = face
        }
        flush(upTo: NSMaxRange(range))
    }

    // MARK: - Lists

    private func appendList(
        _ items: [ListItem],
        ordered: Bool,
        path: AnchorPath,
        to result: NSMutableAttributedString,
        pathRanges: inout [AnchorPath: NSRange]
    ) {
        for (index, item) in items.enumerated() {
            let itemPath = path + [index]
            let itemStart = result.length
            let marker = ordered ? "\(index + 1). " : "• "
            result.append(NSAttributedString(
                string: marker,
                attributes: [
                    .font: textFont(size: baseFontSize, weight: ordered ? .regular : .semibold),
                    .foregroundColor: ns(theme.secondaryTextColor)
                ]
            ))
            appendListItemContents(item, path: itemPath, to: result, pathRanges: &pathRanges)
            pathRanges[itemPath] = NSRange(location: itemStart, length: result.length - itemStart)
        }
    }

    private func appendTaskList(
        _ items: [ListItem],
        path: AnchorPath,
        to result: NSMutableAttributedString,
        pathRanges: inout [AnchorPath: NSRange]
    ) {
        for (index, item) in items.enumerated() {
            let itemPath = path + [index]
            let itemStart = result.length
            let box = item.isChecked == true ? "☑ " : "☐ "
            result.append(NSAttributedString(
                string: box,
                attributes: [
                    .font: textFont(size: baseFontSize),
                    .foregroundColor: ns(theme.taskListColor)
                ]
            ))
            appendListItemContents(item, path: itemPath, to: result, pathRanges: &pathRanges)
            pathRanges[itemPath] = NSRange(location: itemStart, length: result.length - itemStart)
        }
    }

    private func appendListItemContents(
        _ item: ListItem,
        path: AnchorPath,
        to result: NSMutableAttributedString,
        pathRanges: inout [AnchorPath: NSRange]
    ) {
        // Append straight into `result` so nested anchor ranges stay in the
        // final document's coordinate space.
        for (index, child) in item.children.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            append(child, path: path + [index], to: result, pathRanges: &pathRanges)
        }
        // Ensure the item ends with a newline.
        if !result.string.hasSuffix("\n") { result.append(NSAttributedString(string: "\n")) }
    }

    // MARK: - Table

    /// Tables are laid out by WebKit: the text gets a sized placeholder and
    /// `MarkdownPreviewSurface` positions a table block view over it, so borders,
    /// cell padding and column widths come from the same CSS the HTML export
    /// uses.
    ///
    /// The native alternatives were measured and do not work: TextKit 2 ignores
    /// `NSTextBlock`/`NSTextTable` entirely, and on macOS 27 even a TextKit 1
    /// `NSTextView` lays table cells out as ordinary tabbed paragraphs, so the
    /// columns do not line up. A drawn text grid is not an option either: the
    /// system monospaced font's Latin advance is 0.618 em while a CJK glyph is a
    /// full em, so a Chinese cell drifts out of its column as soon as it wraps.
    private func appendTable(
        _ table: TableData,
        path: AnchorPath,
        to result: NSMutableAttributedString
    ) {
        let attachment = TablePreviewHTML.Attachment(
            table: table,
            reservedHeight: tableHeights[path] ?? TablePreviewHTML.estimatedHeight(for: table, zoom: zoom)
        )

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = 8
        style.paragraphSpacing = 8

        let start = result.length
        result.append(NSAttributedString(
            string: "\u{FFFC}\n",
            attributes: [
                .attachment: attachment,
                .font: Self.placeholderFont,
                .paragraphStyle: style
            ]
        ))
        collectedTables.blocks.append(
            RenderedPreview.TableBlock(
                path: path,
                range: NSRange(location: start, length: 1),
                table: table,
                attachment: attachment
            )
        )
    }

    // MARK: - Math

    /// Whether a code-block language renders through MathJax, and whether it is
    /// display math. `nil` leaves the block as code.
    static func mathKind(for language: String?) -> Bool? {
        switch language?.lowercased() {
        case "math", "latex", "tex": return true
        case "math-inline": return false
        default: return nil
        }
    }

    /// Math is typeset by MathJax in a web block (the preview cannot run
    /// JavaScript inline), so the text gets a sized placeholder and
    /// `MarkdownPreviewSurface` positions the rendered formula over it — the
    /// same arrangement tables use.
    private func appendMathBlock(
        tex: String,
        isDisplay: Bool,
        path: AnchorPath,
        to result: NSMutableAttributedString
    ) {
        let attachment = MathPreviewHTML.Attachment(
            tex: tex,
            isDisplay: isDisplay,
            reservedHeight: mathHeights[path] ?? MathPreviewHTML.estimatedHeight(isDisplay: isDisplay, zoom: zoom)
        )

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = isDisplay ? 8 : 2
        style.paragraphSpacing = isDisplay ? 8 : 2

        let start = result.length
        result.append(NSAttributedString(
            string: "\u{FFFC}\n",
            attributes: [
                .attachment: attachment,
                .font: Self.placeholderFont,
                .paragraphStyle: style
            ]
        ))
        collectedMath.blocks.append(
            RenderedPreview.MathBlock(
                path: path,
                range: NSRange(location: start, length: 1),
                tex: tex,
                isDisplay: isDisplay,
                attachment: attachment
            )
        )
    }

    // MARK: - Code block

    private func appendCodeBlock(language: String?, code: String, to result: NSMutableAttributedString) {
        let style = NSMutableParagraphStyle()
        style.headIndent = 8
        style.firstLineHeadIndent = 8
        result.append(NSAttributedString(
            string: code + (code.hasSuffix("\n") ? "" : "\n"),
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: baseFontSize * 0.9, weight: .regular),
                .foregroundColor: ns(theme.codeTextColor),
                .backgroundColor: ns(theme.codeBackgroundColor),
                .paragraphStyle: style
            ]
        ))
    }

    // MARK: - Images

    private func appendImage(url: String?, alt: String, to result: NSMutableAttributedString) {
        guard let resolved = resolve(url: url),
              let image = NSImage(contentsOf: resolved)
        else {
            result.append(NSAttributedString(
                string: "📷 \(alt)\n",
                attributes: [.foregroundColor: ns(theme.secondaryTextColor)]
            ))
            return
        }
        let attachment = NSTextAttachment()
        attachment.image = image
        result.append(NSAttributedString(attachment: attachment))
        result.append(NSAttributedString(string: "\n"))
    }

    private func resolve(url: String?) -> URL? {
        guard let url, !url.isEmpty else { return nil }
        if let absolute = URL(string: url), absolute.scheme != nil, absolute.isFileURL { return absolute }
        guard let baseURL else { return URL(string: url) }
        let directory = baseURL.hasDirectoryPath ? baseURL : baseURL.appendingPathComponent("")
        return URL(string: url, relativeTo: directory)?.absoluteURL
    }

    // MARK: - Attributes

    private func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: textFont(size: baseFontSize),
            .foregroundColor: ns(theme.textColor)
        ]
    }

    private func headingFont(_ level: Int) -> NSFont {
        let size: CGFloat = switch level {
        case 1: 28
        case 2: 24
        case 3: 20
        case 4: 17
        case 5: 15
        default: 14
        }
        return textFont(size: size * zoom, weight: level <= 2 ? .bold : .semibold)
    }

    private func paragraph(spacingBefore: CGFloat, spacingAfter: CGFloat) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        return style
    }
}
