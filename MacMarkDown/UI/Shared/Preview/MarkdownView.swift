import SwiftUI

/// Tracks measured anchor Y-offsets keyed by node path so the preview can
/// report its anchors to the scroll-sync service. Keying by path (not index)
/// keeps values stable across re-parses, where indices may be reused.
/// Class-in-@State so probe closures can mutate it without a view rebuild.
private final class AnchorOffsetStore {
    var values: [AnchorPath: CGFloat] = [:]
    init() {}
}

/// Native SwiftUI rendering of parsed Markdown elements.
///
/// This view walks `[MarkdownElement]` and produces a pure SwiftUI hierarchy —
/// no WKWebView — satisfying the "pure SwiftUI native preview" requirement.
/// Styling comes from the selected `Theme`.
struct MarkdownView: View, Equatable {

    let elements: [MarkdownElement]
    let theme: Theme
    /// Directory of the document, used to resolve relative image paths.
    var baseURL: URL?
    /// Whether fenced code blocks get syntax highlighting in the preview.
    var highlightsCode: Bool = true
    /// Show a line-number gutter beside code blocks.
    var lineNumbers: Bool = false
    /// Code-block accessory: 0 = none, 1 = language name, 2 = custom.
    var codeBlockAccessory: Int = 1
    /// Code token palette name; empty follows the preview theme.
    var highlightingThemeName: String = ""
    /// Web-rendered blocks (MathJax / Mermaid / Graphviz).
    var rendersMath: Bool = true
    var rendersMermaid: Bool = false
    var rendersGraphviz: Bool = false
    /// Preview scale relative to the editor's base font.
    var zoom: CGFloat = 1
    /// The editor's font family; the preview renders its prose in it.
    var fontName: String = ""
    /// Padding between the pane edges and the rendered content, matching the
    /// editor's insets.
    var horizontalInset: CGFloat = 24
    var verticalInset: CGFloat = 16
    /// Create a missing local file when a link is clicked.
    var createsLinkTargets: Bool = false
    /// Ordered scroll anchors produced by the parser (same order as the
    /// editor's anchors). Each is matched to a rendered node by `path`.
    var anchors: [DocumentAnchor] = []
    var onPreviewAnchors: (([CGFloat]) -> Void)?

    @State private var anchorOffsets = AnchorOffsetStore()

    /// Compares only the inputs that affect rendering. `onPreviewAnchors` is
    /// deliberately excluded: it is a stable callback, and comparing closures
    /// would make every comparison unequal and force a full preview rebuild on
    /// each scroll-driven update (the parent's body re-evaluates when the
    /// `ScrollPosition` binding changes). Combined with `.equatable()` at the
    /// call site, this lets SwiftUI skip re-rendering the element tree when only
    /// the scroll position changed.
    nonisolated static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.elements == rhs.elements
            && lhs.theme == rhs.theme
            && lhs.baseURL == rhs.baseURL
            && lhs.highlightsCode == rhs.highlightsCode
            && lhs.lineNumbers == rhs.lineNumbers
            && lhs.codeBlockAccessory == rhs.codeBlockAccessory
            && lhs.highlightingThemeName == rhs.highlightingThemeName
            && lhs.rendersMath == rhs.rendersMath
            && lhs.rendersMermaid == rhs.rendersMermaid
            && lhs.rendersGraphviz == rhs.rendersGraphviz
            && lhs.zoom == rhs.zoom
            && lhs.fontName == rhs.fontName
            && lhs.horizontalInset == rhs.horizontalInset
            && lhs.verticalInset == rhs.verticalInset
            && lhs.createsLinkTargets == rhs.createsLinkTargets
            && lhs.anchors == rhs.anchors
    }

    private static let contentSpace = "previewContentSpace"

    /// Anchor index for a node path, built from the parser's anchor list.
    private var anchorIndexByPath: [AnchorPath: Int] {
        var map: [AnchorPath: Int] = [:]
        for (index, anchor) in anchors.enumerated() {
            map[anchor.path] = index
        }
        return map
    }

    var body: some View {
        let indexByPath = anchorIndexByPath
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(elements.enumerated()), id: \.offset) { index, element in
                AnyView(renderElement(element, path: [index], indexByPath: indexByPath))
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.vertical, verticalInset)
        .frame(maxWidth: 860, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: Self.contentSpace)
        .background(theme.backgroundColor)
    }

    private func anchorProbe(path: AnchorPath) -> some View {
        GeometryReader { geo in
            Color.clear
                .onAppear { record(path: path, y: geo.frame(in: .named(Self.contentSpace)).minY) }
                .onChange(of: geo.frame(in: .named(Self.contentSpace)).minY) { _, newY in
                    record(path: path, y: newY)
                }
        }
    }

    private func record(path: AnchorPath, y: CGFloat) {
        anchorOffsets.values[path] = y
        reportAnchors()
    }

    /// Reports the anchors only once every anchor has been measured, so the
    /// editor and preview arrays stay index-aligned.
    private func reportAnchors() {
        guard !anchors.isEmpty else { return }
        let ys = anchors.map { anchorOffsets.values[$0.path] }
        guard ys.allSatisfy({ $0 != nil }) else { return }
        onPreviewAnchors?(ys.map { $0 ?? 0 })
    }

    /// Wraps an anchored node with a geometry probe. Nodes the parser did not
    /// anchor are returned unchanged.
    @ViewBuilder
    private func anchored<V: View>(_ view: V, path: AnchorPath, indexByPath: [AnchorPath: Int]) -> some View {
        if indexByPath[path] != nil {
            view.background(anchorProbe(path: path))
        } else {
            view
        }
    }

    /// Whether the preference for a web-rendered block kind is enabled.
    private func isWebBlockEnabled(_ kind: WebBlockView.Kind) -> Bool {
        switch kind {
        case .math, .mathInline: rendersMath
        case .mermaid: rendersMermaid
        case .graphviz: rendersGraphviz
        }
    }

    @ViewBuilder
    private func renderElement(
        _ element: MarkdownElement,
        path: AnchorPath,
        indexByPath: [AnchorPath: Int]
    ) -> some View {
        switch element {
        case .heading(let level, let text):
            anchored(heading(text, level: level), path: path, indexByPath: indexByPath)

        case .paragraph(let inlines):
            anchored(
                ParagraphView(
                    inlines: inlines,
                    theme: theme,
                    baseURL: baseURL,
                    zoom: zoom,
                    fontName: fontName,
                    createsLinkTargets: createsLinkTargets
                )
                .padding(.vertical, 4),
                path: path, indexByPath: indexByPath
            )

        case .codeBlock(let language, let code):
            anchored(codeBlockView(language: language, code: code), path: path, indexByPath: indexByPath)

        case .blockQuote(let children):
            anchored(
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                        AnyView(renderElement(child, path: path + [index], indexByPath: indexByPath))
                    }
                }
                .padding(.leading, 12)
                .overlay(
                    Rectangle()
                        .fill(theme.blockquoteBorderColor)
                        .frame(width: 4),
                    alignment: .leading
                )
                .padding(.vertical, 4),
                path: path, indexByPath: indexByPath
            )

        case .unorderedList(let items):
            anchored(
                listView(items: items, ordered: false, path: path, indexByPath: indexByPath),
                path: path, indexByPath: indexByPath
            )

        case .orderedList(let items):
            anchored(
                listView(items: items, ordered: true, path: path, indexByPath: indexByPath),
                path: path, indexByPath: indexByPath
            )

        case .taskList(let items):
            anchored(
                taskListView(items: items, path: path, indexByPath: indexByPath),
                path: path, indexByPath: indexByPath
            )

        case .table(let table):
            anchored(
                TableView(data: table, theme: theme, zoom: zoom, fontName: fontName).padding(.vertical, 8),
                path: path, indexByPath: indexByPath
            )

        case .tableOfContents(let items):
            anchored(
                TOCView(items: items, theme: theme, zoom: zoom, fontName: fontName).padding(.vertical, 8),
                path: path, indexByPath: indexByPath
            )

        case .footnotes(let items):
            FootnotesView(items: items, theme: theme, zoom: zoom, fontName: fontName)
                .padding(.vertical, 8)

        case .thematicBreak:
            anchored(
                Divider().overlay(theme.dividerColor).padding(.vertical, 12),
                path: path, indexByPath: indexByPath
            )

        case .rawHTML(let html):
            // HTML is not executed; render as source to keep the preview safe.
            Text(html)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(theme.secondaryTextColor)

        case .image(let url, let alt):
            anchored(
                PreviewImageView(url: url, alt: alt, theme: theme, baseURL: baseURL).padding(.vertical, 8),
                path: path, indexByPath: indexByPath
            )

        case .frontMatter(_, let entries):
            FrontMatterView(entries: entries, theme: theme, zoom: zoom)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func codeBlockView(language: String?, code: String) -> some View {
        if let kind = WebBlockView.Kind.from(language: language), isWebBlockEnabled(kind) {
            WebBlockView(kind: kind, code: code, theme: theme)
        } else {
            CodeBlockView(
                language: language,
                code: code,
                theme: theme,
                highlights: highlightsCode,
                lineNumbers: lineNumbers,
                accessory: codeBlockAccessory,
                highlightingThemeName: highlightingThemeName,
                zoom: zoom
            )
        }
    }

    @ViewBuilder
    private func listView(
        items: [ListItem],
        ordered: Bool,
        path: AnchorPath,
        indexByPath: [AnchorPath: Int]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .font(previewTextFont(named: fontName, size: 14, weight: .semibold))
                        .foregroundStyle(theme.secondaryTextColor)
                        .frame(width: ordered ? 22 : 12, alignment: .trailing)
                    AnyView(renderListItem(item, path: path + [index], indexByPath: indexByPath))
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func taskListView(
        items: [ListItem],
        path: AnchorPath,
        indexByPath: [AnchorPath: Int]
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: item.isChecked == true ? "checkmark.square.fill" : "square")
                        .foregroundStyle(theme.taskListColor)
                        .font(.system(size: 14))
                    AnyView(renderListItem(item, path: path + [index], indexByPath: indexByPath))
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func renderListItem(
        _ item: ListItem,
        path: AnchorPath,
        indexByPath: [AnchorPath: Int]
    ) -> some View {
        anchored(
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(item.children.enumerated()), id: \.offset) { index, child in
                    AnyView(renderElement(child, path: path + [index], indexByPath: indexByPath))
                }
            },
            path: path, indexByPath: indexByPath
        )
    }

    private func heading(_ text: String, level: Int) -> some View {
        let baseSize: CGFloat = switch level {
        case 1: 28
        case 2: 24
        case 3: 20
        case 4: 17
        case 5: 15
        default: 14
        }
        let size = baseSize * zoom
        let weight: Font.Weight = level <= 2 ? .bold : .semibold
        return Text(text)
            .font(previewTextFont(named: fontName, size: size, weight: weight))
            .foregroundStyle(theme.headingColor)
            .padding(.top, level == 1 ? 16 : 12)
            .padding(.bottom, 4)
            .overlay(alignment: .bottom) {
                if level == 1 {
                    Rectangle()
                        .fill(theme.headingBorderColor)
                        .frame(height: 1.5)
                        .padding(.top, 4)
                }
            }
    }
}

// MARK: - Paragraph

struct ParagraphView: View {
    let inlines: [InlineElement]
    let theme: Theme
    var baseURL: URL?
    var zoom: CGFloat = 1
    /// The editor's font family; the paragraph renders in it.
    var fontName: String = ""
    var createsLinkTargets = false

    var body: some View {
        InlineRenderer(
            inlines: inlines,
            theme: theme,
            baseURL: baseURL,
            zoom: zoom,
            fontName: fontName,
            createsLinkTargets: createsLinkTargets
        )
        .font(previewTextFont(named: fontName, size: 14 * zoom))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Inline renderer

struct InlineRenderer: View {
    let inlines: [InlineElement]
    let theme: Theme
    var baseURL: URL?
    var zoom: CGFloat = 1
    /// The editor's font family; leaf text renders in it.
    var fontName: String = ""
    var createsLinkTargets = false
    /// Inherited emphasis/strong traits, composed so `***text***` is both.
    var italic = false
    var bold = false
    /// Font size for leaf text; `nil` uses the paragraph default (14 * zoom).
    /// Superscript overrides it. The trait is baked into an explicit `Font`
    /// rather than relying on `View.italic()`/`.bold()` (which do not reliably
    /// reach child `Text` views or survive a container `.font`).
    var fontSize: CGFloat?

    private var resolvedFontSize: CGFloat { fontSize ?? 14 * zoom }

    private func styledText(_ text: String) -> Text {
        var font = previewTextFont(named: fontName, size: resolvedFontSize)
        if bold { font = font.weight(.bold) }
        if italic { font = font.italic() }
        return Text(text).font(font)
    }

    /// Renders a leaf text run. CJK fonts (PingFang) have no italic face, so
    /// `Font.italic()` leaves Chinese/Japanese/Korean upright. For those runs a
    /// synthetic oblique (a horizontal shear) is applied instead, mirroring how
    /// browsers slant CJK for `font-style: italic`.
    @ViewBuilder
    private func inlineText(_ text: String) -> some View {
        if italic, Self.containsCJK(text) {
            Text(text)
                .font(previewTextFont(named: fontName, size: resolvedFontSize, weight: bold ? .bold : .regular))
                .transformEffect(Self.obliqueTransform)
        } else {
            styledText(text)
        }
    }

    /// A ~12° shear whose top leans right (SwiftUI's y axis points down).
    static let obliqueTransform = CGAffineTransform(
        a: 1, b: 0, c: -tan(12 * .pi / 180), d: 1, tx: 0, ty: 0
    )

    /// Whether `text` contains a CJK / kana / Hangul character (which needs a
    /// synthetic italic).
    static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x303F,   // CJK punctuation
                 0x3040...0x30FF,   // Hiragana / Katakana
                 0x3400...0x4DBF,   // CJK Extension A
                 0x4E00...0x9FFF,   // CJK Unified Ideographs
                 0xAC00...0xD7AF,   // Hangul syllables
                 0xF900...0xFAFF,   // CJK Compatibility Ideographs
                 0xFF00...0xFFEF,   // Halfwidth/Fullwidth forms
                 0x20000...0x2FA1F: // CJK Extension B+
                return true
            default:
                return false
            }
        }
    }

    private func child(
        _ children: [InlineElement],
        italic: Bool? = nil,
        bold: Bool? = nil,
        fontSize: CGFloat? = nil
    ) -> InlineRenderer {
        InlineRenderer(
            inlines: children,
            theme: theme,
            baseURL: baseURL,
            zoom: zoom,
            fontName: fontName,
            createsLinkTargets: createsLinkTargets,
            italic: italic ?? self.italic,
            bold: bold ?? self.bold,
            fontSize: fontSize ?? self.fontSize
        )
    }

    var body: some View {
        ForEach(Array(inlines.enumerated()), id: \.offset) { _, inline in
            switch inline {
            case .text(let text):
                inlineText(text)
            case .emphasis(let children):
                child(children, italic: true)
            case .strong(let children):
                child(children, bold: true)
            case .code(let code):
                Text(code)
                    .font(.system(size: 13 * zoom, design: .monospaced))
                    .foregroundStyle(theme.codeTextColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(theme.codeBackgroundColor, in: RoundedRectangle(cornerRadius: 3))
            case .link(let url, let children):
                child(children)
                    .foregroundStyle(theme.linkColor)
                    .underline()
                    .onTapGesture {
                        handleLinkTap(url)
                    }
            case .strikethrough(let children):
                child(children).strikethrough()
            case .image(let url, let alt):
                PreviewImageView(url: url, alt: alt, theme: theme, baseURL: baseURL)
            case .underline(let children):
                child(children).underline()
            case .highlight(let children):
                child(children)
                    .background(theme.linkColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 2))
            case .superscript(let children):
                child(children, fontSize: 10 * zoom)
                    .baselineOffset(5 * zoom)
            case .quote(let children):
                child(children, italic: true)
            case .lineBreak:
                Text("\n")
            case .inlineHTML(let html):
                Text(html)
                    .foregroundStyle(theme.secondaryTextColor)
            }
        }
    }

    /// Opens a link, resolving relative paths against the document and
    /// optionally creating a missing local target.
    private func handleLinkTap(_ urlString: String?) {
        guard let resolved = PreviewLinkResolver.resolve(urlString, baseURL: baseURL) else { return }
        guard resolved.isFileURL else {
            NSWorkspace.shared.open(resolved)
            return
        }
        let target = PreviewLinkResolver.existingTarget(for: resolved)
        if FileManager.default.fileExists(atPath: target.path) {
            NSWorkspace.shared.open(target)
        } else if createsLinkTargets,
                  PreviewLinkResolver.createFileIfNeeded(at: target) {
            NSWorkspace.shared.open(target)
        }
    }
}

// MARK: - Images
/// Renders an image from a remote URL or a local file. Relative paths resolve
/// against the document's directory (the `baseURL`).
struct PreviewImageView: View {
    let url: String?
    let alt: String
    let theme: Theme
    var baseURL: URL?

    /// Decoded local images, keyed by file URL. Re-decoding inside `body`
    /// (which re-evaluates on every preview update, including scroll-driven
    /// ones) allocated a fresh `NSImage` per frame; caching keeps it to once.
    /// `NSCache` is thread-safe, hence `nonisolated(unsafe)`.
    private nonisolated(unsafe) static let imageCache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 64
        return cache
    }()

    private static func cachedImage(at url: URL) -> NSImage? {
        if let cached = imageCache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        imageCache.setObject(image, forKey: url as NSURL)
        return image
    }

    var body: some View {
        if let resolved = Self.resolve(url: url, baseURL: baseURL) {
            if resolved.isFileURL {
                if let image = Self.cachedImage(at: resolved) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    placeholder
                }
            } else {
                AsyncImage(url: resolved) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Text("📷 \(alt)")
            .foregroundStyle(theme.secondaryTextColor)
    }

    /// Absolute URLs pass through; relative paths resolve against `baseURL`.
    static func resolve(url: String?, baseURL: URL?) -> URL? {
        guard let url, !url.isEmpty else { return nil }
        if let absolute = URL(string: url), absolute.scheme != nil {
            return absolute
        }
        guard let baseURL else { return URL(string: url) }
        // Treat the base as a directory even when it lacks a trailing slash,
        // otherwise `URL(string:relativeTo:)` drops the last path component.
        let directory = baseURL.hasDirectoryPath ? baseURL : baseURL.appendingPathComponent("")
        return URL(string: url, relativeTo: directory)?.absoluteURL
    }
}

// MARK: - Code block

struct CodeBlockView: View {
    let language: String?
    let code: String
    let theme: Theme
    var highlights = true
    var lineNumbers = false
    /// 0 = none, 1 = language name, 2 = custom.
    var accessory = 1
    /// Code token palette name; empty follows the preview theme.
    var highlightingThemeName = ""
    var zoom: CGFloat = 1

    private var palette: CodeHighlightTheme.Palette {
        CodeHighlightTheme.palette(
            named: highlightingThemeName,
            fallback: CodeHighlightTheme.Palette(
                keyword: theme.codeKeywordColor,
                string: theme.codeStringColor,
                comment: theme.codeCommentColor,
                number: theme.codeNumberColor
            )
        )
    }

    private var accessoryLabel: String? {
        switch accessory {
        case 1:
            guard let language, !language.isEmpty else { return nil }
            return language
        case 2:
            return "Code"
        default:
            return nil
        }
    }

    private var lineCount: Int {
        max(1, code.components(separatedBy: "\n").count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let accessoryLabel {
                Text(accessoryLabel)
                    .font(.system(size: 11 * zoom, weight: .semibold))
                    .foregroundStyle(theme.secondaryTextColor)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
            }
            HStack(alignment: .top, spacing: 0) {
                if lineNumbers {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(1...lineCount, id: \.self) { number in
                            Text("\(number)")
                                .font(.system(size: 13 * zoom, design: .monospaced))
                                .foregroundStyle(theme.codeCommentColor)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 8)
                    .overlay(alignment: .trailing) {
                        Rectangle()
                            .fill(theme.dividerColor)
                            .frame(width: 1)
                    }
                }
                Text(highlightedCode)
                    .font(.system(size: 13 * zoom, design: .monospaced))
                    .foregroundStyle(theme.codeTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .textSelection(.enabled)
            }
        }
        .background(theme.codeBackgroundColor, in: RoundedRectangle(cornerRadius: 6))
        .padding(.vertical, 6)
    }

    private var highlightedCode: AttributedString {
        guard highlights else { return AttributedString(code) }
        return CodeSyntaxHighlighter.highlight(
            code,
            language: language,
            baseColor: theme.codeTextColor,
            keywordColor: palette.keyword,
            stringColor: palette.string,
            commentColor: palette.comment,
            numberColor: palette.number
        )
    }
}

// MARK: - Table

struct TableView: View {
    let data: TableData
    let theme: Theme
    var zoom: CGFloat = 1
    /// The editor's font family; table text renders in it.
    var fontName: String = ""

    var body: some View {
        Grid(alignment: .leading) {
            GridRow {
                ForEach(Array(data.headers.enumerated()), id: \.offset) { index, header in
                    Text(header)
                        .fontWeight(.semibold)
                        .foregroundStyle(theme.headingColor)
                        .frame(maxWidth: .infinity, alignment: alignment(for: index))
                        .padding(6)
                        .background(theme.tableHeaderBackground)
                }
            }
            Divider().overlay(theme.tableBorderColor)
            ForEach(Array(data.rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        Text(cell)
                            .foregroundStyle(theme.textColor)
                            .frame(maxWidth: .infinity, alignment: alignment(for: index))
                            .padding(6)
                    }
                }
                if rowIndex < data.rows.count - 1 {
                    Divider().overlay(theme.tableBorderColor)
                }
            }
        }
        .font(previewTextFont(named: fontName, size: 14 * zoom))
        .padding(8)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(theme.tableBorderColor, lineWidth: 1)
        )
    }

    /// Maps the parsed column alignment (`|:---:|`) onto a frame alignment.
    private func alignment(for column: Int) -> Alignment {
        guard column < data.alignments.count else { return .leading }
        switch data.alignments[column] {
        case .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}

// MARK: - Table of contents

struct TOCView: View {
    let items: [TOCItem]
    let theme: Theme
    var zoom: CGFloat = 1
    /// The editor's font family; the entries render in it.
    var fontName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                Text(item.text)
                    .font(previewTextFont(
                        named: fontName,
                        size: 14 * zoom,
                        weight: item.level <= 1 ? .semibold : .regular
                    ))
                    .foregroundStyle(item.level <= 1 ? theme.headingColor : theme.textColor)
                    .padding(.leading, CGFloat(max(0, item.level - 1)) * 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(theme.codeBackgroundColor.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}

// MARK: - Footnotes

struct FootnotesView: View {
    let items: [FootnoteItem]
    let theme: Theme
    var zoom: CGFloat = 1
    /// The editor's font family; footnote text renders in it.
    var fontName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider().overlay(theme.dividerColor)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    Text("\(index + 1).")
                        .foregroundStyle(theme.secondaryTextColor)
                    Text(item.text)
                        .foregroundStyle(theme.textColor)
                }
                .font(previewTextFont(named: fontName, size: 13 * zoom))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Front matter

/// Renders YAML front matter as a key/value table (nested mappings/sequences
/// become nested tables).
struct FrontMatterView: View {
    let entries: [FrontMatterEntry]
    let theme: Theme
    var zoom: CGFloat = 1

    var body: some View {
        if !entries.isEmpty {
            Grid(alignment: .leading) {
                GridRow {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        Text(entry.key)
                            .fontWeight(.semibold)
                            .foregroundStyle(theme.headingColor)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                            .background(theme.tableHeaderBackground)
                    }
                }
                GridRow {
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                        FrontMatterValueView(value: entry.value, theme: theme, zoom: zoom)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                }
            }
            .font(.system(size: 13 * zoom))
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(theme.tableBorderColor, lineWidth: 1)
            )
        }
    }
}

/// Renders a single front-matter value, recursing into nested mappings and
/// sequences.
struct FrontMatterValueView: View {
    let value: FrontMatterValue
    let theme: Theme
    var zoom: CGFloat = 1

    var body: some View {
        switch value {
        case .scalar(let text):
            Text(text)
                .foregroundStyle(theme.textColor)
        case .map(let entries):
            FrontMatterView(entries: entries, theme: theme, zoom: zoom)
        case .list(let items):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(theme.secondaryTextColor)
                        FrontMatterValueView(value: item, theme: theme, zoom: zoom)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct Preview: View {
    let elements: [MarkdownElement]

    var body: some View {
        MarkdownView(elements: elements, theme: .clearness)
    }
}

// MARK: - Text font

/// Maps the preview's font family onto the SwiftUI preview's text font: the
/// chosen family when it resolves, otherwise the system font — the proportional
/// face the bundled preview stylesheets use. `Font.custom` silently falls back
/// to the system font for a name it cannot resolve, so the family is resolved
/// up front (the system font has no reachable name and therefore keeps the
/// preview's system look).
///
/// Fixed-width runs (code, front matter) keep their monospaced design and do
/// not go through here.
@MainActor
private func previewTextFont(named name: String, size: CGFloat, weight: Font.Weight = .regular) -> Font {
    guard FontResolver.font(named: name, size: size) != nil else {
        return .system(size: size, weight: weight)
    }
    return .custom(name, size: size).weight(weight)
}