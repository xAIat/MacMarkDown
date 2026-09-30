import XCTest

@testable import MacMarkDownKit

final class PreviewSupportTests: XCTestCase {

    // MARK: - Zoom

    func testZoomDisabledIsUnity() {
        XCTAssertEqual(PreviewZoom.factor(enabled: false, editorFontSize: 20), 1)
    }

    func testZoomRelativeToReferenceFont() {
        XCTAssertEqual(PreviewZoom.factor(enabled: true, editorFontSize: 14), 1)
        XCTAssertEqual(PreviewZoom.factor(enabled: true, editorFontSize: 28), 2)
        XCTAssertEqual(PreviewZoom.factor(enabled: true, editorFontSize: 7), 0.5)
    }

    func testZoomIgnoresInvalidFontSize() {
        XCTAssertEqual(PreviewZoom.factor(enabled: true, editorFontSize: 0), 1)
        XCTAssertEqual(PreviewZoom.factor(enabled: true, editorFontSize: -3), 1)
    }

    // MARK: - Link resolution

    func testRelativeLinkResolvesAgainstDocumentDirectory() {
        let base = URL(fileURLWithPath: "/tmp/docs")
        XCTAssertEqual(
            PreviewLinkResolver.resolve("notes/other.md", baseURL: base)?.path,
            "/tmp/docs/notes/other.md"
        )
    }

    func testAbsoluteLinkPassesThrough() {
        XCTAssertEqual(
            PreviewLinkResolver.resolve("https://example.com", baseURL: URL(fileURLWithPath: "/tmp"))?.absoluteString,
            "https://example.com"
        )
    }

    func testMissingLinkReturnsNil() {
        XCTAssertNil(PreviewLinkResolver.resolve(nil, baseURL: nil))
        XCTAssertNil(PreviewLinkResolver.resolve("", baseURL: nil))
    }

    // MARK: - Existing target / creation

    func testAppendsMarkdownExtensionWhenSiblingExists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = directory.appendingPathComponent("page")
        let markdown = directory.appendingPathComponent("page.md")
        try "x".write(to: markdown, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            PreviewLinkResolver.existingTarget(for: target).path,
            markdown.path
        )
    }

    func testExistingTargetUnchangedWhenFileExists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = directory.appendingPathComponent("page.md")
        try "x".write(to: target, atomically: true, encoding: .utf8)
        XCTAssertEqual(PreviewLinkResolver.existingTarget(for: target).path, target.path)
    }

    func testCreatesMissingLinkTarget() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("link-\(UUID().uuidString)")
        let target = directory.appendingPathComponent("new/note.md")
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(PreviewLinkResolver.createFileIfNeeded(at: target))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }
}