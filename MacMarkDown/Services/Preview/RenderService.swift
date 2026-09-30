import Foundation
import Observation

/// Coordinates Markdown parsing and preview updates.
///
/// The render service debounces text changes (default 300 ms) and re-parses
/// the document on the main actor, publishing the `[MarkdownElement]` output
/// that `PreviewView` observes. It also exposes the HTML fragment used for
/// export.
@MainActor
@Observable
public final class RenderService: @unchecked Sendable {

    public private(set) var elements: [MarkdownElement] = []
    /// Ordered scroll anchors shared with the editor (see `ParsedDocument`).
    public private(set) var anchors: [DocumentAnchor] = []
    public private(set) var renderedHTML: String = ""
    public private(set) var isRendering = false
    public private(set) var lastError: String?

    private let parser: MarkdownParser
    private let renderer: Renderer
    private var workItem: DispatchWorkItem?
    private var latestText: String = ""
    private var latestOptions: MarkdownParseOptions = .init()
    private var baseTheme: Theme = .clearness

    public init(parser: MarkdownParser = MarkdownParser(), preferences: Preferences = Preferences()) {
        self.parser = parser
        self.renderer = Renderer(parser: parser, theme: preferences.previewTheme)
    }

    // MARK: - Scheduling

    /// Parse immediately (no debounce).
    public func parseNow(text: String, options: MarkdownParseOptions) {
        workItem?.cancel()
        isRendering = true
        let parsed = parser.parseDocument(text, options: options)
        self.elements = parsed.elements
        self.anchors = parsed.anchors
        renderedHTML = renderer.renderFragment(text)
        isRendering = false
    }

    /// Schedule a debounced parse.
    public func scheduleRender(text: String, options: MarkdownParseOptions) {
        workItem?.cancel()
        latestText = text
        latestOptions = options

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.parseNow(text: self.latestText, options: self.latestOptions)
        }
        workItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.defaultDebounceInterval,
            execute: work
        )
    }

    /// Re-render with a new theme (e.g. when the user changes the preview style).
    public func updateTheme(_ theme: Theme) {
        baseTheme = theme
        // Elements stay the same; only HTML export uses the theme.
    }

    public var currentTheme: Theme { baseTheme }

    // MARK: - Update geometry for sync scroll

    public func updateHeaderLocations(for text: String, width: CGFloat) -> [CGFloat] {
        var locations: [CGFloat] = []
        var charCount = 0
        let headerRegex = try? NSRegularExpression(pattern: "^(#+)\\s")
        let dashRegex = try? NSRegularExpression(pattern: "^(?:[-=]+)$")

        for line in text.components(separatedBy: "\n") {
            let range = NSRange(location: 0, length: (line as NSString).length)
            let isHeader = headerRegex?.firstMatch(in: line, range: range) != nil
            let isUnderline = dashRegex?.firstMatch(in: line, range: range) != nil
            if isHeader || isUnderline {
                // Approximate vertical position by line index scaled to width
                locations.append(CGFloat(charCount) * 0.01)
            }
            charCount += line.count + 1
        }
        return locations
    }
}

// MARK: - Preferences extension

extension Preferences {
    /// The selected preview theme.
    public var previewTheme: Theme {
        Theme.theme(named: htmlStyleName)
    }
}