import XCTest

@testable import MacMarkDownKit

/// Autosave is opt-in: `Preferences.editorAutosaveEnabled` defaults to `false`
/// and gates both the debounced writes and the quit/close flush.
@MainActor
final class MarkdownDocumentAutosaveTests: XCTestCase {

    private func makePreferences() -> Preferences {
        let suite = UserDefaults(suiteName: "MacMarkDownTests.autosave.\(UUID().uuidString)")
        return Preferences(defaults: suite ?? .standard)
    }

    private func makeTempFile(contents: String = "original") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("autosave-\(UUID().uuidString).md")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func contents(of url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func testAutosaveIsDisabledByDefault() {
        XCTAssertFalse(makePreferences().editorAutosaveEnabled)
    }

    func testUpdateTextDoesNotWriteWhenDisabled() throws {
        let url = try makeTempFile()
        let preferences = makePreferences()
        preferences.editorEnsuresNewlineAtEndOfFile = false
        let document = MarkdownDocument(preferences: preferences, url: url)

        document.updateText("changed")
        document.autosaveNow()

        XCTAssertEqual(try contents(of: url), "original")
        XCTAssertTrue(document.isEdited)
    }

    func testAutosaveNowWritesWhenEnabled() throws {
        let url = try makeTempFile()
        let preferences = makePreferences()
        preferences.editorEnsuresNewlineAtEndOfFile = false
        preferences.editorAutosaveEnabled = true
        let document = MarkdownDocument(preferences: preferences, url: url)

        document.updateText("changed")
        document.autosaveNow()

        XCTAssertEqual(try contents(of: url), "changed")
        XCTAssertFalse(document.isEdited)
    }

    func testManualSaveIsUnaffectedByAutosavePreference() throws {
        let url = try makeTempFile()
        let preferences = makePreferences()
        preferences.editorEnsuresNewlineAtEndOfFile = false
        let document = MarkdownDocument(preferences: preferences, url: url)

        document.updateText("manually saved")
        try document.save(to: url, checkConflict: false)

        XCTAssertEqual(try contents(of: url), "manually saved")
        XCTAssertFalse(document.isEdited)
    }

    // MARK: - Edited flag tracks the saved content (undo clears it)

    func testUndoBackToSavedContentClearsEditedFlag() throws {
        let url = try makeTempFile(contents: "original")
        let preferences = makePreferences()
        preferences.editorEnsuresNewlineAtEndOfFile = false
        let document = MarkdownDocument(preferences: preferences, url: url)

        XCTAssertFalse(document.isEdited)
        document.updateText("changed")
        XCTAssertTrue(document.isEdited)

        // ⌘Z brings the buffer back to the saved content.
        document.updateText("original")
        XCTAssertFalse(document.isEdited)
    }

    func testPartialUndoKeepsEditedFlag() throws {
        let url = try makeTempFile(contents: "original")
        let preferences = makePreferences()
        preferences.editorEnsuresNewlineAtEndOfFile = false
        let document = MarkdownDocument(preferences: preferences, url: url)

        document.updateText("changed")
        document.updateText("changed again")
        // Still ahead of the saved content after a partial undo.
        document.updateText("changed")
        XCTAssertTrue(document.isEdited)
    }

    func testLoadedFileWithoutTrailingNewlineIsCleanWhenSettingOn() throws {
        let url = try makeTempFile(contents: "line1")
        let preferences = makePreferences()
        preferences.editorEnsuresNewlineAtEndOfFile = true
        let document = MarkdownDocument(preferences: preferences, url: url)

        XCTAssertFalse(document.isEdited)
    }

    func testTrailingNewlineIsNotAnEditWhenSettingOn() throws {
        let url = try makeTempFile(contents: "line1")
        let preferences = makePreferences()
        preferences.editorEnsuresNewlineAtEndOfFile = true
        let document = MarkdownDocument(preferences: preferences, url: url)

        // Typing Return at the end produces "line1\n" — the same normalized
        // form the file will be saved in, so it is not an edit.
        document.updateText("line1\n")
        XCTAssertFalse(document.isEdited)

        document.updateText("line1\nchanged")
        XCTAssertTrue(document.isEdited)
    }

    func testSaveClearsEditedFlagWhenSettingOn() throws {
        let url = try makeTempFile(contents: "original")
        let preferences = makePreferences()
        preferences.editorEnsuresNewlineAtEndOfFile = true
        let document = MarkdownDocument(preferences: preferences, url: url)

        document.updateText("changed")
        XCTAssertTrue(document.isEdited)
        try document.save(to: url, checkConflict: false)
        XCTAssertFalse(document.isEdited)
        XCTAssertEqual(try contents(of: url), "changed\n")
    }
}
// MARK: - Blank-buffer routing

@MainActor
final class MarkdownDocumentBlankStateTests: XCTestCase {

    func testFreshDocumentIsBlankAndUnedited() {
        let suite = UserDefaults(suiteName: "MacMarkDownTests.blank.\(UUID().uuidString)")
        let document = MarkdownDocument(preferences: Preferences(defaults: suite ?? .standard))
        XCTAssertTrue(document.isBlankAndUnedited)
    }

    func testEditedDocumentIsNotBlank() {
        let suite = UserDefaults(suiteName: "MacMarkDownTests.blank.\(UUID().uuidString)")
        let document = MarkdownDocument(preferences: Preferences(defaults: suite ?? .standard))
        document.updateText("x")
        XCTAssertFalse(document.isBlankAndUnedited)
    }

    func testFileBoundDocumentIsNotBlank() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("blank-\(UUID().uuidString).md")
        try "".write(to: url, atomically: true, encoding: .utf8)
        let suite = UserDefaults(suiteName: "MacMarkDownTests.blank.\(UUID().uuidString)")
        let document = MarkdownDocument(preferences: Preferences(defaults: suite ?? .standard), url: url)
        XCTAssertFalse(document.isBlankAndUnedited)
    }
}
