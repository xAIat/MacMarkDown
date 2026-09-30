import AppKit

// MARK: - Dragging the selection out
//
// `MarkdownTextView` acts as an `NSDraggingSource` so the selected text can be
// dragged into other applications (or another editor window). The destination
// side is handled by `MarkdownTextView+Host.swift`.

extension MarkdownTextView: @MainActor NSDraggingSource {

    /// Content coordinates where a possible drag-out gesture began.
    var pendingDragOrigin: NSPoint? {
        get { _pendingDragOrigin }
        set { _pendingDragOrigin = newValue }
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Move inside the app, copy to other apps.
        context == .withinApplication ? .move : .copy
    }
}
