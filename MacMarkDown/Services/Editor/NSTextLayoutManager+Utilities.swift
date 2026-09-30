import AppKit

extension NSRange {
    /// An "empty/absent" range: no location, no length.
    static var notFound: NSRange { NSRange(location: NSNotFound, length: 0) }
}

extension NSTextContentManager {
    /// UTF-16 `NSRange` (document-relative) → `NSTextRange`, or `nil` when the
    /// range does not fit inside the document.
    ///
    /// SDK 25+ removed the `NSTextRange(_:in:)`/`NSRange(_:in:)` convenience
    /// initializers; location↔offset is the remaining public coordinate bridge.
    func textRange(from range: NSRange) -> NSTextRange? {
        guard range.location != NSNotFound else { return nil }
        guard let start = location(documentRange.location, offsetBy: range.location) else { return nil }
        guard let end = location(documentRange.location, offsetBy: range.location + range.length) else { return nil }
        return NSTextRange(location: start, end: end)
    }

    /// `NSTextRange` → UTF-16 `NSRange` (document-relative).
    func range(from textRange: NSTextRange) -> NSRange {
        let start = offset(from: documentRange.location, to: textRange.location)
        let end = offset(from: documentRange.location, to: textRange.endLocation)
        guard start != NSNotFound, end != NSNotFound else { return .notFound }
        return NSRange(location: start, length: max(0, end - start))
    }

    /// The document character length in UTF-16 code units.
    var documentLength: Int {
        let end = offset(from: documentRange.location, to: documentRange.endLocation)
        return end == NSNotFound ? 0 : end
    }
}

extension NSTextLayoutManager {
    /// Resolves a UTF-16 character index to its location, or `nil` when the
    /// index is out of bounds.
    ///
    /// `NSTextLayoutManager` exposes no character-index API of its own; offsets
    /// are computed through the owning `NSTextContentManager`, whose offset
    /// counts UTF-16 code units. This bridge keeps the document and every
    /// downstream consumer (`NSRange`-based scroll sync and smart editing) on
    /// one coordinate system.
    func location(atCharacter index: Int) -> (any NSTextLocation)? {
        guard let contentManager = textContentManager else { return nil }
        return contentManager.location(documentRange.location, offsetBy: index)
    }

    /// The UTF-16 character offset of a location measured from the document
    /// start, or `nil` when the two are not comparable.
    func characterOffset(of location: any NSTextLocation) -> Int? {
        guard let contentManager = textContentManager else { return nil }
        let offset = contentManager.offset(from: documentRange.location, to: location)
        guard offset != NSNotFound else { return nil }
        return offset
    }
}