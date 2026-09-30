import Foundation
import Observation

/// Application preferences stored in `UserDefaults` and observed via the
/// `@Observable` macro.
///
/// Every stored property maps to a `UserDefaults` key. Read access is safe
/// at any time; writes are performed through `@MainActor`-isolated setters to
/// satisfy Swift 6.4 strict concurrency.
@MainActor
@Observable
public final class Preferences {

    private let defaults: UserDefaults

    // MARK: - General

    public var suppressUntitledDocumentOnLaunch: Bool {
        didSet { defaults.set(suppressUntitledDocumentOnLaunch, forKey: Keys.suppressUntitled) }
    }
    public var updateIncludesPreReleases: Bool {
        didSet { defaults.set(updateIncludesPreReleases, forKey: Keys.updateIncludesPreReleases) }
    }
    public var createFileForLinkTarget: Bool {
        didSet { defaults.set(createFileForLinkTarget, forKey: Keys.createLinkTarget) }
    }

    // MARK: - Markdown Extensions

    public var extensionIntraEmphasis: Bool {
        didSet { write(extensionIntraEmphasis, .extensionIntraEmphasis) }
    }
    public var extensionTables: Bool {
        didSet { write(extensionTables, .extensionTables) }
    }
    public var extensionFencedCode: Bool {
        didSet { write(extensionFencedCode, .extensionFencedCode) }
    }
    public var extensionAutolink: Bool {
        didSet { write(extensionAutolink, .extensionAutolink) }
    }
    public var extensionStrikethrough: Bool {
        didSet { write(extensionStrikethrough, .extensionStrikethrough) }
    }
    public var extensionFootnotes: Bool {
        didSet { write(extensionFootnotes, .extensionFootnotes) }
    }
    public var extensionQuote: Bool {
        didSet { write(extensionQuote, .extensionQuote) }
    }
    public var extensionSmartyPants: Bool {
        didSet { write(extensionSmartyPants, .extensionSmartyPants) }
    }
    public var extensionUnderline: Bool {
        didSet { write(extensionUnderline, .extensionUnderline) }
    }
    public var extensionHighlight: Bool {
        didSet { write(extensionHighlight, .extensionHighlight) }
    }
    public var extensionSuperscript: Bool {
        didSet { write(extensionSuperscript, .extensionSuperscript) }
    }
    public var markdownManualRender: Bool {
        didSet { write(markdownManualRender, .manualRender) }
    }

    // MARK: - Editor

    /// The editor's font family. The empty string means the system font: the
    /// editor renders in the system monospaced face (SF Mono).
    public var editorBaseFontName: String {
        didSet { defaults.set(editorBaseFontName, forKey: Keys.editorFontName) }
    }
    public var editorBaseFontSize: Double {
        didSet { defaults.set(editorBaseFontSize, forKey: Keys.editorFontSize) }
    }
    public var editorStyleName: String {
        didSet { defaults.set(editorStyleName, forKey: Keys.editorStyleName) }
    }
    public var editorHorizontalInset: Double {
        didSet { defaults.set(editorHorizontalInset, forKey: Keys.editorHInset) }
    }
    public var editorVerticalInset: Double {
        didSet { defaults.set(editorVerticalInset, forKey: Keys.editorVInset) }
    }
    public var editorLineSpacing: Double {
        didSet { defaults.set(editorLineSpacing, forKey: Keys.editorLineSpacing) }
    }
    public var editorWidthLimited: Bool {
        didSet { write(editorWidthLimited, .editorWidthLimited) }
    }
    public var editorMaximumWidth: Double {
        didSet { defaults.set(editorMaximumWidth, forKey: Keys.editorMaxWidth) }
    }
    public var editorOnRight: Bool {
        didSet { write(editorOnRight, .editorOnRight) }
    }
    public var editorShowWordCount: Bool {
        didSet { write(editorShowWordCount, .editorShowWordCount) }
    }
    public var editorWordCountType: Int {
        didSet { defaults.set(editorWordCountType, forKey: Keys.editorWordCountType) }
    }
    public var editorUnorderedListMarkerType: Int {
        didSet { defaults.set(editorUnorderedListMarkerType, forKey: Keys.editorListMarkerType) }
    }
    public var editorScrollsPastEnd: Bool {
        didSet { write(editorScrollsPastEnd, .editorScrollsPastEnd) }
    }
    public var editorAutoIncrementNumberedLists: Bool {
        didSet { write(editorAutoIncrementNumberedLists, .editorAutoNumberedLists) }
    }
    public var editorConvertTabs: Bool {
        didSet { write(editorConvertTabs, .editorConvertTabs) }
    }
    public var editorInsertPrefixInBlock: Bool {
        didSet { write(editorInsertPrefixInBlock, .editorInsertPrefix) }
    }
    public var editorCompleteMatchingCharacters: Bool {
        didSet { write(editorCompleteMatchingCharacters, .editorCompleteMatching) }
    }
    public var editorSyncScrolling: Bool {
        didSet { write(editorSyncScrolling, .editorSyncScroll) }
    }
    /// When enabled, scrolling the preview also drives the editor. Off by
    /// default (one-way sync is more stable).
    public var editorBidirectionalScrollSync: Bool {
        didSet { write(editorBidirectionalScrollSync, .editorBidirectionalScrollSync) }
    }
    public var editorSmartHome: Bool {
        didSet { write(editorSmartHome, .editorSmartHome) }
    }
    public var editorEnsuresNewlineAtEndOfFile: Bool {
        didSet { write(editorEnsuresNewlineAtEndOfFile, .editorNewlineAtEOF) }
    }
    /// Dotted-red underlines for misspelled words while editing.
    public var editorSpellChecking: Bool {
        didSet { write(editorSpellChecking, .editorSpellChecking) }
    }
    /// Show a line-number gutter in the editor margin.
    public var editorShowLineNumbers: Bool {
        didSet { write(editorShowLineNumbers, .editorShowLineNumbers) }
    }
    /// Render the preview as a selectable TextKit 2 text surface (enables
    /// whole-document selection, ⌘A and copy-with-HTML).
    public var previewUsesTextSurface: Bool {
        didSet { write(previewUsesTextSurface, .previewUsesTextSurface) }
    }
    /// Draw whitespace/newline symbols in the editor.
    public var editorShowInvisibleCharacters: Bool {
        didSet { write(editorShowInvisibleCharacters, .editorShowInvisibleCharacters) }
    }
    /// Writes edits back to file-bound documents a moment after typing stops.
    /// Opt-in: disabled by default.
    public var editorAutosaveEnabled: Bool {
        didSet { write(editorAutosaveEnabled, .editorAutosaveEnabled) }
    }

    // MARK: - HTML / Preview

    public var htmlStyleName: String {
        didSet { defaults.set(htmlStyleName, forKey: Keys.htmlStyleName) }
    }
    /// Bundled `.handlebars` template used for exported HTML.
    public var htmlTemplateName: String {
        didSet { defaults.set(htmlTemplateName, forKey: Keys.htmlTemplateName) }
    }
    public var htmlDetectFrontMatter: Bool {
        didSet { write(htmlDetectFrontMatter, .htmlDetectFrontMatter) }
    }
    public var htmlTaskList: Bool {
        didSet { write(htmlTaskList, .htmlTaskList) }
    }
    public var htmlHardWrap: Bool {
        didSet { write(htmlHardWrap, .htmlHardWrap) }
    }
    public var htmlSyntaxHighlighting: Bool {
        didSet { write(htmlSyntaxHighlighting, .htmlSyntaxHighlighting) }
    }
    /// Renders TeX-like math — `\[…\]`, `\(…\)`, `$$…$$` — with MathJax in the
    /// preview ("TeX-like math syntax").
    public var htmlMathJax: Bool {
        didSet { write(htmlMathJax, .htmlMathJax) }
    }
    /// Also renders `$…$` as inline math (the inline-dollar toggle;
    /// `htmlMathJax` must be on).
    public var htmlMathJaxInlineDollar: Bool {
        didSet { write(htmlMathJaxInlineDollar, .htmlMathJaxInlineDollar) }
    }
    /// Renders ` ```mermaid ` blocks as diagrams.
    public var htmlMermaid: Bool {
        didSet { write(htmlMermaid, .htmlMermaid) }
    }
    /// Renders ` ```dot `/` ```graphviz ` blocks as diagrams.
    public var htmlGraphviz: Bool {
        didSet { write(htmlGraphviz, .htmlGraphviz) }
    }
    public var htmlRendersTOC: Bool {
        didSet { write(htmlRendersTOC, .htmlTOC) }
    }
    /// Shows a line-number gutter beside fenced code blocks.
    public var htmlLineNumbers: Bool {
        didSet { write(htmlLineNumbers, .htmlLineNumbers) }
    }
    /// Code-block accessory: 0 = none, 1 = language name, 2 = custom.
    public var htmlCodeBlockAccessory: Int {
        didSet { defaults.set(htmlCodeBlockAccessory, forKey: Keys.htmlCodeBlockAccessory) }
    }
    /// Code token palette name; empty follows the preview theme.
    public var htmlHighlightingThemeName: String {
        didSet { defaults.set(htmlHighlightingThemeName, forKey: Keys.htmlHighlightingThemeName) }
    }
    /// Base directory used to resolve relative links/images in unsaved
    /// documents.
    public var htmlDefaultDirectoryUrl: String {
        didSet { defaults.set(htmlDefaultDirectoryUrl, forKey: Keys.htmlDefaultDirectoryUrl) }
    }
    public var previewZoomRelativeToBaseFontSize: Bool {
        didSet { write(previewZoomRelativeToBaseFontSize, .previewZoomRelative) }
    }

    /// How the preview picks its text font.
    public var previewFontPolicy: PreviewFontPolicy {
        didSet { defaults.set(previewFontPolicy.rawValue, forKey: Keys.previewFontPolicy) }
    }
    /// Font family used when `previewFontPolicy` is `.custom`.
    public var previewFontName: String {
        didSet { defaults.set(previewFontName, forKey: Keys.previewFontName) }
    }

    /// The font family the preview renders in, per `previewFontPolicy`. The
    /// empty string means the system font (SF Pro with PingFang SC for Chinese).
    public var previewFontFamily: String {
        switch previewFontPolicy {
        case .followEditor: editorBaseFontName
        case .system: FontResolver.systemFontName
        case .custom: previewFontName
        }
    }

    // MARK: - Factory defaults

    /// Factory defaults for the settings sliders. They are the reset targets of
    /// the sliders' reset buttons, and `init` seeds fresh installs with them, so
    /// the value a button restores and the value a fresh install gets can never
    /// drift apart.
    public static let defaultEditorBaseFontSize: Double = 15
    public static let defaultEditorLineSpacing: Double = 1.4
    public static let defaultEditorMaximumWidth: Double = 800
    public static let defaultEditorHorizontalInset: Double = 16
    public static let defaultEditorVerticalInset: Double = 16

    // MARK: - Initialization

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        suppressUntitledDocumentOnLaunch = defaults.bool(forKey: Keys.suppressUntitled)
        updateIncludesPreReleases = defaults.bool(forKey: Keys.updateIncludesPreReleases)
        createFileForLinkTarget = defaults.bool(forKey: Keys.createLinkTarget)
        extensionIntraEmphasis = defaults.object(forKey: Keys.extensionIntraEmphasis) as? Bool ?? true
        extensionTables = defaults.object(forKey: Keys.extensionTables) as? Bool ?? true
        extensionFencedCode = defaults.object(forKey: Keys.extensionFencedCode) as? Bool ?? true
        extensionAutolink = defaults.object(forKey: Keys.extensionAutolink) as? Bool ?? true
        extensionStrikethrough = defaults.object(forKey: Keys.extensionStrikethrough) as? Bool ?? true
        extensionFootnotes = defaults.object(forKey: Keys.extensionFootnotes) as? Bool ?? true
        extensionQuote = defaults.object(forKey: Keys.extensionQuote) as? Bool ?? false
        extensionSmartyPants = defaults.object(forKey: Keys.extensionSmartyPants) as? Bool ?? true
        extensionUnderline = defaults.object(forKey: Keys.extensionUnderline) as? Bool ?? false
        extensionHighlight = defaults.object(forKey: Keys.extensionHighlight) as? Bool ?? false
        extensionSuperscript = defaults.object(forKey: Keys.extensionSuperscript) as? Bool ?? false
        markdownManualRender = defaults.object(forKey: Keys.manualRender) as? Bool ?? false
        editorBaseFontName = FontResolver.normalized(defaults.string(forKey: Keys.editorFontName))
        editorBaseFontSize = defaults.object(forKey: Keys.editorFontSize) as? Double ?? Self.defaultEditorBaseFontSize
        editorStyleName = defaults.string(forKey: Keys.editorStyleName) ?? EditorTheme.default.name
        editorHorizontalInset = defaults.object(forKey: Keys.editorHInset) as? Double ?? Self.defaultEditorHorizontalInset
        editorVerticalInset = defaults.object(forKey: Keys.editorVInset) as? Double ?? Self.defaultEditorVerticalInset
        editorLineSpacing = defaults.object(forKey: Keys.editorLineSpacing) as? Double ?? Self.defaultEditorLineSpacing
        editorWidthLimited = defaults.object(forKey: Keys.editorWidthLimited) as? Bool ?? false
        editorMaximumWidth = defaults.object(forKey: Keys.editorMaxWidth) as? Double ?? Self.defaultEditorMaximumWidth
        editorOnRight = defaults.object(forKey: Keys.editorOnRight) as? Bool ?? false
        editorShowWordCount = defaults.object(forKey: Keys.editorShowWordCount) as? Bool ?? true
        editorWordCountType = defaults.object(forKey: Keys.editorWordCountType) as? Int ?? 0
        editorUnorderedListMarkerType = defaults.object(forKey: Keys.editorListMarkerType) as? Int ?? 0
        editorScrollsPastEnd = defaults.object(forKey: Keys.editorScrollsPastEnd) as? Bool ?? false
        editorAutoIncrementNumberedLists = defaults.object(forKey: Keys.editorAutoNumberedLists) as? Bool ?? true
        editorConvertTabs = defaults.object(forKey: Keys.editorConvertTabs) as? Bool ?? true
        editorInsertPrefixInBlock = defaults.object(forKey: Keys.editorInsertPrefix) as? Bool ?? true
        editorCompleteMatchingCharacters = defaults.object(forKey: Keys.editorCompleteMatching) as? Bool ?? true
        editorSyncScrolling = defaults.object(forKey: Keys.editorSyncScroll) as? Bool ?? true
        editorBidirectionalScrollSync = defaults.object(forKey: Keys.editorBidirectionalScrollSync) as? Bool ?? false
        editorSmartHome = defaults.object(forKey: Keys.editorSmartHome) as? Bool ?? true
        editorEnsuresNewlineAtEndOfFile = defaults.object(forKey: Keys.editorNewlineAtEOF) as? Bool ?? true
        editorSpellChecking = defaults.object(forKey: Keys.editorSpellChecking) as? Bool ?? true
        editorShowLineNumbers = defaults.object(forKey: Keys.editorShowLineNumbers) as? Bool ?? false
        previewUsesTextSurface = defaults.object(forKey: Keys.previewUsesTextSurface) as? Bool ?? true
        editorShowInvisibleCharacters = defaults.object(forKey: Keys.editorShowInvisibleCharacters) as? Bool ?? false
        editorAutosaveEnabled = defaults.object(forKey: Keys.editorAutosaveEnabled) as? Bool ?? false
        htmlStyleName = defaults.string(forKey: Keys.htmlStyleName) ?? "Clearness"
        htmlTemplateName = defaults.string(forKey: Keys.htmlTemplateName) ?? "Default"
        htmlDetectFrontMatter = defaults.object(forKey: Keys.htmlDetectFrontMatter) as? Bool ?? true
        htmlTaskList = defaults.object(forKey: Keys.htmlTaskList) as? Bool ?? true
        htmlHardWrap = defaults.object(forKey: Keys.htmlHardWrap) as? Bool ?? false
        htmlSyntaxHighlighting = defaults.object(forKey: Keys.htmlSyntaxHighlighting) as? Bool ?? true
        htmlMathJax = defaults.object(forKey: Keys.htmlMathJax) as? Bool ?? true
        htmlMathJaxInlineDollar = defaults.object(forKey: Keys.htmlMathJaxInlineDollar) as? Bool ?? false
        htmlMermaid = defaults.object(forKey: Keys.htmlMermaid) as? Bool ?? false
        htmlGraphviz = defaults.object(forKey: Keys.htmlGraphviz) as? Bool ?? false
        htmlRendersTOC = defaults.object(forKey: Keys.htmlTOC) as? Bool ?? false
        htmlLineNumbers = defaults.object(forKey: Keys.htmlLineNumbers) as? Bool ?? false
        htmlCodeBlockAccessory = defaults.object(forKey: Keys.htmlCodeBlockAccessory) as? Int ?? 1
        htmlHighlightingThemeName = defaults.string(forKey: Keys.htmlHighlightingThemeName) ?? ""
        htmlDefaultDirectoryUrl = defaults.string(forKey: Keys.htmlDefaultDirectoryUrl)
            ?? NSHomeDirectory()
        previewZoomRelativeToBaseFontSize = defaults.object(forKey: Keys.previewZoomRelative) as? Bool ?? true
        previewFontPolicy = PreviewFontPolicy(rawValue: defaults.integer(forKey: Keys.previewFontPolicy)) ?? .followEditor
        previewFontName = FontResolver.normalized(defaults.string(forKey: Keys.previewFontName))
    }

    // MARK: - Parse options

    public var parseOptions: MarkdownParseOptions {
        MarkdownParseOptions(
            enableTables: extensionTables,
            enableFencedCode: extensionFencedCode,
            enableStrikethrough: extensionStrikethrough,
            enableAutolink: extensionAutolink,
            enableFootnotes: extensionFootnotes,
            enableTaskList: htmlTaskList,
            enableIntraEmphasis: extensionIntraEmphasis,
            enableUnderline: extensionUnderline,
            enableHighlight: extensionHighlight,
            enableSuperscript: extensionSuperscript,
            enableQuote: extensionQuote,
            enableSmartyPants: extensionSmartyPants,
            enableFrontMatter: htmlDetectFrontMatter,
            templateName: htmlTemplateName,
            enableLineNumbers: htmlLineNumbers,
            codeBlockAccessory: htmlCodeBlockAccessory,
            highlightingThemeName: htmlHighlightingThemeName,
            enableMath: htmlMathJax,
            enableInlineMath: htmlMathJax && htmlMathJaxInlineDollar,
            enableTOC: htmlRendersTOC,
            enableHardWrap: htmlHardWrap,
            enableSyntaxHighlighting: htmlSyntaxHighlighting
        )
    }

    /// The unconverted spacing for indentation based on `editorUnorderedListMarkerType`.
    public var editorUnorderedListMarker: String {
        switch editorUnorderedListMarkerType {
        case 1: "- "
        case 2: "+ "
        default: "* "
        }
    }

    private func write(_ value: Bool, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}

// MARK: - Keys

extension Preferences {
    enum Key: String {
        case suppressionStd
        case suppressUntitled = "suppressesUntitledDocumentOnLaunch"
        case updateIncludesPreReleases = "updateIncludesPreReleases"
        case createLinkTarget = "createFileForLinkTarget"
        case extensionIntraEmphasis = "extensionIntraEmphasis"
        case extensionTables = "extensionTables"
        case extensionFencedCode = "extensionFencedCode"
        case extensionAutolink = "extensionAutolink"
        case extensionStrikethrough = "extensionStrikethough"
        case extensionFootnotes = "extensionFootnotes"
        case extensionQuote = "extensionQuote"
        case extensionSmartyPants = "extensionSmartyPants"
        case extensionUnderline = "extensionUnderline"
        case extensionHighlight = "extensionHighlight"
        case extensionSuperscript = "extensionSuperscript"
        case manualRender = "markdownManualRender"
        case editorFontName = "editorFontName"
        case editorFontSize = "editorFontSize"
        case editorStyleName = "editorStyleName"
        case editorHInset = "editorHorizontalInset"
        case editorVInset = "editorVerticalInset"
        case editorLineSpacing = "editorLineSpacing"
        case editorWidthLimited = "editorWidthLimited"
        case editorMaxWidth = "editorMaximumWidth"
        case editorOnRight = "editorOnRight"
        case editorShowWordCount = "editorShowWordCount"
        case editorWordCountType = "editorWordCountType"
        case editorListMarkerType = "editorUnorderedListMarkerType"
        case editorScrollsPastEnd = "editorScrollsPastEnd"
        case editorAutoNumberedLists = "editorAutoIncrementNumberedLists"
        case editorConvertTabs = "editorConvertTabs"
        case editorInsertPrefix = "editorInsertPrefixInBlock"
        case editorCompleteMatching = "editorCompleteMatchingCharacters"
        case editorSyncScroll = "editorSyncScrolling"
        case editorBidirectionalScrollSync = "editorBidirectionalScrollSync"
        case editorSmartHome = "editorSmartHome"
        case editorNewlineAtEOF = "editorEnsuresNewlineAtEndOfFile"
        case editorSpellChecking = "editorSpellChecking"
        case editorShowLineNumbers = "editorShowLineNumbers"
        case editorShowInvisibleCharacters = "editorShowInvisibleCharacters"
        case previewUsesTextSurface = "previewUsesTextSurface"
        case editorAutosaveEnabled = "editorAutosaveEnabled"
        case htmlStyleName = "htmlStyleName"
        case htmlTemplateName = "htmlTemplateName"
        case htmlDetectFrontMatter = "htmlDetectFrontMatter"
        case htmlTaskList = "htmlTaskList"
        case htmlHardWrap = "htmlHardWrap"
        case htmlSyntaxHighlighting = "htmlSyntaxHighlighting"
        case htmlMathJax = "htmlMathJax"
        case htmlMathJaxInlineDollar = "htmlMathJaxInlineDollar"
        case htmlMermaid = "htmlMermaid"
        case htmlGraphviz = "htmlGraphviz"
        case htmlTOC = "htmlRendersTOC"
        case htmlLineNumbers = "htmlLineNumbers"
        case htmlCodeBlockAccessory = "htmlCodeBlockAccessory"
        case htmlHighlightingThemeName = "htmlHighlightingThemeName"
        case htmlDefaultDirectoryUrl = "htmlDefaultDirectoryUrl"
        case previewZoomRelative = "previewZoomRelativeToBaseFontSize"
        case previewFontPolicy = "previewFontPolicy"
        case previewFontName = "previewFontName"
    }

    private enum Keys {
        static let suppressUntitled = Key.suppressUntitled.rawValue
        static let updateIncludesPreReleases = Key.updateIncludesPreReleases.rawValue
        static let createLinkTarget = Key.createLinkTarget.rawValue
        static let extensionIntraEmphasis = Key.extensionIntraEmphasis.rawValue
        static let extensionTables = Key.extensionTables.rawValue
        static let extensionFencedCode = Key.extensionFencedCode.rawValue
        static let extensionAutolink = Key.extensionAutolink.rawValue
        static let extensionStrikethrough = Key.extensionStrikethrough.rawValue
        static let extensionFootnotes = Key.extensionFootnotes.rawValue
        static let extensionQuote = Key.extensionQuote.rawValue
        static let extensionSmartyPants = Key.extensionSmartyPants.rawValue
        static let extensionUnderline = Key.extensionUnderline.rawValue
        static let extensionHighlight = Key.extensionHighlight.rawValue
        static let extensionSuperscript = Key.extensionSuperscript.rawValue
        static let manualRender = Key.manualRender.rawValue
        static let editorFontName = Key.editorFontName.rawValue
        static let editorFontSize = Key.editorFontSize.rawValue
        static let editorStyleName = Key.editorStyleName.rawValue
        static let editorHInset = Key.editorHInset.rawValue
        static let editorVInset = Key.editorVInset.rawValue
        static let editorLineSpacing = Key.editorLineSpacing.rawValue
        static let editorWidthLimited = Key.editorWidthLimited.rawValue
        static let editorMaxWidth = Key.editorMaxWidth.rawValue
        static let editorOnRight = Key.editorOnRight.rawValue
        static let editorShowWordCount = Key.editorShowWordCount.rawValue
        static let editorWordCountType = Key.editorWordCountType.rawValue
        static let editorListMarkerType = Key.editorListMarkerType.rawValue
        static let editorScrollsPastEnd = Key.editorScrollsPastEnd.rawValue
        static let editorAutoNumberedLists = Key.editorAutoNumberedLists.rawValue
        static let editorConvertTabs = Key.editorConvertTabs.rawValue
        static let editorInsertPrefix = Key.editorInsertPrefix.rawValue
        static let editorCompleteMatching = Key.editorCompleteMatching.rawValue
        static let editorSyncScroll = Key.editorSyncScroll.rawValue
        static let editorBidirectionalScrollSync = Key.editorBidirectionalScrollSync.rawValue
        static let editorSmartHome = Key.editorSmartHome.rawValue
        static let editorNewlineAtEOF = Key.editorNewlineAtEOF.rawValue
        static let editorSpellChecking = Key.editorSpellChecking.rawValue
        static let editorShowLineNumbers = Key.editorShowLineNumbers.rawValue
        static let editorShowInvisibleCharacters = Key.editorShowInvisibleCharacters.rawValue
        static let previewUsesTextSurface = Key.previewUsesTextSurface.rawValue
        static let editorAutosaveEnabled = Key.editorAutosaveEnabled.rawValue
        static let htmlStyleName = Key.htmlStyleName.rawValue
        static let htmlTemplateName = Key.htmlTemplateName.rawValue
        static let htmlDetectFrontMatter = Key.htmlDetectFrontMatter.rawValue
        static let htmlTaskList = Key.htmlTaskList.rawValue
        static let htmlHardWrap = Key.htmlHardWrap.rawValue
        static let htmlSyntaxHighlighting = Key.htmlSyntaxHighlighting.rawValue
        static let htmlMathJax = Key.htmlMathJax.rawValue
        static let htmlMathJaxInlineDollar = Key.htmlMathJaxInlineDollar.rawValue
        static let htmlMermaid = Key.htmlMermaid.rawValue
        static let htmlGraphviz = Key.htmlGraphviz.rawValue
        static let htmlTOC = Key.htmlTOC.rawValue
        static let htmlLineNumbers = Key.htmlLineNumbers.rawValue
        static let htmlCodeBlockAccessory = Key.htmlCodeBlockAccessory.rawValue
        static let htmlHighlightingThemeName = Key.htmlHighlightingThemeName.rawValue
        static let htmlDefaultDirectoryUrl = Key.htmlDefaultDirectoryUrl.rawValue
        static let previewZoomRelative = Key.previewZoomRelative.rawValue
        static let previewFontPolicy = Key.previewFontPolicy.rawValue
        static let previewFontName = Key.previewFontName.rawValue
    }
}

/// How the preview picks its text font.
public enum PreviewFontPolicy: Int, CaseIterable, Sendable {
    /// Use the editor's font family (the default).
    case followEditor = 0
    /// Always use the system font: SF Pro, with PingFang SC for Chinese.
    case system = 1
    /// Use `Preferences.previewFontName`.
    case custom = 2
}