import XCTest
@testable import MacMarkDownKit

@MainActor
final class DocumentOpenQueueTests: XCTestCase {

    private let queue = DocumentOpenQueue.shared

    override func setUp() async throws {
        _ = queue.takeAll()
    }

    func testTakeAllReturnsAndClearsPendingURLs() {
        let first = URL(fileURLWithPath: "/tmp/first.md")
        let second = URL(fileURLWithPath: "/tmp/second.md")

        queue.enqueue([first, second])

        XCTAssertEqual(queue.takeAll(), [first, second])
        XCTAssertTrue(queue.takeAll().isEmpty)
    }

    func testEnqueueIgnoresNonFileURLs() {
        queue.enqueue([URL(string: "https://example.com")!])
        XCTAssertTrue(queue.takeAll().isEmpty)
    }

    func testEnqueueAnnouncesOpenRequests() {
        let expectation = expectation(description: "open notification")
        let token = NotificationCenter.default.addObserver(
            forName: .openDocumentFiles, object: nil, queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(token) }

        queue.enqueue([URL(fileURLWithPath: "/tmp/file.md")])

        wait(for: [expectation], timeout: 1)
    }
}

// MARK: - URL scheme

final class AppURLSchemeTests: XCTestCase {

    func testPlainFileURLPassesThrough() {
        let url = URL(fileURLWithPath: "/tmp/doc.md")
        XCTAssertEqual(AppURLScheme.fileURL(from: url), url)
    }

    func testCustomSchemeResolvesFileURL() {
        let incoming = URL(string: "x-macmarkdown://open?url=file:///tmp/doc.md")!
        XCTAssertEqual(AppURLScheme.fileURL(from: incoming)?.path, "/tmp/doc.md")
    }

    func testCustomSchemeWithoutFileURLIsNil() {
        XCTAssertNil(AppURLScheme.fileURL(from: URL(string: "x-macmarkdown://open?url=https://example.com")!))
        XCTAssertNil(AppURLScheme.fileURL(from: URL(string: "x-macmarkdown://open")!))
    }

    func testUnknownSchemeIsNil() {
        XCTAssertNil(AppURLScheme.fileURL(from: URL(string: "https://example.com/doc.md")!))
    }
}

// MARK: - takeFirst (multi-window)

@MainActor
final class DocumentOpenQueueTakeFirstTests: XCTestCase {

    func testTakeFirstReturnsURLsInOrder() {
        let queue = DocumentOpenQueue.shared
        _ = queue.takeAll()
        let first = URL(fileURLWithPath: "/tmp/one.md")
        let second = URL(fileURLWithPath: "/tmp/two.md")
        queue.enqueue([first, second])

        XCTAssertEqual(queue.takeFirst(), first)
        XCTAssertEqual(queue.takeFirst(), second)
        XCTAssertNil(queue.takeFirst())
    }

    func testHasPendingReflectsQueue() {
        let queue = DocumentOpenQueue.shared
        _ = queue.takeAll()
        XCTAssertFalse(queue.hasPending)
        queue.enqueue([URL(fileURLWithPath: "/tmp/pending.md")])
        XCTAssertTrue(queue.hasPending)
        _ = queue.takeFirst()
        XCTAssertFalse(queue.hasPending)
    }
}
