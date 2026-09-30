import AppKit
import XCTest
@testable import MacMarkDownKit

@MainActor
final class SyntaxHighlighterTests: XCTestCase {

    private let theme = EditorTheme.defaultLight
    private let font = NSFont.systemFont(ofSize: 14)
    private var paragraph: NSParagraphStyle { NSParagraphStyle.default }

    private func attributed(_ text: String) -> NSAttributedString {
        MarkdownSyntaxHighlighter(theme: theme)
            .attributedString(for: text, font: font, paragraphStyle: paragraph)
    }

    private func color(at index: Int, in string: NSAttributedString) -> NSColor? {
        string.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    func testBaseColor() {
        let attrs = attributed("plain text")
        XCTAssertEqual(color(at: 0, in: attrs), theme.nsTextColor)
    }

    func testATXHeading() {
        let attrs = attributed("# Hello")
        XCTAssertEqual(color(at: 0, in: attrs), theme.nsHeadingColor)
        XCTAssertEqual(color(at: 6, in: attrs), theme.nsHeadingColor)
    }

    func testSetextHeading() {
        let attrs = attributed("Title\n=====")
        XCTAssertEqual(color(at: 0, in: attrs), theme.nsHeadingColor)
    }

    func testUnorderedListMarker() {
        let attrs = attributed("- Item")
        XCTAssertEqual(color(at: 0, in: attrs), theme.nsListMarkerColor)
        XCTAssertEqual(color(at: 2, in: attrs), theme.nsTextColor)
    }

    func testOrderedListMarker() {
        let attrs = attributed("1. Item")
        XCTAssertEqual(color(at: 0, in: attrs), theme.nsListMarkerColor)
    }

    func testBlockquoteMarker() {
        let attrs = attributed("> quoted")
        XCTAssertEqual(color(at: 0, in: attrs), theme.nsQuoteColor)
    }

    func testFencedCodeBlock() {
        let attrs = attributed("```swift\nlet x = 1\n```")
        XCTAssertEqual(color(at: 3, in: attrs), theme.nsCodeColor)
    }

    func testInlineCode() {
        let attrs = attributed("A `x` B")
        let x = (attrs.string as NSString).range(of: "x").location
        XCTAssertEqual(color(at: x, in: attrs), theme.nsCodeColor)
    }

    func testStrong() {
        let attrs = attributed("**bold**")
        XCTAssertEqual(color(at: 2, in: attrs), theme.nsStrongColor)
        let fontAt = attrs.attribute(.font, at: 2, effectiveRange: nil) as? NSFont
        let traits = NSFontManager.shared.traits(of: fontAt!)
        XCTAssertTrue(traits.contains(.boldFontMask))
    }

    func testEmphasis() {
        let attrs = attributed("*italic*")
        XCTAssertEqual(color(at: 1, in: attrs), theme.nsEmphasisColor)
    }

    func testLink() {
        let attrs = attributed("[Apple](https://apple.com)")
        let textRange = (attrs.string as NSString).range(of: "Apple")
        XCTAssertEqual(color(at: textRange.location, in: attrs), theme.nsLinkColor)
        let urlRange = (attrs.string as NSString).range(of: "https://apple.com")
        XCTAssertEqual(color(at: urlRange.location, in: attrs), theme.nsCodeColor)
    }

    func testStrikethrough() {
        let attrs = attributed("~~gone~~")
        let strikethrough = attrs.attribute(
            .strikethroughStyle, at: 2, effectiveRange: nil
        ) as? Int
        XCTAssertEqual(strikethrough, NSUnderlineStyle.single.rawValue)
    }

    func testInlineCodeSuppressesStrong() {
        let attrs = attributed("`**not bold**`")
        let loc = (attrs.string as NSString).range(of: "**not bold**").location
        XCTAssertEqual(color(at: loc, in: attrs), theme.nsCodeColor)
    }
}