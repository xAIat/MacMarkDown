import XCTest
@testable import MacMarkDownKit

/// The preview hands its tables to WebKit, so this markup and the page wrapping
/// it decide how a preview table looks. The markup must stay the one the HTML
/// export produces, and the page must carry the height channel the preview uses
/// to size the block.
@MainActor
final class TablePreviewHTMLTests: XCTestCase {

    private let table = TableData(
        headers: ["类别", "数值"],
        rows: [["运动相关", "12"], ["生活习惯", "8"]],
        alignments: [.center, .right]
    )

    func testMarkupIsARealTable() {
        let html = TablePreviewHTML.tableMarkup(table)
        XCTAssertTrue(html.contains("<table>"))
        XCTAssertTrue(html.contains("<thead><tr>"))
        XCTAssertTrue(html.contains("<th style=\"text-align: center\">类别</th>"))
        XCTAssertTrue(html.contains("<td style=\"text-align: right\">12</td>"))
        XCTAssertTrue(html.contains("</tbody></table>"))
    }

    func testMarkupEscapesCellText() {
        let html = TablePreviewHTML.tableMarkup(
            TableData(headers: ["<b>x</b>"], rows: [["a & b"]], alignments: [])
        )
        XCTAssertTrue(html.contains("&lt;b&gt;x&lt;/b&gt;"))
        XCTAssertTrue(html.contains("a &amp; b"))
    }

    func testExportAndPreviewShareTheTableMarkup() throws {
        let source = "| 类别 | 数值 |\n|:-:|--:|\n| 运动相关 | 12 |"
        let parsed = MarkdownParser().parseDocument(source, options: MarkdownParseOptions(enableTables: true))
        let table = try XCTUnwrap(parsed.elements.lazy.compactMap { element -> TableData? in
            if case .table(let data) = element { return data }
            return nil
        }.first)
        let exported = Renderer(theme: .clearness).renderToHTML(source, title: "T")
        XCTAssertTrue(
            exported.contains(TablePreviewHTML.tableMarkup(table)),
            "the export must emit the same markup the preview renders"
        )
    }

    func testPageCarriesTheStylesheetAndTheHeightChannel() {
        let page = TablePreviewHTML.page(markup: "<table></table>", theme: .clearness, zoom: 2)
        // The theme's own stylesheet decides borders and cell padding, exactly
        // as in the export.
        XCTAssertTrue(page.contains("border-collapse"))
        // The page is embedded, so it drops its own document chrome.
        XCTAssertTrue(page.contains("background: transparent"))
        XCTAssertTrue(page.contains("overflow: hidden"))
        XCTAssertTrue(page.contains("font-size: 28.0px"), "the preview zoom scales the table text")
        XCTAssertTrue(page.contains("messageHandlers.height.postMessage"))
    }

    func testEstimateGrowsWithTheRowCount() {
        let few = TablePreviewHTML.estimatedHeight(for: table, zoom: 1)
        let many = TablePreviewHTML.estimatedHeight(
            for: TableData(
                headers: table.headers,
                rows: Array(repeating: table.rows[0], count: 20),
                alignments: []
            ),
            zoom: 1
        )
        XCTAssertGreaterThan(many, few)
        XCTAssertGreaterThan(few, 0)
    }

    /// The preview stores a table as one placeholder character, so the copy path
    /// has to get the cells back out of the attachment.
    @MainActor
    func testAttachmentCarriesTheTableContent() {
        let attachment = TablePreviewHTML.Attachment(table: table, reservedHeight: 120)
        XCTAssertEqual(attachment.bounds.height, 120)
        XCTAssertEqual(
            attachment.plainText,
            "类别\t数值\n运动相关\t12\n生活习惯\t8"
        )
        XCTAssertEqual(attachment.html, TablePreviewHTML.tableMarkup(table))
    }

    @MainActor
    func testCopyingASelectionExpandsTablesIntoCells() {
        let attachment = TablePreviewHTML.Attachment(table: table, reservedHeight: 120)
        let content = NSMutableAttributedString(
            string: "before\n",
            attributes: [.font: NSFont.systemFont(ofSize: 14)]
        )
        content.append(NSAttributedString(attachment: attachment))
        content.append(NSAttributedString(string: "\nafter"))

        let expanded = MarkdownTextView.expandingWebBlockAttachments(in: content)
        XCTAssertTrue(expanded.string.contains("before"))
        XCTAssertTrue(expanded.string.contains("after"))
        XCTAssertTrue(expanded.string.contains("类别\t数值"))
        XCTAssertTrue(expanded.string.contains("生活习惯\t8"))
        XCTAssertFalse(
            expanded.string.contains("\u{FFFC}"),
            "the placeholder must not survive into the clipboard"
        )
    }

    /// End to end through the pasteboard the preview actually writes: a table in
    /// the selection must reach other apps as a real HTML table, and the RTF
    /// flavour (which cannot carry it, and which rich editors prefer) must not be
    /// offered alongside it.
    @MainActor
    func testWriteSelectionPutsTheTableTextOnThePasteboard() throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("MacMarkDownTableCopyTests"))
        pasteboard.clearContents()

        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        textView.isEditable = false
        let attachment = TablePreviewHTML.Attachment(table: table, reservedHeight: 120)
        let content = NSMutableAttributedString(string: "标题\n")
        content.append(NSAttributedString(attachment: attachment))
        XCTAssertTrue(textView.writeSelection(content, to: pasteboard))

        let copied = try XCTUnwrap(pasteboard.string(forType: .string))
        XCTAssertTrue(copied.contains("类别\t数值"), "the copied text must carry the table cells")
        XCTAssertFalse(copied.contains("\u{FFFC}"))

        let html = try XCTUnwrap(pasteboard.data(forType: .html))
            .withUnsafeBytes { String(decoding: $0, as: UTF8.self) }
        XCTAssertTrue(html.contains("<table>"), "the HTML flavour must carry a real table")
        XCTAssertTrue(html.contains("运动相关"), "and the cells themselves")
        XCTAssertFalse(html.contains("MACMARKDOWNTABLE"), "the splice token must not leak")

        XCTAssertNil(
            pasteboard.data(forType: .rtf),
            "RTF cannot carry the table and would win over HTML in rich editors"
        )
    }
}
