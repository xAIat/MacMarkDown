import Foundation

/// Manages the `macmarkdown` command-line utility: locates the binary inside
/// the app bundle and installs/removes a symlink under `/usr/local/bin`.
public enum TerminalUtility {

    public enum InstallError: LocalizedError {
        case cliNotFound
        case permissionDenied(String)

        public var errorDescription: String? {
            switch self {
            case .cliNotFound:
                return "The macmarkdown utility was not found inside the app bundle."
            case .permissionDenied(let path):
                return "Couldn’t write \(path). Check the permissions of /usr/local/bin."
            }
        }
    }

    /// The bundled CLI binary, if this app was built with the CLI target
    /// embedded. The product is named `macmarkdown-cli` on disk (the plain
    /// `macmarkdown` name collides with the `MacMarkDown` source folder on
    /// case-insensitive filesystems) and installed under `macmarkdown`.
    public static var bundledCLIURL: URL? {
        let macos = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS")
        for name in ["macmarkdown", "macmarkdown-cli"] {
            let url = macos.appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    public static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Constants.cliInstallPath)
    }

    public static func install() throws {
        guard let cli = bundledCLIURL else { throw InstallError.cliNotFound }
        let destination = Constants.cliInstallPath
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                atPath: (destination as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            if fileManager.fileExists(atPath: destination) {
                try fileManager.removeItem(atPath: destination)
            }
            try fileManager.createSymbolicLink(atPath: destination, withDestinationPath: cli.path)
        } catch {
            if (error as NSError).code == NSFileWriteNoPermissionError {
                throw InstallError.permissionDenied(destination)
            }
            throw error
        }
    }

    public static func uninstall() throws {
        let destination = Constants.cliInstallPath
        guard FileManager.default.fileExists(atPath: destination) else { return }
        try FileManager.default.removeItem(atPath: destination)
    }
}