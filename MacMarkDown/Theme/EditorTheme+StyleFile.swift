import Foundation
import SwiftUI

// MARK: - `.style` file support
//
// Editor themes ship as INI-like `.style` files whose sections name Markdown
// elements (title, emphasis, strong, code, …). The parser below maps the
// supported subset of rules onto `EditorTheme`.

extension EditorTheme {

    /// Themes discovered in `Resources/Themes/*.style`, sorted by display name.
    public static let fileBased: [EditorTheme] = {
        let names = ResourceLoader.availableThemeNames
        return names.compactMap { styleFile(named: $0) }.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }()

    /// All selectable editor themes: built-ins first, then bundled files.
    public static var selectable: [EditorTheme] {
        all + fileBased
    }

    /// Loads a `.style` file by its base name (e.g. `Tomorrow+`).
    public static func styleFile(named name: String) -> EditorTheme? {
        guard let text = ResourceLoader.text(named: "\(name).style", in: Constants.themesDirectoryName) else {
            return nil
        }
        return parseStyleFile(text, name: name)
    }

    /// Parses the INI-like format: a bare section line followed by
    /// `key: value` pairs, sections separated by blank lines.
    static func parseStyleFile(_ text: String, name: String) -> EditorTheme {
        var sections: [String: [String: String]] = [:]
        var currentSection: String?

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if let colon = line.firstIndex(of: ":") {
                guard let section = currentSection else { continue }
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                sections[section, default: [:]][key] = value
            } else {
                currentSection = line
            }
        }

        func color(_ section: String, _ key: String) -> Color? {
            guard let value = sections[section]?[key] else { return nil }
            return Color(hexString: value)
        }

        let background = color("editor", "background") ?? Color(red: 1, green: 1, blue: 1)
        let foreground = color("editor", "foreground") ?? Color(red: 0.1, green: 0.1, blue: 0.1)
        let caret = color("editor", "caret") ?? foreground
        let selectionColor = color("editor-selection", "background")
            ?? Color(red: 0.8, green: 0.87, blue: 0.95)

        // Fallback colors derived from the base pair when a section is absent.
        let heading = color("H1", "foreground") ?? foreground
        let link = color("LINK", "foreground") ?? color("AUTO_LINK_URL", "foreground") ?? foreground
        let code = color("CODE", "foreground") ?? foreground
        let emphasis = color("EMPH", "foreground") ?? foreground
        let strong = color("STRONG", "foreground") ?? foreground
        let quote = color("BLOCKQUOTE", "foreground") ?? foreground
        let listMarker = color("LIST_BULLET", "foreground")
            ?? color("LIST_ENUMERATOR", "foreground") ?? foreground

        return EditorTheme(
            name: name,
            displayName: name,
            backgroundColor: background,
            textColor: foreground,
            cursorColor: caret,
            selectionColor: selectionColor,
            lineHighlightColor: background,
            titleColor: color("H1", "foreground") ?? heading,
            emphasisColor: emphasis,
            strongColor: strong,
            codeColor: code,
            linkColor: link,
            quoteColor: quote,
            listMarkerColor: listMarker,
            headingColor: heading,
            boldColor: strong,
            italicColor: emphasis
        )
    }
}

// MARK: - Hex colors

extension Color {
    /// Parses `RRGGBB` / `#RRGGBB` (and the 3-digit shorthand).
    init?(hexString: String) {
        var hex = hexString.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 3,
              let value = UInt64(hex, radix: 16)
        else { return nil }
        let r, g, b: Double
        if hex.count == 3 {
            r = Double((value >> 8) & 0xF) / 15.0
            g = Double((value >> 4) & 0xF) / 15.0
            b = Double(value & 0xF) / 15.0
        } else {
            r = Double((value >> 16) & 0xFF) / 255.0
            g = Double((value >> 8) & 0xFF) / 255.0
            b = Double(value & 0xFF) / 255.0
        }
        self.init(red: r, green: g, blue: b)
    }
}