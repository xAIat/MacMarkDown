import Foundation

/// Buffers file URLs that arrive from the Finder ("Open With", double-click,
/// drag onto the Dock icon) until a `DocumentView` is ready to display them.
///
/// macOS delivers `application(_:open:)` before SwiftUI builds its scene when
/// the app is launched by opening a file, so the URLs must be held until the
/// document view appears. Requests that arrive while the app is already
/// running are announced through `.openDocumentFiles`.
@MainActor
public final class DocumentOpenQueue {

    public static let shared = DocumentOpenQueue()

    private var pending: [URL] = []

    private init() {}

    /// Records `urls` and notifies any visible document view.
    public func enqueue(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        pending.append(contentsOf: files)
        NotificationCenter.default.post(name: .openDocumentFiles, object: nil)
    }

    /// Returns and clears the URLs waiting to be opened.
    public func takeAll() -> [URL] {
        defer { pending.removeAll() }
        return pending
    }

    /// Returns and clears the first waiting URL. New windows each take one so
    /// a multi-file open spreads across windows.
    public func takeFirst() -> URL? {
        guard !pending.isEmpty else { return nil }
        return pending.removeFirst()
    }

    /// Whether a request is waiting (without consuming it).
    public var hasPending: Bool { !pending.isEmpty }
}

extension Notification.Name {
    /// Posted when file-open requests are waiting in `DocumentOpenQueue`.
    public static let openDocumentFiles = Notification.Name("MacMarkDownOpenDocumentFiles")
}
