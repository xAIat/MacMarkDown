import AppKit
import AVFoundation

/// A TextKit 2 editor view that owns its entire layout stack
/// (`NSTextContentStorage` → `MarkdownTextLayoutManager` → `NSTextContainer`),
/// so a later phase can render Markdown markers itself instead of inheriting
/// `NSTextView`'s stubbornly opaque rendering pipeline.
///
/// View hierarchy:
///
///     NSScrollView
///         └─ MarkdownTextView (flipped document view)
///             └─ contentView
///                 ├─ selectionView (highlight bands, below the text)
///                 └─ contentViewportView
///                     └─ MarkdownTextFragmentView per laid-out fragment
///
/// Text reaches the screen through `NSTextViewportLayoutController`, which asks
/// this view to create/cache one `MarkdownTextFragmentView` per visible
/// `NSTextLayoutFragment`. Only the visible band is ever laid out, so very long
/// documents scroll cheaply (the same lazy contract `NSTextView` uses).
///
/// Display, selection, editing, IME, drag & drop and smart editing are all
/// implemented on this view and its extensions.
@MainActor
final class MarkdownTextView: NSView {

    // MARK: - Text stack

    let textContentStorage = NSTextContentStorage()
    let textLayoutManager: NSTextLayoutManager = MarkdownTextLayoutManager()
    let textContainer = NSTextContainer()

    /// Anchor held across the pointer-based selection session (click/drag,
    /// double/triple-click, shift-click). Read by `mouseDragged` and
    /// `mouseDown`; extensions cannot add stored properties, so it lives here.
    var _selectionAnchor: NSTextSelection?

    // MARK: - Subviews

    /// Full-size container. Flipped, so drawing matches TextKit's top-origin
    /// fragment coordinates. Fragments and the insertion point live here.
    let contentView = MarkdownContentView(frame: .zero)
    /// Paints the selection highlight *under* the fragment views. A dedicated,
    /// non-tiled view: `contentView` is `CATiledLayer`-backed, where a plain
    /// `needsDisplay` never invalidates the cached tiles, so a selection drawn
    /// there would never repaint — hence the dedicated view.
    let selectionView = MarkdownSelectionView(frame: .zero)
    /// Holds the cached fragment views for the current viewport.
    private let contentViewportView = MarkdownContentViewportView(frame: .zero)

    /// The view web blocks (tables, math) are added to: the document view
    /// itself.
    ///
    /// The fragment host would seem like the natural place, but it is
    /// `CATiledLayer`-backed (that is what keeps redraws cheap while scrolling)
    /// and a hosted `WKWebView` does not composite reliably inside a tiled
    /// layer. The document view is flipped and its origin is the document's top,
    /// so a block is placed at a text-layout rect plus `textContainerOrigin` —
    /// the same conversion the scroll-sync anchors use.
    var webBlockOverlayHost: NSView { self }

    var fragmentViewMap: NSMapTable<NSTextLayoutFragment, MarkdownTextFragmentView>
    private var unusedFragmentViews: Set<MarkdownTextFragmentView> = []
    private var isLayingOut = false

    /// Backing store for `showsInvisibleCharacters` (see
    /// `MarkdownTextView+Invisibles.swift`).
    var _showsInvisibleCharacters = false

    /// Backing store for `showsLineNumbers` (see
    /// `MarkdownTextView+Gutter.swift`).
    var _showsLineNumbers = false
    /// The line-number gutter, when visible.
    var gutterView: MarkdownGutterView?
    /// Bumped on every text mutation so the gutter's line index is rebuilt.
    var textMutationGeneration = 0

    /// Installed text-view plugins (see `MarkdownTextView+Plugins.swift`).
    var pluginEntries: [PluginEntry] = []

    /// Content-space origin of a possible selection drag-out gesture.
    var _pendingDragOrigin: NSPoint?
    /// Timestamp of the mouse-down that armed `_pendingDragOrigin`. A press
    /// inside the selection only becomes a drag-out after it is held past
    /// `dragOutHoldDuration`; a quicker drag extends the selection instead.
    var _pendingDragStartTime: TimeInterval = 0
    /// How long the pointer must be held inside the selection before a drag
    /// starts a drag-out session.
    var dragOutHoldDuration: TimeInterval { NSEvent.doubleClickInterval / 3 }
    /// Set while the window is live-resizing (layout/size updates are deferred).
    var isLiveResizing = false
    /// Set by the scroll observer while a live scroll gesture is active.
    var isLiveScrolling = false

    /// Read-aloud synthesizer (created on first use).
    lazy var speechSynthesizer = AVSpeechSynthesizer()
    /// Retained delegate for the speech synthesizer.
    lazy var speechDelegate = MarkdownSpeechDelegate(textView: self)
    /// Whether a read-aloud utterance is currently in progress.
    var isSpeaking = false
    /// Cached logical line start offsets (UTF-16) for the gutter.
    var lineStartOffsets: [Int] = [0]
    /// Generation the cached line offsets correspond to.
    var lineStartGeneration = -1

    /// Whether the document height must be re-measured with a forced full
    /// TextKit layout. Set on text/wrap-width changes; pure scrolling reuses
    /// the existing frame instead of forcing `ensureLayout` on every pass.
    var needsFullHeightMeasurement = true

    // MARK: - Responder / editing state

    /// Mirrors responder responsibility; gate for drawing the insertion point.
    /// Kept separately from `window?.firstResponder` so `shouldDrawInsertionPoint`
    /// stays cheap and testable.
    var isFirstResponder = false

    /// Test-only: draw the caret even though a headless test runner's window
    /// can never become key. Production code leaves this at its default.
    var forcesInsertionPointDrawForTesting = false

    // MARK: - Typing / document attributes

    var _defaultTypingAttributes: [NSAttributedString.Key: Any] = [
        .paragraphStyle: NSParagraphStyle.default,
        .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
        .foregroundColor: NSColor.textColor
    ]

    /// Attributes applied to text the user enters. Newly typed text inherits
    /// the attributes at the caret (minus anything the syntax highlighter
    /// colored), merged over the document defaults.
    var typingAttributes: [NSAttributedString.Key: Any] {
        get { _typingAttributes.merging(_defaultTypingAttributes) { current, _ in current } }
        set { _typingAttributes = newValue }
    }

    var _typingAttributes: [NSAttributedString.Key: Any] = [:]

    /// The font of the document. Assigning stamps the whole document.
    var font: NSFont {
        get { _defaultTypingAttributes[.font] as? NSFont ?? NSFont.monospacedSystemFont(ofSize: 14, weight: .regular) }
        set {
            _defaultTypingAttributes[.font] = newValue
            invalidateAttributes(updating: { [.font: newValue] })
        }
    }

    /// The document text color. Assigning stamps the whole document.
    var textColor: NSColor {
        get { _defaultTypingAttributes[.foregroundColor] as? NSColor ?? .textColor }
        set {
            _defaultTypingAttributes[.foregroundColor] = newValue
            invalidateAttributes(updating: { [.foregroundColor: newValue] })
        }
    }

    /// The document default paragraph style. Assigning stamps the document.
    var defaultParagraphStyle: NSParagraphStyle {
        get { _defaultTypingAttributes[.paragraphStyle] as? NSParagraphStyle ?? .default }
        set {
            _defaultTypingAttributes[.paragraphStyle] = newValue
            invalidateAttributes(updating: { [.paragraphStyle: newValue] })
        }
    }

    /// The view's background color. `nil` defers to the enclosing scroll view
    /// (tracking the preview pane's transparency).
    var backgroundColor: NSColor? {
        didSet {
            layer?.backgroundColor = backgroundColor?.cgColor
            contentView.layer?.backgroundColor = backgroundColor?.cgColor
        }
    }

    /// Color of the insertion point.
    var insertionPointColor: NSColor = .textColor {
        didSet {
            for view in contentView.subviews.compactMap({ $0 as? MarkdownInsertionPointView }) {
                view.insertionPointColor = insertionPointColor
            }
        }
    }

    /// Fill color for the selected text. `nil` draws no selection.
    var selectionBackgroundColor: NSColor? = .selectedTextBackgroundColor {
        didSet {
            selectionView.updateHighlights()
        }
    }

    /// Attributes used to draw the selection (drawn once selection lands in M2).
    var selectedTextAttributes: [NSAttributedString.Key: Any] = [:]

    /// Temporary attributes applied to marked (in-progress IME) text.
    var markedTextAttributes: [NSAttributedString.Key: Any] = [.underlineStyle: NSUnderlineStyle.single.rawValue]

    /// Provisional, in-progress IME text currently replacing the marked range.
    var markedText: MarkdownTextMarking?

    var isEditable = true
    var isSelectable = true
    var allowsUndo = true

    /// Edits about to land are first offered here (the host coordinator's
    /// `shouldChangeTextIn`-equivalent). Returning `false` vetoes them.
    var shouldChangeTextHandler: ((NSRange, String?) -> Bool)?

    /// `doCommand(by:)` consults this before running the default action.
    var doCommandHandler: ((Selector) -> Bool)?

    /// File drops open the document instead of pasting its contents.
    var onOpenFile: ((URL) -> Void)?
    /// File-drop targeting entered/exited, to drive the drop highlight.
    var onDragTargetingChanged: ((Bool) -> Void)?

    /// Called whenever the selection changes (mouse, keyboard, programmatic or
    /// as a side effect of an edit) so surrounding UI can mirror it.
    var onSelectionChange: ((NSRange) -> Void)?

    /// Called for standard Edit > Find menu actions.
    var onFindAction: ((NSFindPanelAction) -> Void)?

    /// Smart quotes are not synthesized for the custom host, so this stays off.
    var isAutomaticQuoteSubstitutionEnabled = false

    /// Enables the `NSSpellChecker` pass (dotted red underlines).
    var isContinuousSpellCheckingEnabled = false {
        didSet { updateSpelling() }
    }

    /// Ranges flagged by the last spelling pass (stored here because
    /// extensions cannot add stored properties).
    var _spellingRanges: [NSRange] = []

    /// Horizontal / vertical padding between the viewport edge and the text.
    /// Zero by default so unit tests exercise the bare coordinate space; the
    /// app applies the user's insets from Preferences.
    var contentInsets: NSEdgeInsets = .init(top: 0, left: 0, bottom: 0, right: 0) {
        didSet {
            needsFullHeightMeasurement = true
            needsLayout = true
        }
    }

    /// When enabled, the document view keeps one viewport of empty space below
    /// the last line so the end of the text can be scrolled to the top.
    var scrollsPastEnd = false {
        didSet {
            needsFullHeightMeasurement = true
            needsLayout = true
        }
    }

    // MARK: - NSTextView-compatible surface

    /// The document's text. Setting replaces the whole document (like `textView.string`).
    var string: String {
        get { textContentStorage.attributedString?.string ?? "" }
        set { setString(newValue) }
    }

    /// The backing `NSTextStorage`, for highlighters that mutate attributes in place.
    var textStorage: NSTextStorage? { textContentStorage.textStorage }

    /// Layout origin inside the document view (`ScrollSyncPane` reads this; the
    /// selection/caret layers offset their container-space frames by it).
    var textContainerOrigin: NSPoint { NSPoint(x: resolvedContentInsets.left, y: resolvedContentInsets.top) }

    /// `contentInsets` plus the gutter's reserved width on the left.
    var resolvedContentInsets: NSEdgeInsets {
        var insets = contentInsets
        if _showsLineNumbers { insets.left += gutterWidth }
        return insets
    }

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        fragmentViewMap = .weakToWeakObjects()

        textLayoutManager.textContainer = textContainer
        textContentStorage.addTextLayoutManager(textLayoutManager)
        textContentStorage.primaryTextLayoutManager = textLayoutManager

        textContainer.size = NSSize(
            width: max(1, frameRect.width),
            height: .greatestFiniteMagnitude
        )
        textContainer.widthTracksTextView = true

        textLayoutManager.textSelections = [
            NSTextSelection(
                range: NSTextRange(location: textContentStorage.documentRange.location, end: textContentStorage.documentRange.location)!,
                affinity: .downstream,
                granularity: .character
            )
        ]

        super.init(frame: frameRect)

        contentView.autoresizingMask = [.width, .height]
        selectionView.autoresizingMask = [.width, .height]
        contentViewportView.autoresizingMask = [.width, .height]
        wantsLayer = true
        contentView.wantsLayer = true
        selectionView.wantsLayer = true
        contentViewportView.wantsLayer = true
        contentViewportView.clipsToBounds = true

        addSubview(contentView)
        // Selection highlight below the text: fragment views draw after the
        // selection view, so glyphs stay on top of the highlight band.
        contentView.addSubview(selectionView)
        contentView.addSubview(contentViewportView)

        selectionView.textView = self
        textLayoutManager.textViewportLayoutController.delegate = self
        textLayoutManager.delegate = self
        registerForDraggedTypes([.fileURL, .string])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Text mutation

    /// Replaces the whole document with pre-attributed content (used by the
    /// read-only preview surface, which renders outside the editor).
    func setAttributedContent(_ attributed: NSAttributedString) {
        guard let storage = textStorage else { return }
        textContentStorage.performEditingTransaction {
            storage.replaceCharacters(
                in: NSRange(location: 0, length: storage.length),
                with: attributed
            )
        }
        needsFullHeightMeasurement = true
        textMutationGeneration &+= 1
        needsLayout = true
        needsDisplay = true
        layoutSubtreeIfNeeded()
    }

    /// Replaces the whole document. Repeating text stamps font/text color/
    /// paragraph style across the entire replacement, mirroring how `NSTextView`
    /// applies `typingAttributes` when `string` is assigned.
    func setString(_ newString: String) {
        let stamped = NSAttributedString(
            string: newString,
            attributes: stampAttributes
        )
        guard let storage = textStorage else { return }
        textContentStorage.performEditingTransaction {
            storage.replaceCharacters(
                in: NSRange(location: 0, length: storage.length),
                with: stamped
            )
        }
        needsFullHeightMeasurement = true
        textMutationGeneration &+= 1
        needsLayout = true
        needsDisplay = true
        // Force the layout pass now. When the document is replaced from a drag
        // & drop (a non-window event, inside the drag-tracking run loop),
        // AppKit does not always schedule a layout pass afterwards, so the
        // document view keeps the previous (empty) height and only the first
        // line is visible until a scroll forces `layout()`.
        layoutSubtreeIfNeeded()
    }

    private var stampAttributes: [NSAttributedString.Key: Any] {
        _defaultTypingAttributes
    }

    /// Applies attribute mutations in an editing transaction (the TextKit 2
    /// contract for external `NSTextStorage` edits) then asks for relayout.
    /// Used by the syntax highlighter once integration lands.
    func applyAttributes(_ mutations: (NSTextStorage) -> Void) {
        guard let storage = textStorage else { return }
        textContentStorage.performEditingTransaction {
            mutations(storage)
        }
        needsFullHeightMeasurement = true
        textMutationGeneration &+= 1
        needsLayout = true
        needsDisplay = true
    }

    /// Tells the layout that the attachments in `range` changed.
    ///
    /// An `NSTextAttachment` is a reference type shared with the text storage, so
    /// changing its `bounds` — which is how a WebKit-rendered table block grows
    /// or shrinks its reserved space once WebKit has measured it — is invisible
    /// to TextKit until the attributes are written again.
    func invalidateAttachmentLayout(in range: NSRange) {
        guard let storage = textStorage,
              let attachment = storage.attribute(.attachment, at: range.location, effectiveRange: nil)
        else { return }
        applyAttributes { editable in
            editable.removeAttribute(.attachment, range: range)
            editable.addAttribute(.attachment, value: attachment, range: range)
        }
        layoutSubtreeIfNeeded()
    }

    private func invalidateAttributes(updating attrs: () -> [NSAttributedString.Key: Any]) {
        if textContentStorage.documentRange.isEmpty {
            return
        }
        let attributes = attrs()
        guard !attributes.isEmpty else { return }
        if let storage = textStorage {
            textContentStorage.performEditingTransaction {
                storage.addAttributes(attributes, range: NSRange(location: 0, length: storage.length))
            }
        }
        needsFullHeightMeasurement = true
        needsLayout = true
        needsDisplay = true
    }

    // MARK: - Sizing & layout

    override var isFlipped: Bool { true }

    /// Legacy (non-responsive) scrolling, matching `NSTextView` in an
    /// `NSScrollView` that we resize by hand.
    override class var isCompatibleWithResponsiveScrolling: Bool { false }

    override var intrinsicContentSize: NSSize {
        let size = textLayoutManager.usageBoundsForTextContainer.size
        return NSSize(width: bounds.width, height: size.height)
    }

    override func layout() {
        super.layout()
        guard !isLayingOut else { return }

        isLayingOut = true
        defer { isLayingOut = false }

        contentView.frame = bounds
        selectionView.frame = contentView.bounds
        contentViewportView.frame = contentFrame
        updateTextContainerSize()
        textLayoutManager.textViewportLayoutController.layoutViewport()
        if updateContentSizeIfNeeded() {
            // The frame grew/shrank: the viewport layout above only created
            // fragment views for the *old* visible band, so re-run it against
            // the new bounds. Without this, a document replaced from a drag &
            // drop (inside the drag-tracking run loop, where AppKit schedules
            // no further layout pass) leaves everything past the first line
            // unrendered until a scroll forces another pass.
            selectionView.frame = contentView.bounds
            contentViewportView.frame = contentFrame
            textLayoutManager.textViewportLayoutController.layoutViewport()
        }
        layoutGutter()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        contentView.frame = bounds
        contentViewportView.frame = contentFrame
        updateTextContainerSize()
        needsLayout = true
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        updateTextContainerSize()
        needsLayout = true
    }

    /// The region the text (and its fragment views) occupies inside the view,
    /// offset by `contentInsets`.
    private var contentFrame: CGRect {
        let insets = resolvedContentInsets
        return CGRect(
            x: insets.left,
            y: insets.top,
            width: max(0, bounds.width - insets.left - insets.right),
            height: max(0, bounds.height - insets.top - insets.bottom)
        )
    }

    var effectiveVisibleRect: CGRect {
        let visible = visibleRect
        if visible.size == .zero || visible.isInfinite {
            return bounds
        }
        return visible
    }

    private var isVerticallyResizable: Bool { true }

    /// Width tracks the document view's width (like
    /// `textContainer.widthTracksTextView`), minus the horizontal insets.
    ///
    /// The view's own width — not `visibleRect.width` — is authoritative: the
    /// visible rect can momentarily report a narrower band (a pane transition,
    /// a window that is partly off-screen, a re-layout in flight), and wrapping
    /// the text at that bogus width over-reports the document height, which
    /// then leaks into the scroll sync as a blank well under the last line.
    private func updateTextContainerSize() {
        let insets = resolvedContentInsets
        // While a pane is collapsed (toggled off) the width is 0; shrinking the
        // container to 1pt would re-wrap every character and measure an absurd
        // height that then leaks into the scroll sync. Keep the last good width
        // until the pane is visible again.
        let paneWidth = bounds.width
        guard paneWidth > 0 else { return }
        let width = max(1, paneWidth - insets.left - insets.right)
        if !textContainer.size.width.isApproximatelyEqual(to: width) {
            textContainer.size.width = width
            needsFullHeightMeasurement = true
        }
        if !textContainer.lineFragmentPadding.isApproximatelyEqual(to: 0) {
            textContainer.lineFragmentPadding = 0
        }
    }

    /// Grows/shrinks the document view height to match the laid-out text.
    /// `usageBoundsForTextContainer` is an expanding estimate; the trailing
    /// empty-line segment at the document end pins the bottom edge without
    /// forcing a full-document layout pass.
    ///
    /// Returns `true` when the document view's size changed.
    @discardableResult
    private func updateContentSizeIfNeeded() -> Bool {
        let layoutManager = textLayoutManager

        var estimatedHeight: CGFloat
        if needsFullHeightMeasurement, !shouldDeferContentSizeUpdate {
            // Text or wrap width changed: force a full layout once so the
            // document height (and therefore the scrollable range) is exact.
            // Laying out the whole document (not just the end location) keeps
            // the height stable: a partial estimate that later grows mid-scroll
            // would move every anchor and reverse the synced pane.
            needsFullHeightMeasurement = false
            layoutManager.ensureLayout(for: layoutManager.documentRange)

            estimatedHeight = layoutManager.usageBoundsForTextContainer.height
            let endRange = NSTextRange(location: layoutManager.documentRange.endLocation)
            layoutManager.enumerateTextSegments(
                in: endRange,
                type: .standard,
                options: .middleFragmentsExcluded
            ) { _, rect, _, _ in
                estimatedHeight = max(estimatedHeight, rect.maxY)
                return true
            }
        } else {
            // Pure scroll: the layout is unchanged, so reuse the current
            // estimate rather than re-laying out the whole document.
            estimatedHeight = layoutManager.usageBoundsForTextContainer.height
        }

        var estimatedWidth = layoutManager.usageBoundsForTextContainer.width
        estimatedWidth = max(estimatedWidth, bounds.width)

        // Padding plus, when enabled, one viewport of trailing space so the
        // last line can scroll up to the top (the "scroll past end" behavior).
        estimatedHeight += resolvedContentInsets.top + resolvedContentInsets.bottom
        if scrollsPastEnd {
            estimatedHeight += effectiveVisibleRect.height
        }

        guard !isApproximatelyEqual(estimatedWidth, frame.width)
            || !isApproximatelyEqual(estimatedHeight, frame.height)
        else { return false }

        let newFrame = backingAlignedRect(
            CGRect(origin: frame.origin, size: CGSize(width: estimatedWidth, height: estimatedHeight)),
            options: .alignAllEdgesOutward
        )
        guard !isApproximatelyEqual(newFrame.width, frame.width)
            || !isApproximatelyEqual(newFrame.height, frame.height)
        else { return false }
        let previousHeight = frame.height
        setFrameSize(newFrame.size)
        // When the document shrinks (a pane was collapsed and re-shown, or a
        // wrap-width correction), the clip view keeps its old origin and the
        // viewport is left scrolled past the content — a large blank area.
        // Pull it back inside the new scrollable range.
        if newFrame.height < previousHeight - 0.5 {
            clampScrollOrigin(forContentHeight: newFrame.height)
        }
        return true
    }

    /// True content height from the text layout (used + insets), independent of
    /// the document view's *frame* height. A stale frame (e.g. the preview pane
    /// sat at a narrower width and its frame has not yet self-healed) can
    /// overstate the scrollable range; scroll-sync reports this value so the
    /// preview can never be driven past its real content into a blank area.
    var layoutContentHeight: CGFloat {
        var height = textLayoutManager.usageBoundsForTextContainer.height
            + resolvedContentInsets.top + resolvedContentInsets.bottom
        if scrollsPastEnd {
            height += effectiveVisibleRect.height
        }
        return max(height, effectiveVisibleRect.height)
    }

    /// Clamps the enclosing scroll view's origin so the viewport cannot sit
    /// past the (possibly just-shrunk) document.
    private func clampScrollOrigin(forContentHeight height: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let clip = scrollView.contentView
        let maxY = max(0, height - clip.bounds.height)
        guard clip.bounds.origin.y > maxY + 0.5 else { return }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: maxY))
        scrollView.reflectScrolledClipView(clip)
    }

    private func isApproximatelyEqual(_ a: CGFloat, _ b: CGFloat) -> Bool {
        abs(a - b) <= 0.5
    }

    // MARK: - Scroll observation

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        let center = NotificationCenter.default
        // Drop any observer from a previous superview before re-registering;
        // otherwise re-parenting stacks duplicate observers and multiplies the
        // per-tick layout work.
        center.removeObserver(self, name: NSView.boundsDidChangeNotification, object: nil)
        guard let scrollView = enclosingScrollView else { return }
        scrollView.contentView.postsBoundsChangedNotifications = true
        center.addObserver(
            self,
            selector: #selector(clipViewBoundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        center.addObserver(
            self,
            selector: #selector(liveScrollWillStart(_:)),
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        center.addObserver(
            self,
            selector: #selector(liveScrollDidEnd(_:)),
            name: NSScrollView.didEndLiveScrollNotification,
            object: scrollView
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Services-menu support: advertise the pasteboard types this view can
    /// provide (selection) and accept (editable). Overridden here — not in an
    /// extension — because Swift requires overrides in the class body.
    override func validRequestor(
        forSendType sendType: NSPasteboard.PasteboardType?,
        returnType: NSPasteboard.PasteboardType?
    ) -> Any? {
        let hasSelection = selectedRange().length > 0
        let sendOK: Bool
        if let sendType {
            sendOK = hasSelection && writablePasteboardTypes.contains(sendType)
        } else {
            sendOK = true
        }
        let returnOK: Bool
        if let returnType {
            returnOK = isEditable && readablePasteboardTypes.contains(returnType)
        } else {
            returnOK = true
        }
        if sendOK && returnOK { return self }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    /// Context menu: standard editing commands plus spelling suggestions.
    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let contentPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let hasSelection = selectedRange().length > 0
        if !hasSelection,
           let location = textLayoutManager.caretLocation(
               interactingAt: contentPoint,
               options: .allowOutside,
               inContainerAt: textLayoutManager.documentRange.location
           ) {
            setSelectedTextRange(NSTextRange(location: location))
        }

        let menu = NSMenu()
        if isEditable {
            menu.addItem(withTitle: NSLocalizedString("Cut", comment: ""), action: #selector(cut(_:)), keyEquivalent: "")
            menu.addItem(withTitle: NSLocalizedString("Copy", comment: ""), action: #selector(copy(_:)), keyEquivalent: "")
            menu.addItem(withTitle: NSLocalizedString("Paste", comment: ""), action: #selector(paste(_:)), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: NSLocalizedString("Copy", comment: ""), action: #selector(copy(_:)), keyEquivalent: "")
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: NSLocalizedString("Select All", comment: ""), action: #selector(selectAll(_:)), keyEquivalent: "")
        appendSpellingMenuItems(to: menu, at: contentPoint)
        return menu
    }

    @objc private func clipViewBoundsDidChange(_ notification: Notification) {
        needsLayout = true
    }

    // MARK: - Testing hook

    /// Drives a full layout pass without requiring the view to be in a window.
    /// Unit tests exercise the real viewport pipeline headlessly through this.
    func performFullLayoutForTesting() {
        layout()
    }

    /// The fragment views currently backing the visible viewport. Diagnostic
    /// access for unit tests (the view does not rely on them externally).
    var renderedFragmentViews: [MarkdownTextFragmentView] {
        contentViewportView.subviews.compactMap { $0 as? MarkdownTextFragmentView }
    }

    /// The caret indicator views currently in the content view. Diagnostic
    /// access for unit tests.
    var insertionPointViews: [MarkdownInsertionPointView] {
        contentView.subviews.compactMap { $0 as? MarkdownInsertionPointView }
    }
}

// MARK: - NSTextViewportLayoutControllerDelegate
//
// The delegate protocol is not actor-isolated (legacy AppKit), so the
// conformance itself is declared `@MainActor`-isolated (SE-0466). The
// controller only ever calls in from the main runloop.

extension MarkdownTextView: @MainActor NSTextViewportLayoutControllerDelegate {

    func viewportBounds(for textViewportLayoutController: NSTextViewportLayoutController) -> CGRect {
        var viewportBounds = contentViewportView.visibleRect
        if viewportBounds.size == .zero || viewportBounds.isInfinite {
            viewportBounds = contentViewportView.bounds
        }

        // Keep a prefetch band around the visible area so small scrolls reuse
        // the current TextKit viewport instead of re-laying out.
        let verticalPrefetch = max(viewportBounds.height * 0.5, 0)
        let upwardPrefetch = min(verticalPrefetch, viewportBounds.minY)
        viewportBounds.origin.y -= upwardPrefetch
        viewportBounds.size.height += upwardPrefetch + verticalPrefetch

        viewportBounds.origin.x = 0
        viewportBounds.size.width = contentViewportView.bounds.width
        return viewportBounds
    }

    func textViewportLayoutControllerWillLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        unusedFragmentViews = Set(fragmentViewMap.objectEnumerator()?.allObjects as? [MarkdownTextFragmentView] ?? [])
    }

    func textViewportLayoutController(
        _ textViewportLayoutController: NSTextViewportLayoutController,
        configureRenderingSurfaceFor textLayoutFragment: NSTextLayoutFragment
    ) {
        let fragmentView: MarkdownTextFragmentView
        if let cached = fragmentViewMap.object(forKey: textLayoutFragment) {
            fragmentView = cached
            unusedFragmentViews.remove(cached)
        } else {
            fragmentView = MarkdownTextFragmentView(
                layoutFragment: textLayoutFragment,
                frame: textLayoutFragment.layoutFragmentFrame
            )
            fragmentViewMap.setObject(fragmentView, forKey: textLayoutFragment)
        }

        syncInvisibleCharacterState(textLayoutFragment)

        fragmentView.frame = textLayoutFragment.layoutFragmentFrame
        if fragmentView.superview != contentViewportView {
            contentViewportView.addSubview(fragmentView)
        }
    }

    func textViewportLayoutControllerDidLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        for staleView in unusedFragmentViews {
            staleView.removeFromSuperview()
            fragmentViewMap.removeObject(forKey: staleView.layoutFragment)
        }
        unusedFragmentViews.removeAll(keepingCapacity: true)
        // The bands are clamped to the viewport, so a re-wrap or a scroll
        // changes which parts of the selection need a band.
        selectionView.updateHighlights()
        updateInsertionPointStateAndRestartTimer()
    }

    func textViewportLayoutControllerReceivedSetNeedsLayout(_ textViewportLayoutController: NSTextViewportLayoutController) {
        needsLayout = true
    }
}

// MARK: - Flipped containers

final class MarkdownContentView: NSView {
    override var isFlipped: Bool { true }

    /// Tiled backing keeps redraw cost bounded for very long documents.
    /// Nothing is drawn into this layer itself, so its tiles never need
    /// invalidating (the selection lives in `MarkdownSelectionView`).
    override func makeBackingLayer() -> CALayer {
        CATiledLayer()
    }
}

/// Hosts the selection highlight bands. Sits between `contentView` and the
/// fragment views so the bands render below the glyphs, in the same flipped
/// coordinate space as the text layout.
///
/// Each band is a small layer-backed subview rather than a `draw(_:)` of the
/// full-size container: the view spans the whole (potentially very long)
/// document, so drawing into it would allocate a document-sized backing store
/// while the tiled `contentView` deliberately avoids exactly that. It is also
/// *not* tiled itself, because a `CATiledLayer` ignores `needsDisplay`-style
/// invalidation, which made the selection invisible in the first place.
final class MarkdownSelectionView: NSView {
    weak var textView: MarkdownTextView?

    /// One band per selection rect; pooled across selection changes.
    private(set) var highlightViews: [MarkdownSelectionHighlightView] = []

    override var isFlipped: Bool { true }

    /// Rebuilds the bands from the text view's current selection. Called on
    /// every selection change and again after layout (re-wraps move them).
    func updateHighlights() {
        guard let textView else { return }
        let rects = textView.visibleTextSelectionRects
        let color = textView.selectionBackgroundColor

        while highlightViews.count < rects.count {
            let highlight = MarkdownSelectionHighlightView(frame: .zero)
            addSubview(highlight)
            highlightViews.append(highlight)
        }
        for (index, highlight) in highlightViews.enumerated() {
            guard index < rects.count, color != nil else {
                highlight.isHidden = true
                continue
            }
            highlight.frame = rects[index]
            highlight.backgroundColor = color
            highlight.isHidden = false
        }
    }
}

/// One selection band. Pure decoration: it never draws and never takes hits,
/// so text interaction is untouched.
final class MarkdownSelectionHighlightView: NSView {
    var backgroundColor: NSColor? {
        didSet { layer?.backgroundColor = backgroundColor?.cgColor }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class MarkdownContentViewportView: NSView {
    override var isFlipped: Bool { true }

    override func makeBackingLayer() -> CALayer {
        CATiledLayer()
    }
}

fileprivate extension CGFloat {
    func isApproximatelyEqual(to other: CGFloat) -> Bool {
        abs(self - other) <= 0.5
    }
}