import AppKit

// MARK: - Invisible characters & custom layout fragments
//
// TextKit 2 asks its delegate to create the `NSTextLayoutFragment` for each
// text element; returning a `MarkdownTextLayoutFragment` lets the view draw
// whitespace symbols when enabled.

extension MarkdownTextView: @MainActor NSTextLayoutManagerDelegate {

    func textLayoutManager(
        _ textLayoutManager: NSTextLayoutManager,
        textLayoutFragmentFor location: any NSTextLocation,
        in textElement: NSTextElement
    ) -> NSTextLayoutFragment {
        let fragment = MarkdownTextLayoutFragment(
            textElement: textElement,
            range: textElement.elementRange
        )
        fragment.showsInvisibleCharacters = showsInvisibleCharacters
        fragment.defaultFont = font
        return fragment
    }
}

extension MarkdownTextView {

    /// Whether whitespace/newline symbols are drawn over the text.
    var showsInvisibleCharacters: Bool {
        get { _showsInvisibleCharacters }
        set {
            guard newValue != _showsInvisibleCharacters else { return }
            _showsInvisibleCharacters = newValue
            invalidateViewportLayout()
        }
    }

    /// Applies the current flag/font to already-created fragments (called from
    /// the viewport layout callback).
    func syncInvisibleCharacterState(_ fragment: NSTextLayoutFragment) {
        guard let fragment = fragment as? MarkdownTextLayoutFragment else { return }
        fragment.showsInvisibleCharacters = _showsInvisibleCharacters
        fragment.defaultFont = font
    }

    private func invalidateViewportLayout() {
        let controller = textLayoutManager.textViewportLayoutController
        if let viewportRange = controller.viewportRange {
            textLayoutManager.invalidateLayout(for: viewportRange)
        }
        needsLayout = true
    }
}
