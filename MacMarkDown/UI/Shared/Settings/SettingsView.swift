import AppKit
import SwiftUI

/// The preferences window, opened via the app's `Settings` scene.
public struct SettingsView: View {
    @Environment(Preferences.self) private var preferences

    public init() {}

    public var body: some View {
        TabView {
            GeneralSettingsView()
                .environment(preferences)
                .tabItem { Label("General", systemImage: "gearshape") }
            MarkdownSettingsView()
                .environment(preferences)
                .tabItem { Label("Markdown", systemImage: "text.quote") }
            EditorSettingsView()
                .environment(preferences)
                .tabItem { Label("Editor", systemImage: "pencil") }
            HtmlSettingsView()
                .environment(preferences)
                .tabItem { Label("HTML", systemImage: "globe") }
            TerminalSettingsView()
                .tabItem { Label("Terminal", systemImage: "terminal") }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - Terminal

struct TerminalSettingsView: View {

    @State private var isInstalled = TerminalUtility.isInstalled
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("Command-Line Utility") {
                HStack(spacing: 8) {
                    Circle()
                        .fill(isInstalled ? Color.green : Color.secondary)
                        .frame(width: 10, height: 10)
                    Text(isInstalled ? "Installed at \(Constants.cliInstallPath)" : "Not installed")
                        .font(.callout)
                }
                HStack {
                    Button(isInstalled ? "Reinstall" : "Install") {
                        install()
                    }
                    Button("Uninstall") {
                        uninstall()
                    }
                    .disabled(!isInstalled)
                }
            }
            Section {
                Text("""
                The `macmarkdown` utility opens files in MacMarkDown from the \
                terminal. Piping content (for example `cat notes.md | macmarkdown`) \
                opens it as a new document.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { isInstalled = TerminalUtility.isInstalled }
    }

    private func install() {
        do {
            try TerminalUtility.install()
            isInstalled = true
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func uninstall() {
        do {
            try TerminalUtility.uninstall()
            isInstalled = false
            statusMessage = nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @Environment(Preferences.self) private var preferences

    @State private var suppress = UserDefaults.standard.bool(forKey: "suppressesUntitledDocumentOnLaunch")
    @State private var createLinkTarget = UserDefaults.standard.bool(forKey: "createFileForLinkTarget")
    @State private var prereleases = UserDefaults.standard.bool(forKey: "updateIncludesPreReleases")

    var body: some View {
        Form {
            Section("Launch") {
                Toggle("Suppress Untitled Document on Launch", isOn: $suppress)
                    .onChange(of: suppress) { _, newValue in
                        preferences.suppressUntitledDocumentOnLaunch = newValue
                    }
                Toggle("Create File for Link Targets", isOn: $createLinkTarget)
                    .onChange(of: createLinkTarget) { _, newValue in
                        preferences.createFileForLinkTarget = newValue
                    }
            }
            Section("Updates") {
                Toggle("Include Pre-Releases", isOn: $prereleases)
                    .onChange(of: prereleases) { _, newValue in
                        preferences.updateIncludesPreReleases = newValue
                    }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Markdown

struct MarkdownSettingsView: View {
    @Environment(Preferences.self) private var preferences

    @State private var manualRender = UserDefaults.standard.object(forKey: "markdownManualRender") as? Bool ?? false

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("Rendering") {
                Toggle("Manual Render", isOn: $manualRender)
                    .onChange(of: manualRender) { _, newValue in
                        preferences.markdownManualRender = newValue
                    }
            }
            Section("Extensions") {
                Toggle("Intra-word Emphasis", isOn: $preferences.extensionIntraEmphasis)
                Toggle("Tables", isOn: $preferences.extensionTables)
                Toggle("Fenced Code Blocks", isOn: $preferences.extensionFencedCode)
                Toggle("Autolink", isOn: $preferences.extensionAutolink)
                Toggle("Strikethrough", isOn: $preferences.extensionStrikethrough)
                Toggle("Underline", isOn: $preferences.extensionUnderline)
                Toggle("Highlight", isOn: $preferences.extensionHighlight)
                Toggle("Superscript", isOn: $preferences.extensionSuperscript)
                Toggle("Footnotes", isOn: $preferences.extensionFootnotes)
                Toggle("Blockquote", isOn: $preferences.extensionQuote)
                Toggle("SmartyPants", isOn: $preferences.extensionSmartyPants)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Editor

struct EditorSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @State private var fontPanel = FontPanelController()

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("Font") {
                HStack {
                    TextField("System (SF Mono)", text: $preferences.editorBaseFontName)
                    Button("Choose…") {
                        fontPanel.onChange = { name, size in
                            preferences.editorBaseFontName = name
                            preferences.editorBaseFontSize = size
                        }
                        fontPanel.showPanel(
                            seededWith: FontResolver.editorFont(
                                named: preferences.editorBaseFontName,
                                size: preferences.editorBaseFontSize
                            )
                        )
                    }
                    ResetButton(label: "Reset Font to System (SF Mono)") {
                        preferences.editorBaseFontName = FontResolver.systemFontName
                    }
                    .disabled(preferences.editorBaseFontName.isEmpty)
                }
                SettingsSliderRow(
                    title: "Size",
                    value: $preferences.editorBaseFontSize,
                    range: 9...32,
                    defaultValue: Preferences.defaultEditorBaseFontSize
                )
                if !FontResolver.isMonospacedCJK(preferences.editorBaseFontName) {
                    Text("Chinese text lines up with the Latin grid only in a CJK monospaced font, for example Sarasa Mono SC.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section("Theme") {
                Picker("Editor Theme", selection: $preferences.editorStyleName) {
                    ForEach(EditorTheme.selectable) { theme in
                        Text(theme.displayName).tag(theme.name)
                    }
                }
            }
            Section("Layout") {
                Toggle("Width Limited", isOn: $preferences.editorWidthLimited)
                SettingsSliderRow(
                    title: "Max Width",
                    value: $preferences.editorMaximumWidth,
                    range: 400...1400,
                    defaultValue: Preferences.defaultEditorMaximumWidth
                )
                .disabled(!preferences.editorWidthLimited)
                Toggle("Editor on Right", isOn: $preferences.editorOnRight)
                SettingsSliderRow(
                    title: "Line Spacing",
                    value: $preferences.editorLineSpacing,
                    range: 1.0...2.5,
                    defaultValue: Preferences.defaultEditorLineSpacing,
                    format: "%.1f"
                )
                SettingsSliderRow(
                    title: "Horizontal Inset",
                    value: $preferences.editorHorizontalInset,
                    range: 0...80,
                    defaultValue: Preferences.defaultEditorHorizontalInset
                )
                SettingsSliderRow(
                    title: "Vertical Inset",
                    value: $preferences.editorVerticalInset,
                    range: 0...80,
                    defaultValue: Preferences.defaultEditorVerticalInset
                )
            }
            Section("Behavior") {
                Toggle("Show Word Count", isOn: $preferences.editorShowWordCount)
                Picker("Word Count Type", selection: $preferences.editorWordCountType) {
                    Text("Words").tag(0)
                    Text("Characters").tag(1)
                    Text("Characters (no spaces)").tag(2)
                }
                .disabled(!preferences.editorShowWordCount)
                Toggle("Sync Scrolling", isOn: $preferences.editorSyncScrolling)
                Toggle("Bidirectional Sync", isOn: $preferences.editorBidirectionalScrollSync)
                    .disabled(!preferences.editorSyncScrolling)
                Toggle("Smart Home", isOn: $preferences.editorSmartHome)
                Toggle("Convert Tabs to Spaces", isOn: $preferences.editorConvertTabs)
                Toggle("Insert Prefix in Block", isOn: $preferences.editorInsertPrefixInBlock)
                Toggle("Complete Matching Characters", isOn: $preferences.editorCompleteMatchingCharacters)
                Picker("Unordered List Marker", selection: $preferences.editorUnorderedListMarkerType) {
                    Text("* (Asterisk)").tag(0)
                    Text("- (Hyphen)").tag(1)
                    Text("+ (Plus)").tag(2)
                }
                Toggle("Scrolls Past End", isOn: $preferences.editorScrollsPastEnd)
                Toggle("Ensure Newline at End of File", isOn: $preferences.editorEnsuresNewlineAtEndOfFile)
                Toggle("Auto Save Changes", isOn: $preferences.editorAutosaveEnabled)
                Toggle("Spell Checking", isOn: $preferences.editorSpellChecking)
                Toggle("Show Line Numbers", isOn: $preferences.editorShowLineNumbers)
                Toggle("Show Invisible Characters", isOn: $preferences.editorShowInvisibleCharacters)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - HTML

struct HtmlSettingsView: View {
    @Environment(Preferences.self) private var preferences
    @State private var previewFontPanel = FontPanelController()

    private var templateNames: [String] {
        let names = ResourceLoader.availableTemplateNames
        return names.isEmpty ? ["Default"] : names
    }

    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("Preview Style") {
                Picker("Stylesheet", selection: $preferences.htmlStyleName) {
                    ForEach(Theme.all) { theme in
                        Text(theme.displayName).tag(theme.name)
                    }
                }
                Picker("HTML Template", selection: $preferences.htmlTemplateName) {
                    ForEach(templateNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                Toggle("Selectable Preview (Text Surface)", isOn: $preferences.previewUsesTextSurface)
                Toggle("Detect Front Matter", isOn: $preferences.htmlDetectFrontMatter)
                Toggle("Task List", isOn: $preferences.htmlTaskList)
                Toggle("Hard Wrap", isOn: $preferences.htmlHardWrap)
                Toggle("Render TOC", isOn: $preferences.htmlRendersTOC)
                Toggle("Syntax Highlighting", isOn: $preferences.htmlSyntaxHighlighting)
                Picker("Highlighting Theme", selection: $preferences.htmlHighlightingThemeName) {
                    Text("Default").tag("")
                    ForEach(CodeHighlightTheme.all) { theme in
                        Text(theme.displayName).tag(theme.name)
                    }
                }
                Toggle("Line Numbers", isOn: $preferences.htmlLineNumbers)
                Picker("Code Block Accessory", selection: $preferences.htmlCodeBlockAccessory) {
                    Text("None").tag(0)
                    Text("Language Name").tag(1)
                    Text("Custom").tag(2)
                }
                Toggle("TeX Math (MathJax)", isOn: $preferences.htmlMathJax)
                Toggle("Inline Math ($…$)", isOn: $preferences.htmlMathJaxInlineDollar)
                    .disabled(!preferences.htmlMathJax)
                Toggle("Mermaid Diagrams", isOn: $preferences.htmlMermaid)
                Toggle("Graphviz Diagrams", isOn: $preferences.htmlGraphviz)
                Picker("Preview Font", selection: $preferences.previewFontPolicy) {
                    Text("Follow Editor Font").tag(PreviewFontPolicy.followEditor)
                    Text("System Font").tag(PreviewFontPolicy.system)
                    Text("Custom…").tag(PreviewFontPolicy.custom)
                }
                if preferences.previewFontPolicy == .custom {
                    HStack {
                        TextField("System Font", text: $preferences.previewFontName)
                        Button("Choose…") {
                            previewFontPanel.onChange = { name, _ in
                                preferences.previewFontName = name
                            }
                            previewFontPanel.showPanel(
                                seededWith: FontResolver.previewFont(
                                    named: preferences.previewFontName,
                                    size: preferences.editorBaseFontSize
                                )
                            )
                        }
                    }
                }
                Toggle("Zoom Relative to Base Font Size", isOn: $preferences.previewZoomRelativeToBaseFontSize)
            }
            Section("Links") {
                HStack {
                    Text(preferences.htmlDefaultDirectoryUrl)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Choose…") { chooseDefaultDirectory() }
                }
                Text("Relative links and images in unsaved documents resolve against this folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func chooseDefaultDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: preferences.htmlDefaultDirectoryUrl, isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            preferences.htmlDefaultDirectoryUrl = url.path
        }
    }
}

// MARK: - Settings slider

/// A labeled settings slider with a reset button beside the value that restores
/// the default value. Every slider in the settings window uses it, so they all
/// share one layout: the same label column, the same value column and therefore
/// the same track length.
///
/// The fixed label and value widths matter: a `Form` lays every row out on its
/// own, so without them the slider's length depended on the label's width
/// (Horizontal Inset and Vertical Inset ended up different lengths) and changed
/// while dragging across a digit boundary (9 → 10 grew the value text and
/// pushed the whole track left).
struct SettingsSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let defaultValue: Double
    /// printf-style format for the value and the reset button's tooltip.
    var format: String = "%.0f"

    /// Wide enough for the longest label ("Horizontal Inset") at the default
    /// system font. `minWidth` keeps a longer label from being truncated.
    private let labelWidth: CGFloat = 112
    /// Wide enough for the widest value the settings ranges produce ("1400").
    private let valueWidth: CGFloat = 36

    var body: some View {
        HStack {
            Text(title)
                .frame(minWidth: labelWidth, alignment: .leading)
            Slider(value: $value, in: range)
            resetButton
            Text("\(value, specifier: format)")
                .monospacedDigit()
                .frame(minWidth: valueWidth, alignment: .trailing)
        }
    }

    /// Restores the default value. Placed between the slider and the value so
    /// the number column stays right-aligned with the rows that have no button.
    private var resetButton: some View {
        ResetButton(label: "Reset \(title) to \(String(format: format, defaultValue))") {
            value = defaultValue
        }
    }
}

// MARK: - Reset button

/// The circular "restore the default" button used by the settings' sliders and
/// by the font rows. Plain-styled, so it stays quiet until hovered.
struct ResetButton: View {
    /// Tooltip and accessibility label.
    let label: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.counterclockwise")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .onHover { isHovering = $0 }
        .help(label)
        .accessibilityLabel(Text(label))
    }

    private var tint: Color {
        guard isEnabled else { return .secondary.opacity(0.4) }
        return isHovering ? .accentColor : .secondary
    }
}
