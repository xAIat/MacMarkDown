import AppKit

// MARK: - Standard editing commands
//
// `MarkdownTextView` is an `NSView`, so AppKit's standard editing actions
// (`copy:`, `paste:`, …) do not exist on it the way they do on `NSTextView`.
// The Edit menu resolves actions through the responder chain, so implementing
// them here restores Cut/Copy/Paste/Select All/Delete/Undo/Redo for the
// custom editor.

extension MarkdownTextView {

    // MARK: Clipboard

    @objc func copy(_ sender: Any?) {
        guard let attributed = textLayoutManager.textSelectionsAttributedString() else { return }
        writeSelection(attributed, to: .general)
    }

    @objc func cut(_ sender: Any?) {
        let range = selectedRange()
        guard isEditable, range.length > 0 else { return }
        copy(sender)
        deleteSelection(range)
    }

    @objc func paste(_ sender: Any?) {
        guard isEditable,
              let pasted = NSPasteboard.general.string(forType: .string)
        else { return }
        insertText(pasted, replacementRange: selectedRange())
    }

    /// Explicit "Paste and Match Style": the editor is plain-text Markdown, so
    /// this matches `paste:` (only the text is inserted).
    @objc func pasteAsPlainText(_ sender: Any?) {
        paste(sender)
    }

    @objc func delete(_ sender: Any?) {
        let range = selectedRange()
        guard isEditable, range.length > 0 else { return }
        deleteSelection(range)
    }

    private func deleteSelection(_ range: NSRange) {
        replaceCharacters(in: range, with: "")
        setSelectedRange(NSRange(location: range.location, length: 0))
    }

    // MARK: Selection

    override func selectAll(_ sender: Any?) {
        setSelectedRange(NSRange(location: 0, length: textContentStorage.documentLength))
    }

    // MARK: Undo / redo

    @objc func undo(_ sender: Any?) {
        undoManager?.undo()
    }

    @objc func redo(_ sender: Any?) {
        undoManager?.redo()
    }

    // MARK: Find

    /// Standard Edit > Find actions (`performFindPanelAction:`). The find bar
    /// itself lives in the SwiftUI layer; the view just forwards the action.
    @objc func performFindPanelAction(_ sender: Any?) {
        var action: NSFindPanelAction = .showFindPanel
        if let item = sender as? NSMenuItem,
           let parsed = NSFindPanelAction(rawValue: UInt(item.tag)) {
            action = parsed
        }
        onFindAction?(action)
    }

    // MARK: Menu validation

    @objc func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        guard let action = item.action else { return true }
        switch action {
        case #selector(copy(_:)), #selector(cut(_:)), #selector(delete(_:)):
            return selectedRange().length > 0
        case #selector(paste(_:)):
            return isEditable
                && NSPasteboard.general.canReadItem(
                    withDataConformingToTypes: [NSPasteboard.PasteboardType.string.rawValue]
                )
        case #selector(selectAll(_:)):
            return textContentStorage.documentLength > 0
        case #selector(undo(_:)):
            return undoManager?.canUndo ?? false
        case #selector(redo(_:)):
            return undoManager?.canRedo ?? false
        default:
            return super.responds(to: action)
        }
    }
}