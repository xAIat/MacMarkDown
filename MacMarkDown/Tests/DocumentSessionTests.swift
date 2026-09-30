import AppKit
import XCTest

@testable import MacMarkDownKit

@MainActor
final class DocumentSessionTests: XCTestCase {

    private func makeDocument() -> MarkdownDocument {
        let suite = UserDefaults(suiteName: "MacMarkDownTests.session.\(UUID().uuidString)")
        return MarkdownDocument(preferences: Preferences(defaults: suite ?? .standard))
    }

    func testRegistersAndLooksUpMostRecent() {
        let session = DocumentSession.shared
        let first = makeDocument()
        let second = makeDocument()
        let firstID = UUID()
        let secondID = UUID()
        session.register(id: firstID, document: first, window: nil) { _ in }
        session.register(id: secondID, document: second, window: nil) { _ in }

        // No key window in tests → most recently registered wins.
        XCTAssertTrue(session.document === second)
        XCTAssertEqual(session.documents.count, 2)

        session.unregister(id: firstID)
        session.unregister(id: secondID)
        XCTAssertTrue(session.documents.isEmpty)
    }

    func testUnregisterRemovesEntry() {
        let session = DocumentSession.shared
        let document = makeDocument()
        let id = UUID()
        session.register(id: id, document: document, window: nil) { _ in }
        XCTAssertTrue(session.document === document)

        session.unregister(id: id)
        XCTAssertFalse(session.documents.contains { $0 === document })
    }

    func testOpenFileReusesBlankKeyDocument() {
        let session = DocumentSession.shared
        let document = makeDocument()
        let id = UUID()
        var loaded: URL?
        session.register(id: id, document: document, window: nil) { loaded = $0 }

        let url = URL(fileURLWithPath: "/tmp/blank-target.md")
        session.openFile(url)
        XCTAssertEqual(loaded, url)
        // No window request needed for a blank buffer.
        session.unregister(id: id)
    }

    func testOpenFileQueuesForDirtyDocument() {
        let session = DocumentSession.shared
        let document = makeDocument()
        document.updateText("dirty")
        let id = UUID()
        var loaded: URL?
        session.register(id: id, document: document, window: nil) { loaded = $0 }

        let url = URL(fileURLWithPath: "/tmp/dirty-target.md")
        session.openFile(url)
        // The dirty window must not be clobbered; the URL waits for a new window.
        XCTAssertNil(loaded)
        XCTAssertEqual(DocumentOpenQueue.shared.takeFirst(), url)

        session.unregister(id: id)
    }

    func testFlushAutosaveVisitsAllDocuments() throws {
        let session = DocumentSession.shared
        let directory = FileManager.default.temporaryDirectory
        let firstURL = directory.appendingPathComponent("flush-\(UUID().uuidString).md")
        let secondURL = directory.appendingPathComponent("flush-\(UUID().uuidString).md")
        try "a".write(to: firstURL, atomically: true, encoding: .utf8)
        try "b".write(to: secondURL, atomically: true, encoding: .utf8)

        let suite = UserDefaults(suiteName: "MacMarkDownTests.session.\(UUID().uuidString)")
        let preferences = Preferences(defaults: suite ?? .standard)
        preferences.editorEnsuresNewlineAtEndOfFile = false
        preferences.editorAutosaveEnabled = true

        let first = MarkdownDocument(preferences: preferences, url: firstURL)
        let second = MarkdownDocument(preferences: preferences, url: secondURL)
        first.updateText("first")
        second.updateText("second")

        let firstID = UUID()
        let secondID = UUID()
        session.register(id: firstID, document: first, window: nil) { _ in }
        session.register(id: secondID, document: second, window: nil) { _ in }

        session.flushAutosave()

        XCTAssertEqual(try String(contentsOf: firstURL, encoding: .utf8), "first")
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "second")

        session.unregister(id: firstID)
        session.unregister(id: secondID)
    }
}