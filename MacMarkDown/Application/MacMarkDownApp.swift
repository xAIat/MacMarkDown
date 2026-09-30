import SwiftUI
import MacMarkDownKit

@main
struct MacMarkDownApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var preferences = Preferences()
    @State private var recentDocuments = RecentDocumentsStore.shared
    @State private var plugIns = PlugInManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("MacMarkDown", id: Constants.mainWindowID) {
            ContentView()
                .environment(preferences)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    Self.showUpdatesPlaceholder()
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New") {
                    openWindow(id: Constants.mainWindowID)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Open…") {
                    post(.openDocumentRequest)
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Menu("Open Recent") {
                    ForEach(recentDocuments.urls, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            NotificationCenter.default.post(
                                name: .openRecentDocumentRequest,
                                object: nil,
                                userInfo: [Constants.recentDocumentURLUserInfoKey: url]
                            )
                        }
                    }
                    if !recentDocuments.urls.isEmpty {
                        Divider()
                        Button("Clear Menu") {
                            recentDocuments.clear()
                        }
                    }
                }
                .disabled(recentDocuments.urls.isEmpty)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    post(.saveDocumentRequest)
                }
                .keyboardShortcut("s", modifiers: .command)
                Button("Save As…") {
                    post(.saveDocumentAsRequest)
                }
                .keyboardShortcut("S", modifiers: [.command, .shift])
                Divider()
                Button("Revert to Saved") {
                    post(.revertDocumentRequest)
                }
                .disabled(!DocumentSession.shared.isCurrentDocumentBound)
                Divider()
                Button("Export HTML…") {
                    post(.exportHTMLRequest)
                }
                .keyboardShortcut("e", modifiers: .command)
                Button("Export PDF…") {
                    post(.exportPDFRequest)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                Divider()
                Button("Page Setup…") {
                    Self.showPageSetup()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Print…") {
                    post(.printDocumentRequest)
                }
                .keyboardShortcut("p", modifiers: .command)
                Button("Copy HTML") {
                    post(.copyHTMLRequest)
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
            }
            CommandGroup(after: .toolbar) {
                Button("Show/Hide Toolbar") {
                    NotificationCenter.default.post(name: .toggleToolbar, object: nil)
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
                Button("Toggle Editor Pane") {
                    NotificationCenter.default.post(name: .toggleEditorPane, object: nil)
                }
                .keyboardShortcut("E", modifiers: [.command, .shift])
                Button("Toggle Preview Pane") {
                    NotificationCenter.default.post(name: .togglePreviewPane, object: nil)
                }
                .keyboardShortcut("H", modifiers: [.command, .shift])
                Divider()
                Button("Left 1:1 Right") {
                    NotificationCenter.default.post(name: .setEqualSplit, object: nil)
                }
                Button("Left 1:3 Right") {
                    NotificationCenter.default.post(name: .setEditorQuarter, object: nil)
                }
                Button("Left 3:1 Right") {
                    NotificationCenter.default.post(name: .setEditorThreeQuarters, object: nil)
                }
                Divider()
                Button("Render Markdown") {
                    NotificationCenter.default.post(name: .renderDocumentRequest, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Format") {
                Button("Strong") { postFormat(.strong) }
                    .keyboardShortcut("b", modifiers: .command)
                Button("Emphasize") { postFormat(.emphasis) }
                    .keyboardShortcut("i", modifiers: .command)
                Button("Inline Code") { postFormat(.inlineCode) }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Strikethrough") { postFormat(.strikethrough) }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                Button("Underline") { postFormat(.underline) }
                    .keyboardShortcut("u", modifiers: .command)
                Button("Highlight") { postFormat(.highlight) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Comment") { postFormat(.comment) }
                    .keyboardShortcut("/", modifiers: [.command, .option])
                Divider()
                Button("Link") { postFormat(.link) }
                Button("Image") { postFormat(.image) }
                Divider()
                Button("Paragraph") { postFormat(.paragraph) }
                    .keyboardShortcut("0", modifiers: .command)
                Button("Heading 1") { postFormat(.h1) }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Heading 2") { postFormat(.h2) }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Heading 3") { postFormat(.h3) }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Heading 4") { postFormat(.h4) }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Heading 5") { postFormat(.h5) }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Heading 6") { postFormat(.h6) }
                    .keyboardShortcut("6", modifiers: .command)
                Divider()
                Button("Unordered List") { postFormat(.unorderedList) }
                    .keyboardShortcut("u", modifiers: [.command, .control])
                Button("Ordered List") { postFormat(.orderedList) }
                    .keyboardShortcut("o", modifiers: [.command, .control])
                Button("Blockquote") { postFormat(.blockquote) }
                    .keyboardShortcut("b", modifiers: [.command, .control])
                Divider()
                Button("Indent") { postFormat(.indent) }
                    .keyboardShortcut("]", modifiers: .command)
                Button("Unindent") { postFormat(.unindent) }
                    .keyboardShortcut("[", modifiers: .command)
                Divider()
                Button("New Paragraph") { postFormat(.newParagraph) }
                    .keyboardShortcut(.return, modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("MacMarkDown Help") {
                    Self.openBundledDocument("help")
                }
                Button("Contributing to MacMarkDown") {
                    Self.openBundledDocument("contribute")
                }
            }
            CommandMenu("Plug-ins") {
                if plugIns.plugIns.isEmpty {
                    Button("No Plug-ins Installed") {}
                        .disabled(true)
                } else {
                    ForEach(Array(plugIns.plugIns.enumerated()), id: \.offset) { _, plugIn in
                        Button(plugIn.name.isEmpty ? "Untitled Plug-in" : plugIn.name) {
                            plugIn.run(nil)
                        }
                    }
                }
                Divider()
                Button("Reload Plug-ins") {
                    plugIns.reload()
                }
            }
        }

        Settings {
            SettingsView()
                .environment(preferences)
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }

    private func postFormat(_ command: EditorFormatCommand) {
        NotificationCenter.default.post(
            name: .formatCommandRequest,
            object: nil,
            userInfo: [Constants.formatCommandUserInfoKey: command.rawValue]
        )
    }

    /// Opens a bundled Markdown document (help/contribute) in the user's
    /// default Markdown application.
    private static func openBundledDocument(_ name: String) {
        AppDelegate.openBundledDocument(name)
    }

    /// Shows the system page-setup dialog, editing the shared print info used
    /// by Print/Export PDF.
    private static func showPageSetup() {
        NSPageLayout().runModal(with: NSPrintInfo.shared)
    }

    /// Sparkle is deliberately not wired up yet: the Info.plist carries
    /// placeholder feed/key values, so the menu item just explains how to
    /// enable real updates.
    private static func showUpdatesPlaceholder() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Updates Are Not Configured")
        alert.informativeText = String(localized: "This build ships placeholder update settings. Set SUFeedURL and SUPublicEDKey, then add the Sparkle package before enabling automatic updates.")
        alert.addButton(withTitle: String(localized: "OK"))
        alert.runModal()
    }
}

struct ContentView: View {
    var body: some View {
        DocumentView()
    }
}