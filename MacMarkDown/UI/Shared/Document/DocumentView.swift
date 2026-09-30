import Combine
import SwiftUI
import UniformTypeIdentifiers

/// The main document view: editor + preview in a split layout, backed by a
/// `MarkdownDocument`. Handles the toolbar, word-count bar, and the
/// synchronized scroll between the two panes.
public struct DocumentView: View {

    @State private var document: MarkdownDocument
    @State private var editorColumnVisible = true
    @State private var previewColumnVisible = true
    @State private var splitRatio: Double = 0.5
    @State private var dragStartRatio: Double?
    @State private var scrollSync = ScrollSyncCoordinator()
    @State private var isDropTargeted = false
    @State private var openErrorMessage: String?

    /// Protects unsaved edits on window close (the app keeps running with no
    /// window, so a close is as destructive as a quit).
    @State private var closeGuard = UnsavedChangesGuard()

    /// Stable identity of this window in the multi-window session registry.
    @State private var windowID = UUID()

    /// Set when the "Suppress Untitled on Launch" preference applies to this
    /// window; the window closes once it knows its `NSWindow`.
    @State private var suppressesBlankWindow = false

    /// The hosting `NSWindow`, reported by `WindowAccessor`. Commands act on
    /// the key window only.
    @State private var windowReference = WindowReference()

    /// The editor's selection, mirrored so the formatting toolbar operates on
    /// the caret/selection instead of the document start.
    @State private var editorSelection = NSRange(location: 0, length: 0)

    /// Bumped whenever the whole buffer is replaced from disk (open/revert),
    /// so the editor clears its undo history alongside the text swap.
    @State private var undoResetGeneration = 0

    /// Find/replace state, driven by the Edit > Find menu and the find bar.
    @State private var find = FindController()
    @State private var isShowingFindBar = false

    // Save / open pipeline state.
    @State private var isShowingUnsavedPrompt = false
    @State private var unsavedAction: (() -> Void)?
    @State private var isShowingConflictAlert = false
    @State private var conflictURL: URL?

    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow

    @Environment(Preferences.self) private var preferences

    /// Minimum width either pane may shrink to while dragging the divider.
    private let minimumPaneWidth: CGFloat = 200
    /// Hit area of the draggable divider between the two panes.
    private let dividerHitWidth: CGFloat = 8

    public init(document: MarkdownDocument = MarkdownDocument()) {
        _document = State(initialValue: document)
    }

    public var body: some View {
        attachDocumentChrome(
            GeometryReader { proxy in
                let showsBoth = editorColumnVisible && previewColumnVisible
                let available = showsBoth
                    ? max(0, proxy.size.width - dividerHitWidth)
                    : proxy.size.width
                HStack(spacing: 0) {
                    if preferences.editorOnRight {
                        previewColumn(available: available, showsBoth: showsBoth)
                        if showsBoth {
                            PaneDivider()
                                .frame(width: dividerHitWidth)
                                .gesture(dividerGesture(available: available))
                        }
                        editorColumn(available: available, showsBoth: showsBoth)
                    } else {
                        editorColumn(available: available, showsBoth: showsBoth)
                        if showsBoth {
                            PaneDivider()
                                .frame(width: dividerHitWidth)
                                .gesture(dividerGesture(available: available))
                        }
                        previewColumn(available: available, showsBoth: showsBoth)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .navigationTitle(windowTitle)
            .onChange(of: preferences.editorOnRight) { _, _ in
                resetSplitIfBothVisible()
            }
            .onChange(of: preferences.editorSyncScrolling) { _, isEnabled in
                scrollSync.service.isEnabled = isEnabled
            }
            .onChange(of: preferences.editorBidirectionalScrollSync) { _, isBidirectional in
                scrollSync.isBidirectional = isBidirectional
            }
            .onAppear {
                scrollSync.install()
                scrollSync.service.isEnabled = preferences.editorSyncScrolling
                scrollSync.isBidirectional = preferences.editorBidirectionalScrollSync
            }
            .toolbar {
                ToolbarItemGroup {
                    ToolbarView(
                        text: Binding(
                            get: { document.text },
                            set: { document.updateText($0) }
                        ),
                        selection: $editorSelection,
                        preferences: preferences,
                        onTogglePreview: { toggleEditor() },
                        onToggleEditor: { togglePreview() },
                        onExportHTML: { exportHTML() },
                        onManualRender: { document.renderService.parseNow(text: document.text, options: preferences.parseOptions) }
                    )
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                openDroppedFiles(urls)
            } isTargeted: { isTargeted in
                isDropTargeted = isTargeted
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.accentColor, lineWidth: 3)
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
        )
    }

    // MARK: - Panes

    /// The editor column: applies pane visibility, the split share and the
    /// optional width limit.
    @ViewBuilder
    private func editorColumn(available: CGFloat, showsBoth: Bool) -> some View {
        if editorColumnVisible {
            editorPane
                .frame(width: showsBoth ? available * splitRatio : available)
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func previewColumn(available: CGFloat, showsBoth: Bool) -> some View {
        if previewColumnVisible {
            previewPane
                .frame(width: showsBoth ? available * (1 - splitRatio) : available)
                .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var editorPane: some View {
        if preferences.editorWidthLimited {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                editorContent
                    .frame(maxWidth: preferences.editorMaximumWidth)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            editorContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var editorContent: some View {
        ScrollSyncPane(
            driver: scrollSync.editor,
            onScroll: { metrics in
                scrollSync.editorDidScroll(
                    offsetY: metrics.offsetY,
                    contentHeight: metrics.contentHeight,
                    visibleHeight: metrics.visibleHeight
                )
            },
            measuresTextAnchors: true
        ) {
            VStack(spacing: 0) {
                MarkdownEditorView(
                    text: document.text,
                    fontName: preferences.editorBaseFontName,
                    fontSize: preferences.editorBaseFontSize,
                    lineSpacing: preferences.editorLineSpacing,
                    editorTheme: EditorTheme.theme(named: preferences.editorStyleName),
                    horizontalInset: preferences.editorHorizontalInset,
                    verticalInset: preferences.editorVerticalInset,
                    scrollsPastEnd: preferences.editorScrollsPastEnd,
                    spellChecking: preferences.editorSpellChecking,
                    showsLineNumbers: preferences.editorShowLineNumbers,
                    showsInvisibleCharacters: preferences.editorShowInvisibleCharacters,
                    smartHome: preferences.editorSmartHome,
                    convertTabsToSpaces: preferences.editorConvertTabs,
                    insertPrefixInBlock: preferences.editorInsertPrefixInBlock,
                    autoIncrementNumberedLists: preferences.editorAutoIncrementNumberedLists,
                    completeMatchingCharacters: preferences.editorCompleteMatchingCharacters,
                    strikethroughEnabled: preferences.extensionStrikethrough,
                    onTextChange: { document.updateText($0) },
                    onOpenFile: { openDocument(at: $0) },
                    onDragTargetingChanged: { isDropTargeted = $0 },
                    selection: editorSelection,
                    onSelectionChange: { editorSelection = $0 },
                    onFindAction: handleFindAction,
                    undoResetGeneration: undoResetGeneration
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: document.text) { _, newValue in
                    // Rendering itself is scheduled by `MarkdownDocument`
                    // (and skipped when manual render is on); this only keeps
                    // scroll sync, find matches and word count current.
                    scrollSync.textDidChange(newValue)
                    find.updateText(newValue)
                }
                .onChange(of: document.renderService.anchors) { _, newAnchors in
                    scrollSync.anchorsDidChange(lines: newAnchors.map(\.line))
                }
                WordCountBar(documents: text, preferences: preferences)
                    .frame(height: preferences.editorShowWordCount ? 28 : 0)
                    .opacity(preferences.editorShowWordCount ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if isShowingFindBar {
                FindBar(
                    find: find,
                    onNext: { selectMatch(forward: true) },
                    onPrevious: { selectMatch(forward: false) },
                    onReplace: replaceCurrentMatch,
                    onReplaceAll: replaceAllMatches,
                    onClose: { isShowingFindBar = false }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Find / replace

    /// Handles the standard Edit > Find actions forwarded by the editor.
    private func handleFindAction(_ action: NSFindPanelAction) {
        find.updateText(document.text)
        switch action {
        case .showFindPanel:
            find.showsReplace = false
            isShowingFindBar = true
        case .replace, .replaceAndFind:
            // The standard Find submenu's "Replace…" item opens the bar with
            // the replacement field visible.
            find.showsReplace = true
            isShowingFindBar = true
        case .next:
            selectMatch(forward: true)
        case .previous:
            selectMatch(forward: false)
        case .replaceAll:
            replaceAllMatches()
        case .setFindString:
            if editorSelection.length > 0,
               let range = EditorTextRange.range(from: editorSelection, in: document.text) {
                find.query = String(document.text[range])
            }
            isShowingFindBar = true
        default:
            break
        }
    }

    /// Selects the next/previous match, starting from the editor's caret.
    private func selectMatch(forward: Bool) {
        find.updateText(document.text)
        let match = forward
            ? find.nextMatch(after: editorSelection.location)
            : find.previousMatch(before: editorSelection.location)
        if let match {
            editorSelection = match
        }
    }

    private func replaceCurrentMatch() {
        guard let result = find.replaceCurrent(in: document.text) else { return }
        document.updateText(result.text)
        find.updateText(result.text)
        editorSelection = result.selection
    }

    private func replaceAllMatches() {
        guard let result = find.replaceAll(in: document.text) else { return }
        document.updateText(result.text)
        find.updateText(result.text)
    }

    @ViewBuilder
    private var previewPane: some View {
        VStack(spacing: 0) {
            PreviewPane(
                elements: document.renderService.elements,
                anchors: document.renderService.anchors,
                theme: preferences.previewTheme,
                driver: scrollSync.preview,
                baseURL: previewBaseURL,
                highlightsCode: preferences.htmlSyntaxHighlighting,
                lineNumbers: preferences.htmlLineNumbers,
                codeBlockAccessory: preferences.htmlCodeBlockAccessory,
                highlightingThemeName: preferences.htmlHighlightingThemeName,
                rendersMath: preferences.htmlMathJax,
                rendersMermaid: preferences.htmlMermaid,
                rendersGraphviz: preferences.htmlGraphviz,
                zoom: PreviewZoom.factor(
                    enabled: preferences.previewZoomRelativeToBaseFontSize,
                    editorFontSize: preferences.editorBaseFontSize
                ),
                fontName: preferences.previewFontFamily,
                contentInsets: NSEdgeInsets(
                    top: preferences.editorVerticalInset,
                    left: preferences.editorHorizontalInset,
                    bottom: preferences.editorVerticalInset,
                    right: preferences.editorHorizontalInset
                ),
                createsLinkTargets: preferences.createFileForLinkTarget,
                onScroll: { metrics in
                    scrollSync.previewDidScroll(
                        offsetY: metrics.offsetY,
                        contentHeight: metrics.contentHeight,
                        visibleHeight: metrics.visibleHeight
                    )
                },
                onPreviewAnchors: { anchors in
                    scrollSync.previewAnchorsDidChange(anchors)
                },
                onOpenFile: { openDocument(at: $0) },
                onDragTargetingChanged: { isDropTargeted = $0 },
                usesTextSurface: preferences.previewUsesTextSurface
            )
            WordCountBar(documents: text, preferences: preferences)
                .frame(height: preferences.editorShowWordCount ? 28 : 0)
                .opacity(preferences.editorShowWordCount ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The draggable divider between two visible panes.
    private func dividerGesture(available: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartRatio == nil { dragStartRatio = splitRatio }
                let start = dragStartRatio ?? splitRatio
                let span = max(available, 1)
                let minimum = span > minimumPaneWidth * 2
                    ? minimumPaneWidth / span
                    : 0
                let proposed = start + value.translation.width / span
                splitRatio = min(max(proposed, minimum), 1 - minimum)
            }
            .onEnded { _ in
                dragStartRatio = nil
            }
    }

    /// Applies the window chrome — save/open alerts, File-menu and lifecycle
    /// notification handlers — on top of the split-view content. Kept as a
    /// single generic helper so the type checker bounds the whole modifier
    /// chain in one small expression instead of an enormous `body`.
    private func attachDocumentChrome<Content: View>(_ content: Content) -> some View {
        content
            .background {
                WindowAccessor { window in
                    windowReference.window = window
                    closeGuard.document = document
                    closeGuard.install(on: window)
                    TouchBarController.shared.attach(to: window)
                    DocumentSession.shared.updateWindow(id: windowID, window: window)
                    if suppressesBlankWindow,
                       document.isBlankAndUnedited,
                       !DocumentOpenQueue.shared.hasPending {
                        window.close()
                    }
                }
                .frame(width: 0, height: 0)
            }
            .alert(
                "Unable to Open File",
                isPresented: Binding(
                    get: { openErrorMessage != nil },
                    set: { if !$0 { openErrorMessage = nil } }
                ),
                presenting: openErrorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { message in
                Text(message)
            }
            .alert(
                "Unsaved Changes",
                isPresented: Binding(
                    get: { isShowingUnsavedPrompt },
                    set: { if !$0 { unsavedAction = nil } }
                )
            ) {
                Button("Save") { respondToUnsavedPrompt(save: true) }
                Button("Don’t Save", role: .destructive) { respondToUnsavedPrompt(save: false) }
                Button("Cancel", role: .cancel) { unsavedAction = nil }
            } message: {
                Text("Do you want to save the changes made to “\(document.displayTitle)”?")
            }
            .alert(
                "Document Changed on Disk",
                isPresented: Binding(
                    get: { isShowingConflictAlert },
                    set: {
                        if !$0 {
                            isShowingConflictAlert = false
                            conflictURL = nil
                        }
                    }
                ),
                presenting: conflictURL
            ) { url in
                Button("Save Anyway") {
                    try? document.save(to: url, checkConflict: false)
                }
                Button("Save a Copy…") { presentSavePanel { _ in } }
                Button("Revert to Saved") {
                    if (try? document.load(from: url)) != nil {
                        undoResetGeneration += 1
                        editorSelection = NSRange(location: 0, length: 0)
                        scrollSync.textDidChange(document.text)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: { url in
                Text("“\(url.lastPathComponent)” was modified by another program. What do you want to do?")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDocumentFiles)) { _ in
                guard windowReference.window?.isKeyWindow ?? true else { return }
                openPendingFile()
            }
            .modifier(DocumentCommandReceiver(
                newDocument: newDocument,
                openDocument: requestOpen,
                saveDocument: saveDocument,
                saveDocumentAs: saveDocumentAs,
                revertDocument: revertDocument,
                toggleEditor: toggleEditor,
                togglePreview: togglePreview,
                toggleToolbar: {
                    windowReference.window?.toolbar?.isVisible.toggle()
                },
                setSplitRatio: { ratio in
                    if !editorColumnVisible { editorColumnVisible = true }
                    if !previewColumnVisible { previewColumnVisible = true }
                    splitRatio = ratio
                },
                renderDocument: {
                    document.renderService.parseNow(text: document.text, options: preferences.parseOptions)
                },
                flushAutosave: { document.autosaveNow() },
                formatCommand: applyFormatCommand,
                exportHTML: exportHTML,
                exportPDF: exportPDF,
                printDocument: printDocument,
                copyHTML: copyHTML,
                openRecent: { url in openDocument(at: url) },
                isActive: { windowReference.window?.isKeyWindow ?? true }
            ))
            .onChange(of: preferences.markdownManualRender) { _, isManual in
                // Leaving manual mode catches the preview up with the buffer.
                if !isManual {
                    document.renderService.parseNow(text: document.text, options: preferences.parseOptions)
                }
            }
            .onAppear {
                DocumentSession.shared.openNewWindow = {
                    openWindow(id: Constants.mainWindowID)
                }
                let registeredDocument = document
                let registeredScrollSync = scrollSync
                DocumentSession.shared.register(
                    id: windowID,
                    document: registeredDocument,
                    window: windowReference.window
                ) { url in
                    // Finder/CLI routing only loads into blank windows, so no
                    // unsaved-changes guard is needed here.
                    do {
                        try registeredDocument.load(from: url)
                    } catch {
                        return
                    }
                    undoResetGeneration += 1
                    RecentDocumentsStore.shared.record(url)
                    registeredScrollSync.textDidChange(registeredDocument.text)
                    registeredScrollSync.editor.applyOffsetY?(0)
                    registeredScrollSync.preview.applyOffsetY?(0)
                }
                if DocumentSession.shared.suppressNextBlankWindow {
                    DocumentSession.shared.suppressNextBlankWindow = false
                    suppressesBlankWindow = true
                }
                RecentDocumentsStore.shared.pruneMissing()
                scrollSync.textDidChange(document.text)
                document.renderService.parseNow(text: document.text, options: preferences.parseOptions)
                scrollSync.anchorsDidChange(lines: document.renderService.anchors.map(\.line))
                openPendingFile()
            }
            .onDisappear {
                DocumentSession.shared.unregister(id: windowID)
                document.autosaveNow()
            }
    }

    /// The `NSWindow` backing this view, tracked for key-window command
    /// routing.
    @MainActor
    final class WindowReference {
        weak var window: NSWindow?
        init() {}
    }

    /// The window title, prefixed with an edit dot when the buffer is dirty.
    private var windowTitle: String {
        (document.isEdited ? "● " : "") + document.displayTitle
    }

    private var text: String { document.text }

    /// Directory used to resolve relative links/images. Saved documents use
    /// their own folder; unsaved ones fall back to the configured default
    /// directory.
    private var previewBaseURL: URL? {
        if let fileURL = document.fileURL {
            return fileURL.deletingLastPathComponent()
        }
        let path = preferences.htmlDefaultDirectoryUrl
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    // MARK: - Pane toggling

    private func togglePreview() {
        previewColumnVisible.toggle()
        if !editorColumnVisible && !previewColumnVisible {
            editorColumnVisible = true
        }
        resetSplitIfBothVisible()
    }

    private func toggleEditor() {
        editorColumnVisible.toggle()
        if !editorColumnVisible && !previewColumnVisible {
            previewColumnVisible = true
        }
        resetSplitIfBothVisible()
    }

    /// Restores an even split whenever both panes are visible, so toggling a
    /// pane off and back on never leaves the restored pane at minimum width.
    private func resetSplitIfBothVisible() {
        if editorColumnVisible && previewColumnVisible {
            splitRatio = 0.5
        }
    }



    // MARK: - Save / Open / New

    /// Runs a Format-menu command against the editor's current selection.
    private func applyFormatCommand(_ rawCommand: String) {
        guard let command = EditorFormatCommand(rawValue: rawCommand),
              let result = EditorFormatting.apply(
                  command,
                  to: document.text,
                  selection: editorSelection,
                  listMarker: preferences.editorUnorderedListMarker,
                  tabPadding: preferences.editorConvertTabs ? "    " : "\t"
              )
        else { return }
        document.updateText(result.text)
        editorSelection = result.selection
    }

    /// Saves the document, prompting for a location the first time.
    private func saveDocument() {
        guard let url = document.fileURL else {
            presentSavePanel { _ in }
            return
        }
        do {
            try document.save(to: url)
            RecentDocumentsStore.shared.record(url)
        } catch {
            if case MarkdownDocument.SaveError.fileChangedExternally = error {
                conflictURL = url
                isShowingConflictAlert = true
            } else {
                openErrorMessage = "The document couldn’t be saved."
            }
        }
    }

    private func saveDocumentAs() {
        presentSavePanel { _ in }
    }

    /// Cmd+N: opens a fresh window with a blank document (multi-window
    /// semantics; the old behavior reset the current window).
    private func newDocument() {
        DocumentSession.shared.requestNewWindow()
    }

    private func requestOpen() {
        runWithUnsavedGuard {
            presentOpenPanel()
        }
    }

    private func revertDocument() {
        guard let url = document.fileURL else { return }
        runWithUnsavedGuard {
            do {
                try document.load(from: url)
                undoResetGeneration += 1
                editorSelection = NSRange(location: 0, length: 0)
                scrollSync.textDidChange(document.text)
                scrollSync.editor.applyOffsetY?(0)
                scrollSync.preview.applyOffsetY?(0)
            } catch {
                openErrorMessage = "“\(url.lastPathComponent)” couldn’t be read as text."
            }
        }
    }

    /// Runs `action`, first asking the user to save when the buffer is dirty.
    private func runWithUnsavedGuard(_ action: @escaping () -> Void) {
        guard document.isEdited else {
            action()
            return
        }
        unsavedAction = action
        isShowingUnsavedPrompt = true
    }

    /// Resolves the "Unsaved Changes" alert: save (or discard) then continue.
    private func respondToUnsavedPrompt(save: Bool) {
        guard let action = unsavedAction else { return }
        if !save {
            unsavedAction = nil
            action()
            return
        }
        if let url = document.fileURL {
            do {
                try document.save(to: url)
                unsavedAction = nil
                action()
            } catch {
                unsavedAction = nil
                if case MarkdownDocument.SaveError.fileChangedExternally = error {
                    conflictURL = url
                    isShowingConflictAlert = true
                }
            }
        } else {
            presentSavePanel { saved in
                guard saved else { return }
                unsavedAction = nil
                action()
            }
        }
    }

    private func presentSavePanel(completion: @escaping (Bool) -> Void) {
        let panel = NSSavePanel()
        let types = markdownUTTypes
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }
        panel.nameFieldStringValue = document.displayTitle + ".md"
        guard let window = NSApp.keyWindow else {
            completion(false)
            return
        }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else {
                completion(false)
                return
            }
            do {
                try document.save(to: url)
                RecentDocumentsStore.shared.record(url)
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    private func presentOpenPanel() {
        let panel = NSOpenPanel()
        let types = markdownUTTypes
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }
        panel.allowsMultipleSelection = false
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            openDocument(at: url)
        }
    }

    private var markdownUTTypes: [UTType] {
        ["md", "markdown", "mdown", "mkd", "mkdn"].compactMap {
            UTType(filenameExtension: $0)
        }
    }

    // MARK: - Opening documents

    /// Handles files dropped anywhere on the document view.
    private func openDroppedFiles(_ urls: [URL]) -> Bool {
        guard let url = urls.first(where: \.isFileURL) else { return false }
        return openDocument(at: url)
    }

    /// Opens the file the Finder handed to the app ("Open With", double-click,
    /// a drop onto the Dock icon, or the CLI). Each new window takes one.
    private func openPendingFile() {
        guard let url = DocumentOpenQueue.shared.takeFirst() else { return }
        _ = openDocument(at: url)
    }

    /// Loads `url` into the current document, replacing its contents. If the
    /// current buffer is dirty the user is asked to save first.
    @discardableResult
    private func openDocument(at url: URL) -> Bool {
        guard !document.isEdited else {
            runWithUnsavedGuard {
                self.replaceDocument(with: url)
            }
            return true
        }
        return replaceDocument(with: url)
    }

    @discardableResult
    private func replaceDocument(with url: URL) -> Bool {
        do {
            try document.load(from: url)
        } catch {
            openErrorMessage = "“\(url.lastPathComponent)” couldn’t be read as text."
            return false
        }
        undoResetGeneration += 1
        editorSelection = NSRange(location: 0, length: 0)
        RecentDocumentsStore.shared.record(url)
        scrollSync.textDidChange(document.text)
        scrollSync.editor.applyOffsetY?(0)
        scrollSync.preview.applyOffsetY?(0)
        return true
    }

    // MARK: - Export

    private func exportHTML() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "html")!]
        panel.nameFieldStringValue = "\(document.displayTitle).html"

        // Export options: base styles and syntax highlighting are toggled
        // independently.
        let includeStyles = NSButton(checkboxWithTitle: "Include styles", target: nil, action: nil)
        includeStyles.state = .on
        let includeHighlighting = NSButton(checkboxWithTitle: "Include syntax highlighting", target: nil, action: nil)
        includeHighlighting.state = .on
        let accessory = NSStackView(views: [includeStyles, includeHighlighting])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        panel.accessoryView = accessory

        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            try? ExportService.exportHTML(
                text: document.text,
                title: document.displayTitle,
                theme: preferences.previewTheme,
                parser: document.parser,
                options: preferences.parseOptions,
                to: url,
                inlineStyles: includeStyles.state == .on,
                highlighting: includeHighlighting.state == .on
            )
        }
    }

    private func exportPDF() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "pdf")!]
        panel.nameFieldStringValue = "\(document.displayTitle).pdf"
        guard let window = NSApp.keyWindow else { return }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            ExportService.exportPDF(
                text: document.text,
                title: document.displayTitle,
                theme: preferences.previewTheme,
                options: preferences.parseOptions,
                to: url
            )
        }
    }

    private func printDocument() {
        ExportService.print(
            text: document.text,
            title: document.displayTitle,
            theme: preferences.previewTheme,
            options: preferences.parseOptions
        )
    }

    private func copyHTML() {
        ExportService.copyHTML(
            text: document.text,
            title: document.displayTitle,
            theme: preferences.previewTheme,
            parser: document.parser,
            options: preferences.parseOptions
        )
    }
}

// MARK: - Pane divider

/// A thin separator with a wide drag target, used between the editor and
/// preview panes in place of `HSplitView`'s implicit divider (whose remembered
/// per-child widths collapsed a pane whenever it was toggled back on).
private struct PaneDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                (hovering ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            }
    }
}

// MARK: - Preview pane

/// Preview scroll container.
///
/// The scroll position is owned by SwiftUI (`ScrollPosition` binding) instead
/// of poking the underlying `NSScrollView`: SwiftUI re-asserts its own state
/// at the end of a scroll gesture, which used to snap the preview back to the
/// top after the editor had driven it.
struct PreviewPane: View {
    let elements: [MarkdownElement]
    /// Ordered scroll anchors from the parser, paired 1:1 with the editor.
    var anchors: [DocumentAnchor] = []
    let theme: Theme
    let driver: PaneDriver
    /// Directory of the document, for resolving relative image paths.
    var baseURL: URL?
    /// Whether fenced code blocks are syntax highlighted.
    var highlightsCode: Bool = true
    /// Show a line-number gutter beside code blocks.
    var lineNumbers: Bool = false
    /// Code-block accessory: 0 = none, 1 = language name, 2 = custom.
    var codeBlockAccessory: Int = 1
    /// Code token palette name; empty follows the preview theme.
    var highlightingThemeName: String = ""
    var rendersMath: Bool = true
    var rendersMermaid: Bool = false
    var rendersGraphviz: Bool = false
    /// Preview scale relative to the editor base font.
    var zoom: CGFloat = 1
    /// The editor's font family; the preview renders its prose in it.
    var fontName: String = ""
    /// Padding between the pane edges and the text, matching the editor's
    /// horizontal and vertical insets.
    var contentInsets: NSEdgeInsets = NSEdgeInsets()
    /// Create missing local files when their links are clicked.
    var createsLinkTargets = false
    var onScroll: (ScrollMetrics) -> Void
    var onPreviewAnchors: (([CGFloat]) -> Void)?
    /// File drops on the preview open the document, matching the editor.
    var onOpenFile: ((URL) -> Void)?
    /// File-drop targeting entered/exited, to drive the drop highlight.
    var onDragTargetingChanged: ((Bool) -> Void)?
    /// Use the TextKit 2 text surface (selectable, ⌘A, copy-with-HTML) instead
    /// of the native SwiftUI element tree.
    var usesTextSurface = true

    @State private var position = ScrollPosition()

    @ViewBuilder
    var body: some View {
        if usesTextSurface {
            MarkdownPreviewSurface(
                elements: elements,
                anchors: anchors,
                theme: theme,
                driver: driver,
                baseURL: baseURL,
                zoom: zoom,
                fontName: fontName,
                rendersMath: rendersMath,
                contentInsets: contentInsets,
                onScroll: onScroll,
                onPreviewAnchors: onPreviewAnchors,
                onOpenFile: onOpenFile,
                onDragTargetingChanged: onDragTargetingChanged
            )
            .background(theme.backgroundColor)
        } else {
            legacyBody
        }
    }

    @ViewBuilder
    private var legacyBody: some View {
        ScrollView {
            MarkdownView(
                elements: elements,
                theme: theme,
                baseURL: baseURL,
                highlightsCode: highlightsCode,
                rendersMath: rendersMath,
                rendersMermaid: rendersMermaid,
                rendersGraphviz: rendersGraphviz,
                zoom: zoom,
                fontName: fontName,
                horizontalInset: contentInsets.left,
                verticalInset: contentInsets.top,
                createsLinkTargets: createsLinkTargets,
                anchors: anchors,
                onPreviewAnchors: onPreviewAnchors
            )
            // Skip re-rendering the element tree when only the scroll position
            // changed (the parent body re-evaluates on every `position` write).
            .equatable()
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offsetY: geometry.contentOffset.y + geometry.contentInsets.top,
                contentHeight: geometry.contentSize.height,
                visibleHeight: geometry.containerSize.height
            )
        } action: { _, newMetrics in
            onScroll(newMetrics)
        }
        .onAppear {
            // The service already clamps to the preview's scrollable range, so
            // apply the value directly.
            driver.applyOffsetY = { y in
                Task { @MainActor in
                    position.scrollTo(y: max(0, y))
                }
            }
        }
        .background(theme.backgroundColor)
    }
}

// MARK: - Command routing

/// Routes the File/View menu notifications into `DocumentView` actions. Kept
/// as a separate modifier so the main view's modifier chain stays within the
/// type checker's expression budget.
private struct DocumentCommandReceiver: ViewModifier {
    let newDocument: () -> Void
    let openDocument: () -> Void
    let saveDocument: () -> Void
    let saveDocumentAs: () -> Void
    let revertDocument: () -> Void
    let toggleEditor: () -> Void
    let togglePreview: () -> Void
    let toggleToolbar: () -> Void
    let setSplitRatio: (Double) -> Void
    let renderDocument: () -> Void
    let flushAutosave: () -> Void
    let formatCommand: (String) -> Void
    let exportHTML: () -> Void
    let exportPDF: () -> Void
    let printDocument: () -> Void
    let copyHTML: () -> Void
    let openRecent: (URL) -> Void
    /// Whether this window is the key window; commands broadcast through
    /// notifications must only act on it.
    let isActive: () -> Bool

    func body(content: Content) -> some View {
        fileCommands(viewCommands(exportCommands(content)))
    }

    // MARK: - Command groups
    //
    // Split across helpers so each modifier chain stays within the type
    // checker's expression budget.

    private func fileCommands<V: View>(_ content: V) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .newDocumentRequest)) { _ in
                guard isActive() else { return }
                newDocument()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openDocumentRequest)) { _ in
                guard isActive() else { return }
                openDocument()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveDocumentRequest)) { _ in
                guard isActive() else { return }
                saveDocument()
            }
            .onReceive(NotificationCenter.default.publisher(for: .saveDocumentAsRequest)) { _ in
                guard isActive() else { return }
                saveDocumentAs()
            }
            .onReceive(NotificationCenter.default.publisher(for: .revertDocumentRequest)) { _ in
                guard isActive() else { return }
                revertDocument()
            }
            .onReceive(NotificationCenter.default.publisher(for: .flushAutosaveRequest)) { _ in
                flushAutosave()
            }
            .onReceive(NotificationCenter.default.publisher(for: .openRecentDocumentRequest)) { note in
                guard isActive(),
                      let url = note.userInfo?[Constants.recentDocumentURLUserInfoKey] as? URL
                else { return }
                openRecent(url)
            }
    }

    private func viewCommands<V: View>(_ content: V) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .toggleEditorPane)) { _ in
                guard isActive() else { return }
                toggleEditor()
            }
            .onReceive(NotificationCenter.default.publisher(for: .togglePreviewPane)) { _ in
                guard isActive() else { return }
                togglePreview()
            }
            .onReceive(NotificationCenter.default.publisher(for: .toggleToolbar)) { _ in
                guard isActive() else { return }
                toggleToolbar()
            }
            .onReceive(NotificationCenter.default.publisher(for: .setEqualSplit)) { _ in
                guard isActive() else { return }
                setSplitRatio(0.5)
            }
            .onReceive(NotificationCenter.default.publisher(for: .setEditorQuarter)) { _ in
                guard isActive() else { return }
                setSplitRatio(0.25)
            }
            .onReceive(NotificationCenter.default.publisher(for: .setEditorThreeQuarters)) { _ in
                guard isActive() else { return }
                setSplitRatio(0.75)
            }
            .onReceive(NotificationCenter.default.publisher(for: .renderDocumentRequest)) { _ in
                guard isActive() else { return }
                renderDocument()
            }
    }

    private func exportCommands<V: View>(_ content: V) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .formatCommandRequest)) { note in
                guard isActive(),
                      let raw = note.userInfo?[Constants.formatCommandUserInfoKey] as? String
                else { return }
                formatCommand(raw)
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportHTMLRequest)) { _ in
                guard isActive() else { return }
                exportHTML()
            }
            .onReceive(NotificationCenter.default.publisher(for: .exportPDFRequest)) { _ in
                guard isActive() else { return }
                exportPDF()
            }
            .onReceive(NotificationCenter.default.publisher(for: .printDocumentRequest)) { _ in
                guard isActive() else { return }
                printDocument()
            }
            .onReceive(NotificationCenter.default.publisher(for: .copyHTMLRequest)) { _ in
                guard isActive() else { return }
                copyHTML()
            }
    }
}

// MARK: - Word count bar

struct WordCountBar: View {
    let documents: String
    let preferences: Preferences

    private var words: Int { documents.wordCount }
    private var characters: Int { documents.count }
    private var charactersNoSpaces: Int { documents.characterCountNoSpaces }

    private var wordCountText: String {
        switch preferences.editorWordCountType {
        case 1: "\(characters) characters"
        case 2: "\(charactersNoSpaces) characters (no spaces)"
        default: "\(words) words"
        }
    }

    var body: some View {
        HStack {
            Spacer()
            Text(wordCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
    }
}