import AppKit
import SwiftUI

/// The Markdown editor pane, backed by the phase-3 `MarkdownTextView`.
///
/// SwiftUI's `TextEditor` uses AppKit's stock drag handling, which pastes the
/// *contents* of a dropped document into the editor and keeps the drop from
/// ever reaching the window's drop destination. `MarkdownTextView` intercepts
/// file drops and hands them to `onOpenFile`; text drops insert at the drop
/// location.
///
/// The text view hosts the two editor features governed by the Preferences:
/// live syntax highlighting (an `EditorTheme` applied to the text storage) and
/// the "smart editing" set (auto-completed matching characters, Return-key
/// list/blockquote/indent continuation, smart Home, and tab-to-spaces). Both
/// live in the coordinator, which drives the custom view through the
/// `EditorTextViewHost` surface (the same surface `NSTextView` also satisfies,
/// so the smart-editing helpers stay testable against AppKit's text view).
struct MarkdownEditorView: NSViewRepresentable {

    let text: String
    let fontName: String
    let fontSize: Double
    let lineSpacing: Double
    let editorTheme: EditorTheme
    /// Text padding inside the editor viewport.
    var horizontalInset: Double = 0
    var verticalInset: Double = 0
    /// Keep one viewport of space below the last line.
    var scrollsPastEnd = false
    /// Mark misspelled words with a dotted red underline.
    var spellChecking = true
    /// Show a line-number gutter in the editor margin.
    var showsLineNumbers = false
    /// Draw whitespace/newline symbols in the editor.
    var showsInvisibleCharacters = false

    // Smart editing preferences.
    let smartHome: Bool
    let convertTabsToSpaces: Bool
    let insertPrefixInBlock: Bool
    let autoIncrementNumberedLists: Bool
    let completeMatchingCharacters: Bool
    let strikethroughEnabled: Bool

    var onTextChange: (String) -> Void
    var onOpenFile: (URL) -> Void
    var onDragTargetingChanged: (Bool) -> Void
    /// The selection the surrounding UI wants the editor to show. The editor
    /// reports changes back through `onSelectionChange`.
    var selection: NSRange = NSRange(location: 0, length: 0)
    var onSelectionChange: (NSRange) -> Void = { _ in }
    var onFindAction: (NSFindPanelAction) -> Void = { _ in }

    /// Bumped by the document layer every time the whole buffer is replaced
    /// from disk (open/revert). The editor treats the accompanying text change
    /// as a document load: it replaces the text wholesale and clears its undo
    /// history instead of applying an undoable diff.
    var undoResetGeneration: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = false

        let host = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 1, height: 400))
        host.autoresizingMask = [.width]
        host.onOpenFile = onOpenFile
        host.onDragTargetingChanged = onDragTargetingChanged
        host.onSelectionChange = onSelectionChange
        host.onFindAction = onFindAction
        scrollView.documentView = host

        context.coordinator.setUp(host: host)
        syncSmartPreferences(to: context.coordinator)
        applyStyle(to: host, coordinator: context.coordinator)
        host.showsLineNumbers = showsLineNumbers
        host.showsInvisibleCharacters = showsInvisibleCharacters

        context.coordinator.isUpdatingFromModel = true
        host.string = text
        context.coordinator.isUpdatingFromModel = false
        host.setSelectedRange(NSRange(location: 0, length: 0))
        context.coordinator.applyHighlight()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let host = scrollView.documentView as? MarkdownTextView else { return }
        // Resize to the pane before touching the text so the wrap width (and
        // therefore the measured document height) is correct from the start.
        let contentWidth = scrollView.contentSize.width
        if contentWidth > 1, abs(host.frame.width - contentWidth) > 0.5 {
            host.setFrameSize(NSSize(width: contentWidth, height: host.frame.height))
        }
        host.onOpenFile = onOpenFile
        host.onDragTargetingChanged = onDragTargetingChanged
        host.onSelectionChange = onSelectionChange
        host.onFindAction = onFindAction
        context.coordinator.onTextChange = onTextChange
        context.coordinator.setUp(host: host)
        syncSmartPreferences(to: context.coordinator)
        applyStyle(to: host, coordinator: context.coordinator)
        if host.showsLineNumbers != showsLineNumbers {
            host.showsLineNumbers = showsLineNumbers
        }
        if host.showsInvisibleCharacters != showsInvisibleCharacters {
            host.showsInvisibleCharacters = showsInvisibleCharacters
        }

        let resetsDocument = undoResetGeneration != context.coordinator.appliedUndoResetGeneration
        if resetsDocument {
            context.coordinator.appliedUndoResetGeneration = undoResetGeneration
            host.resetUndoHistory()
        }

        if host.string != text {
            context.coordinator.isUpdatingFromModel = true
            if resetsDocument {
                // A load/revert replaces the whole document and re-stamps the
                // default attributes; not undoable.
                host.string = text
            } else {
                // A user-facing edit (Format command, find/replace, …) is
                // applied as a minimal undoable replacement so Cmd+Z/Cmd+⇧+Z
                // walk it back like any typing step.
                host.applyModelEdit(to: text, selection: clamped(selection, to: text))
            }
            context.coordinator.isUpdatingFromModel = false
            // Apply the selection the model asked for (e.g. the wrapped content
            // range after a Format command), not the pre-edit editor selection
            // clamped to the new text — the latter shifted by the inserted
            // markers and selected `*ABC` for `ABCD` -> `*ABCD*`.
            let target = clamped(selection, to: text)
            host.setSelectedRange(target)
            host.scrollRangeToVisible(target)
            context.coordinator.applyHighlight()
        } else if host.selectedRange() != selection {
            host.setSelectedRange(selection)
            host.scrollRangeToVisible(selection)
        }
    }

    private func syncSmartPreferences(to coordinator: Coordinator) {
        coordinator.smartHome = smartHome
        coordinator.convertTabsToSpaces = convertTabsToSpaces
        coordinator.insertPrefixInBlock = insertPrefixInBlock
        coordinator.autoIncrementNumberedLists = autoIncrementNumberedLists
        coordinator.completeMatchingCharacters = completeMatchingCharacters
        coordinator.strikethroughEnabled = strikethroughEnabled
    }

    // MARK: - Styling

    private func applyStyle(to host: MarkdownTextView, coordinator: Coordinator) {
        let fontChanged = coordinator.appliedFontName != fontName
            || coordinator.appliedFontSize != fontSize
        let spacingChanged = coordinator.appliedLineSpacing != lineSpacing
        let themeChanged = coordinator.appliedTheme != editorTheme
        let geometryChanged = coordinator.appliedHorizontalInset != horizontalInset
            || coordinator.appliedVerticalInset != verticalInset
            || coordinator.appliedScrollsPastEnd != scrollsPastEnd
        let spellChanged = host.isContinuousSpellCheckingEnabled != spellChecking
        guard fontChanged || spacingChanged || themeChanged || geometryChanged || spellChanged else { return }

        if geometryChanged {
            host.contentInsets = NSEdgeInsets(
                top: verticalInset,
                left: horizontalInset,
                bottom: verticalInset,
                right: horizontalInset
            )
            host.scrollsPastEnd = scrollsPastEnd
            coordinator.appliedHorizontalInset = horizontalInset
            coordinator.appliedVerticalInset = verticalInset
            coordinator.appliedScrollsPastEnd = scrollsPastEnd
        }

        if spellChanged {
            host.isContinuousSpellCheckingEnabled = spellChecking
        }

        guard fontChanged || spacingChanged || themeChanged else { return }

        let font = FontResolver.editorFont(named: fontName, size: fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing

        host.font = font
        host.defaultParagraphStyle = paragraph
        host.textColor = editorTheme.nsTextColor
        host.insertionPointColor = editorTheme.nsCursorColor
        host.backgroundColor = editorTheme.nsBackgroundColor
        host.selectionBackgroundColor = editorTheme.nsSelectionColor
        host.typingAttributes[.font] = font
        host.typingAttributes[.paragraphStyle] = paragraph

        coordinator.appliedFontName = fontName
        coordinator.appliedFontSize = fontSize
        coordinator.appliedLineSpacing = lineSpacing
        coordinator.appliedTheme = editorTheme

        coordinator.applyHighlight()
    }

    private func clamped(_ range: NSRange, to text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(range.location, length)
        let rangeLength = min(range.length, length - location)
        return NSRange(location: max(0, location), length: max(0, rangeLength))
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject {
        var onTextChange: (String) -> Void
        weak var host: MarkdownTextView?
        var isUpdatingFromModel = false

        // Applied-style bookkeeping (only re-highlight when these change).
        var appliedFontName = ""
        var appliedFontSize: Double = 0
        var appliedLineSpacing: Double = 0
        var appliedTheme: EditorTheme?
        var appliedHorizontalInset: Double = -1
        var appliedVerticalInset: Double = -1
        var appliedScrollsPastEnd = false
        /// The last `undoResetGeneration` the host consumed (document load/revert
        /// resets). Seeded so the first render with generation 0 is a no-op.
        var appliedUndoResetGeneration = 0

        // Smart editing behavior.
        var smartHome = false
        var convertTabsToSpaces = false
        var insertPrefixInBlock = false
        var autoIncrementNumberedLists = false
        var completeMatchingCharacters = false
        var strikethroughEnabled = false

        var editorTheme: EditorTheme { appliedTheme ?? .default }

        private enum S {
            static let insertTab = #selector(NSResponder.insertTab(_:))
            static let insertBacktab = #selector(NSResponder.insertBacktab(_:))
            static let insertNewline = #selector(NSResponder.insertNewline(_:))
            static let deleteBackward = #selector(NSResponder.deleteBackward(_:))
            static let moveToLeftEndOfLine = #selector(NSResponder.moveToLeftEndOfLine(_:))
        }

        private var observesTextStorage = false

        init(onTextChange: @escaping (String) -> Void) {
            self.onTextChange = onTextChange
        }

        // MARK: - Host wiring

        /// Installs command interception and the text-change observation on the
        /// host. Idempotent across SwiftUI view updates.
        func setUp(host: MarkdownTextView) {
            self.host = host
            host.shouldChangeTextHandler = { [weak self] range, replacement in
                self?.hostShouldChangeText(in: range, replacementString: replacement) ?? true
            }
            host.doCommandHandler = { [weak self] selector in
                self?.hostDoCommand(by: selector) ?? false
            }
            installTextStorageObservation(on: host)
        }

        private func installTextStorageObservation(on host: any EditorTextViewHost) {
            guard !observesTextStorage, let storage = host.textStorage else { return }
            observesTextStorage = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(hostTextDidProcessEditing(_:)),
                name: NSTextStorage.didProcessEditingNotification,
                object: storage
            )
        }

        /// The host broadcasts text changes through its storage; model-driven
        /// updates are suppressed via `isUpdatingFromModel`, so user edits are
        /// reported exactly once.
        @objc private func hostTextDidProcessEditing(_ note: Notification) {
            guard !isUpdatingFromModel,
                  let storage = note.object as? NSTextStorage,
                  storage.editedMask.contains(.editedCharacters),
                  let host
            else { return }
            onTextChange(host.string)
            applyHighlight()
            host.updateSpelling()
        }

        // MARK: - Command handling ("should" -> true means run the default).

        private func hostShouldChangeText(in range: NSRange, replacementString text: String?) -> Bool {
            guard let host else { return true }
            // Model-driven applications (format commands via `applyModelEdit`)
            // and undo/redo replays must never be vetoed or auto-completed:
            // their replacements are already final.
            if isUpdatingFromModel { return true }
            if host.undoManager?.isUndoing == true || host.undoManager?.isRedoing == true {
                return true
            }
            guard completeMatchingCharacters else { return true }
            // Ignore input-method (marked-text) regions.
            if Self.intersection(host.markedRange(), range).length > 0 {
                return true
            }
            let replacement = text ?? ""
            if host.completeMatchingCharacters(
                forRange: range,
                replacementString: replacement,
                strikethroughEnabled: strikethroughEnabled
            ) {
                return false
            }
            return true
        }

        private func hostDoCommand(by commandSelector: Selector) -> Bool {
            guard let host else { return false }
            switch commandSelector {
            case S.insertTab:
                return !shouldInsertTab(in: host)
            case S.insertBacktab:
                return !shouldInsertBacktab(in: host)
            case S.insertNewline:
                return !shouldInsertNewline(in: host)
            case S.deleteBackward:
                return !shouldDeleteBackward(in: host)
            case S.moveToLeftEndOfLine:
                return !shouldMoveToLeftEndOfLine(in: host)
            default:
                return false
            }
        }

        private func shouldInsertTab(in host: any EditorTextViewHost) -> Bool {
            if host.selectedRange().length != 0 {
                host.indentSelectedLines(padding: convertTabsToSpaces ? "    " : "\t")
                return false
            } else if convertTabsToSpaces {
                host.insertSpacesForTab()
                return false
            }
            return true
        }

        private func shouldInsertBacktab(in host: any EditorTextViewHost) -> Bool {
            host.unindentSelectedLines()
            return false
        }

        private func shouldInsertNewline(in host: any EditorTextViewHost) -> Bool {
            if insertPrefixInBlock {
                if host.completeNextListItem(autoIncrement: autoIncrementNumberedLists) {
                    return false
                }
                if host.completeNextBlockquoteLine() {
                    return false
                }
            }
            if host.completeNextIndentedLine() {
                return false
            }
            return true
        }

        private func shouldDeleteBackward(in host: any EditorTextViewHost) -> Bool {
            if completeMatchingCharacters {
                let location = host.selectedRange().location
                if host.deleteMatchingCharactersAround(location) {
                    return false
                }
            }
            if convertTabsToSpaces, host.selectedRange().length == 0 {
                let location = host.selectedRange().location
                if host.unindentForSpacesBefore(location) {
                    return false
                }
            }
            return true
        }

        private func shouldMoveToLeftEndOfLine(in host: any EditorTextViewHost) -> Bool {
            guard smartHome else { return true }
            guard let location = host.smartHomeLocation() else { return true }
            host.setSelectedRange(NSRange(location: location, length: 0))
            return false
        }

        // MARK: - Highlighting

        func applyHighlight() {
            guard let storage = host?.textStorage, storage.length > 0 else { return }
            let font = (host?.typingAttributes[.font] as? NSFont)
                ?? .monospacedSystemFont(ofSize: 14, weight: .regular)
            let paragraph = (host?.typingAttributes[.paragraphStyle] as? NSParagraphStyle)
                ?? NSParagraphStyle.default
            MarkdownSyntaxHighlighter(theme: editorTheme).apply(
                to: storage, font: font, paragraphStyle: paragraph
            )
            // Re-applying fonts/paragraph styles across the whole document
            // invalidates the TextKit layout, which collapses
            // `usageBoundsForTextContainer` to a partial estimate. Without
            // forcing a full re-measure the document view shrinks (the editor's
            // scrollbar gets too long) until a later live-scroll happens to
            // correct it.
            host?.needsFullHeightMeasurement = true
            host?.needsLayout = true
        }

        private static func intersection(_ a: NSRange, _ b: NSRange) -> NSRange {
            let location = max(a.location, b.location)
            let aEnd = a.location + a.length
            let bEnd = b.location + b.length
            let end = min(aEnd, bEnd)
            guard end > location else { return NSRange(location: 0, length: 0) }
            return NSRange(location: location, length: end - location)
        }
    }
}

// MARK: - Test hook