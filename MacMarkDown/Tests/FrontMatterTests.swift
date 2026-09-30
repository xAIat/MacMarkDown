import XCTest
@testable import MacMarkDownKit

final class FrontMatterTests: XCTestCase {

    func testExtractFrontMatter() {
        let text = """
        ---
        title: My Document
        author: Test
        ---

        Actual markdown body.
        """
        let fm = FrontMatter.extract(from: text)
        XCTAssertNotNil(fm)
        XCTAssertEqual(fm?.title, "My Document")
        XCTAssertEqual(fm?.data["author"], "Test")
        XCTAssertEqual(fm?.body, "Actual markdown body.")
    }

    func testNoFrontMatter() {
        let text = """
        # Just a heading

        Some paragraph.
        """
        XCTAssertNil(FrontMatter.extract(from: text))
    }

    func testHasFrontMatter() {
        let text = "---\ntitle: X\n---\n# Heading"
        XCTAssertTrue(FrontMatter.hasFrontMatter(text))
    }

    func testParsesSequences() {
        let text = """
        ---
        title: Doc
        tags:
          - swift
          - markdown
        ---
        body
        """
        let fm = FrontMatter.extract(from: text)
        XCTAssertEqual(fm?.data["tags"], "swift, markdown")
        let tags = fm?.entries.first { $0.key == "tags" }?.value
        if case .list(let items)? = tags {
            XCTAssertEqual(items.map(\.displayString), ["swift", "markdown"])
        } else {
            XCTFail("Expected a list value")
        }
    }

    func testParsesNestedMapping() {
        let text = """
        ---
        title: Doc
        author:
          name: Ada
          email: ada@example.com
        ---
        body
        """
        let fm = FrontMatter.extract(from: text)
        let author = fm?.entries.first { $0.key == "author" }?.value
        guard case .map(let entries)? = author else {
            return XCTFail("Expected a nested mapping")
        }
        XCTAssertEqual(entries.first { $0.key == "name" }?.value.displayString, "Ada")
    }

    func testParsesBooleanScalar() {
        let text = "---\ndraft: true\n---\nbody"
        let fm = FrontMatter.extract(from: text)
        XCTAssertEqual(fm?.data["draft"], "true")
    }
}