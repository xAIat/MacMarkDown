import Foundation
import Markdown

// MARK: - Markdown Element

/// A lightweight, renderer-agnostic representation of a Markdown document's
/// parse tree. Produced by `MarkdownParser` from a `swift-markdown` AST and
/// consumed by `MarkdownView` (native rendering) and `Renderer` (HTML output).
public enum MarkdownElement: Sendable, Hashable {
    case heading(level: Int, text: String)
    case paragraph([InlineElement])
    case codeBlock(language: String?, code: String)
    case blockQuote([MarkdownElement])
    case unorderedList([ListItem])
    case orderedList([ListItem])
    case table(TableData)
    case thematicBreak
    case rawHTML(String)
    case image(url: String?, alt: String)
    case taskList([ListItem])
    case tableOfContents([TOCItem])
    case footnotes([FootnoteItem])
    case frontMatter(title: String?, entries: [FrontMatterEntry])
}

/// One footnote definition, rendered as a numbered entry with an anchor.
public struct FootnoteItem: Sendable, Hashable {
    public var id: String
    public var text: String

    public init(id: String, text: String) {
        self.id = id
        self.text = text
    }
}

/// One heading entry in a rendered table of contents.
public struct TOCItem: Sendable, Hashable {
    public var level: Int
    public var text: String

    public init(level: Int, text: String) {
        self.level = level
        self.text = text
    }
}

/// A stable path to a node in the parsed element tree: the sequence of child
/// indices from the root. Used to pair editor and preview scroll anchors 1:1.
public typealias AnchorPath = [Int]

/// One scroll-sync reference point. `path` identifies the node in the element
/// tree; `line` is the 1-based line in the *original* document text where the
/// node starts.
public struct DocumentAnchor: Sendable, Hashable {
    public var path: AnchorPath
    public var line: Int

    public init(path: AnchorPath, line: Int) {
        self.path = path
        self.line = line
    }
}

/// The result of parsing a document: the render tree plus the ordered scroll
/// anchors (pre-order) shared by the editor and the preview.
public struct ParsedDocument: Sendable {
    public var elements: [MarkdownElement]
    public var anchors: [DocumentAnchor]

    public init(elements: [MarkdownElement], anchors: [DocumentAnchor]) {
        self.elements = elements
        self.anchors = anchors
    }
}

public enum InlineElement: Sendable, Hashable {
    case text(String)
    case emphasis([InlineElement])
    case strong([InlineElement])
    case code(String)
    case link(url: String?, children: [InlineElement])
    case strikethrough([InlineElement])
    case image(url: String?, alt: String)
    case underline([InlineElement])
    case highlight([InlineElement])
    case superscript([InlineElement])
    /// `"quoted"` span rendered as `<q>`.
    case quote([InlineElement])
    case lineBreak
    case inlineHTML(String)
}

public struct ListItem: Sendable, Hashable {
    public var children: [MarkdownElement]
    public var isChecked: Bool?
    public init(children: [MarkdownElement], isChecked: Bool? = nil) {
        self.children = children
        self.isChecked = isChecked
    }
}

public struct TableData: Sendable, Hashable {
    public var headers: [String]
    public var rows: [[String]]
    public var alignments: [TableColumnAlignment]

    public init(
        headers: [String],
        rows: [[String]],
        alignments: [TableColumnAlignment] = []
    ) {
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
    }
}

public enum TableColumnAlignment: Sendable, Hashable {
    case left
    case center
    case right
}

// MARK: - Parse Options

public struct MarkdownParseOptions: Sendable, Hashable {
    public var enableTables: Bool
    public var enableFencedCode: Bool
    public var enableStrikethrough: Bool
    public var enableAutolink: Bool
    public var enableFootnotes: Bool
    public var enableTaskList: Bool
    public var enableIntraEmphasis: Bool
    public var enableUnderline: Bool
    public var enableHighlight: Bool
    public var enableSuperscript: Bool
    /// Renders `"quoted"` spans as `<q>`.
    public var enableQuote: Bool
    public var enableSmartyPants: Bool
    /// Strips YAML front matter from the body and renders it as a table.
    public var enableFrontMatter: Bool
    /// Bundled `.handlebars` template used for the exported HTML document.
    public var templateName: String
    /// Shows a line-number gutter beside fenced code blocks.
    public var enableLineNumbers: Bool
    /// Code-block accessory: 0 = none, 1 = language name, 2 = custom.
    public var codeBlockAccessory: Int
    /// Code token palette name; empty means "follow the preview theme".
    public var highlightingThemeName: String
    /// Renders `\[…\]`, `\(…\)` and `$$…$$` math with MathJax
    /// ("TeX-like math syntax").
    public var enableMath: Bool
    /// Renders `$…$` inline math (MathJax).
    public var enableInlineMath: Bool
    /// Renders `[toc]` as a table of contents.
    public var enableTOC: Bool
    /// Renders single newlines inside paragraphs as line breaks.
    public var enableHardWrap: Bool
    /// Emits highlighted code spans in exported HTML.
    public var enableSyntaxHighlighting: Bool

    public init(
        enableTables: Bool = true,
        enableFencedCode: Bool = true,
        enableStrikethrough: Bool = true,
        enableAutolink: Bool = true,
        enableFootnotes: Bool = true,
        enableTaskList: Bool = true,
        enableIntraEmphasis: Bool = true,
        enableUnderline: Bool = false,
        enableHighlight: Bool = false,
        enableSuperscript: Bool = false,
        enableQuote: Bool = false,
        enableSmartyPants: Bool = true,
        enableFrontMatter: Bool = true,
        templateName: String = "Default",
        enableLineNumbers: Bool = false,
        codeBlockAccessory: Int = 1,
        highlightingThemeName: String = "",
        enableMath: Bool = false,
        enableInlineMath: Bool = false,
        enableTOC: Bool = false,
        enableHardWrap: Bool = false,
        enableSyntaxHighlighting: Bool = true
    ) {
        self.enableTables = enableTables
        self.enableFencedCode = enableFencedCode
        self.enableStrikethrough = enableStrikethrough
        self.enableAutolink = enableAutolink
        self.enableFootnotes = enableFootnotes
        self.enableTaskList = enableTaskList
        self.enableIntraEmphasis = enableIntraEmphasis
        self.enableUnderline = enableUnderline
        self.enableHighlight = enableHighlight
        self.enableSuperscript = enableSuperscript
        self.enableQuote = enableQuote
        self.enableSmartyPants = enableSmartyPants
        self.enableFrontMatter = enableFrontMatter
        self.templateName = templateName
        self.enableLineNumbers = enableLineNumbers
        self.codeBlockAccessory = codeBlockAccessory
        self.highlightingThemeName = highlightingThemeName
        self.enableMath = enableMath
        self.enableInlineMath = enableInlineMath
        self.enableTOC = enableTOC
        self.enableHardWrap = enableHardWrap
        self.enableSyntaxHighlighting = enableSyntaxHighlighting
    }
}