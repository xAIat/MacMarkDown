import AppKit
import CoreText

// MARK: - Local TextKit 2 helpers
//
// A handful of convenience APIs that TextKit 2 does not ship itself. They are
// built on public TextKit 2 API so no external dependency is required.

// MARK: - NSRange

extension NSRange {
    /// A zero-length range, mirroring the removed `NSRange.isEmpty`.
    var isEmpty: Bool { length == 0 }

    /// Bridges a location-only `NSTextRange` (caret) to an `NSRange`.
    init(_ location: any NSTextLocation, in contentManager: NSTextContentManager) {
        self = NSRange(
            location: contentManager.offset(from: contentManager.documentRange.location, to: location),
            length: 0
        )
    }

    /// Bridges a `NSTextRange` to an `NSRange`, or `.notFound` when it cannot
    /// be resolved against the content manager.
    init(_ textRange: NSTextRange, in contentManager: NSTextContentManager) {
        self = contentManager.range(from: textRange)
    }
}

// MARK: - NSTextLocation ordering

extension NSTextLocation {
    /// Whether this location precedes `other`.
    func isOrdered(before other: any NSTextLocation) -> Bool {
        compare(other) == .orderedAscending
    }

    /// Whether this location precedes or equals `other`.
    func isOrdered(beforeOrEqual other: any NSTextLocation) -> Bool {
        compare(other) != .orderedDescending
    }
}

// MARK: - NSTextRange

extension NSTextRange {
    /// The UTF-16 length of the range, resolved against `contentManager`.
    func length(in contentManager: NSTextContentManager) -> Int {
        let offset = contentManager.offset(from: location, to: endLocation)
        return offset == NSNotFound ? 0 : max(0, offset)
    }

    /// Returns the portion of this range that also lies inside `other`, or
    /// `nil` when they do not intersect.
    func clamped(to other: NSTextRange) -> NSTextRange? {
        let start = location.isOrdered(before: other.location) ? other.location : location
        let end = endLocation.isOrdered(before: other.endLocation) ? endLocation : other.endLocation
        guard start.isOrdered(beforeOrEqual: end) else { return nil }
        return NSTextRange(location: start, end: end)
    }
}

// MARK: - NSTextContentManager

extension NSTextContentManager {
    /// Resolves a UTF-16 offset (from the document start) to a location.
    func location(atCharacterOffset offset: Int) -> (any NSTextLocation)? {
        location(documentRange.location, offsetBy: offset)
    }

    /// The attributed string covering `textRange`, or the whole document when
    /// `textRange` is `nil`. Only meaningful for `NSTextContentStorage`.
    func attributedString(in textRange: NSTextRange?) -> NSAttributedString? {
        guard let storage = self as? NSTextContentStorage,
              let full = storage.attributedString
        else { return nil }
        guard let textRange else { return full }
        let range = range(from: textRange)
        guard range.location != NSNotFound,
              range.location >= 0,
              range.location + range.length <= full.length
        else { return nil }
        return full.attributedSubstring(from: range)
    }
}

// MARK: - NSTextLayoutManager

extension NSTextLayoutManager {

    /// Options for `caretLocation(interactingAt:options:inContainerAt:)`.
    struct CaretLocationOptions: OptionSet {
        let rawValue: Int
        /// Resolve a caret even when the point falls outside the container,
        /// clamping to the nearest text position.
        static let allowOutside = CaretLocationOptions(rawValue: 1 << 0)
    }

    /// The text segment frame (in container coordinates) covering `textRange`,
    /// or `nil` when the range does not lay out to a segment.
    func textSegmentFrame(
        in textRange: NSTextRange,
        type: NSTextLayoutManager.SegmentType
    ) -> CGRect? {
        var result: CGRect?
        enumerateTextSegments(in: textRange, type: type, options: [.rangeNotRequired]) { _, frame, _, _ in
            result = frame
            return false
        }
        return result
    }

    /// The text segment frame at a single location (zero-length range).
    func textSegmentFrame(
        at location: any NSTextLocation,
        type: NSTextLayoutManager.SegmentType
    ) -> CGRect? {
        textSegmentFrame(in: NSTextRange(location: location), type: type)
    }

    /// Resolves the caret position nearest to `point`. With `.allowOutside`,
    /// points beyond the container clamp to the document start/end.
    func caretLocation(
        interactingAt point: CGPoint,
        options: CaretLocationOptions = [],
        inContainerAt containerLocation: any NSTextLocation
    ) -> (any NSTextLocation)? {
        let bounds: CGRect = options.contains(.allowOutside) ? usageBoundsForTextContainer : .zero
        if let selection = textSelectionNavigation.textSelections(
            interactingAt: point,
            inContainerAt: containerLocation,
            anchors: [],
            modifiers: [],
            selecting: false,
            bounds: bounds
        ).first, let range = selection.textRanges.last {
            return range.location
        }
        guard options.contains(.allowOutside) else { return nil }
        let bounds2 = usageBoundsForTextContainer
        if point.y < bounds2.minY { return documentRange.location }
        if point.y > bounds2.maxY { return documentRange.endLocation }
        return nil
    }

    /// Selections that are pure insertion points (empty ranges).
    var insertionPointSelections: [NSTextSelection] {
        textSelections.filter { $0.textRanges.allSatisfy(\.isEmpty) }
    }

    /// Locations of the insertion-point selections.
    var insertionPointLocations: [any NSTextLocation] {
        insertionPointSelections.flatMap(\.textRanges).map(\.location)
    }

    /// All non-empty selection ranges, sorted in document order.
    func textSelectionRanges() -> [NSTextRange] {
        textSelections
            .flatMap(\.textRanges)
            .filter { !$0.isEmpty }
            .sorted { $0.location.isOrdered(before: $1.location) }
    }

    /// The selected text as a single string (ranges joined by newlines).
    func textSelectionsString() -> String? {
        let ranges = textSelectionRanges()
        guard !ranges.isEmpty else { return nil }
        return ranges.compactMap { textContentManager?.attributedString(in: $0)?.string }
            .joined(separator: "\n")
    }

    /// The selected ranges as one attributed string (ranges joined by newlines).
    func textSelectionsAttributedString() -> NSAttributedString? {
        let ranges = textSelectionRanges()
        guard !ranges.isEmpty else { return nil }
        let result = NSMutableAttributedString()
        for range in ranges {
            guard let substring = textContentManager?.attributedString(in: range) else { continue }
            if result.length != 0 { result.append(NSAttributedString(string: "\n")) }
            result.append(substring)
        }
        return result.length == 0 ? nil : result
    }

    /// The typographic bounds of a text range (unioned across its segments).
    func typographicBounds(in textRange: NSTextRange) -> CGRect? {
        var result: CGRect?
        enumerateTextSegments(in: textRange, type: .standard, options: [.rangeNotRequired]) { _, frame, _, _ in
            result = result.map { $0.union(frame) } ?? frame
            return true
        }
        return result
    }
}

// MARK: - NSTextLayoutFragment / NSTextLineFragment

extension NSTextLineFragment {
    /// Whether this is TextKit 2's synthetic "extra" line fragment (the empty
    /// line after a trailing newline, or an empty document). It always has a
    /// zero-length character range.
    var isExtraLineFragment: Bool { characterRange.length == 0 }
}

extension NSTextLayoutFragment {
    /// Whether the layout fragment's only content is an extra line fragment.
    var isExtraLineFragment: Bool {
        textLineFragments.last?.isExtraLineFragment ?? false
    }
}

// MARK: - CoreText

extension CTLine {
    enum HeightKind {
        case typographic
    }

    /// The line height derived from its typographic bounds.
    func height(_ kind: HeightKind) -> CGFloat {
        switch kind {
        case .typographic:
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(self, &ascent, &descent, &leading)
            return ascent + descent
        }
    }
}
