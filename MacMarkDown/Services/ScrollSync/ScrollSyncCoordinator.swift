import Foundation
import Observation

/// Write-side bridge for a single scroll pane. A pane's `ScrollSyncPane`
/// representable installs its `applyOffsetY` closure here once it has
/// introspected its underlying `NSScrollView`/`NSTextView`.
@MainActor
final class PaneDriver {
    var applyOffsetY: ((CGFloat) -> Void)?
    /// Editor-only: measures anchor Y positions for the given 1-based source
    /// lines from the real `NSTextView` layout, returning `nil` while the text
    /// view does not yet reflect the expected text. `forceLayout` performs a
    /// full layout; otherwise the measurement is cached by layout signature.
    var measureAnchors: ((String, [Int], CGFloat, CGFloat, Bool) -> [CGFloat]?)?

    /// Set by the pane while a live scroll gesture (scrollbar drag, trackpad or
    /// wheel) is active. Anchors cannot move during a pure scroll, so the
    /// coordinator skips re-measuring them on every tick until the gesture ends.
    var isLiveScrolling = false

    /// Fired when the pane's live scroll gesture begins/ends. The coordinator
    /// freezes its mapping inputs (anchors + content heights) for the duration,
    /// then re-measures once the gesture ends.
    var onLiveScrollBegan: (() -> Void)?
    var onLiveScrollEnded: (() -> Void)?

    init() {}
}

/// Glues the editor and preview panes together: observes both scroll positions
/// and drives each pane from the other using `ScrollSyncService`.
///
/// Sync is one-way (editor → preview) by default: the editor is the sole
/// master and the preview never feeds back. When `isBidirectional` is enabled,
/// *only a genuine user gesture* on the preview drives the editor — programmatic
/// preview scrolls are recognised as echoes (synchronously via `isSyncing`, and
/// asynchronously by the last commanded target) so the panes never fight.
///
/// During a live gesture the mapping inputs are frozen (anchors and content
/// heights), so a document whose lazily-measured height settles mid-scroll
/// cannot make the mapping jump or reverse.
@MainActor
final class ScrollSyncCoordinator {

    let service = ScrollSyncService()

    let editor = PaneDriver()
    let preview = PaneDriver()

    /// When true, a user scroll gesture on the preview also drives the editor
    /// (off by default).
    var isBidirectional = false

    private var editorOffset: CGFloat = 0
    private var editorContentHeight: CGFloat = 0
    private var editorVisibleHeight: CGFloat = 0

    private var previewOffset: CGFloat = 0
    private var previewContentHeight: CGFloat = 0
    private var previewVisibleHeight: CGFloat = 0

    private var currentText = ""
    /// 1-based source lines of the parser's anchors (editor side).
    private var currentAnchorLines: [Int] = []
    private var editorReady = false
    private var previewReady = false
    private var isSyncing = false

    /// Live gesture state. While `isGestureActive` the mapping uses the frozen
    /// heights captured at gesture start. `isPreviewGestureActive` gates the
    /// bidirectional path so only real preview gestures drive the editor.
    private var isGestureActive = false
    private var isPreviewGestureActive = false
    private var frozenEditorContentHeight: CGFloat = 0
    private var frozenEditorVisibleHeight: CGFloat = 0
    private var frozenPreviewContentHeight: CGFloat = 0
    private var frozenPreviewVisibleHeight: CGFloat = 0

    /// The last offset we commanded the preview/editor to. The resulting scroll
    /// may be reported asynchronously, after `isSyncing` has been reset, so the
    /// echo is recognised by value (clamped to the pane's scrollable range).
    private var programmaticPreviewTarget: CGFloat?
    private var programmaticEditorTarget: CGFloat?
    private static let echoTolerance: CGFloat = 2

    // MARK: - Lifecycle

    func install() {
        editor.onLiveScrollBegan = { [weak self] in self?.beginGesture() }
        editor.onLiveScrollEnded = { [weak self] in self?.endGesture(resyncPreview: true) }
        preview.onLiveScrollBegan = { [weak self] in
            self?.beginGesture()
            self?.isPreviewGestureActive = true
        }
        preview.onLiveScrollEnded = { [weak self] in
            self?.isPreviewGestureActive = false
            // A preview gesture must not snap the preview back to the editor:
            // in one-way mode the user may park the preview anywhere, and in
            // bidirectional mode the preview was the master. Just re-measure.
            self?.endGesture(resyncPreview: false)
        }
    }

    /// Called when a new parse produced a new anchor list. The editor anchors
    /// are re-measured against the (possibly new) layout and the preview is
    /// re-synced.
    func anchorsDidChange(lines: [Int]) {
        currentAnchorLines = lines
        refreshEditorAnchors(forceLayout: true)
        syncPreview()
        scheduleDeferredAnchorRefresh()
    }

    func textDidChange(_ newText: String) {
        currentText = newText
        scheduleDeferredAnchorRefresh()
    }

    func editorDidScroll(offsetY: CGFloat, contentHeight: CGFloat, visibleHeight: CGFloat) {
        editorOffset = offsetY
        editorContentHeight = contentHeight
        editorVisibleHeight = visibleHeight
        editorReady = contentHeight > 0 && visibleHeight > 0

        // A programmatic editor scroll (from a preview gesture) echoes back
        // synchronously; ignore it so the panes don't fight.
        guard !isSyncing else { return }
        if consumeProgrammaticEditorEcho(offsetY) { return }
        // During a live gesture the layout is unchanged, so the cached anchor
        // positions remain valid. Re-measuring every tick materializes the
        // whole document string and re-checks its layout signature; skip it
        // and let the post-gesture report refresh them.
        if !isGestureActive {
            refreshEditorAnchors(forceLayout: false)
        }
        syncPreview()
    }

    func previewDidScroll(offsetY: CGFloat, contentHeight: CGFloat, visibleHeight: CGFloat) {
        previewOffset = offsetY
        previewContentHeight = contentHeight
        previewVisibleHeight = visibleHeight
        previewReady = contentHeight > 0 && visibleHeight > 0

        guard !isSyncing else { return }
        // Drop the asynchronous echo of a preview command we issued ourselves.
        if consumeProgrammaticPreviewEcho(offsetY) { return }
        // Only a genuine user gesture on the preview may drive the editor.
        guard isBidirectional, isPreviewGestureActive, editorReady, previewReady else { return }
        syncEditor()
    }

    func previewAnchorsDidChange(_ anchors: [CGFloat]) {
        service.updatePreviewAnchors(anchors)
        // Anchor positions cannot change during a scroll; ignore mid-gesture
        // updates so the frozen mapping stays consistent.
        guard !isSyncing, !isGestureActive else { return }
        syncPreview()
    }

    // MARK: - Gesture freezing

    private func beginGesture() {
        guard !isGestureActive else { return }
        isGestureActive = true
        frozenEditorContentHeight = editorContentHeight
        frozenEditorVisibleHeight = editorVisibleHeight
        frozenPreviewContentHeight = previewContentHeight
        frozenPreviewVisibleHeight = previewVisibleHeight
    }

    private func endGesture(resyncPreview: Bool) {
        guard isGestureActive else { return }
        isGestureActive = false
        // The post-gesture report carries the settled heights; re-measure the
        // anchors against the (possibly corrected) layout.
        refreshEditorAnchors(forceLayout: true)
        if resyncPreview {
            syncPreview()
        }
    }

    // MARK: - Scroll computation

    private func syncPreview() {
        guard editorReady, previewReady else { return }
        let target = service.previewOffset(
            forEditorOffset: editorOffset,
            editorContentHeight: mappedEditorContentHeight,
            editorVisibleHeight: mappedEditorVisibleHeight,
            previewContentHeight: mappedPreviewContentHeight,
            previewVisibleHeight: mappedPreviewVisibleHeight
        )
        apply(target: target, to: .preview)
    }

    private func syncEditor() {
        let target = service.editorOffset(
            forPreviewOffset: previewOffset,
            previewContentHeight: mappedPreviewContentHeight,
            previewVisibleHeight: mappedPreviewVisibleHeight,
            editorContentHeight: mappedEditorContentHeight,
            editorVisibleHeight: mappedEditorVisibleHeight
        )
        apply(target: target, to: .editor)
    }

    // A pane may not have reported its metrics before the gesture begins (the
    // very first gesture on a fresh window); fall back to the live value rather
    // than freezing a bogus zero.
    private var mappedEditorContentHeight: CGFloat {
        isGestureActive && frozenEditorContentHeight > 0 ? frozenEditorContentHeight : editorContentHeight
    }

    private var mappedEditorVisibleHeight: CGFloat {
        isGestureActive && frozenEditorVisibleHeight > 0 ? frozenEditorVisibleHeight : editorVisibleHeight
    }

    private var mappedPreviewContentHeight: CGFloat {
        isGestureActive && frozenPreviewContentHeight > 0 ? frozenPreviewContentHeight : previewContentHeight
    }

    private var mappedPreviewVisibleHeight: CGFloat {
        isGestureActive && frozenPreviewVisibleHeight > 0 ? frozenPreviewVisibleHeight : previewVisibleHeight
    }

    private func apply(target: CGFloat, to pane: Pane) {
        guard !isSyncing else { return }
        isSyncing = true
        switch pane {
        case .editor:
            let clamped = min(max(0, target), max(0, mappedEditorContentHeight - mappedEditorVisibleHeight))
            if abs(clamped - editorOffset) > Self.echoTolerance {
                programmaticEditorTarget = clamped
                scheduleClearEditorEcho(clamped)
            }
            editor.applyOffsetY?(target)
        case .preview:
            let clamped = min(max(0, target), max(0, mappedPreviewContentHeight - mappedPreviewVisibleHeight))
            // A command that does not move the pane produces no echo; noting it
            // would swallow a later, legitimate report at that offset.
            if abs(clamped - previewOffset) > Self.echoTolerance {
                programmaticPreviewTarget = clamped
                scheduleClearPreviewEcho(clamped)
            }
            preview.applyOffsetY?(target)
        }
        isSyncing = false
    }

    // MARK: - Echo recognition

    /// Returns `true` when `offsetY` is the asynchronous echo of a preview
    /// scroll we commanded ourselves.
    private func consumeProgrammaticPreviewEcho(_ offsetY: CGFloat) -> Bool {
        guard let target = programmaticPreviewTarget else { return false }
        programmaticPreviewTarget = nil
        return abs(offsetY - target) <= Self.echoTolerance
    }

    /// Returns `true` when `offsetY` is the asynchronous echo of an editor
    /// scroll we commanded ourselves (bidirectional only).
    private func consumeProgrammaticEditorEcho(_ offsetY: CGFloat) -> Bool {
        guard let target = programmaticEditorTarget else { return false }
        programmaticEditorTarget = nil
        return abs(offsetY - target) <= Self.echoTolerance
    }

    /// Clears the pending echo once a run loop turn has passed, so a command
    /// whose target was clamped (and therefore never reported verbatim) cannot
    /// block a later genuine scroll.
    private func scheduleClearPreviewEcho(_ target: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.programmaticPreviewTarget == target else { return }
            self.programmaticPreviewTarget = nil
        }
    }

    private func scheduleClearEditorEcho(_ target: CGFloat) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.programmaticEditorTarget == target else { return }
            self.programmaticEditorTarget = nil
        }
    }

    private enum Pane {
        case editor
        case preview
    }

    private func refreshEditorAnchors(forceLayout: Bool) {
        guard !currentAnchorLines.isEmpty else {
            service.updateEditorAnchors([])
            return
        }
        guard let measure = editor.measureAnchors,
              let measured = measure(
                  currentText, currentAnchorLines,
                  editorContentHeight, editorVisibleHeight, forceLayout
              )
        else { return }
        service.updateEditorAnchors(measured)
    }

    /// A text edit reaches the underlying `NSTextView` a render step later;
    /// re-measure the anchors once it has settled (font/wrap changes alter all
    /// subsequent anchor positions).
    private func scheduleDeferredAnchorRefresh() {
        guard editor.measureAnchors != nil else { return }
        let text = currentText
        let lines = currentAnchorLines
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self, self.currentText == text, self.currentAnchorLines == lines else { return }
            self.refreshEditorAnchors(forceLayout: true)
            self.syncPreview()
        }
    }
}
