import AppKit

/// A layout fragment that can additionally draw invisible characters
/// (spaces, tabs, line feeds, …).
final class MarkdownTextLayoutFragment: NSTextLayoutFragment {

    /// Draw whitespace/newline symbols on top of the laid-out text.
    var showsInvisibleCharacters = false

    /// Font used for a whitespace run when the run carries no explicit font.
    var defaultFont: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular)

    override func draw(at point: CGPoint, in context: CGContext) {
        super.draw(at: point, in: context)
        guard showsInvisibleCharacters else { return }
        drawInvisibles(at: point, in: context)
    }

    private func drawInvisibles(at point: CGPoint, in context: CGContext) {
        guard let textLayoutManager else { return }
        let whitespace = CharacterSet.whitespacesAndNewlines

        context.saveGState()
        defer { context.restoreGState() }

        for lineFragment in textLineFragments where !lineFragment.isExtraLineFragment {
            let string = lineFragment.attributedString.string as NSString
            guard string.length > 0 else { continue }

            for index in 0..<string.length {
                let character = string.character(at: index)
                guard let scalar = Unicode.Scalar(character), whitespace.contains(scalar) else { continue }
                guard let location = textLayoutManager.location(
                    rangeInElement.location,
                    offsetBy: lineFragment.characterRange.location + index
                ) else { continue }

                let characterRange = NSTextRange(location: location)
                guard let frame = textLayoutManager.textSegmentFrame(in: characterRange, type: .standard) else { continue }

                let symbol = Self.symbol(for: character)
                let font = (lineFragment.attributedString.attribute(.font, at: index, effectiveRange: nil) as? NSFont)
                    ?? defaultFont
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: NSColor.placeholderTextColor
                ]
                let drawPoint = CGPoint(x: frame.minX - point.x, y: frame.minY - point.y)
                (symbol as NSString).draw(at: drawPoint, withAttributes: attributes)
            }
        }
    }

    private static func symbol(for character: unichar) -> String {
        switch character {
        case 0x0020: "\u{00B7}" // space
        case 0x0009: "\u{00BB}" // tab
        case 0x000A: "\u{00AC}" // line feed
        case 0x000D: "\u{21A9}" // carriage return
        case 0x00A0: "\u{235F}" // no-break space
        case 0x200B: "\u{205F}" // zero-width space
        case 0x200C: "\u{200C}" // zero-width non-joiner
        case 0x200D: "\u{200D}" // zero-width joiner
        case 0x2060: "\u{205F}" // word joiner
        case 0x2028: "\u{23CE}" // line separator
        case 0x2029: "\u{00B6}" // paragraph separator
        default: "\u{00B7}"
        }
    }
}
