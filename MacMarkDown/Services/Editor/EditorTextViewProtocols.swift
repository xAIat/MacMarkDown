import AppKit

/// The editing surface `MarkdownEditorView`'s coordinator drives. Both the
/// legacy `NSTextView` and the phase-3 `MarkdownTextView` conform, so the
/// coordinator, the syntax highlighter and the smart-editing helpers stay
/// text-stack agnostic (Milestone 4 wiring).
///
/// Font / paragraph / color styling is intentionally *not* part of the host:
/// `NSTextView` exposes those as nullable while `MarkdownTextView` stores them
/// non-optional, so the coordinator applies them through per-class branches.
@MainActor
public protocol EditorTextViewHost: AnyObject {
    var string: String { get set }
    var textStorage: NSTextStorage? { get }
    /// The live layout manager (smart editing resolves wrapped-line positions
    /// through it). A function rather than a property so each host — whose
    /// member is stored differently (`NSTextView`'s is optional, the custom
    /// view's is not) — can witness it exactly.
    func layoutManagerForGeometry() -> NSTextLayoutManager?
    var typingAttributes: [NSAttributedString.Key: Any] { get set }
    func setSelectedRange(_ range: NSRange)
    func selectedRange() -> NSRange
    func insertText(_ string: Any, replacementRange: NSRange)
    func markedRange() -> NSRange
    func insertNewline(_ sender: Any?)
    /// Registration point before a host-side edit, mirroring
    /// `NSTextView.shouldChangeText(in:replacementString:)`. Returns `false`
    /// when the edit should be vetoed (e.g. an auto-complete already handled it).
    func shouldChangeText(in range: NSRange, replacementString: String?) -> Bool
    /// Direct character-replacement edit in `NSRange` space (the smart-editing
    /// helpers use this in place of `NSTextView.replaceCharacters(in:with:)`).
    func replaceCharacters(in range: NSRange, with string: String)
    var isAutomaticQuoteSubstitutionEnabled: Bool { get set }
}

extension NSTextView: EditorTextViewHost {
    public func layoutManagerForGeometry() -> NSTextLayoutManager? { textLayoutManager }
}

extension MarkdownTextView {

    public func layoutManagerForGeometry() -> NSTextLayoutManager? { textLayoutManager }
}