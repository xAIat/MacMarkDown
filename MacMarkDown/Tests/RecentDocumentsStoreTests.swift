import XCTest

@testable import MacMarkDownKit

@MainActor
final class RecentDocumentsStoreTests: XCTestCase {

    private func makeStore() -> RecentDocumentsStore {
        let suite = UserDefaults(suiteName: "MacMarkDownTests.recents.\(UUID().uuidString)")
        return RecentDocumentsStore(defaults: suite ?? .standard)
    }

    func testRecordsMostRecentFirst() {
        let store = makeStore()
        store.record(URL(fileURLWithPath: "/tmp/a.md"))
        store.record(URL(fileURLWithPath: "/tmp/b.md"))
        XCTAssertEqual(store.urls.map(\.lastPathComponent), ["b.md", "a.md"])
    }

    func testRecordingSameURLMovesItToFront() {
        let store = makeStore()
        store.record(URL(fileURLWithPath: "/tmp/a.md"))
        store.record(URL(fileURLWithPath: "/tmp/b.md"))
        store.record(URL(fileURLWithPath: "/tmp/a.md"))
        XCTAssertEqual(store.urls.map(\.lastPathComponent), ["a.md", "b.md"])
    }

    func testCapsAtTenEntries() {
        let store = makeStore()
        for index in 0..<15 {
            store.record(URL(fileURLWithPath: "/tmp/\(index).md"))
        }
        XCTAssertEqual(store.urls.count, 10)
        XCTAssertEqual(store.urls.first?.lastPathComponent, "14.md")
    }

    func testClearRemovesEntries() {
        let store = makeStore()
        store.record(URL(fileURLWithPath: "/tmp/a.md"))
        store.clear()
        XCTAssertTrue(store.urls.isEmpty)
    }

    func testPruneDropsMissingFiles() throws {
        let store = makeStore()
        let existing = FileManager.default.temporaryDirectory
            .appendingPathComponent("recent-\(UUID().uuidString).md")
        try "x".write(to: existing, atomically: true, encoding: .utf8)
        store.record(existing)
        store.record(URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).md"))

        store.pruneMissing()
        XCTAssertEqual(store.urls.map(\.lastPathComponent), [existing.lastPathComponent])
    }

    func testNonFileURLIsIgnored() {
        let store = makeStore()
        store.record(URL(string: "https://example.com/a.md")!)
        XCTAssertTrue(store.urls.isEmpty)
    }
}