import Foundation

/// Loads bundled resources (preview stylesheets, editor themes and HTML
/// templates). Resources live under `Resources/` in the app/framework bundle.
public enum ResourceLoader {

    /// The bundle that carries the resources. The SwiftUI preview and the
    /// tests both resolve the framework bundle.
    public static var bundle: Bundle {
        Bundle(for: ResourceBundleToken.self)
    }

    /// Reads `Resources/<directory>/<name>` as UTF-8 text, or `nil`.
    ///
    /// XcodeGen flattens a resource folder into the bundle root, so both the
    /// nested and the flattened layouts are probed.
    public static func text(named name: String, in directory: String) -> String? {
        let candidates = [
            bundle.url(forResource: name, withExtension: nil, subdirectory: directory),
            bundle.url(forResource: name, withExtension: nil, subdirectory: "Resources/\(directory)"),
            bundle.url(forResource: name, withExtension: nil),
        ]
        guard let url = candidates.compactMap({ $0 }).first else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// The CSS stylesheet bundled for a preview theme name, if one exists
    /// (`Clearness Dark`, `Solarized (Dark)`, …).
    public static func styleSheet(forTheme name: String) -> String? {
        text(named: "\(name).css", in: Constants.stylesDirectoryName)
    }

    /// All bundled stylesheet names (file names without the extension).
    public static var availableStyleNames: [String] {
        resourceNames(withExtension: "css", directory: Constants.stylesDirectoryName)
    }

    /// All bundled editor theme names (`.style` files, without the extension).
    public static var availableThemeNames: [String] {
        resourceNames(withExtension: Constants.themeFileExtension, directory: Constants.themesDirectoryName)
    }

    /// The Handlebars-style HTML template bundled for a name, if one exists.
    public static func template(named name: String) -> String? {
        text(named: "\(name).handlebars", in: Constants.templatesDirectoryName)
    }

    /// All bundled HTML template names (`.handlebars`, without the extension).
    public static var availableTemplateNames: [String] {
        resourceNames(withExtension: "handlebars", directory: Constants.templatesDirectoryName)
    }

    private static func resourceNames(withExtension ext: String, directory: String) -> [String] {
        let nested = bundle.urls(forResourcesWithExtension: ext, subdirectory: directory) ?? []
        let flat = bundle.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        let names = (nested + flat).map { $0.deletingPathExtension().lastPathComponent }
        return Set(names).sorted()
    }
}

/// Anchor class so `Bundle(for:)` resolves the framework bundle.
private final class ResourceBundleToken {}
