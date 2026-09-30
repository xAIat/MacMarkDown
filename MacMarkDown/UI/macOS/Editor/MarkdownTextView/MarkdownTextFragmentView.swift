import AppKit

/// A rendering surface for one `NSTextLayoutFragment`.
///
/// `NSTextViewportLayoutController` hands out fragment objects for the visible
/// area; each is wrapped in one of these lightweight views that simply draws
/// `fragment.draw(at:in:)`. Views are cached in a weak map and recycled across
/// layout passes (the Phase 4 custom renderer hooks in here).
final class MarkdownTextFragmentView: NSView {
    private(set) var layoutFragment: NSTextLayoutFragment

    override var isFlipped: Bool { true }

    init(layoutFragment: NSTextLayoutFragment, frame: NSRect) {
        self.layoutFragment = layoutFragment
        super.init(frame: frame)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        layoutFragment.draw(at: .zero, in: context)
        context.restoreGState()
    }

    override func layout() {
        super.layout()
        layoutAttachmentViews()
    }

    /// Positions any `NSTextAttachmentViewProvider` views (images, tables,
    /// web blocks) that belong to this fragment.
    private func layoutAttachmentViews() {
        for provider in layoutFragment.textAttachmentViewProviders {
            guard let attachmentView = provider.view else { continue }
            let frame = layoutFragment.frameForTextAttachment(at: provider.location)
            guard frame != .zero else { continue }
            attachmentView.frame = frame
            if attachmentView.superview !== self {
                addSubview(attachmentView)
            }
        }
    }
}