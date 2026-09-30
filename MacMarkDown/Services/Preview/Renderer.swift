import Foundation
import SwiftUI

/// Generates a complete HTML document from parsed `MarkdownElement`s.
/// Used exclusively for HTML export (Copy HTML, Export to File, Print).
/// The live native preview does **not** use this — it renders SwiftUI views.
///
/// Output structure follows the bundled HTML template:
/// `<!DOCTYPE html><head>…styleTags…</head><body>{body}</body></html>`.
@MainActor
public final class Renderer: @unchecked Sendable {

    private let parser: MarkdownParser
    private let theme: Theme
    private let options: MarkdownParseOptions

    public init(
        parser: MarkdownParser = MarkdownParser(),
        theme: Theme = .clearness,
        options: MarkdownParseOptions = MarkdownParseOptions()
    ) {
        self.parser = parser
        self.theme = theme
        self.options = options
    }

    // MARK: - Public API

    /// Render a Markdown string to a complete HTML document.
    public func renderToHTML(
        _ text: String,
        title: String = "",
        inlineStyles: Bool = true
    ) -> String {
        let elements = parser.parse(text, options: options)
        headingIndex = 0
        containsMath = false
        containsMermaid = false
        containsGraphviz = false
        let body = renderBody(elements)
        return buildDocument(title: title, body: body, inlineStyles: inlineStyles)
    }

    /// Render to a bare HTML fragment (no `<html>/<head>/<body>` wrapper).
    public func renderFragment(_ text: String) -> String {
        let elements = parser.parse(text, options: options)
        headingIndex = 0
        return renderBody(elements)
    }

    // MARK: - Body rendering

    private func renderBody(_ elements: [MarkdownElement]) -> String {
        var html = ""
        for element in elements {
            html += renderElement(element)
        }
        return html
    }

    /// Running heading index used for `toc_N` anchors; reset per document.
    private var headingIndex = 0

    /// Web-rendered block kinds present in the document; drives the scripts
    /// injected into exported HTML.
    private var containsMath = false
    private var containsMermaid = false
    private var containsGraphviz = false

    private func renderElement(_ element: MarkdownElement) -> String {
        switch element {
        case .heading(let level, let text):
            let anchor = "toc_\(headingIndex)"
            headingIndex += 1
            return "<h\(level) id=\"\(anchor)\">\(escapeHTML(text))</h\(level)>\n"

        case .paragraph(let inlines):
            let content = renderInlines(inlines)
            return "<p>\(content)</p>\n"

        case .codeBlock(let language, let code):
            let lower = language?.lowercased()
            let escaped = escapeHTML(code)
            if lower == "mermaid" {
                containsMermaid = true
                return "<pre class=\"mermaid\">\(escaped)</pre>\n"
            }
            if let lower, ["dot", "graphviz", "circo", "fdp", "neato", "osage", "twopi"].contains(lower) {
                containsGraphviz = true
                return "<div class=\"graphviz\" data-engine=\"\(lower)\">\(escaped)</div>\n"
            }
            if lower == "math-inline" {
                containsMath = true
                let trimmed = escapeHTML(code.trimmingCharacters(in: .whitespacesAndNewlines))
                return "<span class=\"math-inline\">\\(\(trimmed)\\)</span>\n"
            }
            if let lower, ["math", "latex", "tex"].contains(lower) {
                containsMath = true
                // swift-markdown keeps the fence's trailing newline; MathJax
                // reads the TeX either way, but the export should carry just the
                // formula.
                let tex = escapeHTML(code.trimmingCharacters(in: .whitespacesAndNewlines))
                return "<div class=\"math-block\">\\[\(tex)\\]</div>\n"
            }
            return renderCodeBlock(language: language, code: code)

        case .blockQuote(let children):
            let inner = renderBody(children)
            return "<blockquote>\n\(inner)</blockquote>\n"

        case .unorderedList(let items):
            let lis = items.map { item -> String in
                let content = renderBody(item.children)
                return "  <li>\(content)</li>\n"
            }.joined()
            return "<ul>\n\(lis)</ul>\n"

        case .orderedList(let items):
            let lis = items.map { item -> String in
                let content = renderBody(item.children)
                return "  <li>\(content)</li>\n"
            }.joined()
            return "<ol>\n\(lis)</ol>\n"

        case .taskList(let items):
            let lis = items.map { item -> String in
                let checkbox = item.isChecked == true
                    ? "<input type=\"checkbox\" checked disabled>"
                    : item.isChecked == false
                        ? "<input type=\"checkbox\" disabled>"
                        : ""
                let content = renderBody(item.children)
                return "  <li>\(checkbox) \(content)</li>\n"
            }.joined()
            return "<ul class=\"task-list\">\n\(lis)</ul>\n"

        case .table(let table):
            return renderTable(table)

        case .tableOfContents(let items):
            return renderTOC(items)

        case .footnotes(let items):
            return renderFootnotes(items)

        case .thematicBreak:
            return "<hr>\n"

        case .rawHTML(let html):
            return "\(html)\n"

        case .image(let url, let alt):
            let urlStr = url ?? ""
            return "<img src=\"\(escapeHTML(urlStr))\" alt=\"\(escapeHTML(alt))\">\n"

        case .frontMatter(_, let entries):
            return renderFrontMatter(entries)
        }
    }

    /// Renders a fenced code block, optionally with a language/custom
    /// accessory header and a line-number gutter.
    private func renderCodeBlock(language: String?, code: String) -> String {
        let langAttr = language.map { " class=\"language-\(escapeHTML($0))\"" } ?? ""
        let body = highlightedCodeHTML(code, language: language)

        var accessory = ""
        switch options.codeBlockAccessory {
        case 1 where !(language ?? "").isEmpty:
            accessory = "<div class=\"code-language\">\(escapeHTML(language ?? ""))</div>\n"
        case 2:
            accessory = "<div class=\"code-language\">Code</div>\n"
        default:
            break
        }

        let codeTag = "<pre><code\(langAttr)>\(body)</code></pre>"
        if options.enableLineNumbers {
            let lineCount = max(1, code.components(separatedBy: "\n").count)
            let numbers = (1...lineCount).map(String.init).joined(separator: "\n")
            return "<div class=\"code-block\">\n\(accessory)"
                + "<div class=\"line-numbers\">\(numbers)</div>\n\(codeTag)\n</div>\n"
        }
        return "\(accessory)\(codeTag)\n"
    }

    /// Renders YAML front matter as a key/value table (keys as headers, values
    /// as one row, nested mappings/sequences as nested tables).
    private func renderFrontMatter(_ entries: [FrontMatterEntry]) -> String {
        guard !entries.isEmpty else { return "" }
        return renderFrontMatterMap(entries, className: "front-matter")
    }

    private func renderFrontMatterMap(_ entries: [FrontMatterEntry], className: String) -> String {
        var html = "<table class=\"\(className)\">\n<thead><tr>"
        for entry in entries {
            html += "<th>\(escapeHTML(entry.key))</th>"
        }
        html += "</tr></thead>\n<tbody><tr>"
        for entry in entries {
            html += "<td>\(renderFrontMatterValue(entry.value))</td>"
        }
        html += "</tr></tbody></table>\n"
        return html
    }

    private func renderFrontMatterValue(_ value: FrontMatterValue) -> String {
        switch value {
        case .scalar(let text):
            return escapeHTML(text)
        case .map(let entries):
            return renderFrontMatterMap(entries, className: "front-matter-nested")
        case .list(let items):
            var html = "<table class=\"front-matter-nested\">\n<tbody><tr>"
            for item in items {
                html += "<td>\(renderFrontMatterValue(item))</td>"
            }
            html += "</tr></tbody></table>\n"
            return html
        }
    }

    /// The table markup is shared with the live preview's WebKit table block,
    /// so a preview table and an exported table can never differ.
    private func renderTable(_ table: TableData) -> String {
        TablePreviewHTML.tableMarkup(table)
    }

    // MARK: - Inline rendering

    private func renderInlines(_ inlines: [InlineElement]) -> String {
        inlines.map { renderInline($0) }.joined()
    }

    private func renderInline(_ inline: InlineElement) -> String {
        switch inline {
        case .text(let text):
            return escapeHTML(text)
        case .emphasis(let children):
            return "<em>\(renderInlines(children))</em>"
        case .strong(let children):
            return "<strong>\(renderInlines(children))</strong>"
        case .code(let code):
            return "<code>\(escapeHTML(code))</code>"
        case .link(let url, let children):
            let urlStr = url ?? ""
            return "<a href=\"\(escapeHTML(urlStr))\">\(renderInlines(children))</a>"
        case .strikethrough(let children):
            return "<del>\(renderInlines(children))</del>"
        case .image(let url, let alt):
            let urlStr = url ?? ""
            return "<img src=\"\(escapeHTML(urlStr))\" alt=\"\(escapeHTML(alt))\">"
        case .underline(let children):
            return "<u>\(renderInlines(children))</u>"
        case .highlight(let children):
            return "<mark>\(renderInlines(children))</mark>"
        case .superscript(let children):
            return "<sup>\(renderInlines(children))</sup>"
        case .quote(let children):
            return "<q>\(renderInlines(children))</q>"
        case .lineBreak:
            return "<br>\n"
        case .inlineHTML(let html):
            return html
        }
    }

    /// Renders the footnote section as an ordered list with anchors.
    private func renderFootnotes(_ items: [FootnoteItem]) -> String {
        guard !items.isEmpty else { return "" }
        var html = "<hr class=\"footnotes-sep\">\n<ol class=\"footnotes\">\n"
        for item in items {
            html += "  <li id=\"fn-\(escapeHTML(item.id))\">\(escapeHTML(item.text))</li>\n"
        }
        html += "</ol>\n"
        return html
    }

    /// Renders a flat `<ul class="toc">` with heading levels as classes.
    private func renderTOC(_ items: [TOCItem]) -> String {
        guard !items.isEmpty else { return "" }
        var html = "<ul class=\"toc\">\n"
        for (index, item) in items.enumerated() {
            html += "  <li class=\"toc-level-\(item.level)\"><a href=\"#toc_\(index)\">\(escapeHTML(item.text))</a></li>\n"
        }
        html += "</ul>\n"
        return html
    }

    // MARK: - Document wrapper

    private func buildDocument(title: String, body: String, inlineStyles: Bool) -> String {
        let titleTag = title.isEmpty ? "" : "<title>\(escapeHTML(title))</title>\n"
        let styleCSS = inlineStyles ? stylesheet() : ""
        let highlightCSS = codeHighlightCSS()
        let scripts = webBlockScripts()

        if let template = ResourceLoader.template(named: options.templateName) {
            return template
                .replacingOccurrences(of: "{{{titleTag}}}", with: titleTag)
                .replacingOccurrences(of: "{{{styleTags}}}", with: styleCSS)
                .replacingOccurrences(of: "{{{codeHighlightCSS}}}", with: highlightCSS)
                .replacingOccurrences(of: "{{{body}}}", with: body)
                .replacingOccurrences(of: "{{{scriptTags}}}", with: scripts)
        }

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        \(titleTag)<style>\(styleCSS)</style>
        \(highlightCSS)
        </head>
        <body>\(body)\(scripts)</body>
        </html>
        """
    }

    // MARK: - Web-rendered blocks in exported HTML

    /// Scripts for Mermaid/Graphviz/MathJax blocks, inlined from the bundled
    /// resources where available (Mermaid/Viz) so exports work offline.
    private func webBlockScripts() -> String {
        var scripts = ""
        if containsMermaid {
            scripts += Self.scriptTag(named: "mermaid.min.js", cdn: "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js")
            scripts += """
            <script>if (window.mermaid) { mermaid.initialize({ startOnLoad: true }); }</script>

            """
        }
        if containsGraphviz {
            scripts += Self.scriptTag(named: "viz.js", cdn: "https://cdn.jsdelivr.net/npm/@viz-js/viz@3/lib/viz-standalone.js")
            scripts += """
            <script>
            document.querySelectorAll('.graphviz').forEach(function(el) {
              Viz.instance().then(function(viz) {
                el.innerHTML = viz.renderSVGElement(el.textContent).outerHTML;
              });
            });
            </script>

            """
        }
        if containsMath {
            scripts += """
            <script>
            window.MathJax = { tex: { inlineMath: [['$','$']] }, svg: { fontCache: 'global' } };
            </script>
            \(Self.scriptTag(named: "mathjax-tex-svg.js", cdn: "https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js"))

            """
        }
        return scripts
    }

    private static func scriptTag(named name: String, cdn: String) -> String {
        if let js = ResourceLoader.text(named: name, in: Constants.extensionsDirectoryName) {
            return "<script>\(js)</script>\n"
        }
        return "<script src=\"\(cdn)\"></script>\n"
    }

    // MARK: - Code highlighting for HTML

    /// Wraps tokens from `CodeSyntaxHighlighter` in spans; the colors come
    /// from `codeHighlightCSS()`.
    private func highlightedCodeHTML(_ code: String, language: String?) -> String {
        guard options.enableSyntaxHighlighting else { return escapeHTML(code) }
        let tokens = CodeSyntaxHighlighter.tokenize(code, language: language)
        guard !tokens.isEmpty else { return escapeHTML(code) }
        let ns = code as NSString
        var html = ""
        var cursor = 0
        for token in tokens {
            guard token.range.location >= cursor else { continue }
            if token.range.location > cursor {
                html += escapeHTML(ns.substring(with: NSRange(location: cursor, length: token.range.location - cursor)))
            }
            let tokenText = escapeHTML(ns.substring(with: token.range))
            html += "<span class=\"tok-\(token.kind)\">\(tokenText)</span>"
            cursor = NSMaxRange(token.range)
        }
        if cursor < ns.length {
            html += escapeHTML(ns.substring(from: cursor))
        }
        return html
    }

    /// CSS for the highlighted token classes and the code-block structure
    /// (accessory header and line-number gutter). Structural rules are always
    /// emitted; token colors only when highlighting is enabled.
    private func codeHighlightCSS() -> String {
        let palette = CodeHighlightTheme.palette(
            named: options.highlightingThemeName,
            fallback: CodeHighlightTheme.Palette(
                keyword: theme.codeKeywordColor,
                string: theme.codeStringColor,
                comment: theme.codeCommentColor,
                number: theme.codeNumberColor
            )
        )
        var css = """
        .code-block { display: flex; align-items: stretch; margin: 1em 0; }
        .code-block .line-numbers {
            white-space: pre; text-align: right; padding: 0.8em 0.6em;
            font-family: "SF Mono", Menlo, Monaco, monospace; font-size: 0.9em;
            color: \(theme.codeCommentColor.hex); background: \(theme.codeBackgroundColor.hex);
            border-right: 1px solid \(theme.dividerColor.hex); border-radius: 4px 0 0 4px;
            user-select: none;
        }
        .code-block pre { margin: 0; border-radius: 0 4px 4px 0; flex: 1; }
        .code-language {
            font: 0.8em/1.4 -apple-system, sans-serif; color: \(theme.codeCommentColor.hex);
            background: \(theme.codeBackgroundColor.hex); padding: 0.2em 0.6em;
            border-radius: 4px 4px 0 0; display: inline-block;
        }
        """
        if options.enableSyntaxHighlighting {
            css += """
            .tok-keyword { color: \(palette.keyword.hex); }
            .tok-string { color: \(palette.string.hex); }
            .tok-comment { color: \(palette.comment.hex); font-style: italic; }
            .tok-number { color: \(palette.number.hex); }
            """
        }
        return "<style>\n\(css)</style>"
    }

    /// The bundled stylesheet for the theme when one ships with the
    /// app; otherwise the generated CSS keeps export self-contained.
    private func stylesheet() -> String {
        let candidates = [theme.displayName, theme.name]
        for candidate in candidates {
            if let css = ResourceLoader.styleSheet(forTheme: candidate) {
                return css
            }
        }
        return inlineCSS()
    }

    private func inlineCSS() -> String {
        """
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font: 14px/1.5 -apple-system, BlinkMacSystemFont, "PingFang SC", "Segoe UI", Helvetica, Arial, sans-serif;
            color: \(theme.textColor.hex);
            background-color: \(theme.backgroundColor.hex);
            padding: 1em 2em;
            max-width: 860px;
            margin: 0 auto;
        }
        h1, h2, h3, h4, h5, h6 { color: \(theme.headingColor.hex); margin: 1.2em 0 0.6em; }
        h1 { font-size: 2em; border-bottom: 2px solid \(theme.headingBorderColor.hex); padding-bottom: 0.3em; }
        h2 { font-size: 1.5em; }
        h3 { font-size: 1.25em; }
        p { margin: 0.8em 0; line-height: 1.6; }
        a { color: \(theme.linkColor.hex); text-decoration: none; }
        a:hover { text-decoration: underline; }
        code { font-family: "SF Mono", Menlo, Monaco, monospace; font-size: 0.9em;
               background: \(theme.codeBackgroundColor.hex); color: \(theme.codeTextColor.hex);
               padding: 0.15em 0.3em; border-radius: 3px; }
        pre { margin: 1em 0; padding: 0.8em; overflow-x: auto; border-radius: 4px;
              background: \(theme.codeBackgroundColor.hex); }
        pre code { background: none; padding: 0; }
        blockquote { border-left: 4px solid \(theme.blockquoteBorderColor.hex);
                     padding: 0.4em 1em; margin: 1em 0; color: \(theme.blockquoteColor.hex); }
        table { border-collapse: collapse; margin: 1em 0; width: 100%; }
        th, td { padding: 0.4em 0.8em; border: 1px solid \(theme.tableBorderColor.hex); }
        th { background: \(theme.tableHeaderBackground.hex); }
        hr { border: none; border-top: 1px solid \(theme.dividerColor.hex); margin: 1.5em 0; }
        img { max-width: 100%; }
        ul.task-list { list-style: none; padding-left: 0; }
        ul.task-list li { padding-left: 1.5em; }
        """
    }
}

// MARK: - Color helper

extension Color {
    var hex: String {
        guard let components = self.cgColor?.components, components.count >= 3 else {
            return "#000000"
        }
        let r = Int(components[0] * 255)
        let g = Int(components[1] * 255)
        let b = Int(components[2] * 255)
        return String(format: "#%02x%02x%02x", r, g, b)
    }
}

// MARK: - HTML escape

func escapeHTML(_ text: String) -> String {
    text
        .replacingOccurrences(of: "&", with: "&amp;")
        .replacingOccurrences(of: "<", with: "&lt;")
        .replacingOccurrences(of: ">", with: "&gt;")
        .replacingOccurrences(of: "\"", with: "&quot;")
        .replacingOccurrences(of: "'", with: "&#39;")
}