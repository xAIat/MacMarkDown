import Foundation

/// Preview zoom math: the preview scales relative to the editor's base font,
/// with 14 pt as the reference.
public enum PreviewZoom {
    public static let referenceFontSize: Double = 14

    /// The scale factor for the preview, or `1` when zoom is disabled.
    public static func factor(enabled: Bool, editorFontSize: Double) -> Double {
        guard enabled, editorFontSize > 0 else { return 1 }
        return editorFontSize / referenceFontSize
    }
}

/// Resolves preview link clicks, including creating the file when a local
/// link target is missing.
public enum PreviewLinkResolver {

    /// Absolute URLs pass through; relative paths resolve against the
    /// document's directory.
    public static func resolve(_ urlString: String?, baseURL: URL?) -> URL? {
        guard let urlString, !urlString.isEmpty else { return nil }
        if let absolute = URL(string: urlString), absolute.scheme != nil {
            return absolute
        }
        guard let baseURL else { return URL(string: urlString) }
        let directory = baseURL.hasDirectoryPath ? baseURL : baseURL.appendingPathComponent("")
        return URL(string: urlString, relativeTo: directory)?.absoluteURL
    }

    /// Appends `.md` when a local link has no extension but the sibling
    /// Markdown file exists.
    public static func existingTarget(for url: URL, fileManager: FileManager = .default) -> URL {
        guard url.isFileURL,
              url.pathExtension.isEmpty,
              !fileManager.fileExists(atPath: url.path)
        else { return url }
        let markdown = URL(fileURLWithPath: url.path + ".md")
        return fileManager.fileExists(atPath: markdown.path) ? markdown : url
    }

    /// Creates an empty file (and its parent directories) for a missing local
    /// link target. Returns `true` when the file exists afterwards.
    @discardableResult
    public static func createFileIfNeeded(at url: URL, fileManager: FileManager = .default) -> Bool {
        guard url.isFileURL else { return false }
        if fileManager.fileExists(atPath: url.path) { return true }
        let directory = url.deletingLastPathComponent()
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return fileManager.createFile(atPath: url.path, contents: Data())
    }
}
