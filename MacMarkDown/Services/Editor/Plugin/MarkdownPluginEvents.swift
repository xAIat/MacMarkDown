import AppKit

// MARK: - Text-view plugin API
//
// A lightweight extension point for the editor. No concrete plugins ship
// in-tree; this is the seam future features (syntax highlighting,
// annotations, …) can plug into without subclassing `MarkdownTextView`.

/// Events a plugin can observe. Each registration returns an opaque token that
/// must be passed back to `remove`.
@MainActor
final class MarkdownPluginEvents {

    struct Token: Hashable {
        fileprivate let id = UUID()
    }

    private var shouldChangeHandlers: [Token: (NSTextRange, String?) -> Bool] = [:]
    private var didChangeHandlers: [Token: (NSTextRange, String) -> Void] = [:]
    private var didLayoutViewportHandlers: [Token: () -> Void] = [:]

    /// Called before a text change; returning `false` vetoes it.
    func onShouldChangeText(_ handler: @escaping (NSTextRange, String?) -> Bool) -> Token {
        let token = Token()
        shouldChangeHandlers[token] = handler
        return token
    }

    /// Called after a text change.
    func onDidChangeText(_ handler: @escaping (NSTextRange, String) -> Void) -> Token {
        let token = Token()
        didChangeHandlers[token] = handler
        return token
    }

    /// Called after each viewport layout pass.
    func onDidLayoutViewport(_ handler: @escaping () -> Void) -> Token {
        let token = Token()
        didLayoutViewportHandlers[token] = handler
        return token
    }

    func remove(_ token: Token) {
        shouldChangeHandlers[token] = nil
        didChangeHandlers[token] = nil
        didLayoutViewportHandlers[token] = nil
    }

    // MARK: Dispatch (internal)

    func shouldChange(_ range: NSTextRange, replacement: String?) -> Bool {
        shouldChangeHandlers.values.allSatisfy { $0(range, replacement) }
    }

    func didChange(_ range: NSTextRange, replacement: String) {
        for handler in didChangeHandlers.values { handler(range, replacement) }
    }

    func didLayoutViewport() {
        for handler in didLayoutViewportHandlers.values { handler() }
    }

    var isEmpty: Bool {
        shouldChangeHandlers.isEmpty && didChangeHandlers.isEmpty && didLayoutViewportHandlers.isEmpty
    }
}

/// A plugin that can observe and influence the editor.
@MainActor
protocol MarkdownPlugin: AnyObject {
    /// Called once when the plugin is added to a text view.
    func setUp(textView: MarkdownTextView, events: MarkdownPluginEvents)
    /// Called when the plugin is removed.
    func tearDown()
}

extension MarkdownPlugin {
    func tearDown() {}
}
