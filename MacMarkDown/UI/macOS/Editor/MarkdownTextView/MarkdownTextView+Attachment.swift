import AppKit

// MARK: - Text attachments
//
// Attachments let a single text surface host non-text content (images, tables,
// embedded web views) as `NSTextAttachment` objects. The fragment view lays out
// their `NSTextAttachmentViewProvider` views (see `MarkdownTextFragmentView`).

extension MarkdownTextView {

    /// All attachments in the given range (or the whole document).
    func textAttachments(in range: NSTextRange? = nil) -> [(attachment: NSTextAttachment, range: NSTextRange)] {
        let searchRange = range ?? textLayoutManager.documentRange
        guard let attributed = textContentStorage.attributedString(in: searchRange) else { return [] }
        var result: [(NSTextAttachment, NSTextRange)] = []
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, attributeRange, _ in
            guard let attachment = value as? NSTextAttachment,
                  let start = textLayoutManager.location(searchRange.location, offsetBy: attributeRange.location),
                  let end = textLayoutManager.location(start, offsetBy: attributeRange.length),
                  let textRange = NSTextRange(location: start, end: end)
            else { return }
            result.append((attachment, textRange))
        }
        return result
    }

    /// Inserts `attachment` at the given location.
    func insertAttachment(_ attachment: NSTextAttachment, at location: any NSTextLocation) {
        replaceCharacters(
            in: NSTextRange(location: location),
            with: NSAttributedString(attachment: attachment),
            allowsTypingCoalescing: false
        )
    }

    /// Replaces the attachment at `range` with a new one.
    func replaceAttachment(in range: NSTextRange, with attachment: NSTextAttachment) {
        replaceCharacters(
            in: range,
            with: NSAttributedString(attachment: attachment),
            allowsTypingCoalescing: false
        )
    }

    /// Removes the attachment at `range`.
    func removeAttachment(in range: NSTextRange) {
        replaceCharacters(
            in: range,
            with: NSAttributedString(),
            allowsTypingCoalescing: false
        )
    }

    /// The attachment views currently laid out (diagnostic/testing aid).
    func visibleAttachmentViews() -> [NSView] {
        var views: [NSView] = []
        for case let fragmentView as MarkdownTextFragmentView in contentView.subviews {
            views.append(contentsOf: fragmentView.subviews)
        }
        return views
    }

    /// Selects the attachment at `location` (caret before it).
    func selectAttachment(at location: any NSTextLocation) {
        setSelectedTextRange(NSTextRange(location: location))
    }
}
