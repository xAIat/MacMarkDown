import AppKit

/// Installs a formatting Touch Bar on each document window. Buttons post the
/// same notification-based commands the menu and toolbar use, so all three
/// stay in lockstep.
@MainActor
final class TouchBarController: NSObject, NSTouchBarDelegate {

    static let shared = TouchBarController()

    private enum Item {
        static let bold = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.bold")
        static let italic = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.italic")
        static let code = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.code")
        static let strikethrough = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.strikethrough")
        static let link = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.link")
        static let image = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.image")
        static let unorderedList = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.ul")
        static let orderedList = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.ol")
        static let blockquote = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.quote")
        static let indent = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.indent")
        static let unindent = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.unindent")
        static let toggleEditor = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.editor")
        static let togglePreview = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.preview")
        static let copyHTML = NSTouchBarItem.Identifier("com.xaiat.MacMarkDown.touchbar.copyhtml")
    }

    private let identifiers: [NSTouchBarItem.Identifier] = [
        Item.bold, Item.italic, Item.code, Item.strikethrough,
        .flexibleSpace,
        Item.link, Item.image,
        Item.unorderedList, Item.orderedList, Item.blockquote,
        .flexibleSpace,
        Item.indent, Item.unindent,
        .flexibleSpace,
        Item.toggleEditor, Item.togglePreview, Item.copyHTML,
    ]

    private override init() {
        super.init()
    }

    /// Builds a touch bar and assigns it to `window`.
    func attach(to window: NSWindow) {
        let touchBar = NSTouchBar()
        touchBar.delegate = self
        touchBar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("com.xaiat.MacMarkDown.touchbar")
        touchBar.defaultItemIdentifiers = identifiers
        touchBar.customizationAllowedItemIdentifiers = identifiers
        window.touchBar = touchBar
    }

    // MARK: - NSTouchBarDelegate

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        switch identifier {
        case Item.bold:
            return button(identifier, symbol: "bold", accessibility: "Bold", action: #selector(applyStrong))
        case Item.italic:
            return button(identifier, symbol: "italic", accessibility: "Italic", action: #selector(applyEmphasis))
        case Item.code:
            return button(identifier, symbol: "chevron.left.forwardslash.chevron.right", accessibility: "Inline Code", action: #selector(applyInlineCode))
        case Item.strikethrough:
            return button(identifier, symbol: "strikethrough", accessibility: "Strikethrough", action: #selector(applyStrikethrough))
        case Item.link:
            return button(identifier, symbol: "link", accessibility: "Link", action: #selector(applyLink))
        case Item.image:
            return button(identifier, symbol: "photo", accessibility: "Image", action: #selector(applyImage))
        case Item.unorderedList:
            return button(identifier, symbol: "list.bullet", accessibility: "Unordered List", action: #selector(applyUnorderedList))
        case Item.orderedList:
            return button(identifier, symbol: "list.number", accessibility: "Ordered List", action: #selector(applyOrderedList))
        case Item.blockquote:
            return button(identifier, symbol: "text.quote", accessibility: "Blockquote", action: #selector(applyBlockquote))
        case Item.indent:
            return button(identifier, symbol: "increase.indent", accessibility: "Indent", action: #selector(applyIndent))
        case Item.unindent:
            return button(identifier, symbol: "decrease.indent", accessibility: "Unindent", action: #selector(applyUnindent))
        case Item.toggleEditor:
            return button(identifier, symbol: "sidebar.left", accessibility: "Toggle Editor", action: #selector(toggleEditor))
        case Item.togglePreview:
            return button(identifier, symbol: "sidebar.right", accessibility: "Toggle Preview", action: #selector(togglePreview))
        case Item.copyHTML:
            return button(identifier, symbol: "doc.on.doc", accessibility: "Copy HTML", action: #selector(copyHTML))
        default:
            return nil
        }
    }

    // MARK: - Helpers

    private func button(
        _ identifier: NSTouchBarItem.Identifier,
        symbol: String,
        accessibility: String,
        action: Selector
    ) -> NSTouchBarItem {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: accessibility)
        let item = NSButtonTouchBarItem(identifier: identifier, image: image ?? NSImage(), target: self, action: action)
        item.bezelColor = nil
        return item
    }

    private func postFormat(_ command: EditorFormatCommand) {
        NotificationCenter.default.post(
            name: .formatCommandRequest,
            object: nil,
            userInfo: [Constants.formatCommandUserInfoKey: command.rawValue]
        )
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    @objc private func applyStrong() { postFormat(.strong) }
    @objc private func applyEmphasis() { postFormat(.emphasis) }
    @objc private func applyInlineCode() { postFormat(.inlineCode) }
    @objc private func applyStrikethrough() { postFormat(.strikethrough) }
    @objc private func applyLink() { postFormat(.link) }
    @objc private func applyImage() { postFormat(.image) }
    @objc private func applyUnorderedList() { postFormat(.unorderedList) }
    @objc private func applyOrderedList() { postFormat(.orderedList) }
    @objc private func applyBlockquote() { postFormat(.blockquote) }
    @objc private func applyIndent() { postFormat(.indent) }
    @objc private func applyUnindent() { postFormat(.unindent) }
    @objc private func toggleEditor() { post(.toggleEditorPane) }
    @objc private func togglePreview() { post(.togglePreviewPane) }
    @objc private func copyHTML() { post(.copyHTMLRequest) }
}
