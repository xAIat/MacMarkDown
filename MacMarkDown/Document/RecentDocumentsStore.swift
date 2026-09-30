import Foundation

/// Tracks recently opened documents in `UserDefaults`, mirroring
/// `NSDocumentController`'s recent-documents list for the app's single-window
/// session model.
@MainActor
@Observable
public final class RecentDocumentsStore {

    public static let shared = RecentDocumentsStore()

    /// The most recent first; capped at `maxCount`.
    public private(set) var urls: [URL] = []

    private let defaults: UserDefaults
    private static let key = "recentDocumentPaths"
    private static let maxCount = 10

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let paths = defaults.stringArray(forKey: Self.key) ?? []
        urls = paths.map { URL(fileURLWithPath: $0) }
    }

    /// Records `url` as the most recent document.
    public func record(_ url: URL) {
        guard url.isFileURL else { return }
        var paths = urls.map(\.path)
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        if paths.count > Self.maxCount {
            paths = Array(paths.prefix(Self.maxCount))
        }
        urls = paths.map { URL(fileURLWithPath: $0) }
        defaults.set(paths, forKey: Self.key)
    }

    public func clear() {
        urls = []
        defaults.removeObject(forKey: Self.key)
    }

    /// Drops entries whose files no longer exist.
    public func pruneMissing() {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard existing.count != urls.count else { return }
        urls = existing
        defaults.set(existing.map(\.path), forKey: Self.key)
    }
}