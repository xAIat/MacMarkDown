import AppKit

/// A plug-in loaded from `~/Library/Application Support/MacMarkDown/PlugIns`.
/// A `.plugin` bundle whose principal class implements the optional `name`
/// and `run(_:)` members.
public protocol MacMarkDownPlugIn: AnyObject {
    /// The menu title. Defaults to the bundle name when omitted.
    var name: String { get }
    /// Invoked when the user selects the plug-in's menu item.
    func run(_ sender: Any?)
}

public extension MacMarkDownPlugIn {
    var name: String { "" }
}

/// Loads plug-in bundles and exposes their menu items.
@MainActor
public final class PlugInManager {

    public static let shared = PlugInManager()

    public private(set) var plugIns: [MacMarkDownPlugIn] = []

    private var bundles: [Bundle] = []

    private init() {}

    /// The plug-ins directory (`~/Library/Application Support/MacMarkDown/PlugIns`).
    public static var plugInsDirectory: URL {
        URL(fileURLWithPath: Constants.dataDirectory(Constants.plugInsDirectoryName))
    }

    /// Scans the plug-ins directory and loads every `.plugin` bundle.
    public func reload() {
        unloadAll()
        let fileManager = FileManager.default
        let directory = Self.plugInsDirectory
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []

        for url in contents where url.pathExtension == Constants.plugInFileExtension {
            guard let bundle = Bundle(url: url),
                  let principalClass = bundle.principalClass as? NSObject.Type,
                  let instance = principalClass.init() as? MacMarkDownPlugIn
            else { continue }
            bundles.append(bundle)
            plugIns.append(instance)
        }
    }

    /// Calls `plugInDidInitialize`-style setup if the plug-in exposes it.
    public func initializePlugIns() {
        reload()
    }

    private func unloadAll() {
        plugIns.removeAll()
        bundles.removeAll()
    }
}