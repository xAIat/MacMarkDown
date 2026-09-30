import AppKit

/// Font-name resolution shared by the editor and the preview.
///
/// The settings store a font *name*. The empty name means "the system font",
/// and each pane picks the face that suits it: the editor the system monospaced
/// face (SF Mono), the preview the proportional system font (SF Pro, with
/// PingFang SC for Chinese). Both resolve through this one explicit branch
/// instead of relying on a failed name lookup.
///
/// Any other name resolves by PostScript name (`Menlo-Regular`,
/// `SarasaMonoSC-Regular`) and then by family name (`Menlo`, `Sarasa Mono SC`),
/// so names typed into the settings and names returned by the system font panel
/// both work.
@MainActor
public enum FontResolver {

    /// The name that means "the system font" (see the type's documentation).
    nonisolated public static let systemFontName = ""

    /// Names earlier versions stored for the system monospaced face. They are
    /// not resolvable families — the face is only reachable through AppKit —
    /// and CoreText silently substitutes Helvetica for them, so they fold into
    /// `systemFontName` rather than depending on a failed lookup.
    nonisolated private static let systemMonospacedAliases: Set<String> = [
        "SF Mono", "SFMono-Regular", "SFMono-Medium", "SFMono-Bold"
    ]

    /// Trims a stored name and folds the legacy system-monospaced aliases into
    /// `systemFontName`.
    nonisolated public static func normalized(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return systemMonospacedAliases.contains(trimmed) ? systemFontName : trimmed
    }

    /// Resolves a family by PostScript name or family name. Returns `nil` for
    /// the system name and for names that resolve to nothing.
    public static func font(named name: String, size: CGFloat) -> NSFont? {
        let name = normalized(name)
        guard !name.isEmpty else { return nil }
        if let font = NSFont(name: name, size: size) { return font }
        return NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size)
    }

    /// The editor's face: the chosen family, or the system monospaced face
    /// (SF Mono) for the system name or an unresolvable name.
    public static func editorFont(named name: String, size: CGFloat) -> NSFont {
        font(named: name, size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// The preview's face: the chosen family (a non-regular `weight` asks the
    /// family for its bold face), or the proportional system font — SF Pro,
    /// falling back to PingFang SC for Chinese — for the system name or an
    /// unresolvable name.
    public static func previewFont(
        named name: String,
        size: CGFloat,
        weight: NSFont.Weight = .regular
    ) -> NSFont {
        guard let font = font(named: name, size: size) else {
            return .systemFont(ofSize: size, weight: weight)
        }
        guard weight != .regular else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    /// The angle (in degrees) of the synthetic oblique used when no real
    /// italic face covers a run. Matches the ~12° browsers apply for
    /// `font-style: italic`.
    public static let syntheticItalicAngle: CGFloat = 12

    /// A synthetic italic: `font` sheared horizontally so its glyph tops lean
    /// right in the preview's flipped text views (the only drawing context that
    /// uses it). CoreText's fallback faces for Chinese (PingFang SC, Hiragino,
    /// …) have no italic member, and some families have no italic face at all,
    /// so the preview substitutes this for them. The shear leaves glyph
    /// advances unchanged, so it cannot affect line breaking or shaping.
    public static func syntheticItalic(_ font: NSFont) -> NSFont {
        let radians = syntheticItalicAngle * .pi / 180
        var transform = CGAffineTransform(a: 1, b: 0, c: tan(radians), d: 1, tx: 0, ty: 0)
        return CTFontCreateCopyWithAttributes(font as CTFont, font.pointSize, &transform, nil) as NSFont
    }

    /// Whether `name` is a fixed-pitch family that covers Chinese, i.e. one
    /// whose CJK glyphs line up with the Latin grid (Sarasa Mono SC, Maple
    /// Mono, …). The system faces are not: SF Mono's Latin advance is 0.618 em,
    /// so a 1 em CJK glyph takes 1.61 cells.
    public static func isMonospacedCJK(_ name: String) -> Bool {
        guard let font = font(named: name, size: 14), font.isFixedPitch else { return false }
        let coverage = CTFontCopyCharacterSet(font as CTFont) as CharacterSet
        return coverage.contains(Unicode.Scalar("中")) && coverage.contains(Unicode.Scalar("，"))
    }
}
