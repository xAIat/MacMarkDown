import AppKit

// MARK: - Font panel & capitalization
//
// Standard `NSResponder` formatting actions used by the Format menu and the
// system Fonts panel.

extension MarkdownTextView {

    // MARK: Font panel

    @objc func changeFont(_ sender: Any?) {
        guard isEditable, let fontManager = sender as? NSFontManager else { return }
        let newFont = fontManager.convert(font)

        let range = selectedRange()
        guard range.length > 0 else {
            font = newFont
            return
        }
        applyAttributes { storage in
            storage.addAttribute(.font, value: newFont, range: range)
        }
    }

    func validModesForFontPanel(_ fontPanel: NSFontPanel) -> NSFontPanel.ModeMask {
        [.collection, .face, .size]
    }

    // MARK: Capitalization

    @objc override func capitalizeWord(_ sender: Any?) { transformSelection { $0.capitalized } }
    @objc override func lowercaseWord(_ sender: Any?) { transformSelection { $0.lowercased() } }
    @objc override func uppercaseWord(_ sender: Any?) { transformSelection { $0.uppercased() } }

    /// Applies `transform` to the current selection (or the word at the caret),
    /// preserving attributes and restoring the selection.
    private func transformSelection(_ transform: (String) -> String) {
        guard isEditable else { return }
        let selection = selectedRange()
        var range = selection
        if range.length == 0 {
            // Expand to the word under the caret.
            let text = string as NSString
            var start = range.location
            var end = range.location
            while start > 0, !Self.isWordBoundaryUnit(text.character(at: start - 1)) { start -= 1 }
            while end < text.length, !Self.isWordBoundaryUnit(text.character(at: end)) { end += 1 }
            range = NSRange(location: start, length: end - start)
        }
        guard range.length > 0 else { return }

        let original = (string as NSString).substring(with: range)
        let transformed = transform(original)
        guard transformed != original else { return }

        replaceCharacters(in: range, with: transformed)
        setSelectedRange(NSRange(location: range.location, length: (transformed as NSString).length))
    }
}
