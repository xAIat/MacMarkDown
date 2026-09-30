import AppKit
import QuartzCore
import SwiftUI

/// Scroll metrics for one pane, read from its underlying `NSScrollView`.
struct ScrollMetrics: Equatable, Sendable {
    var offsetY: CGFloat
    var contentHeight: CGFloat
    var visibleHeight: CGFloat
}

/// The editor-text surface scroll-sync's anchor measurement needs. The legacy
/// `NSTextView` and the phase-3 `MarkdownTextView` both qualify, captured here
/// into one value type without requiring either class to declare a protocol
/// conformance.
@MainActor
struct TextAnchorHost {
    var string: String
    var textLayoutManager: NSTextLayoutManager?
    var textContainerOrigin: NSPoint
    var font: NSFont?
    var textStorage: NSTextStorage?
    /// Text container width — part of the layout signature so anchor positions
    /// are re-measured when the pane is resized (text re-wraps).
    var containerWidth: CGFloat
    var textContainerInset: NSSize
}

/// Identifies the layout state anchor positions depend on. A change (new text,
/// resize, font, inset) invalidates the measured-anchor cache.
private struct AnchorLayoutSignature: Equatable {
    var text: String
    var containerWidth: CGFloat
    var fontName: String
    var fontSize: CGFloat
    var insetWidth: CGFloat
    var insetHeight: CGFloat
}

/// Hosts `content` and introspects the `NSScrollView` it renders so scroll
/// position can be read and driven programmatically.
///
/// SwiftUI's `TextEditor` and `ScrollView` both wrap an `NSScrollView`;
/// hosting the content inside this representable gives us a well-scoped
/// subtree that contains exactly the pane's scroll view (and, for the
/// editor, its text view used to measure line height).
struct ScrollSyncPane<Content: View>: NSViewRepresentable {

    private let content: Content
    private let driver: PaneDriver
    private let onScroll: (ScrollMetrics) -> Void
    private let measuresTextAnchors: Bool

    init(driver: PaneDriver,
         onScroll: @escaping (ScrollMetrics) -> Void,
         measuresTextAnchors: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.driver = driver
        self.onScroll = onScroll
        self.measuresTextAnchors = measuresTextAnchors
        self.content = content()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onScroll: ((ScrollMetrics) -> Void)?
        var driver: PaneDriver?
        var measuresTextAnchors = false
        var hosting: NSHostingView<Content>?
        private var scrollView: NSScrollView?
        private weak var textAnchorView: NSView?
        private var anchorHost: TextAnchorHost? {
            guard let view = textAnchorView else { return nil }
            return Self.textAnchorHost(from: view)
        }
        private var anchorCacheSignature: AnchorLayoutSignature?
        private var anchorCache: [CGFloat] = []
        /// Scroll offset captured before a text edit. A bulk insertion (paste,
        /// drop) makes `NSTextView` scroll to the end of the inserted text;
        /// when the pane was at the top it must stay there instead.
        private var offsetBeforeTextEdit: CGFloat?
        private var observesTextStorage = false

        /// Live scroll state (scrollbar drag, trackpad or wheel). While active,
        /// `report()` is coalesced to at most one call per display refresh so a
        /// fast drag does not run the full sync pipeline on every raw event.
        private var isLiveScrolling = false
        private var lastReportTime: CFTimeInterval = 0
        private let liveScrollReportInterval: CFTimeInterval = 1.0 / 60.0

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        func report() {
            guard let sv = scrollView else { return }
            if isLiveScrolling {
                let now = CACurrentMediaTime()
                guard now - lastReportTime >= liveScrollReportInterval else { return }
                lastReportTime = now
            }
            let metrics = ScrollMetrics(
                offsetY: sv.contentView.bounds.origin.y,
                contentHeight: sv.documentView?.frame.height ?? 0,
                visibleHeight: sv.contentView.bounds.height
            )
            onScroll?(metrics)
        }

        @objc private func boundsDidChange(_ note: Notification) {
            report()
        }

        @objc private func willStartLiveScroll(_ note: Notification) {
            isLiveScrolling = true
            driver?.isLiveScrolling = true
            driver?.onLiveScrollBegan?()
        }

        @objc private func didEndLiveScroll(_ note: Notification) {
            isLiveScrolling = false
            driver?.isLiveScrolling = false
            // Always deliver the settled position, even if the throttled ticks
            // dropped it.
            report()
            driver?.onLiveScrollEnded?()
        }

        func refresh(from container: NSView, retries: Int) {
            installIfNeeded(on: container)
            if measuresTextAnchors, self.textAnchorView == nil,
               let tv = findTextView(in: container) {
                self.textAnchorView = tv
                if let host = Self.textAnchorHost(from: tv) {
                    installAnchorMeasurement(on: host)
                }
            }
            if scrollView != nil {
                report()
            } else if retries > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.refresh(from: container, retries: retries - 1)
                }
            }
        }

        /// Measures the mid-Y of each anchor line from the real text layout.
        /// The lines come from the parser (`DocumentAnchor.line`), so the editor
        /// and preview anchor arrays are paired 1:1 by index.
        ///
        /// The result is cached by *layout signature* (text + container width +
        /// font + inset), not text alone: a window resize re-wraps the text and
        /// moves every anchor, so the cache must be invalidated.
        private func measuredAnchorLocations(
            expectedText: String,
            lines: [Int],
            forceLayout: Bool
        ) -> [CGFloat]? {
            guard let host = anchorHost, host.string == expectedText else { return nil }
            guard let textLayoutManager = host.textLayoutManager else { return nil }

            let signature = AnchorLayoutSignature(
                text: host.string,
                containerWidth: host.containerWidth,
                fontName: host.font?.fontName ?? "",
                fontSize: host.font?.pointSize ?? 0,
                insetWidth: host.textContainerInset.width,
                insetHeight: host.textContainerInset.height
            )
            let layoutChanged = signature != anchorCacheSignature
            if !forceLayout, !layoutChanged {
                return anchorCache
            }
            textLayoutManager.ensureLayout(for: textLayoutManager.documentRange)

            let ns = host.string as NSString
            var lineStarts: [Int] = [0]
            var index = 0
            while index < ns.length {
                if ns.character(at: index) == 0x0A { lineStarts.append(index + 1) }
                index += 1
            }

            var result: [CGFloat] = []
            result.reserveCapacity(lines.count)
            // A line that cannot be measured carries the previous anchor's Y
            // forward: the array stays 1:1 with the parser's anchors (and the
            // preview's) and monotonically non-decreasing.
            var last: CGFloat = 0
            for line in lines {
                guard line >= 1, line <= lineStarts.count else {
                    result.append(last)
                    continue
                }
                let start = lineStarts[line - 1]
                var end = start
                while end < ns.length && ns.character(at: end) != 0x0A { end += 1 }
                let location = min(start, max(0, ns.length - 1))
                let length = max(1, end - location)
                let rect = boundingRect(
                    forCharacterRange: NSRange(location: location, length: length),
                    in: textLayoutManager
                )
                if rect.height > 0 { last = rect.midY + host.textContainerOrigin.y }
                result.append(last)
            }

            anchorCacheSignature = signature
            anchorCache = result
            return result
        }

        /// TextKit 2 port of `NSLayoutManager.boundingRect(forGlyphRange:in:)`:
        /// unions the `enumerateTextSegments` rects covering a character range.
        private func boundingRect(
            forCharacterRange range: NSRange,
            in textLayoutManager: NSTextLayoutManager
        ) -> CGRect {
            guard let start = textLayoutManager.location(atCharacter: range.location),
                  let end = textLayoutManager.location(atCharacter: range.location + range.length),
                  let textRange = NSTextRange(location: start, end: end)
            else { return .null }

            var result: CGRect = .null
            textLayoutManager.enumerateTextSegments(
                in: textRange,
                type: .standard,
                options: [.rangeNotRequired]
            ) { _, segmentRect, _, _ in
                result = result == .null ? segmentRect : result.union(segmentRect)
                return true
            }
            return result
        }

        func setOffsetY(_ y: CGFloat) {
            guard let sv = scrollView, let doc = sv.documentView else { return }
            let maxY = max(0, doc.frame.height - sv.contentView.bounds.height)
            let clamped = min(max(0, y), maxY)
            guard abs(clamped - sv.contentView.bounds.origin.y) > 0.5 else { return }
            sv.contentView.scroll(to: NSPoint(x: sv.contentView.bounds.origin.x, y: clamped))
            // `NSClipView.scroll(to:)` moves the content but does not update the
            // scroller knob; without this the editor's scrollbar stays behind
            // while the preview drives it.
            sv.reflectScrolledClipView(sv.contentView)
        }

        private func installIfNeeded(on container: NSView) {
            guard scrollView == nil else { return }
            guard let sv = findScrollView(in: container) else { return }
            scrollView = sv
            let center = NotificationCenter.default
            sv.contentView.postsBoundsChangedNotifications = true
            center.addObserver(self,
                               selector: #selector(boundsDidChange(_:)),
                               name: NSView.boundsDidChangeNotification,
                               object: sv.contentView)
            center.addObserver(self,
                               selector: #selector(boundsDidChange(_:)),
                               name: NSView.frameDidChangeNotification,
                               object: sv.contentView)
            center.addObserver(self,
                               selector: #selector(willStartLiveScroll(_:)),
                               name: NSScrollView.willStartLiveScrollNotification,
                               object: sv)
            center.addObserver(self,
                               selector: #selector(didEndLiveScroll(_:)),
                               name: NSScrollView.didEndLiveScrollNotification,
                               object: sv)

            if measuresTextAnchors, let tv = findTextView(in: container),
               let host = Self.textAnchorHost(from: tv) {
                self.textAnchorView = tv
                installAnchorMeasurement(on: host)
            }
        }

        private func installAnchorMeasurement(on tv: TextAnchorHost) {
            driver?.measureAnchors = { [weak self] expectedText, lines, _, _, forceLayout in
                self?.measuredAnchorLocations(
                    expectedText: expectedText,
                    lines: lines,
                    forceLayout: forceLayout
                )
            }
            guard !observesTextStorage, let storage = tv.textStorage else { return }
            observesTextStorage = true
            let center = NotificationCenter.default
            center.addObserver(self,
                               selector: #selector(textWillProcessEditing(_:)),
                               name: NSTextStorage.willProcessEditingNotification,
                               object: storage)
            center.addObserver(self,
                               selector: #selector(textDidProcessEditing(_:)),
                               name: NSTextStorage.didProcessEditingNotification,
                               object: storage)
        }

        @objc private func textWillProcessEditing(_ note: Notification) {
            offsetBeforeTextEdit = scrollView?.contentView.bounds.origin.y
        }

        /// After a bulk edit (more than a single typed character) that started
        /// with the pane scrolled to the top, undo the scroll-to-caret jump
        /// once AppKit has finished the insertion.
        @objc private func textDidProcessEditing(_ note: Notification) {
            let before = offsetBeforeTextEdit
            offsetBeforeTextEdit = nil
            guard let before, before <= 1,
                  let storage = note.object as? NSTextStorage,
                  storage.changeInLength >= 2
            else { return }
            DispatchQueue.main.async { [weak self] in
                self?.setOffsetY(before)
            }
        }

        private func findScrollView(in view: NSView) -> NSScrollView? {
            if let sv = view as? NSScrollView { return sv }
            for sub in view.subviews {
                if let found = findScrollView(in: sub) { return found }
            }
            return nil
        }

        private func findTextView(in view: NSView) -> NSView? {
            if let tv = view as? NSTextView { return tv }
            if let tv = view as? MarkdownTextView { return tv }
            for sub in view.subviews {
                if let found = findTextView(in: sub) { return found }
            }
            return nil
        }

        /// Snapshots the anchor-measurement surface from either live editor
        /// host class.
        static func textAnchorHost(from view: NSView) -> TextAnchorHost? {
            if let tv = view as? NSTextView {
                return TextAnchorHost(
                    string: tv.string,
                    textLayoutManager: tv.textLayoutManager,
                    textContainerOrigin: tv.textContainerOrigin,
                    font: tv.font,
                    textStorage: tv.textStorage,
                    containerWidth: tv.textContainer?.size.width ?? tv.frame.width,
                    textContainerInset: tv.textContainerInset
                )
            }
            if let tv = view as? MarkdownTextView {
                return TextAnchorHost(
                    string: tv.string,
                    textLayoutManager: tv.textLayoutManager,
                    textContainerOrigin: tv.textContainerOrigin,
                    font: tv.font,
                    textStorage: tv.textStorage,
                    containerWidth: tv.textContainer.size.width,
                    textContainerInset: NSSize(width: tv.contentInsets.left, height: tv.contentInsets.top)
                )
            }
            return nil
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.driver = driver
        coordinator.onScroll = onScroll
        coordinator.measuresTextAnchors = measuresTextAnchors
        return coordinator
    }

    func makeNSView(context: Context) -> NSView {
        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        hosting.sizingOptions = [.preferredContentSize]

        let container = NSView()
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        context.coordinator.hosting = hosting
        driver.applyOffsetY = { [weak coordinator = context.coordinator] y in
            coordinator?.setOffsetY(y)
        }
        context.coordinator.refresh(from: container, retries: 40)
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hosting?.rootView = content
        context.coordinator.onScroll = onScroll
        context.coordinator.refresh(from: nsView, retries: 10)
    }
}