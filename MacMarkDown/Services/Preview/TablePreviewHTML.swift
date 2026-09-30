import AppKit

/// The HTML for one preview table, laid out by WebKit the way the original
/// editor lays out its whole preview: the bundled stylesheet's
/// `table { border-collapse }` + `td, th { border; padding }` rules decide the
/// borders, the cell padding and the column widths, so a preview table looks
/// like the exported HTML instead of a hand-drawn approximation.
///
/// The page is a single block: transparent, no scrollbars, and it reports its
/// content height back through a script message (the same mechanism
/// `WebBlockView` uses for math and diagrams) so the surrounding text can
/// reserve the right amount of space.
@MainActor
public enum TablePreviewHTML {

    /// The attachment the preview's text layout reserves for a table.
    ///
    /// The text surface stores tables as one placeholder character (the table
    /// itself is drawn by WebKit on top of it), so the copy path needs a way to
    /// get the table's content back out of a selection: this subclass carries it.
    @MainActor
    public final class Attachment: NSTextAttachment {
        public let table: TableData

        public init(table: TableData, reservedHeight: CGFloat) {
            self.table = table
            super.init(data: nil, ofType: nil)
            image = TablePreviewHTML.placeholderImage
            bounds = NSRect(x: 0, y: 0, width: 1, height: reservedHeight)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// The table as tab-separated rows, the form the preview's old text table
        /// had, so copying a selection yields readable cells.
        public var plainText: String {
            let rows = [table.headers] + table.rows
            return rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
        }

        /// The table as the same `<table>` markup the HTML export writes.
        public var html: String { TablePreviewHTML.tableMarkup(table) }
    }

    /// A fully transparent 1×1 image: the placeholder reserves its space through
    /// the attachment's `bounds` and draws nothing itself.
    private static let placeholderImage: NSImage = {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.addRepresentation(rep)
        return image
    }()

    /// The `<table>` markup for one parsed table. Shared with the HTML export
    /// (`Renderer`) so the two can never drift apart.
    public static func tableMarkup(_ table: TableData) -> String {
        var html = "<table>\n<thead><tr>"
        for (index, header) in table.headers.enumerated() {
            html += "<th\(alignmentAttribute(for: index, in: table))>\(escapeHTML(header))</th>"
        }
        html += "</tr></thead>\n<tbody>"
        for row in table.rows {
            html += "<tr>"
            for (index, cell) in row.enumerated() {
                html += "<td\(alignmentAttribute(for: index, in: table))>\(escapeHTML(cell))</td>"
            }
            html += "</tr>\n"
        }
        html += "</tbody></table>\n"
        return html
    }

    /// A standalone page hosting `markup`, styled by the theme's stylesheet
    /// (the bundled CSS when the theme ships one, like the export).
    public static func page(markup: String, theme: Theme, zoom: CGFloat) -> String {
        let stylesheet = bundledStylesheet(for: theme) ?? ""
        let fontSize = 14 * zoom
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>\(stylesheet)</style>
        <style>
          /* The page is embedded in the preview, so the document chrome from
             the stylesheet (margins, background, page padding) is dropped and
             only the table itself is drawn. */
          html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
          body { font-size: \(fontSize)px; color: \(theme.textColor.hex); }
          table { width: 100%; margin: 0; }
        </style>
        </head>
        <body>
        <div id="content">\(markup)</div>
        <script>
        function reportHeight() {
          var h = document.getElementById('content').getBoundingClientRect().height;
          window.webkit.messageHandlers.height.postMessage(h);
        }
        window.addEventListener('load', reportHeight);
        if (window.ResizeObserver) { new ResizeObserver(reportHeight).observe(document.body); }
        setTimeout(reportHeight, 200);
        </script>
        </body>
        </html>
        """
    }

    /// The height the block is given before WebKit has measured it: a rough
    /// `rows × line box` estimate. The real height arrives through the script
    /// message and the text layout is then corrected.
    public static func estimatedHeight(for table: TableData, zoom: CGFloat) -> CGFloat {
        let line = ceil((14 * zoom) * 1.4) + 2 * 4 + 1  // line box + cell padding + border
        let rows = max(1, table.rows.count) + 1         // + header
        return CGFloat(rows) * line + 8
    }

    private static func alignmentAttribute(for column: Int, in table: TableData) -> String {
        guard column < table.alignments.count else { return "" }
        switch table.alignments[column] {
        case .left: return " style=\"text-align: left\""
        case .center: return " style=\"text-align: center\""
        case .right: return " style=\"text-align: right\""
        }
    }

    /// The bundled stylesheet for the theme, by display name then by id, the
    /// same lookup the HTML export performs.
    private static func bundledStylesheet(for theme: Theme) -> String? {
        for candidate in [theme.displayName, theme.name] {
            if let css = ResourceLoader.styleSheet(forTheme: candidate) { return css }
        }
        return nil
    }
}
