import SwiftUI

/// Selectable code syntax-highlighting palettes for fenced code blocks.
///
/// Code is highlighted natively, so the Rendering preferences offer a small
/// set of token color palettes instead of a JavaScript highlighter.
public struct CodeHighlightTheme: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var displayName: String
    public var palette: Palette

    public init(name: String, displayName: String, palette: Palette) {
        self.name = name
        self.displayName = displayName
        self.palette = palette
    }

    /// The four token colors the highlighter understands.
    public struct Palette: Sendable, Hashable {
        public var keyword: Color
        public var string: Color
        public var comment: Color
        public var number: Color

        public init(keyword: Color, string: Color, comment: Color, number: Color) {
            self.keyword = keyword
            self.string = string
            self.comment = comment
            self.number = number
        }
    }

    /// The sentinel name that means "follow the preview theme's code colors".
    public static let defaultName = ""

    public static let all: [CodeHighlightTheme] = [
        CodeHighlightTheme(name: "Xcode", displayName: "Xcode", palette: Palette(
            keyword: Color(red: 0.61, green: 0.13, blue: 0.55),
            string: Color(red: 0.77, green: 0.10, blue: 0.09),
            comment: Color(red: 0.36, green: 0.42, blue: 0.47),
            number: Color(red: 0.11, green: 0.00, blue: 0.81)
        )),
        CodeHighlightTheme(name: "Solarized (Dark)", displayName: "Solarized (Dark)", palette: Palette(
            keyword: Color(red: 0.52, green: 0.60, blue: 0.00),
            string: Color(red: 0.16, green: 0.63, blue: 0.60),
            comment: Color(red: 0.35, green: 0.43, blue: 0.46),
            number: Color(red: 0.83, green: 0.21, blue: 0.51)
        )),
        CodeHighlightTheme(name: "Monokai", displayName: "Monokai", palette: Palette(
            keyword: Color(red: 0.98, green: 0.15, blue: 0.45),
            string: Color(red: 0.90, green: 0.86, blue: 0.45),
            comment: Color(red: 0.46, green: 0.44, blue: 0.36),
            number: Color(red: 0.68, green: 0.51, blue: 1.00)
        )),
        CodeHighlightTheme(name: "Tomorrow", displayName: "Tomorrow", palette: Palette(
            keyword: Color(red: 0.53, green: 0.32, blue: 0.71),
            string: Color(red: 0.44, green: 0.55, blue: 0.00),
            comment: Color(red: 0.56, green: 0.60, blue: 0.65),
            number: Color(red: 0.68, green: 0.35, blue: 0.00)
        )),
    ]

    /// Resolves a palette by name, or returns `fallback` for the default name.
    public static func palette(named name: String, fallback: Palette) -> Palette {
        guard !name.isEmpty else { return fallback }
        return all.first { $0.name == name }?.palette ?? fallback
    }

    /// All selectable names, with the default (empty) name first.
    public static var selectableNames: [String] {
        [defaultName] + all.map(\.name)
    }
}
