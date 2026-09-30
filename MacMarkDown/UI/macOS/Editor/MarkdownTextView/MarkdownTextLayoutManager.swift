import AppKit

/// The custom `NSTextLayoutManager` behind `MarkdownTextView`.
///
/// Phase 3 Milestone 1 keeps the stock TextKit 2 layout pipeline. This
/// subclass is the seam the Phase 4 custom rendering pass plugs into: hiding
/// `**`/`*` emphasis markers, inline image placeholders, soft-wrapped hard
/// wrapping, and the like will override layout-time behavior here (or a custom
/// `NSTextLayoutFragment` subclass) without the host view knowing.
final class MarkdownTextLayoutManager: NSTextLayoutManager {
    override init() {
        super.init()
        usesFontLeading = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}