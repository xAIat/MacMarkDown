import Foundation
import SwiftUI
import Observation

/// The document model for MacMarkDown. Each opened Markdown file is backed by
/// one instance of this class, which owns the text content and coordinates
/// parsing, rendering, and rendering services.
///
/// The app uses a single-window, single-document "session" architecture:
/// `DocumentView` owns one document and `DocumentSession` keeps a reference to
/// it so the app delegate can flush a pending autosave on quit. Saving is
/// driven by the File menu (Save / Save As) and — when the user opts in via
/// Settings ("Auto Save Changes", off by default) — by a debounced autosave
/// that writes back to disk a short while after editing stops.
@MainActor
@Observable
public final class MarkdownDocument: Identifiable {

    public enum SaveError: Error, Equatable {
        /// The file changed on disk since this document was last written;
        /// the caller should ask the user before overwriting.
        case fileChangedExternally(URL)
    }

    public let id = UUID()
    public var text: String = ""
    public var fileURL: URL?
    /// The last content written to (or read from) disk. Used to detect
    /// external modification for the save-conflict check.
    public private(set) var lastSavedText: String = ""
    /// Whether the buffer differs from what is on disk. Derived, so undo back
    /// to the saved content clears the "modified" dot and the close prompt the
    /// same way a saved `NSDocument` would.
    public var isEdited: Bool {
        normalized(text) != normalized(lastSavedText)
    }

    /// Applies the optional "append newline at EOF" normalization so a file
    /// that lacked a trailing newline is not reported as edited either right
    /// after loading or right after saving it.
    private func normalized(_ string: String) -> String {
        guard preferences.editorEnsuresNewlineAtEndOfFile,
              !string.isEmpty,
              !string.hasSuffix("\n")
        else { return string }
        return string + "\n"
    }

    // Child services (observed by views)
    public let preferences: Preferences
    public let renderService: RenderService
    public let parser: MarkdownParser

    /// Heading locations cached for sync-scroll. Updated on text changes.
    public var editorHeaderLocations: [CGFloat] = []

    private var autosaveTask: Task<Void, Never>?

    public init(preferences: Preferences = Preferences(), url: URL? = nil) {
        self.preferences = preferences
        self.parser = MarkdownParser()
        self.renderService = RenderService(parser: parser, preferences: preferences)
        self.fileURL = url
        if let url, let content = try? String(contentsOf: url, encoding: .utf8) {
            self.text = content
            self.lastSavedText = content
        }
    }

    // MARK: - Text operations

    public func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        // `isEdited` is derived from `text != lastSavedText`, so undo back to
        // the saved content marks the document clean again automatically.
        // Manual render keeps the preview frozen until the user asks for it.
        if !preferences.markdownManualRender {
            renderService.scheduleRender(text: newText, options: preferences.parseOptions)
        }
        scheduleAutosave()
    }

    // MARK: - File I/O

    public func load(from url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        autosaveTask?.cancel()
        self.text = content
        self.fileURL = url
        self.lastSavedText = content
        renderService.scheduleRender(text: content, options: preferences.parseOptions)
    }

    /// Resets the document to an empty, unsaved buffer.
    public func resetToUntitled() {
        autosaveTask?.cancel()
        text = ""
        fileURL = nil
        lastSavedText = ""
        renderService.parseNow(text: "", options: preferences.parseOptions)
    }

    /// Writes the buffer to `url`, optionally detecting external changes.
    ///
    /// - Parameters:
    ///   - url: The destination.
    ///   - checkConflict: When `true` (manual saves) and `url` matches the
    ///     document's current file, an on-disk change that did not come from
    ///     this document throws `SaveError.fileChangedExternally` instead of
    ///     blindly overwriting it. Autosaves pass `false`.
    public func save(to url: URL, checkConflict: Bool = true) throws {
        var content = text
        if preferences.editorEnsuresNewlineAtEndOfFile && !content.hasSuffix("\n") {
            content += "\n"
        }
        if checkConflict, let fileURL, fileURL.path == url.path {
            let onDisk = try? String(contentsOf: url, encoding: .utf8)
            if let onDisk, onDisk != lastSavedText, lastSavedText != content {
                throw SaveError.fileChangedExternally(url)
            }
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
        self.fileURL = url
        self.lastSavedText = content
    }

    /// Persists the buffer to the document's current file, if it has one. Used
    /// by the app delegate and window teardown so pending edits are not lost —
    /// only when the user opted into autosave; otherwise edits stay unsaved.
    public func autosaveNow() {
        autosaveTask?.cancel()
        guard preferences.editorAutosaveEnabled, isEdited, let url = fileURL else { return }
        try? save(to: url, checkConflict: false)
    }

    /// Schedules a debounced autosave for a file-bound document. No-op unless
    /// autosave is enabled in Settings.
    public func scheduleAutosave() {
        autosaveTask?.cancel()
        guard preferences.editorAutosaveEnabled, isEdited, fileURL != nil else { return }
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(
                Constants.autosaveDebounceInterval * 1_000_000_000
            ))
            guard !Task.isCancelled else { return }
            self?.autosaveNow()
        }
    }

    public func ensureNewlineAtEOF() {
        if preferences.editorEnsuresNewlineAtEndOfFile && !text.hasSuffix("\n") {
            text += "\n"
        }
    }

    /// Whether this document is an untouched blank buffer — the state in which
    /// a Finder-open can reuse its window instead of spawning a new one.
    public var isBlankAndUnedited: Bool {
        text.isEmpty && !isEdited && fileURL == nil
    }

    // MARK: - Formatted title

    public var displayTitle: String {
        if let fileURL {
            return fileURL.lastPathComponent.replacingOccurrences(of: ".md", with: "")
        }
        if preferences.htmlDetectFrontMatter, let fm = FrontMatter.extract(from: text) {
            if let title = fm.title { return title }
        }
        return text.firstHeading ?? "Untitled"
    }
}