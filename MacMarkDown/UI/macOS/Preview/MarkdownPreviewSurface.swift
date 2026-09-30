import AppKit
import SwiftUI

/// Read-only, selectable preview surface backed by the same TextKit 2 text
/// view as the editor. Rendering into one attributed string gives the preview
/// whole-document selection, ⌘A and copy-with-HTML, and lets scroll-sync
/// anchors be measured directly from the text layout instead of GeometryReader
/// probes.
struct MarkdownPreviewSurface: NSViewRepresentable {

    let elements: [MarkdownElement]
    var anchors: [DocumentAnchor] = []
    let theme: Theme
    let driver: PaneDriver
    var baseURL: URL?
    var zoom: CGFloat = 1
    /// The editor's font family; the preview renders its prose in it.
    var fontName: String = ""
    /// Whether math fences are typeset by MathJax (a web block) instead of
    /// staying code text. Matches the MathJax preference.
    var rendersMath = true
    /// Padding between the pane edges and the text. Matches the editor's
    /// insets so both panes' text stays off the edges and their columns line up.
    var contentInsets: NSEdgeInsets = NSEdgeInsets()
    var onScroll: (ScrollMetrics) -> Void
    var onPreviewAnchors: (([CGFloat]) -> Void)?
    /// File drops land on the preview's text surface too (it covers the whole
    /// pane once the document has content), so they must open the document
    /// exactly like drops on the editor.
    var onOpenFile: ((URL) -> Void)?
    /// File-drop targeting entered/exited, to drive the drop highlight.
    var onDragTargetingChanged: ((Bool) -> Void)?

    @MainActor
    final class Coordinator: NSObject {
        var onScroll: ((ScrollMetrics) -> Void)?
        var onPreviewAnchors: (([CGFloat]) -> Void)?
        weak var textView: MarkdownTextView?
        weak var driver: PaneDriver?
        /// Everything the preview render depends on. Equatable so a SwiftUI
        /// update that only changed unrelated state (an editor caret click,
        /// a selection change) can skip re-rendering and re-laying out the
        /// preview entirely.
        struct RenderInputs: Equatable {
            var elements: [MarkdownElement]
            var anchorPaths: [AnchorPath]
            var theme: Theme
            var zoom: CGFloat
            var fontName: String
            var baseURL: URL?
            var rendersMath: Bool
        }
        var lastRenderInputs: RenderInputs?
        /// Character ranges aligned 1:1 with the parser's anchors.
        private var anchorRanges: [NSRange?] = []
        /// The last attributed content applied to the text view. The renderer
        /// is deterministic, so an equal value means the preview is already up
        /// to date and the text storage must not be replaced (which would
        /// invalidate the TextKit layout on every SwiftUI update).
        private var lastAttributed: NSAttributedString?
        private var lastMetrics: ScrollMetrics?
        nonisolated(unsafe) private var boundsObserver: NSObjectProtocol?
        nonisolated(unsafe) private var liveScrollObservers: [NSObjectProtocol] = []

        deinit {
            if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
            for observer in liveScrollObservers { NotificationCenter.default.removeObserver(observer) }
        }

        func install(on textView: MarkdownTextView, scrollView: NSScrollView, driver: PaneDriver) {
            self.textView = textView
            self.driver = driver
            guard boundsObserver == nil else { return }
            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reportMetrics(scrollView) }
            }
            let center = NotificationCenter.default
            liveScrollObservers.append(center.addObserver(
                forName: NSScrollView.willStartLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.driver?.onLiveScrollBegan?() }
            })
            liveScrollObservers.append(center.addObserver(
                forName: NSScrollView.didEndLiveScrollNotification,
                object: scrollView,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.driver?.onLiveScrollEnded?() }
            })
        }

        /// A web-rendered block: a table or a math formula. Both reserve a text
        /// placeholder and are drawn by a `PreviewWebBlockView` positioned over
        /// it.
        struct WebBlock {
            enum Kind {
                case table(TableData)
                case math(tex: String, isDisplay: Bool)
            }

            var path: AnchorPath
            /// Range of the placeholder attachment character.
            var range: NSRange
            var attachment: NSTextAttachment
            var kind: Kind
        }

        /// WebKit-laid-out blocks, keyed by anchor path. The text layout
        /// reserves a placeholder for each one; the block view sits over that
        /// placeholder inside the document view, so the block scrolls and clips
        /// with the text.
        private var webViews: [AnchorPath: PreviewWebBlockView] = [:]
        private var webBlocks: [WebBlock] = []
        /// Block views waiting to be assigned to a block. Kept small: each one
        /// is a live web content process.
        private var idleWebViews: [PreviewWebBlockView] = []
        private static let maximumIdleWebViews = 2
        /// Builds a block's page; set by `synchronizeWebBlocks`. The key
        /// identifies the page cheaply (the math pages embed the MathJax
        /// bundle), so a scroll-driven layout pass never compares that HTML.
        private var webBlockPage: ((WebBlock.Kind) -> (html: String, key: String))?
        /// Heights WebKit has already measured, replayed into every render so a
        /// re-render reserves the real height instead of jumping back to an
        /// estimate. Tables and math share the map (a path is one or the other).
        private(set) var measuredBlockHeights: [AnchorPath: CGFloat] = [:]

        /// Flattens a render's web blocks so the host can manage them together.
        static func webBlocks(
            tables: [AttributedRenderer.RenderedPreview.TableBlock],
            math: [AttributedRenderer.RenderedPreview.MathBlock]
        ) -> [WebBlock] {
            tables.map {
                WebBlock(
                    path: $0.path,
                    range: $0.range,
                    attachment: $0.attachment,
                    kind: .table($0.table)
                )
            } + math.map {
                WebBlock(
                    path: $0.path,
                    range: $0.range,
                    attachment: $0.attachment,
                    kind: .math(tex: $0.tex, isDisplay: $0.isDisplay)
                )
            }
        }

        /// Matches the block views to a fresh render: recycles what is gone and
        /// re-positions what is left. Views are *not* created here — see
        /// `layoutWebBlocks`, which only spins up a web view for a block that is
        /// actually near the viewport.
        func synchronizeWebBlocks(
            _ blocks: [WebBlock],
            page: @escaping (WebBlock.Kind) -> (html: String, key: String),
            in textView: MarkdownTextView
        ) {
            webBlocks = blocks
            webBlockPage = page
            let live = Set(blocks.map(\.path))
            for (path, view) in webViews where !live.contains(path) {
                recycle(view)
                webViews.removeValue(forKey: path)
            }
            layoutWebBlocks(in: textView)
        }

        /// Removes `view` from the text view and keeps it for the next block.
        ///
        /// Every live `WKWebView` is a separate web content process, and letting
        /// them come and go makes WebKit log its own process-lifecycle diagnostics
        /// (`XPCConnectionTerminationWatchdog`, `markAllLayersVolatile`). A small
        /// pool keeps the process count bounded by what is on screen.
        private func recycle(_ view: PreviewWebBlockView) {
            view.removeFromSuperview()
            guard idleWebViews.count < Self.maximumIdleWebViews else { return }
            idleWebViews.append(view)
        }

        private func makeWebBlockView(
            for block: WebBlock,
            textView: MarkdownTextView
        ) -> PreviewWebBlockView {
            let view = idleWebViews.popLast() ?? PreviewWebBlockView()
            view.onHeightChange = { [weak self, weak view, weak textView] height in
                // WebKit delivers the page's height messages on the main thread.
                MainActor.assumeIsolated {
                    guard let self, let view, let textView,
                          // A pooled view has no block: ignore whatever it reports
                          // while it waits to be assigned again.
                          let path = self.path(of: view)
                    else { return }
                    self.applyMeasuredHeight(height, path: path, textView: textView)
                }
            }
            webViews[block.path] = view
            textView.webBlockOverlayHost.addSubview(view)
            return view
        }

        /// WebKit measured a block: grow or shrink its placeholder and re-lay
        /// out, so the text after it starts below it instead of under it.
        private func applyMeasuredHeight(
            _ height: CGFloat,
            path: AnchorPath,
            textView: MarkdownTextView
        ) {
            measuredBlockHeights[path] = height
            guard let block = webBlocks.first(where: { $0.path == path }) else { return }
            guard abs(block.attachment.bounds.height - height) > 0.5 else { return }
            block.attachment.bounds.size.height = height
            // The attachment is shared with the text storage; its new bounds only
            // take effect once the range is told its attributes changed.
            textView.invalidateAttachmentLayout(in: block.range)
            layoutWebBlocks(in: textView)
            // Correcting the reservation moved every anchor below the block, and
            // the scroll sync interpolates between anchor positions: without a
            // fresh report it keeps mapping onto the old layout and the two panes
            // drift apart. Wait for the layout pass so the measurement is final.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                if let scrollView = textView.enclosingScrollView {
                    self.reportMetrics(scrollView)
                }
                self.reportAnchors()
            }
        }

        /// Places the blocks over their placeholders and keeps the web views
        /// bounded to what is (nearly) on screen.
        ///
        /// The placeholder rect comes from the text layout in container
        /// coordinates; the blocks live in the (flipped) document view, so the
        /// container origin is added — the same conversion the scroll-sync anchors
        /// make. A block far outside the viewport is recycled instead of kept
        /// alive: each `WKWebView` is a web content process, and a document with
        /// many blocks must not spin them all up at once.
        func layoutWebBlocks(in textView: MarkdownTextView) {
            let containerWidth = textView.textContainer.size.width
            let origin = textView.textContainerOrigin
            let visible = textView.visibleRect
            let near = visible.insetBy(dx: 0, dy: -max(visible.height, 400))
            for block in webBlocks {
                guard let textRange = textView.textContentStorage.textRange(from: block.range),
                      let rect = textView.textLayoutManager.typographicBounds(in: textRange),
                      rect.height > 1 else { continue }
                let frame = NSRect(
                    x: origin.x + rect.minX,
                    y: origin.y + rect.minY,
                    width: containerWidth,
                    height: rect.height
                )
                guard frame.intersects(near) else {
                    if let view = webViews[block.path] {
                        recycle(view)
                        webViews.removeValue(forKey: block.path)
                    }
                    continue
                }
                let view = webViews[block.path] ?? makeWebBlockView(for: block, textView: textView)
                if let webBlockPage {
                    // Loading is skipped when the page is already the block's.
                    let page = webBlockPage(block.kind)
                    view.load(html: page.html, key: page.key)
                }
                view.frame = frame
            }
        }

        private func path(of view: PreviewWebBlockView) -> AnchorPath? {
            webViews.first(where: { $0.value === view })?.key
        }

        func setContent(_ attributed: NSAttributedString, anchorRanges: [NSRange?]) {
            self.anchorRanges = anchorRanges
            guard let textView else { return }
            // The representable runs on every SwiftUI update — including a
            // caret-only click in the editor. Replacing the whole text storage
            // for identical content invalidates the TextKit layout and can move
            // the viewport, so only replace it when the render actually changed.
            if let last = lastAttributed, last.isEqual(to: attributed) { return }
            lastAttributed = attributed
            textView.setAttributedContent(attributed)
        }

        func reportMetrics(_ scrollView: NSScrollView) {
            guard let textView = scrollView.documentView as? MarkdownTextView else { return }
            // The scrollable height must be the TRUE laid-out content height,
            // not `documentView.frame.height`: a frame that is still stale
            // (measured at an earlier, narrower pane width) would widen the
            // scrollable range and let the sync push the preview past its real
            // content into the blank well below it.
            let contentHeight = textView.layoutContentHeight
            let clip = scrollView.contentView
            var offsetY = clip.bounds.origin.y
            // While the layout is settled the preview must never rest below its
            // content: a stale-tall frame (or a rejected sync command) can park
            // the viewport in the blank well under the last line. Pull it back
            // into the real scrollable range.
            if !textView.shouldDeferContentSizeUpdate, contentHeight > clip.bounds.height {
                let maxY = contentHeight - clip.bounds.height
                if offsetY > maxY + 0.5 {
                    clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: maxY))
                    scrollView.reflectScrolledClipView(clip)
                    offsetY = maxY
                }
            }
            let metrics = ScrollMetrics(
                offsetY: offsetY,
                contentHeight: contentHeight,
                visibleHeight: clip.bounds.height
            )
            layoutWebBlocks(in: textView)
            guard metrics != lastMetrics else { return }
            lastMetrics = metrics
            onScroll?(metrics)
        }

        /// Measures the Y position of every anchor from the text layout and
        /// reports them (paired 1:1 with the editor's anchors by index).
        ///
        /// Each anchor now has its own character range (nested list items and
        /// quote children included), so the measurement no longer collapses
        /// every nested anchor onto its parent block's top. A range that cannot
        /// be measured carries the previous anchor's Y forward, which keeps the
        /// array 1:1 with the editor and monotonically non-decreasing.
        func reportAnchors() {
            guard let textView, !anchorRanges.isEmpty, let onPreviewAnchors else { return }
            var ys: [CGFloat] = []
            ys.reserveCapacity(anchorRanges.count)
            var last: CGFloat = 0
            for range in anchorRanges {
                guard let range,
                      let textRange = textView.textContentStorage.textRange(from: range),
                      let frame = textView.textLayoutManager.typographicBounds(in: textRange)
                else {
                    ys.append(last)
                    continue
                }
                last = frame.minY + textView.textContainerOrigin.y
                ys.append(last)
            }
            onPreviewAnchors(ys)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Applies the pane's insets to the preview's text container, so the text
    /// keeps the same margin from the pane edges as the editor's text does.
    /// `contentInsets` requests a relayout on every assignment, and this runs on
    /// every SwiftUI update (including caret-only clicks in the editor), so only
    /// changed values are written.
    static func applyInsets(_ insets: NSEdgeInsets, to textView: MarkdownTextView) {
        let current = textView.contentInsets
        guard abs(current.top - insets.top) > 0.5
            || abs(current.left - insets.left) > 0.5
            || abs(current.bottom - insets.bottom) > 0.5
            || abs(current.right - insets.right) > 0.5
        else { return }
        textView.contentInsets = insets
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = false

        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        textView.isEditable = false
        textView.isSelectable = true
        textView.onOpenFile = onOpenFile
        textView.onDragTargetingChanged = onDragTargetingChanged
        textView.autoresizingMask = [.width]
        textView.backgroundColor = nil
        Self.applyInsets(contentInsets, to: textView)
        scrollView.documentView = textView

        context.coordinator.install(on: textView, scrollView: scrollView, driver: driver)
        driver.applyOffsetY = { [weak scrollView] y in
            guard let scrollView else { return }
            // Clamp against the TRUE content height, not the document view's
            // frame: a stale-tall frame may still be in place while the layout
            // settles, and scrolling to its bottom would show the blank well.
            // Fall back to the frame while a layout is pending.
            let contentHeight: CGFloat
            if let tv = scrollView.documentView as? MarkdownTextView,
               !tv.shouldDeferContentSizeUpdate {
                contentHeight = tv.layoutContentHeight
            } else {
                contentHeight = scrollView.documentView?.frame.height ?? 0
            }
            let maxY = max(0, contentHeight - scrollView.contentView.bounds.height)
            let clamped = min(max(0, y), maxY)
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: clamped))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        context.coordinator.onScroll = onScroll
        context.coordinator.onPreviewAnchors = onPreviewAnchors
        textView.onOpenFile = onOpenFile
        textView.onDragTargetingChanged = onDragTargetingChanged
        Self.applyInsets(contentInsets, to: textView)

        // The document view is created at a placeholder size; resize it to the
        // pane before measuring, otherwise the content is laid out at the
        // placeholder width (every character wrapping) and the absurd height
        // leaks into the scroll sync until a later layout corrects it.
        let contentWidth = scrollView.contentSize.width
        let widthChanged = contentWidth > 1 && abs(textView.frame.width - contentWidth) > 0.5
        if widthChanged {
            textView.setFrameSize(NSSize(width: contentWidth, height: textView.frame.height))
        }
        // A resize re-wraps the text and moves every placeholder, so the web
        // blocks follow the new layout immediately.
        context.coordinator.layoutWebBlocks(in: textView)
        if widthChanged {
            // Re-wrapping also moved every scroll-sync anchor. The editor side
            // re-measures on resize; the preview has to report again too, or the
            // service keeps interpolating onto the pre-resize positions.
            DispatchQueue.main.async { [weak coordinator = context.coordinator, weak scrollView] in
                guard let coordinator, let scrollView else { return }
                coordinator.reportMetrics(scrollView)
                coordinator.reportAnchors()
            }
        }

        // Rendering and laying out the whole document is expensive, and this
        // runs on every SwiftUI update — including ones that do not touch the
        // preview (a caret click in the editor). Only re-render when an input
        // the preview actually depends on changed.
        let inputs = Coordinator.RenderInputs(
            elements: elements,
            anchorPaths: anchors.map(\.path),
            theme: theme,
            zoom: zoom,
            fontName: fontName,
            baseURL: baseURL,
            rendersMath: rendersMath
        )
        if inputs != context.coordinator.lastRenderInputs {
            context.coordinator.lastRenderInputs = inputs
            let measuredHeights = context.coordinator.measuredBlockHeights
            let rendered = AttributedRenderer(
                theme: theme,
                zoom: zoom,
                baseURL: baseURL,
                fontName: fontName,
                tableHeights: measuredHeights,
                mathHeights: measuredHeights,
                rendersMath: rendersMath
            ).render(elements)
            context.coordinator.setContent(
                rendered.attributed,
                anchorRanges: rendered.anchorRanges(for: anchors.map(\.path))
            )
            let theme = self.theme
            let zoom = self.zoom
            context.coordinator.synchronizeWebBlocks(
                Coordinator.webBlocks(tables: rendered.tables, math: rendered.mathBlocks),
                page: { kind in
                    switch kind {
                    case .table(let table):
                        let html = TablePreviewHTML.page(
                            markup: TablePreviewHTML.tableMarkup(table),
                            theme: theme,
                            zoom: zoom
                        )
                        // The table page is small enough to be its own key.
                        return (html, html)
                    case .math(let tex, let isDisplay):
                        let html = MathPreviewHTML.page(
                            tex: tex,
                            isDisplay: isDisplay,
                            theme: theme,
                            zoom: zoom
                        )
                        return (html, "\(theme.name)|\(zoom)|\(isDisplay)|\(tex)")
                    }
                },
                in: textView
            )
            DispatchQueue.main.async {
                context.coordinator.reportMetrics(scrollView)
                context.coordinator.reportAnchors()
            }
        }
    }
}
