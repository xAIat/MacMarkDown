import SwiftUI
import WebKit

/// Renders one math/diagram code block in a `WKWebView` (MathJax, Mermaid,
/// Viz.js). The preview is otherwise native SwiftUI; these three renderers are
/// inherently web-based, so they are isolated in a tiny per-block web view.
///
/// The page reports its rendered height back through a script message so the
/// SwiftUI layout can size the block exactly.
struct WebBlockView: View {

    enum Kind {
        case math
        /// Inline `$…$` math rendered in the same web pipeline.
        case mathInline
        case mermaid
        case graphviz
    }

    let kind: Kind
    let code: String
    let theme: Theme

    @State private var height: CGFloat = 40

    var body: some View {
        WebBlockRepresentable(kind: kind, code: code, theme: theme, height: $height)
            .frame(height: height)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }
}

/// The `WKWebView` bridge; the owner view supplies the height binding so the
/// layout tracks the rendered content.
private struct WebBlockRepresentable: NSViewRepresentable {

    let kind: WebBlockView.Kind
    let code: String
    let theme: Theme
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "height")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(kind: kind, code: code, theme: theme, into: webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedCode != code || context.coordinator.loadedKind != kind else {
            return
        }
        context.coordinator.load(kind: kind, code: code, theme: theme, into: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        private let height: Binding<CGFloat>
        var loadedCode: String?
        var loadedKind: WebBlockView.Kind?

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func load(kind: WebBlockView.Kind, code: String, theme: Theme, into webView: WKWebView) {
            loadedCode = code
            loadedKind = kind
            webView.loadHTMLString(Self.html(kind: kind, code: code, theme: theme), baseURL: nil)
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            // WebKit delivers script messages on the main thread; read the
            // main-actor-isolated `body` under that assumption.
            MainActor.assumeIsolated {
                guard let value = message.body as? Double else { return }
                height.wrappedValue = max(40, CGFloat(value))
            }
        }

        // MARK: HTML

        private static func html(kind: WebBlockView.Kind, code: String, theme: Theme) -> String {
            let escaped = escapeHTML(code)
            let foreground = theme.textColor.hex
            let body = bodyContent(kind: kind, escapedCode: escaped)
            return """
            <!DOCTYPE html>
            <html>
            <head>
            <meta charset="utf-8">
            <style>
              html, body { margin: 0; padding: 0; background: transparent; }
              body { font: 14px -apple-system, Helvetica, sans-serif; color: \(foreground); }
              #content { padding: 4px 0; }
              svg { max-width: 100%; height: auto; }
            </style>
            </head>
            <body>
            <div id="content">\(body)</div>
            <script>
            function reportHeight() {
              var h = document.getElementById('content').getBoundingClientRect().height + 12;
              window.webkit.messageHandlers.height.postMessage(h);
            }
            window.addEventListener('load', reportHeight);
            setTimeout(reportHeight, 300);
            setTimeout(reportHeight, 1200);
            </script>
            </body>
            </html>
            """
        }

        private static func bodyContent(kind: WebBlockView.Kind, escapedCode: String) -> String {
            switch kind {
            case .math, .mathInline:
                // Prefer the bundled MathJax 3 distribution (works offline);
                // fall back to the CDN when the resource is unavailable.
                let delimited = kind == .math ? "\\[\(escapedCode)\\]" : "\\(\(escapedCode)\\)"
                let loader = bundledScript(
                    named: "mathjax-tex-svg.js",
                    cdn: "https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js"
                )
                return """
                <div id="math">\(delimited)</div>
                <script>
                window.MathJax = { tex: { inlineMath: [['$','$']] }, svg: { fontCache: 'global' } };
                </script>
                \(loader)
                """
            case .mermaid:
                return """
                <pre class="mermaid">\(escapedCode)</pre>
                \(bundledScript(named: "mermaid.min.js", cdn: "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"))
                <script>
                if (window.mermaid) { mermaid.initialize({ startOnLoad: true }); }
                </script>
                """
            case .graphviz:
                return """
                <div id="graph"></div>
                \(bundledScript(named: "viz.js", cdn: "https://cdn.jsdelivr.net/npm/@viz-js/viz@3/lib/viz-standalone.js"))
                <script>
                if (window.Viz) {
                  Viz.instance().then(function(viz) {
                    document.getElementById('graph').innerHTML =
                      viz.renderSVGElement(\(jsStringLiteral(escapedCode))).outerHTML;
                  });
                }
                </script>
                """
            }
        }

        /// Inlines a bundled script when present, otherwise falls back to the
        /// CDN so the block still renders on machines without the resource.
        private static func bundledScript(named name: String, cdn: String) -> String {
            if let js = ResourceLoader.text(named: name, in: Constants.extensionsDirectoryName) {
                return "<script>\(js)</script>"
            }
            return "<script src=\"\(cdn)\"></script>"
        }

        private static func jsStringLiteral(_ value: String) -> String {
            let data = try? JSONSerialization.data(withJSONObject: [value], options: [])
            guard let data, let array = String(data: data, encoding: .utf8) else { return "\"\"" }
            return String(array.dropFirst().dropLast()) // strip the array brackets
        }
    }
}

// MARK: - Language mapping

extension WebBlockView.Kind {
    /// Maps a fenced-code language to a web renderer, or `nil` when the block
    /// should stay a plain code block.
    static func from(language: String?) -> WebBlockView.Kind? {
        guard let language = language?.lowercased() else { return nil }
        switch language {
        case "math", "latex", "tex":
            return .math
        case "math-inline":
            return .mathInline
        case "mermaid":
            return .mermaid
        case "dot", "graphviz", "circo", "fdp", "neato", "osage", "twopi":
            return .graphviz
        default:
            return nil
        }
    }
}