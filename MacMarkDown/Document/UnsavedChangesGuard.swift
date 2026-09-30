import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Intercepts window close and application quit so edits are never silently
/// discarded. The alert is presented synchronously (`NSAlert.runModal`) because
/// both `windowShouldClose` and `applicationShouldTerminate` must decide on the
/// spot; an asynchronous SwiftUI alert cannot answer them.
///
/// Autosave is opt-in, so this guard is the only protection for unsaved work.
@MainActor
public final class UnsavedChangesGuard: NSObject, NSWindowDelegate {

    /// The document to protect. Weak: the guard outlives transient view state.
    public weak var document: MarkdownDocument?

    /// Overrides the save step (used by tests to avoid panels). Returns `true`
    /// when the document ended up saved.
    var saveOverride: ((MarkdownDocument) -> Bool)?

    /// Overrides the user prompt (used by tests). Returns the chosen action.
    var promptOverride: ((MarkdownDocument) -> Decision)?

    /// SwiftUI's own window delegate; optional methods we don't implement are
    /// forwarded to it so window management keeps working. `nonisolated(unsafe)`
    /// because `responds(to:)`/`forwardingTarget(for:)` are nonisolated ObjC
    /// overrides; AppKit only touches it on the main thread.
    private nonisolated(unsafe) weak var previousDelegate: NSWindowDelegate?

    public enum Decision: Equatable {
        case save
        case discard
        case cancel
    }

    public override init() {
        super.init()
    }

    // MARK: - Entry points

    /// `NSWindowDelegate` hook. Returns `false` to veto the close.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmClose()
    }

    /// Returns `true` when it is safe to close/quit (document saved or the
    /// user chose to discard).
    @discardableResult
    public func confirmClose() -> Bool {
        guard let document, document.isEdited else { return true }
        switch prompt(document) {
        case .discard:
            return true
        case .cancel:
            return false
        case .save:
            return save(document)
        }
    }

    // MARK: - Prompt / save (overridable for tests)

    private func prompt(_ document: MarkdownDocument) -> Decision {
        if let promptOverride { return promptOverride(document) }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to “\(document.displayTitle)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don’t Save")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .discard
        default:
            return .cancel
        }
    }

    private func save(_ document: MarkdownDocument) -> Bool {
        if let saveOverride { return saveOverride(document) }
        if let url = document.fileURL {
            do {
                try document.save(to: url)
                return true
            } catch {
                presentSaveError(error)
                return false
            }
        }
        return presentSavePanel(for: document)
    }

    private func presentSavePanel(for document: MarkdownDocument) -> Bool {
        let panel = NSSavePanel()
        let types = ["md", "markdown", "mdown", "mkd", "mkdn"].compactMap {
            UTType(filenameExtension: $0)
        }
        if !types.isEmpty {
            panel.allowedContentTypes = types
        }
        panel.nameFieldStringValue = document.displayTitle + ".md"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try document.save(to: url)
            return true
        } catch {
            presentSaveError(error)
            return false
        }
    }

    private func presentSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "The document couldn’t be saved."
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - Window installation

extension UnsavedChangesGuard {

    /// Installs the guard as the window's delegate while preserving SwiftUI's
    /// own delegate. Optional `NSWindowDelegate` calls the guard does not
    /// implement are forwarded to the previous delegate via ObjC forwarding.
    public func install(on window: NSWindow) {
        guard !(window.delegate is UnsavedChangesGuard) else { return }
        previousDelegate = window.delegate
        window.delegate = self
    }

    public override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return previousDelegate?.responds(to: aSelector) ?? false
    }

    public override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if previousDelegate?.responds(to: aSelector) == true {
            return previousDelegate
        }
        return super.forwardingTarget(for: aSelector)
    }
}

// MARK: - SwiftUI installation

/// A zero-size view that reports the hosting window as soon as the view joins
/// the hierarchy. Used to install the close guard and to key per-window state
/// in the multi-window session registry.
public struct WindowAccessor: NSViewRepresentable {

    private let onWindow: (NSWindow) -> Void

    public init(onWindow: @escaping (NSWindow) -> Void) {
        self.onWindow = onWindow
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowReporterView(frame: .zero)
        view.onWindow = onWindow
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        if let window = nsView.window {
            onWindow(window)
        }
    }

    private final class WindowReporterView: NSView {
        var onWindow: ((NSWindow) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                onWindow?(window)
            }
        }
    }
}