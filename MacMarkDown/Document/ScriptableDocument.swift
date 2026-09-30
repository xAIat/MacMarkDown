import AppKit

/// AppleScript bridge for a Markdown document.
///
/// The app is not `NSDocument`-based, so scripting works through KVC: the
/// scripting definition (`MacMarkDown.sdef`) declares a `document` class with
/// `text`, `html`, `name`, `modified` and `file` properties, and the runtime
/// resolves them through `value(forKey:)` on this wrapper.
///
/// `NSApplication` exposes the open documents via the `documents` accessor
/// below; AppleScript's `document 1` then indexes that array.
@objc(ScriptableDocument)
@MainActor
public final class ScriptableDocument: NSObject {

    private let document: MarkdownDocument

    public init(document: MarkdownDocument) {
        self.document = document
        super.init()
    }

    // MARK: - Properties

    @objc public var text: String {
        get { document.text }
        set { document.updateText(newValue) }
    }

    @objc public var html: String {
        Renderer(
            parser: document.parser,
            theme: document.preferences.previewTheme,
            options: document.preferences.parseOptions
        ).renderToHTML(document.text, title: document.displayTitle)
    }

    @objc public var name: String {
        document.displayTitle
    }

    @objc public var modified: Bool {
        document.isEdited
    }

    @objc public var file: String? {
        document.fileURL?.path
    }

    override public func value(forUndefinedKey key: String) -> Any? {
        nil
    }
}

// MARK: - Application scripting root

extension NSApplication {

    /// The open documents, most recently focused first. The scripting
    /// definition binds `application.documents` to this key.
    @objc public var documents: [ScriptableDocument] {
        DocumentSession.shared.documents.map { ScriptableDocument(document: $0) }
    }
}