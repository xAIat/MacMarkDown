import AppKit
import WebKit

/// One web-rendered Markdown block (a table or a math formula), sized to the
/// width the preview's text layout gives it.
///
/// `MarkdownPreviewSurface` keeps one of these per block, positions it over the
/// placeholder the text layout reserved, and feeds the height the page reports
/// back into that placeholder, so the block lays itself out with real CSS
/// (`border-collapse` for tables, MathJax's SVG for formulas) instead of a
/// hand-drawn approximation.
@MainActor
final class PreviewWebBlockView: NSView {

    /// The content height the page last reported, `nil` until it reports once.
    private(set) var reportedHeight: CGFloat?

    /// Called on the main thread whenever WebKit reports a new height (first
    /// layout, a width change, a content change).
    var onHeightChange: ((CGFloat) -> Void)?

    private let webView: WKWebView
    private let heightHandler: WebBlockHeightHandler
    private var loadedKey: String?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        // The configuration is copied when the web view is created, so the
        // handler has to be registered first. It holds `self` weakly;
        // WKUserContentController retains its handlers, and registering the
        // view itself would leak it (and through it, the web view).
        let handler = WebBlockHeightHandler()
        configuration.userContentController.add(handler, name: "height")
        let view = WKWebView(frame: .zero, configuration: configuration)
        self.webView = view
        self.heightHandler = handler
        super.init(frame: .zero)

        // A transparent, non-scrolling block: the page draws only its content
        // and the preview's own background shows through.
        view.setValue(false, forKey: "drawsBackground")
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        handler.owner = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Loads the block's page. `key` identifies the page cheaply so a
    /// scroll-driven layout pass does not compare (or reload) the HTML — the
    /// math pages embed the whole MathJax bundle.
    func load(html: String, key: String) {
        guard key != loadedKey else { return }
        loadedKey = key
        reportedHeight = nil
        webView.loadHTMLString(html, baseURL: nil)
    }

    func handleReportedHeight(_ height: CGFloat) {
        let next = max(1, height)
        guard reportedHeight == nil || abs(next - reportedHeight!) > 0.5 else { return }
        reportedHeight = next
        onHeightChange?(next)
    }
}

/// Bridges the page's `height` script messages to the owning view. Kept weak so
/// the content controller's strong hold on its handlers does not retain the
/// view (and through it, the web view).
private final class WebBlockHeightHandler: NSObject, WKScriptMessageHandler {
    weak var owner: PreviewWebBlockView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        // WebKit delivers script messages on the main thread.
        guard let value = message.body as? Double else { return }
        MainActor.assumeIsolated {
            owner?.handleReportedHeight(CGFloat(value))
        }
    }
}
