import Foundation

/// Bridges between the editor's UTF-16 `NSRange` selection and Swift string
/// ranges. Every consumer of `EditorOperations` must convert the same way or
/// selections drift on CJK/emoji text.
public enum EditorTextRange {

    /// `NSRange` (UTF-16 offsets) → `Range<String.Index>`.
    public static func range(from nsRange: NSRange, in text: String) -> Range<String.Index>? {
        let length = (text as NSString).length
        guard nsRange.location != NSNotFound, nsRange.location <= length else { return nil }
        let location = min(nsRange.location, length)
        let end = min(nsRange.location + nsRange.length, length)
        let start = String.Index(utf16Offset: location, in: text)
        let upper = String.Index(utf16Offset: end, in: text)
        return start..<upper
    }

    /// `Range<String.Index>` → `NSRange` (UTF-16 offsets).
    public static func nsRange(from range: Range<String.Index>, in text: String) -> NSRange {
        let lower = range.lowerBound.utf16Offset(in: text)
        let upper = range.upperBound.utf16Offset(in: text)
        return NSRange(location: lower, length: max(0, upper - lower))
    }
}