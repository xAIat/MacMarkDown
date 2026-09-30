import Foundation
import AppKit

/// Handles export operations: HTML file export, PDF export via printing,
/// printing, and copying HTML to the clipboard.
@MainActor
public enum ExportService {

    /// Export the rendered HTML to a file.
    ///
    /// - Parameters:
    ///   - inlineStyles: Include the theme stylesheet in the output.
    ///   - highlighting: Include code syntax highlighting spans and CSS.
    public static func exportHTML(
        text: String,
        title: String,
        theme: Theme,
        parser: MarkdownParser,
        options: MarkdownParseOptions = MarkdownParseOptions(),
        to url: URL,
        inlineStyles: Bool = true,
        highlighting: Bool = true
    ) throws {
        var options = options
        options.enableSyntaxHighlighting = highlighting
        let renderer = Renderer(parser: parser, theme: theme, options: options)
        let html = renderer.renderToHTML(text, title: title, inlineStyles: inlineStyles)
        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Copy the rendered HTML document to the clipboard (`public.html` and
    /// plain text). The document includes inline styles so pasting into a
    /// rich-text target keeps the formatting.
    public static func copyHTML(
        text: String,
        title: String = "",
        theme: Theme = .clearness,
        parser: MarkdownParser,
        options: MarkdownParseOptions = MarkdownParseOptions()
    ) {
        let renderer = Renderer(parser: parser, theme: theme, options: options)
        let html = renderer.renderToHTML(text, title: title, inlineStyles: true)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .init(Constants.htmlPasteboardType))
        pasteboard.setString(html, forType: .string)
    }

    /// Export to PDF by printing rendered HTML to a file via a print job.
    public static func exportPDF(
        text: String,
        title: String,
        theme: Theme,
        options: MarkdownParseOptions = MarkdownParseOptions(),
        to url: URL
    ) {
        let printInfo = NSPrintInfo.shared
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobDisposition] =
            NSPrintInfo.JobDisposition.save
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        print(text: text, title: title, theme: theme, options: options, printInfo: printInfo, showsPanel: false)
    }

    /// Print the rendered document with the standard print panel.
    public static func print(
        text: String,
        title: String,
        theme: Theme,
        options: MarkdownParseOptions = MarkdownParseOptions()
    ) {
        print(text: text, title: title, theme: theme, options: options, printInfo: .shared, showsPanel: true)
    }

    // MARK: - Printing core

    private static func print(
        text: String,
        title: String,
        theme: Theme,
        options: MarkdownParseOptions,
        printInfo: NSPrintInfo,
        showsPanel: Bool
    ) {
        guard let attributed = attributedDocument(text: text, title: title, theme: theme, options: options) else {
            return
        }

        let pageWidth = printInfo.paperSize.width - printInfo.leftMargin - printInfo.rightMargin
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: printInfo.paperSize.height))
        textView.textStorage?.setAttributedString(attributed)
        textView.sizeToFit()

        let operation = NSPrintOperation(view: textView, printInfo: printInfo)
        operation.showsPrintPanel = showsPanel
        operation.run()
    }

    /// HTML → `NSAttributedString` using AppKit's HTML importer.
    private static func attributedDocument(
        text: String,
        title: String,
        theme: Theme,
        options: MarkdownParseOptions
    ) -> NSAttributedString? {
        let attrs: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        let renderer = Renderer(parser: MarkdownParser(), theme: theme, options: options)
        let html = renderer.renderToHTML(text, title: title, inlineStyles: true)
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(data: data, options: attrs, documentAttributes: nil)
        else { return nil }
        return attributed
    }
}