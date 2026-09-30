import AppKit

/// Bridges the shared `NSFontPanel` into SwiftUI Settings.
///
/// `NSFontManager` requires an Objective-C target/action pair, which a SwiftUI
/// view cannot provide directly; this small retained object receives the
/// `changeFont(_:)` callback and forwards the chosen family/size.
@MainActor
final class FontPanelController: NSObject {

    /// Called with `(fontName, pointSize)` when the user picks a font.
    var onChange: ((String, Double) -> Void)?

    /// Shows the shared font panel, seeded with `font`.
    func showPanel(seededWith font: NSFont) {
        let manager = NSFontManager.shared
        manager.target = self
        manager.action = #selector(changeFont(_:))
        manager.setSelectedFont(font, isMultiple: false)
        manager.orderFrontFontPanel(nil)
    }

    @objc private func changeFont(_ sender: NSFontManager) {
        let selected = sender.selectedFont ?? NSFont.systemFont(ofSize: 14)
        let converted = sender.convert(selected)
        onChange?(converted.fontName, converted.pointSize)
    }
}
