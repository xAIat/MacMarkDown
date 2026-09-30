import XCTest

@testable import MacMarkDownKit

/// The guard's decision logic is separated from the modal alert so it can be
/// exercised headlessly.
@MainActor
final class UnsavedChangesGuardTests: XCTestCase {

    private func makeDocument(edited: Bool, url: URL? = nil) -> MarkdownDocument {
        let suite = UserDefaults(suiteName: "MacMarkDownTests.guard.\(UUID().uuidString)")
        let preferences = Preferences(defaults: suite ?? .standard)
        preferences.editorEnsuresNewlineAtEndOfFile = false
        let document = MarkdownDocument(preferences: preferences, url: url)
        if edited {
            document.updateText("dirty")
        }
        return document
    }

    func testCleanDocumentClosesWithoutPrompt() {
        let guardObject = UnsavedChangesGuard()
        let document = makeDocument(edited: false)
        guardObject.document = document
        var prompted = false
        guardObject.promptOverride = { _ in
            prompted = true
            return .cancel
        }
        XCTAssertTrue(guardObject.confirmClose())
        XCTAssertFalse(prompted)
    }

    func testDiscardClosesWithoutSaving() {
        let guardObject = UnsavedChangesGuard()
        let document = makeDocument(edited: true)
        guardObject.document = document
        var saved = false
        guardObject.promptOverride = { _ in .discard }
        guardObject.saveOverride = { _ in
            saved = true
            return true
        }
        XCTAssertTrue(guardObject.confirmClose())
        XCTAssertFalse(saved)
    }

    func testCancelVetoesClose() {
        let guardObject = UnsavedChangesGuard()
        let document = makeDocument(edited: true)
        guardObject.document = document
        guardObject.promptOverride = { _ in .cancel }
        XCTAssertFalse(guardObject.confirmClose())
    }

    func testSaveClosesWhenSaveSucceeds() {
        let guardObject = UnsavedChangesGuard()
        let document = makeDocument(edited: true)
        guardObject.document = document
        guardObject.promptOverride = { _ in .save }
        guardObject.saveOverride = { _ in true }
        XCTAssertTrue(guardObject.confirmClose())
    }

    func testSaveFailureVetoesClose() {
        let guardObject = UnsavedChangesGuard()
        let document = makeDocument(edited: true)
        guardObject.document = document
        guardObject.promptOverride = { _ in .save }
        guardObject.saveOverride = { _ in false }
        XCTAssertFalse(guardObject.confirmClose())
    }

    func testSaveWritesDocumentToDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("guard-\(UUID().uuidString).md")
        try "original".write(to: url, atomically: true, encoding: .utf8)
        let document = makeDocument(edited: true, url: url)

        let guardObject = UnsavedChangesGuard()
        guardObject.document = document
        guardObject.promptOverride = { _ in .save }

        XCTAssertTrue(guardObject.confirmClose())
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "dirty")
        XCTAssertFalse(document.isEdited)
    }
}