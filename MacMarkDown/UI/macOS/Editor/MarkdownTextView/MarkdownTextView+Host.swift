import AppKit
import UniformTypeIdentifiers

// MARK: - Editor host conformance (Milestone 4)
//
// `MarkdownTextView` implements the coordinator's host surface, the
// drag-and-drop file opening behavior (text drops insert at the drop location;
// file drops become open-document requests) and the two command-interception
// hooks that replace the legacy `NSTextViewDelegate` plumbing.

extension MarkdownTextView: EditorTextViewHost {}

extension MarkdownTextView {

    override func doCommand(by selector: Selector) {
        if let handler = doCommandHandler, handler(selector) {
            return
        }
        super.doCommand(by: selector)
    }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canHandleDrop(sender) else {
            // Declining lets the window keep searching up the hierarchy, so a
            // read-only surface without a file handler still lets the SwiftUI
            // drop destination open the document.
            return super.draggingEntered(sender)
        }
        onDragTargetingChanged?(true)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard droppedFileURL(from: sender) != nil else {
            return super.draggingUpdated(sender)
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onDragTargetingChanged?(false)
        super.draggingExited(sender)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        // `draggingEnded(_:)` is an optional `NSDraggingDestination` method that
        // `NSView` does not implement, so calling `super` would raise
        // `unrecognized selector`. Just clear the highlight.
        onDragTargetingChanged?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let url = droppedFileURL(from: sender) {
            onDragTargetingChanged?(false)
            // Images dropped onto the editable editor are inlined as base64
            // Markdown. A read-only surface (the preview) cannot accept
            // insertions, so its file drops open the document instead.
            if isEditable, let imageMarkdown = Self.base64ImageMarkdown(for: url) {
                insertText(imageMarkdown, replacementRange: dropInsertionRange(sender))
            } else {
                onOpenFile?(url)
            }
            return true
        }
        guard isEditable,
              let droppedString = sender.draggingPasteboard.string(forType: .string)
        else {
            return false
        }
        insertText(droppedString, replacementRange: dropInsertionRange(sender))
        return true
    }

    /// Whether this view can act on the drag: a file drag needs a file-open
    /// handler (or an editable target that inlines images), a text drag needs
    /// editability (the read-only preview must not insert).
    private func canHandleDrop(_ sender: NSDraggingInfo) -> Bool {
        if droppedFileURL(from: sender) != nil {
            return isEditable || onOpenFile != nil
        }
        return isEditable && sender.draggingPasteboard.string(forType: .string) != nil
    }

    /// The range a drop should insert at: the caret under the pointer when it
    /// can be resolved, otherwise the current selection.
    private func dropInsertionRange(_ sender: NSDraggingInfo) -> NSRange {
        if let caret = caretSelection(at: convert(sender.draggingLocation, from: nil)),
           let range = caret.textRanges.first {
            return textContentStorage.range(from: range)
        }
        return selectedRange()
    }

    private func droppedFileURL(from sender: NSDraggingInfo) -> URL? {
        let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return (objects as? [URL])?.first
    }

    /// Builds `![alt](data:image/<subtype>;base64,…)` for a dropped image file,
    /// or `nil` when `url` is not a readable image.
    static func base64ImageMarkdown(for url: URL) -> String? {
        guard let type = UTType(filenameExtension: url.pathExtension),
              type.conforms(to: .image),
              let data = try? Data(contentsOf: url),
              !data.isEmpty
        else { return nil }
        let subtype = type.preferredFilenameExtension ?? url.pathExtension
        let alt = url.deletingPathExtension().lastPathComponent
        return "![\(alt)](data:image/\(subtype);base64,\(data.base64EncodedString()))"
    }
}