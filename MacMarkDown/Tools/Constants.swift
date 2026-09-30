import Foundation
import SwiftUI

/// Application constants — directory names, file extensions, defaults, and
/// the identifier strings shared across the app.
public enum Constants {

    // MARK: - Directories

    public static let stylesDirectoryName = "Styles"
    public static let themesDirectoryName = "Themes"
    public static let templatesDirectoryName = "Templates"
    public static let extensionsDirectoryName = "Extensions"
    public static let plugInsDirectoryName = "PlugIns"

    // MARK: - Extensions

    public static let styleFileExtension = "css"
    public static let themeFileExtension = "style"
    public static let plugInFileExtension = "macmarkdown-plugin"

    // MARK: - Pasteboard

    public static let htmlPasteboardType = "public.html"

    // MARK: - Notifications

    public static let didDetectFreshInstallation = "com.xaiat.MacMarkDown.didDetectFreshInstallation"
    public static let didRequestEditorSetup = "com.xaiat.MacMarkDown.didRequestEditorSetup"
    public static let didRequestPreviewRender = "com.xaiat.MacMarkDown.didRequestPreviewRender"
    public static let notificationKeyName = "key"
    /// userInfo key carrying an `EditorFormatCommand.rawValue`.
    public static let formatCommandUserInfoKey = "formatCommand"
    /// userInfo key carrying a recent document URL.
    public static let recentDocumentURLUserInfoKey = "recentDocumentURL"

    // MARK: - CLI handoff (shared defaults suite)

    /// `UserDefaults` suite shared with the `macmarkdown` CLI. Deliberately
    /// distinct from the app's bundle identifier (using your own bundle id as a
    /// suite name is invalid and silently fails).
    public static let cliHandoffSuiteName = "com.xaiat.MacMarkDown.cli"

    /// Files queued by the `macmarkdown` CLI for the next launch.
    public static let filesToOpenOnNextLaunchKey = "filesToOpenOnNextLaunch"
    /// Piped stdin content queued by the CLI for the next launch.
    public static let pipedContentFileKey = "pipedContentFileToOpenOnNextLaunch"
    /// The CLI's symlink target under `/usr/local/bin`.
    public static let cliInstallPath = "/usr/local/bin/macmarkdown"

    // MARK: - Version tracking

    /// The first app version that ran, used to detect a fresh installation.
    public static let firstVersionInstalledKey = "firstVersionInstalled"

    // MARK: - App Info

    public static let appName = "MacMarkDown"
    public static let bundleIdentifier = "com.xaiat.MacMarkDown"
    public static let mainWindowID = "main"

    // MARK: - Defaults

    public static let defaultEditorFontName = "SF Mono"
    public static let defaultEditorFontSize: Double = 14.0
    public static let defaultEditorLineSpacing: Double = 1.4
    public static let defaultDebounceInterval: TimeInterval = 0.3
    public static let autosaveDebounceInterval: TimeInterval = 1.0

    // MARK: - Data directory

    /// Returns the path to the app's data directory under `~/Library/Application Support/MacMarkDown/`.
    public static func dataDirectory(_ relativePath: String? = nil) -> String {
        let base = NSSearchPathForDirectoriesInDomains(
            .applicationSupportDirectory, .userDomainMask, true
        ).first!
        var path = (base as NSString).appendingPathComponent(appName)
        if let relative = relativePath, !relative.isEmpty {
            path = (path as NSString).appendingPathComponent(relative)
        }
        return path
    }

    /// Returns path to a file inside the data directory.
    public static func pathToDataFile(_ name: String, in directory: String? = nil) -> String {
        let dir = dataDirectory(directory)
        return (dir as NSString).appendingPathComponent(name)
    }

    /// Ensures the data directory exists.
    public static func ensureDataDirectoryExists() {
        let fm = FileManager.default
        let dir = dataDirectory()
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
    }
}