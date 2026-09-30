import AppKit

/// The HTML for one preview math block, typeset by the bundled MathJax
/// distribution (the same resource `WebBlockView` and the HTML export use, so
/// the preview works offline).
///
/// The page is a single block: transparent, no scrollbars, and it reports its
/// rendered height back through a script message (the mechanism
/// `TablePreviewHTML` uses for tables) so the surrounding text can reserve the
/// right amount of space.
@MainActor
public enum MathPreviewHTML {

    /// The attachment the preview's text layout reserves for a math block.
    ///
    /// The text surface stores math as one placeholder character (MathJax draws
    /// the formula on top of it), so the copy path needs a way to get the TeX
    /// back out of a selection: this subclass carries it.
    @MainActor
    public final class Attachment: NSTextAttachment {
        public let tex: String
        /// Display math (`\[…\]`) or inline math (`\(…\)`).
        public let isDisplay: Bool

        public init(tex: String, isDisplay: Bool, reservedHeight: CGFloat) {
            self.tex = tex
            self.isDisplay = isDisplay
            super.init(data: nil, ofType: nil)
            image = MathPreviewHTML.placeholderImage
            bounds = NSRect(x: 0, y: 0, width: 1, height: reservedHeight)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        /// The formula as the TeX source the user wrote, so copying a selection
        /// yields the math text instead of a placeholder character.
        public var plainText: String { MathPreviewHTML.delimited(tex: tex, isDisplay: isDisplay) }
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

    /// The TeX wrapped in the delimiters MathJax reads back, escaped for HTML.
    public static func delimited(tex: String, isDisplay: Bool) -> String {
        let escaped = escapeHTML(tex)
        return isDisplay ? "\\[\(escaped)\\]" : "\\(\(escaped)\\)"
    }

    /// A standalone page typesetting `tex`, sized to report its own height.
    public static func page(tex: String, isDisplay: Bool, theme: Theme, zoom: CGFloat) -> String {
        let markup = delimited(tex: tex, isDisplay: isDisplay)
        let loader: String
        if let js = ResourceLoader.text(named: "mathjax-tex-svg.js", in: Constants.extensionsDirectoryName) {
            loader = "<script>\(js)</script>"
        } else {
            loader = "<script src=\"https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js\"></script>"
        }
        let alignment = isDisplay ? "text-align: center;" : "text-align: left;"
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          html, body { margin: 0; padding: 0; background: transparent; overflow: hidden; }
          body {
            color: \(theme.textColor.hex);
            font-size: \(14 * zoom)px;
            \(alignment)
          }
          #math { display: inline-block; }
          svg { max-width: 100%; height: auto; }
        </style>
        </head>
        <body>
        <div id="math">\(markup)</div>
        <script>
        window.MathJax = { tex: { inlineMath: [['$','$']] }, svg: { fontCache: 'global' } };
        </script>
        \(loader)
        <script>
        function reportHeight() {
          var el = document.getElementById('math');
          var h = el ? el.getBoundingClientRect().height : 0;
          window.webkit.messageHandlers.height.postMessage(h + 2);
        }
        window.addEventListener('load', reportHeight);
        if (window.MathJax && window.MathJax.startup && window.MathJax.startup.promise) {
          MathJax.startup.promise.then(function() {
            reportHeight();
            setTimeout(reportHeight, 100);
          });
        }
        setTimeout(reportHeight, 400);
        setTimeout(reportHeight, 1500);
        </script>
        </body>
        </html>
        """
    }

    /// The height the block is given before MathJax has measured it: one line
    /// box for inline math, two for a display formula (which MathJax centers on
    /// its own line). The real height arrives through the script message and the
    /// text layout is then corrected.
    public static func estimatedHeight(isDisplay: Bool, zoom: CGFloat) -> CGFloat {
        let line = ceil((14 * zoom) * 1.5) + 2
        return isDisplay ? line * 2 : line
    }
}
