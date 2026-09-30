import AppKit
import UniformTypeIdentifiers

// MARK: - Clipboard writing & Services menu
//
// Pasteboard handling: a copy writes the selection as plain text, RTF *and*
// HTML so pasting into a rich target keeps formatting. The view also
// participates in the Services menu.

extension MarkdownTextView: @MainActor NSServicesMenuRequestor {

    /// Types this view can read from the pasteboard.
    var readablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string, .init(rawValue: "NSStringPboardType"), .rtf]
    }

    /// Types this view can provide from the current selection.
    var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        [.string, .init(rawValue: "NSStringPboardType"), .rtf, .html]
    }

    @objc func readSelection(from pboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        guard isEditable else { return false }
        switch type {
        case .string, .init(rawValue: "NSStringPboardType"):
            guard let string = pboard.string(forType: type) else { return false }
            insertText(string, replacementRange: selectedRange())
            return true
        case .rtf, .init(rawValue: "NSRTFPboardType"):
            guard let data = pboard.data(forType: .rtf),
                  let attributed = NSAttributedString(rtf: data, documentAttributes: nil)
            else { return false }
            insertText(attributed.string, replacementRange: selectedRange())
            return true
        default:
            return false
        }
    }

    @objc func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard let attributed = textLayoutManager.textSelectionsAttributedString() else { return false }
        return writeSelection(attributed, to: pboard)
    }

    /// Writes `attributed` to `pboard` as plain text, RTF and HTML.
    ///
    /// A selection that contains a table takes the WebKit route instead: HTML
    /// carrying a real `<table>` plus plain text, and no RTF. RTF cannot express
    /// the table (AppKit's text tables do not lay out on macOS 27) and rich
    /// editors such as Notes prefer RTF over HTML when both are present, so
    /// offering it would paste the cells as loose text.
    @discardableResult
    func writeSelection(_ attributed: NSAttributedString, to pboard: NSPasteboard) -> Bool {
        guard attributed.length > 0 else { return false }
        let cleaned = Self.strippingViewDefaultColor(attributed, defaultColor: textColor)
        // Tables and math formulas are drawn by WebKit on top of a placeholder
        // character, so the selection itself holds no table cells or TeX. Expand
        // each placeholder back into its content, otherwise copying a selection
        // that contains one yields nothing (or just the object-replacement
        // character).
        let hasTables = Self.containsTableAttachments(cleaned)
        let expanded = Self.expandingWebBlockAttachments(in: cleaned)
        let fullRange = NSRange(location: 0, length: expanded.length)

        pboard.clearContents()
        var wrote = false
        if pboard.setString(expanded.string, forType: .string) { wrote = true }

        if hasTables {
            if let html = Self.htmlForSelection(cleaned), let data = html.data(using: .utf8) {
                pboard.setData(data, forType: .init(Constants.htmlPasteboardType))
                wrote = true
            }
            return wrote
        }

        if let rtf = try? expanded.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        ) {
            pboard.setData(rtf, forType: .rtf)
            wrote = true
        }
        if let html = try? expanded.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        ) {
            pboard.setData(html, forType: .init(Constants.htmlPasteboardType))
            wrote = true
        }
        return wrote
    }

    /// Whether the selection holds any table placeholder.
    static func containsTableAttachments(_ attributed: NSAttributedString) -> Bool {
        var found = false
        attributed.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: attributed.length)
        ) { value, _, stop in
            if value is TablePreviewHTML.Attachment {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    /// The selection as HTML in which every table placeholder becomes the same
    /// `<table>` markup the export writes and every math placeholder becomes its
    /// TeX source.
    ///
    /// The text around the tables is converted with the standard AppKit
    /// conversion; the tables themselves are spliced in afterwards, because a
    /// placeholder would otherwise convert to an image (or, once expanded, to
    /// loose paragraphs) and the pasted result would have no table. Math has no
    /// rendering to paste (the target has no MathJax), so its TeX source stands
    /// in for it.
    static func htmlForSelection(_ attributed: NSAttributedString) -> String? {
        let mutable = attributed.mutableCopy() as? NSMutableAttributedString
            ?? NSMutableAttributedString(attributedString: attributed)
        var markups: [String] = []
        var placeholders: [(range: NSRange, token: String)] = []
        var mathPlaceholders: [(range: NSRange, token: String)] = []
        mutable.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: mutable.length)
        ) { value, range, _ in
            if let math = value as? MathPreviewHTML.Attachment {
                mathPlaceholders.append((range, math.plainText))
                return
            }
            guard let table = value as? TablePreviewHTML.Attachment else { return }
            let token = "MACMARKDOWNTABLE\(markups.count)TOKEN"
            markups.append(table.html)
            placeholders.append((range, token))
        }
        guard !markups.isEmpty else { return nil }
        // Back to front, so the earlier ranges stay valid while editing.
        for placeholder in (placeholders + mathPlaceholders).reversed() {
            mutable.replaceCharacters(
                in: placeholder.range,
                with: NSAttributedString(string: placeholder.token)
            )
        }

        let fullRange = NSRange(location: 0, length: mutable.length)
        guard let data = try? mutable.data(
            from: fullRange,
            documentAttributes: [.documentType: NSAttributedString.DocumentType.html]
        ), let html = String(data: data, encoding: .utf8) else { return nil }

        // The token comes back inside the paragraph the placeholder occupied;
        // drop that wrapper so the table is not nested in an empty paragraph.
        var result = html
        for (index, markup) in markups.enumerated() {
            let token = "MACMARKDOWNTABLE\(index)TOKEN"
            let wrapped = try? NSRegularExpression(
                pattern: "<p[^>]*>\\s*\(token)\\s*</p>",
                options: []
            )
            let range = NSRange(location: 0, length: (result as NSString).length)
            if let wrapped, wrapped.firstMatch(in: result, options: [], range: range) != nil {
                result = wrapped.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: markup)
            } else {
                result = result.replacingOccurrences(of: token, with: markup)
            }
        }
        return result
    }

    /// Replaces every table placeholder with the table's text (tab-separated
    /// cells, one row per line) and every math placeholder with its TeX source,
    /// keeping the surrounding formatting.
    static func expandingWebBlockAttachments(in attributed: NSAttributedString) -> NSAttributedString {
        let mutable = attributed.mutableCopy() as? NSMutableAttributedString
            ?? NSMutableAttributedString(attributedString: attributed)
        var replacements: [(range: NSRange, text: String, font: NSFont?)] = []
        mutable.enumerateAttribute(
            .attachment,
            in: NSRange(location: 0, length: mutable.length)
        ) { value, range, _ in
            let text: String
            if let table = value as? TablePreviewHTML.Attachment {
                text = table.plainText
            } else if let math = value as? MathPreviewHTML.Attachment {
                text = math.plainText
            } else {
                return
            }
            let font = mutable.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont
            replacements.append((range, text, font))
        }
        // Back to front, so the earlier ranges stay valid while editing.
        for replacement in replacements.reversed() {
            var attributes: [NSAttributedString.Key: Any] = [:]
            if let font = replacement.font { attributes[.font] = font }
            mutable.replaceCharacters(
                in: replacement.range,
                with: NSAttributedString(string: replacement.text, attributes: attributes)
            )
        }
        return mutable
    }

    /// Removes the view's default foreground color from `attributed`, so a dark
    /// theme's near-white text is not pasted invisibly onto a light background.
    static func strippingViewDefaultColor(
        _ attributed: NSAttributedString,
        defaultColor: NSColor
    ) -> NSAttributedString {
        let mutable = attributed.mutableCopy() as? NSMutableAttributedString ?? NSMutableAttributedString(attributedString: attributed)
        var ranges: [NSRange] = []
        mutable.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: mutable.length)) { value, range, _ in
            if let color = value as? NSColor, color == defaultColor {
                ranges.append(range)
            }
        }
        for range in ranges { mutable.removeAttribute(.foregroundColor, range: range) }
        return mutable
    }
}
