import AppKit

// MARK: - Line-number gutter
//
// Line numbers are drawn in a view that lives inside the (flipped) text view,
// so it shares the document coordinate space and scrolls with the content.
// The text is inset on the left by the gutter's width.

extension MarkdownTextView {

    /// Whether line numbers are shown in the left margin.
    var showsLineNumbers: Bool {
        get { _showsLineNumbers }
        set {
            guard newValue != _showsLineNumbers else { return }
            _showsLineNumbers = newValue
            updateGutterVisibility()
            needsFullHeightMeasurement = true
            needsLayout = true
        }
    }

    /// The width reserved for the gutter (0 when hidden).
    var gutterWidth: CGFloat {
        guard _showsLineNumbers, let gutterView else { return 0 }
        return gutterView.requiredWidth(forLineCount: lineCount())
    }

    /// The 1-based logical line number containing the insertion point.
    func insertionPointLineNumber() -> Int {
        guard let location = textLayoutManager.insertionPointLocations.first else { return 1 }
        let offset = textContentStorage.offset(from: textContentStorage.documentRange.location, to: location)
        guard offset != NSNotFound else { return 1 }
        return lineNumber(atOffset: offset)
    }

    /// Visible (line number, layout-fragment frame) pairs for the gutter.
    func visibleLineNumberFrames() -> [(line: Int, frame: CGRect)] {
        ensureLineStarts()
        let visible = effectiveVisibleRect.insetBy(dx: 0, dy: -120)
        let fragments = fragmentViewMap.keyEnumerator().allObjects.compactMap { $0 as? NSTextLayoutFragment }
        var result: [(Int, CGRect)] = []
        for fragment in fragments {
            guard let firstLine = fragment.textLineFragments.first,
                  !firstLine.isExtraLineFragment
            else { continue }
            let frame = fragment.layoutFragmentFrame
            guard frame.intersects(visible) else { continue }
            let offset = textContentStorage.offset(
                from: textContentStorage.documentRange.location,
                to: fragment.rangeInElement.location
            )
            guard offset != NSNotFound else { continue }
            result.append((lineNumber(atOffset: offset), frame))
        }
        return result.sorted { $0.1.minY < $1.1.minY }
    }

    // MARK: - Internal

    func updateGutterVisibility() {
        if _showsLineNumbers {
            let gutter = gutterView ?? MarkdownGutterView()
            gutter.textView = self
            if gutter.superview !== self {
                addSubview(gutter)
            }
            gutterView = gutter
        } else {
            gutterView?.removeFromSuperview()
            gutterView = nil
        }
    }

    func layoutGutter() {
        guard let gutterView, _showsLineNumbers else { return }
        let width = gutterView.requiredWidth(forLineCount: lineCount())
        gutterView.frame = NSRect(x: 0, y: 0, width: width, height: max(bounds.height, contentView.bounds.height))
        gutterView.needsDisplay = true
    }

    // MARK: - Line index

    private func lineCount() -> Int {
        ensureLineStarts()
        return max(1, lineStartOffsets.count)
    }

    func ensureLineStarts() {
        guard lineStartGeneration != textMutationGeneration else { return }
        let ns = string as NSString
        var starts: [Int] = [0]
        var index = 0
        while index < ns.length {
            if ns.character(at: index) == 0x0A { starts.append(index + 1) }
            index += 1
        }
        lineStartOffsets = starts
        lineStartGeneration = textMutationGeneration
    }

    /// 1-based logical line number for a UTF-16 offset (binary search).
    func lineNumber(atOffset offset: Int) -> Int {
        ensureLineStarts()
        var low = 0
        var high = lineStartOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= offset { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }
}
