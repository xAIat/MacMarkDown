import Foundation
import SwiftUI

/// A preview stylesheet, identified by name. The preview is rendered natively
/// (see `MarkdownView`), so `Theme` carries the semantic color/typography
/// values that `MarkdownView` applies directly and that `Renderer` serializes
/// to CSS for HTML export.
///
/// The palettes are designed in-house (Clearness, GitHub, Solarized, etc.).
public struct Theme: Sendable, Hashable, Identifiable {
    public var id: String { name }
    public var name: String
    public var displayName: String

    // Background / foreground
    public var backgroundColor: Color
    public var textColor: Color
    public var secondaryTextColor: Color

    // Headings
    public var headingColor: Color
    public var headingBorderColor: Color

    // Content elements
    public var linkColor: Color
    public var codeBackgroundColor: Color
    public var codeTextColor: Color
    public var blockquoteColor: Color
    public var blockquoteBorderColor: Color
    public var tableHeaderBackground: Color
    public var tableBorderColor: Color
    public var dividerColor: Color
    public var taskListColor: Color

    // Code token colors (used by the native preview highlighter).
    public var codeKeywordColor: Color
    public var codeStringColor: Color
    public var codeCommentColor: Color
    public var codeNumberColor: Color

    public init(
        name: String,
        displayName: String,
        backgroundColor: Color,
        textColor: Color,
        secondaryTextColor: Color,
        headingColor: Color,
        headingBorderColor: Color,
        linkColor: Color,
        codeBackgroundColor: Color,
        codeTextColor: Color,
        blockquoteColor: Color,
        blockquoteBorderColor: Color,
        tableHeaderBackground: Color,
        tableBorderColor: Color,
        dividerColor: Color,
        taskListColor: Color,
        codeKeywordColor: Color? = nil,
        codeStringColor: Color? = nil,
        codeCommentColor: Color? = nil,
        codeNumberColor: Color? = nil
    ) {
        self.name = name
        self.displayName = displayName
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.secondaryTextColor = secondaryTextColor
        self.headingColor = headingColor
        self.headingBorderColor = headingBorderColor
        self.linkColor = linkColor
        self.codeBackgroundColor = codeBackgroundColor
        self.codeTextColor = codeTextColor
        self.blockquoteColor = blockquoteColor
        self.blockquoteBorderColor = blockquoteBorderColor
        self.tableHeaderBackground = tableHeaderBackground
        self.tableBorderColor = tableBorderColor
        self.dividerColor = dividerColor
        self.taskListColor = taskListColor
        // Sensible defaults derived from the existing palette so the built-in
        // themes gain highlighting without restating four more colors each.
        self.codeKeywordColor = codeKeywordColor ?? headingColor
        self.codeStringColor = codeStringColor ?? linkColor
        self.codeCommentColor = codeCommentColor ?? secondaryTextColor
        self.codeNumberColor = codeNumberColor ?? taskListColor
    }

    public static func theme(named name: String) -> Theme {
        all.first { $0.name == name } ?? all[0]
    }

    public static let all: [Theme] = [clearness, github, solarizedLight, solarizedDark, night]
}

// MARK: - Built-in themes

extension Theme {
    public static let clearness = Theme(
        name: "Clearness",
        displayName: "Clearness",
        backgroundColor: Color(red: 1.0, green: 1.0, blue: 1.0),
        textColor: Color(red: 0.13, green: 0.14, blue: 0.15),
        secondaryTextColor: Color(red: 0.35, green: 0.37, blue: 0.40),
        headingColor: Color(red: 0.13, green: 0.14, blue: 0.15),
        headingBorderColor: Color(red: 0.85, green: 0.87, blue: 0.89),
        linkColor: Color(red: 0.13, green: 0.45, blue: 0.80),
        codeBackgroundColor: Color(red: 0.95, green: 0.96, blue: 0.97),
        codeTextColor: Color(red: 0.25, green: 0.28, blue: 0.30),
        blockquoteColor: Color(red: 0.40, green: 0.44, blue: 0.47),
        blockquoteBorderColor: Color(red: 0.82, green: 0.85, blue: 0.87),
        tableHeaderBackground: Color(red: 0.96, green: 0.97, blue: 0.98),
        tableBorderColor: Color(red: 0.85, green: 0.87, blue: 0.89),
        dividerColor: Color(red: 0.85, green: 0.87, blue: 0.89),
        taskListColor: Color(red: 0.13, green: 0.45, blue: 0.80)
    )

    public static let github = Theme(
        name: "GitHub",
        displayName: "GitHub",
        backgroundColor: Color(red: 0.97, green: 0.97, blue: 0.97),
        textColor: Color(red: 0.0, green: 0.0, blue: 0.0),
        secondaryTextColor: Color(red: 0.35, green: 0.35, blue: 0.35),
        headingColor: Color(red: 0.0, green: 0.0, blue: 0.0),
        headingBorderColor: Color(red: 0.70, green: 0.70, blue: 0.70),
        linkColor: Color(red: 0.26, green: 0.51, blue: 0.77),
        codeBackgroundColor: Color(red: 0.93, green: 0.93, blue: 0.93),
        codeTextColor: Color(red: 0.27, green: 0.27, blue: 0.27),
        blockquoteColor: Color(red: 0.33, green: 0.33, blue: 0.33),
        blockquoteBorderColor: Color(red: 0.87, green: 0.87, blue: 0.87),
        tableHeaderBackground: Color(red: 0.95, green: 0.95, blue: 0.95),
        tableBorderColor: Color(red: 0.87, green: 0.87, blue: 0.87),
        dividerColor: Color(red: 0.87, green: 0.87, blue: 0.87),
        taskListColor: Color(red: 0.26, green: 0.51, blue: 0.77)
    )

    public static let solarizedLight = Theme(
        name: "Solarized Light",
        displayName: "Solarized (Light)",
        backgroundColor: Color(red: 0.996, green: 0.965, blue: 0.890),
        textColor: Color(red: 0.345, green: 0.435, blue: 0.420),
        secondaryTextColor: Color(red: 0.467, green: 0.525, blue: 0.420),
        headingColor: Color(red: 0.169, green: 0.361, blue: 0.463),
        headingBorderColor: Color(red: 0.733, green: 0.796, blue: 0.784),
        linkColor: Color(red: 0.149, green: 0.545, blue: 0.823),
        codeBackgroundColor: Color(red: 0.941, green: 0.921, blue: 0.863),
        codeTextColor: Color(red: 0.271, green: 0.337, blue: 0.323),
        blockquoteColor: Color(red: 0.467, green: 0.525, blue: 0.420),
        blockquoteBorderColor: Color(red: 0.733, green: 0.796, blue: 0.784),
        tableHeaderBackground: Color(red: 0.941, green: 0.921, blue: 0.863),
        tableBorderColor: Color(red: 0.733, green: 0.796, blue: 0.784),
        dividerColor: Color(red: 0.733, green: 0.796, blue: 0.784),
        taskListColor: Color(red: 0.149, green: 0.545, blue: 0.823)
    )

    public static let solarizedDark = Theme(
        name: "Solarized Dark",
        displayName: "Solarized (Dark)",
        backgroundColor: Color(red: 0.004, green: 0.169, blue: 0.208),
        textColor: Color(red: 0.549, green: 0.635, blue: 0.620),
        secondaryTextColor: Color(red: 0.376, green: 0.478, blue: 0.404),
        headingColor: Color(red: 0.752, green: 0.722, blue: 0.404),
        headingBorderColor: Color(red: 0.176, green: 0.294, blue: 0.318),
        linkColor: Color(red: 0.149, green: 0.545, blue: 0.823),
        codeBackgroundColor: Color(red: 0.027, green: 0.211, blue: 0.259),
        codeTextColor: Color(red: 0.549, green: 0.635, blue: 0.620),
        blockquoteColor: Color(red: 0.376, green: 0.478, blue: 0.404),
        blockquoteBorderColor: Color(red: 0.176, green: 0.294, blue: 0.318),
        tableHeaderBackground: Color(red: 0.027, green: 0.211, blue: 0.259),
        tableBorderColor: Color(red: 0.176, green: 0.294, blue: 0.318),
        dividerColor: Color(red: 0.176, green: 0.294, blue: 0.318),
        taskListColor: Color(red: 0.149, green: 0.545, blue: 0.823)
    )

    public static let night = Theme(
        name: "Night",
        displayName: "Mou Night",
        backgroundColor: Color(red: 0.11, green: 0.11, blue: 0.13),
        textColor: Color(red: 0.87, green: 0.87, blue: 0.88),
        secondaryTextColor: Color(red: 0.58, green: 0.58, blue: 0.62),
        headingColor: Color(red: 0.93, green: 0.93, blue: 0.94),
        headingBorderColor: Color(red: 0.30, green: 0.30, blue: 0.34),
        linkColor: Color(red: 0.42, green: 0.62, blue: 0.90),
        codeBackgroundColor: Color(red: 0.16, green: 0.16, blue: 0.19),
        codeTextColor: Color(red: 0.85, green: 0.85, blue: 0.88),
        blockquoteColor: Color(red: 0.62, green: 0.62, blue: 0.66),
        blockquoteBorderColor: Color(red: 0.32, green: 0.32, blue: 0.36),
        tableHeaderBackground: Color(red: 0.16, green: 0.16, blue: 0.19),
        tableBorderColor: Color(red: 0.30, green: 0.30, blue: 0.34),
        dividerColor: Color(red: 0.30, green: 0.30, blue: 0.34),
        taskListColor: Color(red: 0.42, green: 0.62, blue: 0.90)
    )
}