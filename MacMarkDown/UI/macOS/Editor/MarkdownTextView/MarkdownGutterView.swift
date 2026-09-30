import AppKit

/// Draws line numbers in the left margin of `MarkdownTextView`.
///
/// It is a subview of the (flipped) text view, so it shares the document
/// coordinate space and scrolls with the text; only the visible band is drawn.
final class MarkdownGutterView: NSView {

    weak var textView: MarkdownTextView?

    var font: NSFont = .monospacedDigitSystemFont(ofSize: 11, weight: .regular) {
        didSet { needsDisplay = true; textView?.needsLayout = true }
    }
    var textColor: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }
    var selectedLineTextColor: NSColor = .labelColor { didSet { needsDisplay = true } }
    var backgroundColor: NSColor? { didSet { needsDisplay = true } }
    var separatorColor: NSColor = .separatorColor { didSet { needsDisplay = true } }
    /// Highlight the line containing the insertion point.
    var highlightSelectedLine = false { didSet { needsDisplay = true } }

    private let horizontalPadding: CGFloat = 6
    private let separatorWidth: CGFloat = 1

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// The width needed to show `lineCount` numbers in the current font.
    func requiredWidth(forLineCount lineCount: Int) -> CGFloat {
        let digits = max(1, String(max(lineCount, 1)).count)
        let sample = String(repeating: "0", count: digits) as NSString
        let width = sample.size(withAttributes: [.font: font]).width
        return ceil(width) + horizontalPadding * 2 + separatorWidth
    }

    override func draw(_ dirtyRect: NSRect) {
        if let backgroundColor {
            backgroundColor.setFill()
            dirtyRect.fill()
        }
        separatorColor.setFill()
        NSRect(x: bounds.maxX - separatorWidth, y: dirtyRect.minY, width: separatorWidth, height: dirtyRect.height).fill()

        guard let textView else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: selectedLineTextColor
        ]
        let caretLine = textView.insertionPointLineNumber()

        for (line, labelFrame) in lineNumberLabelFrames() {
            guard labelFrame.maxY >= dirtyRect.minY, labelFrame.minY <= dirtyRect.maxY else { continue }
            let textAttributes = (highlightSelectedLine && line == caretLine) ? selectedAttributes : attributes
            ("\(line)" as NSString).draw(at: labelFrame.origin, withAttributes: textAttributes)
        }
    }

    /// Gutter-space rectangles where each visible line number's label sits,
    /// vertically centered on the line it labels. Fragment frames from
    /// `visibleLineNumberFrames()` live in the text container's coordinate
    /// space, so the container's vertical origin (`textContainerOrigin.y`) is
    /// added here to align the numbers with the pixels they label. (The gutter
    /// view shares the document view's flipped coordinate space.)
    func lineNumberLabelFrames() -> [(line: Int, frame: CGRect)] {
        guard let textView else { return [] }
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let originY = textView.textContainerOrigin.y
        return textView.visibleLineNumberFrames().map { line, frame in
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attributes)
            let x = bounds.width - horizontalPadding - size.width
            let y = frame.midY + originY - size.height / 2
            return (line, CGRect(x: x, y: y, width: size.width, height: size.height))
        }
    }
}
