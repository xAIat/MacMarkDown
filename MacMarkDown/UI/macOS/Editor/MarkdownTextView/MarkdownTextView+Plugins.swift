import AppKit

// MARK: - Plugin hosting
//
// Adds/removes `MarkdownPlugin`s and dispatches the plugin events from the
// view's own change/layout callbacks.

extension MarkdownTextView {

    /// Registers a plugin, calling `setUp` immediately.
    func addPlugin(_ plugin: MarkdownPlugin) {
        let entry = PluginEntry(plugin: plugin)
        plugin.setUp(textView: self, events: entry.events)
        pluginEntries.append(entry)
    }

    /// Removes a plugin, calling `tearDown`.
    func removePlugin(_ plugin: MarkdownPlugin) {
        guard let index = pluginEntries.firstIndex(where: { $0.plugin === plugin }) else { return }
        let entry = pluginEntries.remove(at: index)
        entry.plugin.tearDown()
    }

    /// Dispatches a `shouldChange` event; returns `false` if any plugin vetoes.
    func pluginsShouldChangeText(in range: NSTextRange, replacement: String?) -> Bool {
        pluginEntries.allSatisfy { $0.events.shouldChange(range, replacement: replacement) }
    }

    /// Dispatches a `didChange` event.
    func pluginsDidChangeText(in range: NSTextRange, replacement: String) {
        for entry in pluginEntries { entry.events.didChange(range, replacement: replacement) }
    }

    /// Dispatches a viewport-layout event.
    func pluginsDidLayoutViewport() {
        for entry in pluginEntries { entry.events.didLayoutViewport() }
    }

    /// Whether any plugins are installed.
    var hasPlugins: Bool { !pluginEntries.isEmpty }
}

/// One installed plugin plus its event registry.
@MainActor
final class PluginEntry {
    let plugin: MarkdownPlugin
    let events = MarkdownPluginEvents()
    init(plugin: MarkdownPlugin) { self.plugin = plugin }
}
