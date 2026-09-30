import Foundation
import SwiftUI

/// Editor syntax-highlighting themes defined as Swift code.
///
/// Each theme maps token categories to colors used by the editor's attributed
/// rendering; user-installed `.style` files extend the built-in set (see
/// `EditorTheme+StyleFile`).
public struct EditorTheme: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var displayName: String

    // Base
    public var backgroundColor: Color
    public var textColor: Color
    public var cursorColor: Color
    public var selectionColor: Color
    public var lineHighlightColor: Color

    // Token categories
    public var titleColor: Color
    public var emphasisColor: Color
    public var strongColor: Color
    public var codeColor: Color
    public var linkColor: Color
    public var quoteColor: Color
    public var listMarkerColor: Color
    public var headingColor: Color
    public var boldColor: Color
    public var italicColor: Color

    public init(
        name: String,
        displayName: String,
        backgroundColor: Color,
        textColor: Color,
        cursorColor: Color,
        selectionColor: Color,
        lineHighlightColor: Color,
        titleColor: Color,
        emphasisColor: Color,
        strongColor: Color,
        codeColor: Color,
        linkColor: Color,
        quoteColor: Color,
        listMarkerColor: Color,
        headingColor: Color,
        boldColor: Color,
        italicColor: Color
    ) {
        self.name = name
        self.displayName = displayName
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.cursorColor = cursorColor
        self.selectionColor = selectionColor
        self.lineHighlightColor = lineHighlightColor
        self.titleColor = titleColor
        self.emphasisColor = emphasisColor
        self.strongColor = strongColor
        self.codeColor = codeColor
        self.linkColor = linkColor
        self.quoteColor = quoteColor
        self.listMarkerColor = listMarkerColor
        self.headingColor = headingColor
        self.boldColor = boldColor
        self.italicColor = italicColor
    }

    public static let `default` = defaultLight

    public static func theme(named name: String) -> EditorTheme {
        selectable.first { $0.name == name } ?? defaultDark
    }

    public static let all: [EditorTheme] = [
        defaultLight, defaultDark, solarizedLight, solarizedDark, night, tomorrow
    ]
}

// MARK: - Built-in editor themes

extension EditorTheme {
    public static let defaultLight = EditorTheme(
        name: "Default Light",
        displayName: "Default Light",
        backgroundColor: Color(red: 1.0, green: 1.0, blue: 1.0),
        textColor: Color(red: 0.13, green: 0.14, blue: 0.16),
        cursorColor: Color(red: 0.0, green: 0.0, blue: 0.0),
        selectionColor: Color(red: 0.80, green: 0.87, blue: 0.95),
        lineHighlightColor: Color(red: 0.97, green: 0.98, blue: 0.99),
        titleColor: Color(red: 0.85, green: 0.32, blue: 0.14),
        emphasisColor: Color(red: 0.0, green: 0.0, blue: 0.0),
        strongColor: Color(red: 0.0, green: 0.0, blue: 0.0),
        codeColor: Color(red: 0.20, green: 0.22, blue: 0.45),
        linkColor: Color(red: 0.04, green: 0.42, blue: 0.84),
        quoteColor: Color(red: 0.38, green: 0.42, blue: 0.46),
        listMarkerColor: Color(red: 0.55, green: 0.27, blue: 0.07),
        headingColor: Color(red: 0.85, green: 0.32, blue: 0.14),
        boldColor: Color(red: 0.0, green: 0.0, blue: 0.0),
        italicColor: Color(red: 0.0, green: 0.0, blue: 0.0)
    )

    public static let defaultDark = EditorTheme(
        name: "Default Dark",
        displayName: "Default Dark",
        backgroundColor: Color(red: 0.11, green: 0.12, blue: 0.14),
        textColor: Color(red: 0.88, green: 0.89, blue: 0.91),
        cursorColor: Color(red: 1.0, green: 1.0, blue: 1.0),
        selectionColor: Color(red: 0.22, green: 0.36, blue: 0.55),
        lineHighlightColor: Color(red: 0.14, green: 0.15, blue: 0.18),
        titleColor: Color(red: 0.93, green: 0.57, blue: 0.24),
        emphasisColor: Color(red: 0.88, green: 0.89, blue: 0.91),
        strongColor: Color(red: 0.88, green: 0.89, blue: 0.91),
        codeColor: Color(red: 0.54, green: 0.56, blue: 0.87),
        linkColor: Color(red: 0.34, green: 0.66, blue: 1.0),
        quoteColor: Color(red: 0.55, green: 0.58, blue: 0.62),
        listMarkerColor: Color(red: 0.87, green: 0.62, blue: 0.35),
        headingColor: Color(red: 0.93, green: 0.57, blue: 0.24),
        boldColor: Color(red: 0.88, green: 0.89, blue: 0.91),
        italicColor: Color(red: 0.88, green: 0.89, blue: 0.91)
    )

    public static let solarizedLight = EditorTheme(
        name: "Solarized Light",
        displayName: "Solarized (Light)",
        backgroundColor: Color(red: 0.996, green: 0.965, blue: 0.890),
        textColor: Color(red: 0.345, green: 0.435, blue: 0.420),
        cursorColor: Color(red: 0.204, green: 0.267, blue: 0.263),
        selectionColor: Color(red: 0.812, green: 0.851, blue: 0.820),
        lineHighlightColor: Color(red: 0.961, green: 0.937, blue: 0.871),
        titleColor: Color(red: 0.824, green: 0.706, blue: 0.149),
        emphasisColor: Color(red: 0.345, green: 0.435, blue: 0.420),
        strongColor: Color(red: 0.345, green: 0.435, blue: 0.420),
        codeColor: Color(red: 0.769, green: 0.627, blue: 0.486),
        linkColor: Color(red: 0.149, green: 0.545, blue: 0.823),
        quoteColor: Color(red: 0.471, green: 0.525, blue: 0.424),
        listMarkerColor: Color(red: 0.824, green: 0.706, blue: 0.149),
        headingColor: Color(red: 0.824, green: 0.706, blue: 0.149),
        boldColor: Color(red: 0.345, green: 0.435, blue: 0.420),
        italicColor: Color(red: 0.345, green: 0.435, blue: 0.420)
    )

    public static let solarizedDark = EditorTheme(
        name: "Solarized Dark",
        displayName: "Solarized (Dark)",
        backgroundColor: Color(red: 0.004, green: 0.169, blue: 0.208),
        textColor: Color(red: 0.549, green: 0.635, blue: 0.620),
        cursorColor: Color(red: 0.796, green: 0.835, blue: 0.773),
        selectionColor: Color(red: 0.176, green: 0.294, blue: 0.318),
        lineHighlightColor: Color(red: 0.027, green: 0.211, blue: 0.259),
        titleColor: Color(red: 0.941, green: 0.796, blue: 0.294),
        emphasisColor: Color(red: 0.549, green: 0.635, blue: 0.620),
        strongColor: Color(red: 0.549, green: 0.635, blue: 0.620),
        codeColor: Color(red: 0.792, green: 0.624, blue: 0.455),
        linkColor: Color(red: 0.149, green: 0.545, blue: 0.823),
        quoteColor: Color(red: 0.376, green: 0.478, blue: 0.404),
        listMarkerColor: Color(red: 0.941, green: 0.796, blue: 0.294),
        headingColor: Color(red: 0.941, green: 0.796, blue: 0.294),
        boldColor: Color(red: 0.549, green: 0.635, blue: 0.620),
        italicColor: Color(red: 0.549, green: 0.635, blue: 0.620)
    )

    public static let night = EditorTheme(
        name: "Night",
        displayName: "Mou Night",
        backgroundColor: Color(red: 0.106, green: 0.106, blue: 0.125),
        textColor: Color(red: 0.902, green: 0.902, blue: 0.914),
        cursorColor: Color(red: 0.957, green: 0.957, blue: 0.969),
        selectionColor: Color(red: 0.298, green: 0.298, blue: 0.349),
        lineHighlightColor: Color(red: 0.137, green: 0.137, blue: 0.161),
        titleColor: Color(red: 0.898, green: 0.490, blue: 0.043),
        emphasisColor: Color(red: 0.902, green: 0.902, blue: 0.914),
        strongColor: Color(red: 0.902, green: 0.902, blue: 0.914),
        codeColor: Color(red: 0.549, green: 0.643, blue: 0.902),
        linkColor: Color(red: 0.420, green: 0.623, blue: 0.902),
        quoteColor: Color(red: 0.588, green: 0.588, blue: 0.635),
        listMarkerColor: Color(red: 0.898, green: 0.490, blue: 0.043),
        headingColor: Color(red: 0.898, green: 0.490, blue: 0.043),
        boldColor: Color(red: 0.902, green: 0.902, blue: 0.914),
        italicColor: Color(red: 0.902, green: 0.902, blue: 0.914)
    )

    public static let tomorrow = EditorTheme(
        name: "Tomorrow",
        displayName: "Tomorrow",
        backgroundColor: Color(red: 1.0, green: 1.0, blue: 1.0),
        textColor: Color(red: 0.29, green: 0.32, blue: 0.36),
        cursorColor: Color(red: 0.29, green: 0.32, blue: 0.36),
        selectionColor: Color(red: 0.81, green: 0.89, blue: 0.98),
        lineHighlightColor: Color(red: 0.97, green: 0.97, blue: 0.97),
        titleColor: Color(red: 0.79, green: 0.29, blue: 0.26),
        emphasisColor: Color(red: 0.29, green: 0.32, blue: 0.36),
        strongColor: Color(red: 0.29, green: 0.32, blue: 0.36),
        codeColor: Color(red: 0.68, green: 0.35, blue: 0.00),
        linkColor: Color(red: 0.00, green: 0.42, blue: 0.71),
        quoteColor: Color(red: 0.66, green: 0.70, blue: 0.74),
        listMarkerColor: Color(red: 0.68, green: 0.35, blue: 0.00),
        headingColor: Color(red: 0.79, green: 0.29, blue: 0.26),
        boldColor: Color(red: 0.29, green: 0.32, blue: 0.36),
        italicColor: Color(red: 0.29, green: 0.32, blue: 0.36)
    )
}