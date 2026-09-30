import AppKit

// MARK: - Insertion point
//
// The blinking caret is a tiny `NSTextInsertionIndicator` (macOS 14+) that
// AppKit blinks for us. It is placed manually at the empty-selection
// fragments; like the rest of the view it lives in the content coordinate
// space, so scrolling moves it without per-frame re-aligning, and there is no
// caret state to keep in sync.

extension MarkdownTextView {

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowKeyWindowDidChange),
                name: NSWindow.didBecomeKeyNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowKeyWindowDidChange),
                name: NSWindow.didResignKeyNotification,
                object: window
            )
        } else {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
        }
        updateInsertionPointStateAndRestartTimer()
    }

    @objc
    private func windowKeyWindowDidChange(_ notification: Notification) {
        updateInsertionPointStateAndRestartTimer()
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        isFirstResponder = result
        updateInsertionPointStateAndRestartTimer()
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        isFirstResponder = false
        updateInsertionPointStateAndRestartTimer()
        return result
    }

    override func keyDown(with event: NSEvent) {
        guard isEditable else {
            super.keyDown(with: event)
            return
        }
        // The input context claims IME-involved events; everything else is
        // dispatched to the standard `insert*`/`delete*`/`move*` selectors.
        if inputContext?.handleEvent(event) == false {
            interpretKeyEvents([event])
        }
    }
}

extension MarkdownTextView {

    /// Whether the blinking insertion point should be drawn at all.
    var shouldDrawInsertionPoint: Bool {
        guard isFirstResponder, isEditable else { return false }
        guard let window,
              (window.isKeyWindow || forcesInsertionPointDrawForTesting),
              window.firstResponder === self else { return false }
        return true
    }

    /// (Re)builds the caret view(s) to match the current selection. Diff-based:
    /// reuse existing indicator views where frames allow, drop the stale ones.
    func updateInsertionPointStateAndRestartTimer() {
        if shouldDrawInsertionPoint {
            let insertionPointRanges = textLayoutManager.textSelections.flatMap(\.textRanges).filter(\.isEmpty)
            guard !insertionPointRanges.isEmpty else { return }

            var selectionFrames: [CGRect] = []
            for selectionTextRange in insertionPointRanges {
                textLayoutManager.enumerateTextSegments(in: selectionTextRange, type: .standard) { textSegmentRange, fragmentFrame, _, _ in
                    guard let textSegmentRange else { return true }
                    let documentRange = textLayoutManager.documentRange

                    if documentRange.isEmpty {
                        selectionFrames.append(fragmentFrame)
                        return false
                    }

                    if textContentStorage.offset(from: textContentStorage.documentRange.location, to: textSegmentRange.location) == textContentStorage.documentLength {
                        // The trailing empty line yields a zero-height segment;
                        // borrow the last real line's height for the caret.
                        if let previousLocation = textContentStorage.location(textSegmentRange.endLocation, offsetBy: -1),
                           let previousFragment = textLayoutManager.textLayoutFragment(for: previousLocation),
                           let previousLine = previousFragment.textLineFragment(for: previousLocation, isUpstreamAffinity: true) {
                            selectionFrames.append(
                                CGRect(
                                    origin: fragmentFrame.origin,
                                    size: CGSize(
                                        width: fragmentFrame.width,
                                        height: previousLine.typographicBounds.height
                                    )
                                )
                            )
                        }
                        return false
                    }

                    selectionFrames.append(fragmentFrame)
                    return true
                }
            }

            var existingViews = contentView.subviews.compactMap { $0 as? MarkdownInsertionPointView }
            let origin = textContainerOrigin
            for frame in selectionFrames where !frame.isNull && !frame.isInfinite {
                let viewFrame = CGRect(
                    origin: CGPoint(x: frame.origin.x + origin.x, y: frame.origin.y + origin.y),
                    size: CGSize(width: max(2, frame.width), height: frame.height)
                )
                let insertionView: MarkdownInsertionPointView
                if let existing = existingViews.first {
                    existingViews.removeFirst()
                    existing.frame = viewFrame
                    insertionView = existing
                } else {
                    insertionView = MarkdownInsertionPointView(frame: viewFrame)
                    insertionView.insertionPointColor = insertionPointColor
                    contentView.addSubview(insertionView)
                }
                if isFirstResponder {
                    insertionView.blinkStart()
                } else {
                    insertionView.blinkStop()
                }
            }
            for stale in existingViews {
                stale.removeFromSuperview()
            }
        } else {
            removeInsertionPointViews()
        }
    }

    func removeInsertionPointViews() {
        contentView.subviews.removeAll { $0 is MarkdownInsertionPointView }
    }
}

/// A custom caret indicator. Conform to provide your own blinking caret.
protocol MarkdownInsertionPointIndicator: NSView {
    var insertionPointColor: NSColor { get set }
    func blinkStart()
    func blinkStop()
}

/// Thin wrapper that keeps the `NSTextInsertionIndicator` sized to our frame
/// (the indicator does not honor autoresizing masks).
final class MarkdownInsertionPointView: NSView, MarkdownInsertionPointIndicator {
    private let indicator: NSTextInsertionIndicator

    var insertionPointColor: NSColor {
        get { indicator.color }
        set { indicator.color = newValue }
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        indicator = NSTextInsertionIndicator(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        indicator.autoresizingMask = [.width, .height]
        addSubview(indicator)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        indicator.frame.size = newSize
    }

    func blinkStart() {
        indicator.displayMode = .automatic
    }

    func blinkStop() {
        indicator.displayMode = .hidden
    }
}