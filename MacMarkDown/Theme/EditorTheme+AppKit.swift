import AppKit
import SwiftUI

/// AppKit accessors for the editor theme colors so they can be applied to
/// `NSTextStorage` and the `NSTextView` surface.
extension EditorTheme {

    public var nsTextColor: NSColor { nsColor(textColor) }
    public var nsBackgroundColor: NSColor { nsColor(backgroundColor) }
    public var nsCursorColor: NSColor { nsColor(cursorColor) }
    public var nsSelectionColor: NSColor { nsColor(selectionColor) }
    public var nsLineHighlightColor: NSColor { nsColor(lineHighlightColor) }
    public var nsTitleColor: NSColor { nsColor(titleColor) }
    public var nsEmphasisColor: NSColor { nsColor(emphasisColor) }
    public var nsStrongColor: NSColor { nsColor(strongColor) }
    public var nsCodeColor: NSColor { nsColor(codeColor) }
    public var nsLinkColor: NSColor { nsColor(linkColor) }
    public var nsQuoteColor: NSColor { nsColor(quoteColor) }
    public var nsListMarkerColor: NSColor { nsColor(listMarkerColor) }
    public var nsHeadingColor: NSColor { nsColor(headingColor) }
    public var nsBoldColor: NSColor { nsColor(boldColor) }
    public var nsItalicColor: NSColor { nsColor(italicColor) }

    private func nsColor(_ color: Color) -> NSColor {
        let resolved = color.resolve(in: EnvironmentValues())
        return NSColor(cgColor: resolved.cgColor) ?? .labelColor
    }
}