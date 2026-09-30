import SwiftUI

/// Formatting toolbar for the Markdown editor: headers, emphasis, lists,
/// links, indent, and export.
struct ToolbarView: View {

    @Binding var text: String
    /// The editor's current selection, mirrored from the text view; operations
    /// apply here and write the resulting range back so the caret follows.
    @Binding var selection: NSRange
    let preferences: Preferences
    let onTogglePreview: () -> Void
    let onToggleEditor: () -> Void
    let onExportHTML: () -> Void
    let onManualRender: () -> Void

    var body: some View {
        Group {
            Menu {
                Button("Paragraph") { setHeaderLevel(0) }
                Button("Heading 1") { setHeaderLevel(1) }
                Button("Heading 2") { setHeaderLevel(2) }
                Button("Heading 3") { setHeaderLevel(3) }
                Button("Heading 4") { setHeaderLevel(4) }
                Button("Heading 5") { setHeaderLevel(5) }
                Button("Heading 6") { setHeaderLevel(6) }
                Divider()
                Button("Blockquote") { toggleBlockquote() }
                Button("Code Block") { toggleCodeBlock() }
            } label: {
                Label("Style", systemImage: "textformat")
            }

            Divider()

            Button { toggleEmphasis() } label: {
                Label("Italic", systemImage: "italic")
            }
            .help("Italic")

            Button { toggleStrong() } label: {
                Label("Bold", systemImage: "bold")
            }
            .help("Bold")

            Button { toggleCode() } label: {
                Label("Code", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            .help("Inline Code")

            Button { toggleStrikethrough() } label: {
                Label("Strikethrough", systemImage: "strikethrough")
            }
            .help("Strikethrough")

            Button { toggleUnderline() } label: {
                Label("Underline", systemImage: "underline")
            }
            .help("Underline")

            Button { toggleHighlight() } label: {
                Label("Highlight", systemImage: "highlighter")
            }
            .help("Highlight")

            Button { toggleComment() } label: {
                Label("Comment", systemImage: "text.bubble")
            }
            .help("Comment")

            Divider()

            Menu {
                Button("Unordered List") { toggleUnorderedList() }
                Button("Ordered List") { toggleOrderedList() }
                Divider()
                Button("Indent") { indent() }
                Button("Unindent") { unindent() }
            } label: {
                Label("List", systemImage: "list.bullet")
            }

            Button { toggleLink() } label: {
                Label("Link", systemImage: "link")
            }
            .help("Link")

            Button { toggleImage() } label: {
                Label("Image", systemImage: "photo")
            }
            .help("Image")

            Divider()

            Button { onToggleEditor() } label: {
                Label("Editor Only", systemImage: "sidebar.left")
            }
            .help("Toggle Editor Pane")

            Button { onTogglePreview() } label: {
                Label("Preview", systemImage: "sidebar.right")
            }
            .help("Toggle Preview Pane")

            Button { onExportHTML() } label: {
                Label("Export HTML", systemImage: "square.and.arrow.up")
            }
            .help("Export as HTML")

            if preferences.markdownManualRender {
                Button { onManualRender() } label: {
                    Label("Render", systemImage: "arrow.clockwise")
                }
                .help("Render Preview")
            }
        }
    }

    // MARK: - Operations

    private func perform(_ command: EditorFormatCommand) {
        guard let result = EditorFormatting.apply(
            command,
            to: text,
            selection: selection,
            listMarker: preferences.editorUnorderedListMarker,
            tabPadding: preferences.editorConvertTabs ? "    " : "\t"
        ) else { return }
        text = result.text
        selection = result.selection
    }

    private func setHeaderLevel(_ level: Int) {
        switch level {
        case 0: perform(.paragraph)
        case 1: perform(.h1)
        case 2: perform(.h2)
        case 3: perform(.h3)
        case 4: perform(.h4)
        case 5: perform(.h5)
        default: perform(.h6)
        }
    }

    private func toggleEmphasis() { perform(.emphasis) }
    private func toggleStrong() { perform(.strong) }
    private func toggleCode() { perform(.inlineCode) }
    private func toggleStrikethrough() { perform(.strikethrough) }
    private func toggleUnderline() { perform(.underline) }
    private func toggleHighlight() { perform(.highlight) }
    private func toggleComment() { perform(.comment) }
    private func toggleBlockquote() { perform(.blockquote) }
    private func toggleCodeBlock() { perform(.codeBlock) }
    private func toggleUnorderedList() { perform(.unorderedList) }
    private func toggleOrderedList() { perform(.orderedList) }
    private func toggleLink() { perform(.link) }
    private func toggleImage() { perform(.image) }
    private func indent() { perform(.indent) }
    private func unindent() { perform(.unindent) }
}