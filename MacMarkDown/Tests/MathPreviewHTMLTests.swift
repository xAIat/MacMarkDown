import XCTest
import AppKit
@testable import MacMarkDownKit

/// Guards the preview's MathJax page and the attachment the text surface
/// reserves for a formula.
final class MathPreviewHTMLTests: XCTestCase {

    @MainActor
    func testDelimitedWrapsAndEscapes() {
        XCTAssertEqual(
            MathPreviewHTML.delimited(tex: "E = mc^2", isDisplay: true),
            "\\[E = mc^2\\]"
        )
        XCTAssertEqual(
            MathPreviewHTML.delimited(tex: "\\frac{1}{2}", isDisplay: false),
            "\\(\\frac{1}{2}\\)"
        )
        XCTAssertEqual(
            MathPreviewHTML.delimited(tex: "a < b", isDisplay: true),
            "\\[a &lt; b\\]"
        )
    }

    @MainActor
    func testPageTypesetsWithTheBundledMathJax() {
        let page = MathPreviewHTML.page(tex: "E = mc^2", isDisplay: true, theme: .clearness, zoom: 1)
        XCTAssertTrue(page.contains("MathJax"), page)
        XCTAssertTrue(page.contains("\\[E = mc^2\\]"), page)
        XCTAssertFalse(
            page.contains("cdn.jsdelivr.net/npm/mathjax"),
            "the bundled distribution must be inlined, not linked from the CDN"
        )
        XCTAssertTrue(
            page.contains("window.webkit.messageHandlers.height.postMessage"),
            "the page must report its height so the placeholder can be corrected"
        )
    }

    @MainActor
    func testInlineAndDisplayPagesUseDifferentDelimiters() {
        let inline = MathPreviewHTML.page(tex: "x^2", isDisplay: false, theme: .clearness, zoom: 1)
        XCTAssertTrue(inline.contains("\\(x^2\\)"), inline)
        let display = MathPreviewHTML.page(tex: "x^2", isDisplay: true, theme: .clearness, zoom: 1)
        XCTAssertTrue(display.contains("\\[x^2\\]"), display)
    }

    @MainActor
    func testAttachmentCarriesTheTeXSource() {
        let attachment = MathPreviewHTML.Attachment(tex: "E = mc^2", isDisplay: true, reservedHeight: 60)
        XCTAssertEqual(attachment.bounds.height, 60)
        XCTAssertEqual(attachment.plainText, "\\[E = mc^2\\]")
        let inline = MathPreviewHTML.Attachment(tex: "x^2", isDisplay: false, reservedHeight: 24)
        XCTAssertEqual(inline.plainText, "\\(x^2\\)")
    }

    @MainActor
    func testDisplayEstimateIsTallerThanInline() {
        XCTAssertGreaterThan(
            MathPreviewHTML.estimatedHeight(isDisplay: true, zoom: 1),
            MathPreviewHTML.estimatedHeight(isDisplay: false, zoom: 1)
        )
        XCTAssertGreaterThan(
            MathPreviewHTML.estimatedHeight(isDisplay: true, zoom: 2),
            MathPreviewHTML.estimatedHeight(isDisplay: true, zoom: 1)
        )
    }
}
