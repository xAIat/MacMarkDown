import AppKit
import XCTest

@testable import MacMarkDownKit

/// The AppleScript bridge is KVC-based; these tests exercise the same
/// accessors AppleScript resolves through `value(forKey:)`.
@MainActor
final class ScriptableDocumentTests: XCTestCase {

    private func makeDocument(text: String = "# Title\n\nBody") -> MarkdownDocument {
        let suite = UserDefaults(suiteName: "MacMarkDownTests.script.\(UUID().uuidString)")
        let preferences = Preferences(defaults: suite ?? .standard)
        let document = MarkdownDocument(preferences: preferences)
        document.updateText(text)
        return document
    }

    func testTextIsReadableAndWritableThroughKVC() throws {
        let scriptable = ScriptableDocument(document: makeDocument())
        XCTAssertEqual(try XCTUnwrap(scriptable.value(forKey: "text") as? String), "# Title\n\nBody")

        scriptable.setValue("# Changed", forKey: "text")
        XCTAssertEqual(scriptable.text, "# Changed")
    }

    func testHTMLIsRendered() throws {
        let scriptable = ScriptableDocument(document: makeDocument())
        let html = try XCTUnwrap(scriptable.value(forKey: "html") as? String)
        XCTAssertTrue(html.contains("<h1"))
        XCTAssertTrue(html.contains("Title"))
    }

    func testNameModifiedAndFile() throws {
        let scriptable = ScriptableDocument(document: makeDocument(text: "# Hello World"))
        XCTAssertEqual(try XCTUnwrap(scriptable.value(forKey: "name") as? String), "Hello World")
        XCTAssertEqual(try XCTUnwrap(scriptable.value(forKey: "modified") as? Bool), true)
        XCTAssertNil(scriptable.value(forKey: "file") as? String)
    }

    func testApplicationDocumentsExposeOpenWindows() throws {
        let session = DocumentSession.shared
        let document = makeDocument()
        let id = UUID()
        session.register(id: id, document: document, window: nil) { _ in }
        defer { session.unregister(id: id) }

        let documents = NSApplication.shared.documents
        XCTAssertTrue(documents.contains { $0.text == document.text })
    }
}