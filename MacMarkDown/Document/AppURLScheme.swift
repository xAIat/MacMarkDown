import Foundation

/// Parses incoming application URLs. Finder opens arrive as plain `file://`
/// URLs; the `x-macmarkdown://open?url=file:///…` scheme lets other apps and
/// command-line tools ask MacMarkDown to open a document.
public enum AppURLScheme {

    public static let scheme = "x-macmarkdown"

    /// The file URL an incoming app URL refers to, or `nil` when it is not a
    /// document-open request.
    public static func fileURL(from url: URL) -> URL? {
        if url.isFileURL { return url }
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let target = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let fileURL = URL(string: target),
              fileURL.isFileURL
        else { return nil }
        return fileURL
    }
}