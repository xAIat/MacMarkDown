import AppKit
import Foundation

/// Tracks every open document window so non-view entry points (the app
/// delegate, the File menu) can reach the *key* window's document without
/// threading references through the view hierarchy.
///
/// Multi-window model: each `DocumentView` registers an entry keyed by a
/// stable per-window id; commands act on the key window's entry.
@MainActor
public final class DocumentSession {

    public static let shared = DocumentSession()

    /// One window's document plus the closure that loads a file into it.
    public final class Entry {
        public fileprivate(set) weak var document: MarkdownDocument?
        public fileprivate(set) weak var window: NSWindow?
        fileprivate let load: (URL) -> Void

        fileprivate init(document: MarkdownDocument, window: NSWindow?, load: @escaping (URL) -> Void) {
            self.document = document
            self.window = window
            self.load = load
        }

        /// Loads `url` into this window's document (used for Finder opens).
        public func open(_ url: URL) {
            load(url)
        }
    }

    private var entries: [UUID: Entry] = [:]
    private var registrationOrder: [UUID] = []

    /// Set by `DocumentView` so a file-open request can open a fresh window.
    public var openNewWindow: (() -> Void)?

    /// When set, the next blank window that appears closes itself. Used at
    /// launch for the "Suppress Untitled on Launch" preference.
    public var suppressNextBlankWindow = false

    private init() {}

    // MARK: - Registration

    /// Called by `DocumentView` when it appears.
    public func register(
        id: UUID,
        document: MarkdownDocument,
        window: NSWindow?,
        load: @escaping (URL) -> Void
    ) {
        if let existing = entries[id] {
            existing.document = document
            existing.window = window
        } else {
            entries[id] = Entry(document: document, window: window, load: load)
            registrationOrder.append(id)
        }
    }

    /// Updates the window backing a registration (the window appears after the
    /// view's first body evaluation).
    public func updateWindow(id: UUID, window: NSWindow?) {
        entries[id]?.window = window
    }

    /// Called by `DocumentView` when it disappears.
    public func unregister(id: UUID) {
        entries[id] = nil
        registrationOrder.removeAll { $0 == id }
    }

    // MARK: - Lookup

    /// The entry for the key window, or the most recently registered window
    /// when nothing is key (headless tests, app inactive).
    public var keyEntry: Entry? {
        if let keyWindow = NSApplication.shared.keyWindow,
           let match = entries.values.first(where: { $0.window === keyWindow }) {
            return match
        }
        if let last = registrationOrder.last, let entry = entries[last] {
            return entry
        }
        return entries.values.first
    }

    /// Every registered document, most recent first.
    public var documents: [MarkdownDocument] {
        registrationOrder.reversed().compactMap { entries[$0]?.document }
    }

    /// The key window's document.
    public var document: MarkdownDocument? {
        keyEntry?.document
    }

    /// Flushes a pending autosave for every open document.
    public func flushAutosave() {
        for document in documents {
            document.autosaveNow()
        }
    }

    /// Whether the key document was loaded from (or saved to) a file; gates
    /// menu items such as "Revert to Saved".
    public var isCurrentDocumentBound: Bool {
        document?.fileURL != nil
    }

    /// Opens a blank window and returns `true` when a window could be opened.
    @discardableResult
    public func requestNewWindow() -> Bool {
        guard let openNewWindow else { return false }
        openNewWindow()
        return true
    }

    /// Routes a Finder/CLI file open: reuses the key window when it holds a
    /// blank, unedited document; otherwise queues the file for a new window.
    ///
    /// - Returns: `true` when the file was loaded into an existing window,
    ///   `false` when it was queued for a new one (a window is requested here).
    @discardableResult
    public func openFile(_ url: URL) -> Bool {
        if let entry = keyEntry, entry.document?.isBlankAndUnedited == true {
            entry.open(url)
            return true
        }
        DocumentOpenQueue.shared.enqueue([url])
        requestNewWindow()
        return false
    }
}

// MARK: - File menu commands

extension Notification.Name {
    /// Posted by the File menu to ask the document view to create a new doc.
    public static let newDocumentRequest = Notification.Name("MacMarkDownNewDocumentRequest")
    /// Posted by the File menu to ask the document view to open a file.
    public static let openDocumentRequest = Notification.Name("MacMarkDownOpenDocumentRequest")
    /// Posted by the File menu to save the current document.
    public static let saveDocumentRequest = Notification.Name("MacMarkDownSaveDocumentRequest")
    /// Posted by the File menu to save the current document under a new name.
    public static let saveDocumentAsRequest = Notification.Name("MacMarkDownSaveDocumentAsRequest")
    /// Posted when the app is about to quit / a window is closing.
    public static let flushAutosaveRequest = Notification.Name("MacMarkDownFlushAutosaveRequest")
    /// Posted by the File menu to revert the current document from disk.
    public static let revertDocumentRequest = Notification.Name("MacMarkDownRevertDocumentRequest")
    /// Posted by the View menu to toggle the editor pane.
    public static let toggleEditorPane = Notification.Name("MacMarkDownToggleEditorPane")
    /// Posted by the View menu to toggle the preview pane.
    public static let togglePreviewPane = Notification.Name("MacMarkDownTogglePreviewPane")
    /// Posted by the View menu to render the preview on demand.
    public static let renderDocumentRequest = Notification.Name("MacMarkDownRenderDocumentRequest")
    /// Posted by the View menu to show/hide the window toolbar.
    public static let toggleToolbar = Notification.Name("MacMarkDownToggleToolbar")
    /// Posted by the View menu to set the editor/preview split ratios.
    public static let setEqualSplit = Notification.Name("MacMarkDownSetEqualSplit")
    public static let setEditorQuarter = Notification.Name("MacMarkDownSetEditorQuarter")
    public static let setEditorThreeQuarters = Notification.Name("MacMarkDownSetEditorThreeQuarters")
    /// Posted by the Format menu; `userInfo` carries the command raw value.
    public static let formatCommandRequest = Notification.Name("MacMarkDownFormatCommandRequest")
    /// Posted by the File menu to export the document as HTML.
    public static let exportHTMLRequest = Notification.Name("MacMarkDownExportHTMLRequest")
    /// Posted by the File menu to export the document as PDF.
    public static let exportPDFRequest = Notification.Name("MacMarkDownExportPDFRequest")
    /// Posted by the File menu to print the document.
    public static let printDocumentRequest = Notification.Name("MacMarkDownPrintDocumentRequest")
    /// Posted by the File menu to copy the rendered HTML.
    public static let copyHTMLRequest = Notification.Name("MacMarkDownCopyHTMLRequest")
    /// Posted by File > Open Recent; `userInfo` carries the URL.
    public static let openRecentDocumentRequest = Notification.Name("MacMarkDownOpenRecentDocumentRequest")
}