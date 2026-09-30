import SwiftUI
import XCTest
@testable import MacMarkDownKit

/// Pixel-level checks that the preview actually renders emphasis/strong with
/// different glyphs. `View.italic()`/`.bold()` on a container did not reach the
/// child `Text` views, so these pin the leaf-font behavior.
@MainActor
final class InlineStyleRenderingTests: XCTestCase {

    private func render<V: View>(_ view: V) -> Data? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage?.tiffRepresentation
    }

    func testItalicChangesRendering() {
        let plain = render(InlineRenderer(inlines: [.text("hello")], theme: .clearness, italic: false))
        let italic = render(InlineRenderer(inlines: [.text("hello")], theme: .clearness, italic: true))
        XCTAssertNotNil(plain)
        XCTAssertNotNil(italic)
        XCTAssertNotEqual(plain, italic, "italic text must render differently")
    }

    func testBoldChangesRendering() {
        let plain = render(InlineRenderer(inlines: [.text("hello")], theme: .clearness, bold: false))
        let bold = render(InlineRenderer(inlines: [.text("hello")], theme: .clearness, bold: true))
        XCTAssertNotEqual(plain, bold, "bold text must render differently")
    }

    func testEmphasisParagraphDiffersFromPlain() {
        let plain = render(MarkdownView(elements: [.paragraph([.text("hello")])], theme: .clearness))
        let emphasis = render(MarkdownView(elements: [.paragraph([.emphasis([.text("hello")])])], theme: .clearness))
        XCTAssertNotNil(plain)
        XCTAssertNotNil(emphasis)
        XCTAssertNotEqual(plain, emphasis, "emphasis must render differently from plain text")
    }
}
