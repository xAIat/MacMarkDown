import Foundation

/// Every formatting operation the Format menu and the toolbar can run.
public enum EditorFormatCommand: String, Sendable, CaseIterable {
    case paragraph, h1, h2, h3, h4, h5, h6
    case strong, emphasis, inlineCode, strikethrough
    case underline, highlight, comment
    case unorderedList, orderedList, blockquote, codeBlock
    case link, image
    case indent, unindent
    case newParagraph
}

/// Applies `EditorFormatCommand`s to a text buffer. Shared by `ToolbarView`
/// and the Format menu so both act on the same selection with the same
/// behavior.
public enum EditorFormatting {

    /// Applies `command` to `text` with the given UTF-16 selection.
    /// - Returns: the new text and the selection to restore, or `nil` when the
    ///   selection is invalid.
    public static func apply(
        _ command: EditorFormatCommand,
        to text: String,
        selection: NSRange,
        listMarker: String = "* ",
        tabPadding: String = "    "
    ) -> (text: String, selection: NSRange)? {
        guard let range = EditorTextRange.range(from: selection, in: text) else { return nil }

        let result: (text: String, newRange: Range<String.Index>)
        switch command {
        case .paragraph:
            result = EditorOperations.setHeaderLevel(in: text, selectedRange: range, level: 0)
        case .h1, .h2, .h3, .h4, .h5, .h6:
            let level = Int(command.rawValue.dropFirst()) ?? 1
            result = EditorOperations.setHeaderLevel(in: text, selectedRange: range, level: level)
        case .strong:
            result = EditorOperations.toggleMarkup(in: text, selectedRange: range, prefix: "**", suffix: "**")
        case .emphasis:
            result = EditorOperations.toggleMarkup(in: text, selectedRange: range, prefix: "*", suffix: "*")
        case .inlineCode:
            result = EditorOperations.toggleMarkup(in: text, selectedRange: range, prefix: "`", suffix: "`")
        case .strikethrough:
            result = EditorOperations.toggleMarkup(in: text, selectedRange: range, prefix: "~~", suffix: "~~")
        case .underline:
            result = EditorOperations.toggleMarkup(in: text, selectedRange: range, prefix: "_", suffix: "_")
        case .highlight:
            result = EditorOperations.toggleMarkup(in: text, selectedRange: range, prefix: "==", suffix: "==")
        case .comment:
            result = EditorOperations.toggleMarkup(in: text, selectedRange: range, prefix: "<!--", suffix: "-->")
        case .codeBlock:
            result = EditorOperations.toggleMarkup(in: text, selectedRange: range, prefix: "```\n", suffix: "\n```")
        case .unorderedList:
            result = EditorOperations.toggleBlock(
                in: text, selectedRange: range, pattern: #"^[\*\-\+] \S"#, prefix: listMarker
            )
        case .orderedList:
            result = EditorOperations.toggleBlock(
                in: text, selectedRange: range, pattern: #"^[0-9]+ \S"#, prefix: "1. "
            )
        case .blockquote:
            result = EditorOperations.toggleBlock(
                in: text, selectedRange: range, pattern: #"^> \S"#, prefix: "> "
            )
        case .link:
            result = EditorOperations.toggleMarkup(
                in: text, selectedRange: range, prefix: "[", suffix: "](url)", placeholder: "link text"
            )
        case .image:
            result = EditorOperations.toggleMarkup(
                in: text, selectedRange: range, prefix: "![", suffix: "](url)", placeholder: "alt text"
            )
        case .indent:
            result = EditorOperations.indentLines(in: text, selectedRange: range, padding: tabPadding)
        case .unindent:
            result = EditorOperations.unindentLines(in: text, selectedRange: range)
        case .newParagraph:
            let newText = (text as NSString).replacingCharacters(in: selection, with: "\n\n")
            let newSelection = NSRange(location: selection.location + 2, length: 0)
            return (newText, newSelection)
        }
        return (result.text, EditorTextRange.nsRange(from: result.newRange, in: result.text))
    }
}