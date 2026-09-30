import AppKit
import MacMarkDownKit

/// Receives file-open events from the Finder (double-click, "Open With", or a
/// drop onto the Dock icon) and forwards them to the document view.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Guards unsaved edits on quit. `DocumentView` installs the same kind of
    /// guard on the window for the close path.
    private let quitGuard = UnsavedChangesGuard()

    /// Reads the queue the `macmarkdown` CLI wrote before launching the app.
    func applicationDidFinishLaunching(_ notification: Notification) {
        PlugInManager.shared.initializePlugIns()
        showFirstLaunchTipsIfNeeded()
        DocumentSession.shared.suppressNextBlankWindow =
            Preferences(defaults: .standard).suppressUntitledDocumentOnLaunch
        let defaults = UserDefaults(suiteName: Constants.cliHandoffSuiteName)
        var paths: [String] = []
        if let stored = defaults?.stringArray(forKey: Constants.filesToOpenOnNextLaunchKey) {
            paths.append(contentsOf: stored)
        }
        if let piped = defaults?.string(forKey: Constants.pipedContentFileKey) {
            paths.append(piped)
        }
        defaults?.removeObject(forKey: Constants.filesToOpenOnNextLaunchKey)
        defaults?.removeObject(forKey: Constants.pipedContentFileKey)
        guard !paths.isEmpty else { return }
        let urls = paths.map { URL(fileURLWithPath: $0) }
        DocumentOpenQueue.shared.enqueue(urls)
        // The launch window drains one; the rest get their own windows.
        for _ in urls.dropFirst() {
            DocumentSession.shared.requestNewWindow()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let fileURLs = urls.compactMap(AppURLScheme.fileURL(from:))
        guard !fileURLs.isEmpty else { return }
        var reusedWindow = false
        for url in fileURLs {
            if DocumentSession.shared.openFile(url) { reusedWindow = true }
        }
        // `openFile` already requests a window when it queues a file, so only
        // fall back to opening one when nothing was reused and none is visible
        // (e.g. an app URL-scheme open with no file). Requesting unconditionally
        // produced a spurious extra blank window when launching by opening a
        // document.
        if !reusedWindow,
           !DocumentOpenQueue.shared.hasPending,
           !application.windows.contains(where: \.isVisible) {
            DocumentSession.shared.requestNewWindow()
        }
    }

    /// Keep the app alive when the window is closed so a later file-open
    /// request can bring it back, matching the usual macOS behavior.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Ask about unsaved edits before terminating.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitGuard.document = DocumentSession.shared.document
        return quitGuard.confirmClose() ? .terminateNow : .terminateCancel
    }

    /// Persist any pending autosave before the app exits (Cmd+Q).
    func applicationWillTerminate(_ notification: Notification) {
        DocumentSession.shared.flushAutosave()
    }

    // MARK: - First launch

    /// On the very first launch, open the help and contributing documents so
    /// new users land on a readable starting point.
    private func showFirstLaunchTipsIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Constants.firstVersionInstalledKey) == nil else {
            return
        }
        let version = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        defaults.set(version, forKey: Constants.firstVersionInstalledKey)
        // Defer until the launch window exists so the documents open in front.
        DispatchQueue.main.async {
            AppDelegate.openBundledDocument("help")
            AppDelegate.openBundledDocument("contribute")
        }
    }

    /// Opens a bundled Markdown document (help/contribute) in the default
    /// Markdown application.
    static func openBundledDocument(_ name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "md") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
