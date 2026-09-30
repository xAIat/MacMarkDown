# ADR-004: Editor Themes as Swift Value Types with INI-like Style Files

## Status

**Accepted** — September 2026

## Context

macOS 26 and Swift 6.4 opened a new era for Apple's developer frameworks:
SwiftUI, the Observation framework, TextKit 2 and Swift concurrency became
mature enough to carry a complete writing tool, so MacMarkDown was written from
scratch in pure Swift and SwiftUI. Theming is where a writing tool usually
leaves that path: syntax colors are often delegated to a third-party highlighter
whose palettes live in an external file format, outside the type system.

MacMarkDown themes three surfaces:

- **Editor source highlighting** — Markdown tokens in the raw-text pane:
  headings, emphasis, strong, code, links, quotes, list markers, front matter.
  The editor is backed by `NSTextStorage`, so token colors have to reach AppKit
  attributes.
- **Preview styling** — the colors and typography of the rendered document
  (ADR-003, `Theme`).
- **Code token palettes** — keyword/string/comment/number colors for fenced
  code blocks.

The design constraints:

- Theme values should be Swift values: `Sendable`, `Hashable`, usable in
  SwiftUI, and testable without a runtime interpreter.
- The project builds with Swift 6 and complete strict concurrency; a vendored C
  highlighter would sit outside those guarantees.
- Users should be able to add palettes without rebuilding the app. A narrow
  file format is enough for color values; it should not be the only source of
  truth.
- The editor pane needs an AppKit bridge because its text storage is
  `NSTextStorage`.

## Decision

Model themes as Swift value types, and keep a narrow INI-like file format for
additional palettes.

### EditorTheme

`EditorTheme` (`MacMarkDown/Theme/EditorTheme.swift`) is a `Sendable`,
`Hashable`, `Identifiable` struct with named color roles:

- base — background, text, cursor, selection, line highlight
- tokens — title, emphasis, strong, code, link, quote, list marker, heading,
  bold, italic

Built-in themes are `defaultLight`, `defaultDark`, `solarizedLight`,
`solarizedDark`, `night` and `tomorrow`. `EditorTheme.selectable` combines the
built-ins with the file-based themes, and `EditorTheme.theme(named:)` resolves a
stored name.

### INI-like `.style` files

`EditorTheme+StyleFile` parses `.style` files in an INI-like format: a bare
section line names a Markdown element (`H1`, `EMPH`, `STRONG`, `CODE`, `LINK`,
`BLOCKQUOTE`, `LIST_BULLET`, `editor`, `editor-selection`), followed by
`key: value` pairs with hex colors, sections separated by blank lines. Missing
sections fall back to colors derived from the file's `editor` background and
foreground pair, so a partial file still produces a complete theme. The bundled
files live in `MacMarkDown/Resources/Themes/`; `ResourceLoader.availableThemeNames`
discovers them, and they are sorted by display name. Dropping another `.style`
file into that directory adds a selectable theme without changing Swift code.

### Preview styles

Preview appearance is a separate concern: `Theme` (`MacMarkDown/Theme/Theme.swift`)
carries semantic colors and typography for the rendered document, and the
matching CSS files under `MacMarkDown/Resources/Styles/` are the export form
that `Renderer` embeds in exported HTML. `AttributedRenderer` consumes the same
`Theme` values for the text surface, so a preview and its exported HTML share
one palette.

### Code highlight palettes

`CodeHighlightTheme` (`MacMarkDown/Theme/CodeHighlightTheme.swift`) defines four
token colors — keyword, string, comment, number. Built-in palettes are Xcode,
Solarized (Dark), Monokai and Tomorrow; the default (empty) name means "follow
the preview theme's code colors".

### Selection and persistence

Settings → Editor exposes an "Editor Theme" picker over `EditorTheme.selectable`;
the choice is stored as `preferences.editorStyleName` in `UserDefaults` and
resolved with `EditorTheme.theme(named:)`. Preview stylesheet and code palette
have their own pickers in Settings → Rendering.

### AppKit bridge

`EditorTheme+AppKit` maps every color role to `NSColor`. `MarkdownEditorView`
applies background, caret, selection and text color to the editor's text view
and runs `MarkdownSyntaxHighlighter(theme:)` over the text storage. The
highlighter is order-based: it colors fenced code as a unit, then walks each
line for block-level and inline tokens while tracking occupied ranges, so a
later pass never recolors inside an earlier token.

## Alternatives Considered

### 1. Vendor a third-party C highlighter with its own theme format

**Rejected.** A C library conflicts with the pure-Swift build, its palettes live
outside Swift's type system, there is no compile-time validation, the theme
properties are limited to token colors, and the app would depend on a runtime
parser for its own appearance.

### 2. JSON or YAML as the primary theme format

**Rejected as the primary model.** It requires runtime parsing and validation,
falls back silently on typos, and makes authors learn a schema instead of Swift
types. The supported `.style` format is deliberately narrower: it supplies
colors for roles that exist in Swift, and cannot define new roles or behavior.

### 3. plist-based themes (like Xcode)

**Rejected.** Xcode's theme model covers editor, console and debugger layers;
adopting a plist format would add runtime parsing and error handling while
losing type safety the same way.

### 4. SwiftUI `.tint()` / accent color only

**Rejected.** The built-in color system provides accent and tint colors, not
the editor chrome, list/quote/code backgrounds or token colors a Markdown editor
needs.

## Consequences

### Positive

- **Value semantics.** `EditorTheme` is `Sendable`, `Hashable` and
  `Identifiable`; it can be compared for equality (the preview skips work when
  theme inputs are unchanged) and passed across concurrency domains.
- **Type safety.** Built-in themes are Swift code; a missing or misspelled role
  fails to compile rather than falling back at runtime.
- **Discoverability.** Roles read as `.headingColor`, `.selectionColor`, and
  autocomplete in the IDE; `#Preview` can render a palette without launching the
  app.
- **User-extensible palettes.** `.style` files add themes at launch without a
  rebuild; partial files are completed from derived defaults.
- **One palette, several consumers.** The editor applies `EditorTheme` through
  `EditorTheme+AppKit`, while the preview has its own `Theme` values plus CSS;
  the two concerns change independently.
- **Self-contained.** Themes, stylesheets and the highlighter all ship with the
  app; nothing is downloaded at runtime.

### Negative

- **Fixed colors.** A theme is one palette. Following light/dark system
  appearance means selecting matching themes (for example
  `defaultLight`/`defaultDark` or `solarizedLight`/`solarizedDark`) rather than
  deriving them at runtime.
- **The file format is color-only.** A `.style` file can set colors for known
  roles; it cannot add a role, font or layout property. Those require Swift
  changes.
- **Forgiving parsing.** Missing or malformed entries fall back to derived
  defaults, which keeps the app usable but can hide a typo in a user-edited
  file.
- **Binary and source cost.** Every built-in theme is code; the cost is
  negligible (a few hundred bytes of palette values per theme).

### Risks

- **Theme list growth.** If the built-in set grows large, the built-in file
  becomes unwieldy. Mitigation: split built-ins into an extension file (for
  example `EditorTheme+Builtin.swift`) and keep `EditorTheme` to the model and
  resolution logic.
- **Silent fallbacks in user files.** Mitigation: keep the parser small and
  covered by `EditorThemeStyleFileTests`, and document the recognized sections
  so a user can see what a file supports.
- **Unreadable user palettes.** A hand-edited file can produce low-contrast
  colors. Mitigation: ship tested palettes, and keep parsing additive so a
  missing value never removes a sensible default.

## References

- `EditorTheme` — MacMarkDown/Theme/EditorTheme.swift
- Style file parser — MacMarkDown/Theme/EditorTheme+StyleFile.swift
- AppKit bridge — MacMarkDown/Theme/EditorTheme+AppKit.swift
- Editor highlighter — MacMarkDown/Services/Editor/MarkdownSyntaxHighlighter.swift
- Preview theme and stylesheets — MacMarkDown/Theme/Theme.swift, MacMarkDown/Resources/Styles/
- Code highlight palettes — MacMarkDown/Theme/CodeHighlightTheme.swift
- Settings pickers — MacMarkDown/UI/Shared/Settings/SettingsView.swift
- Apple SwiftUI Color — https://developer.apple.com/documentation/swiftui/color
- Apple NSColor — https://developer.apple.com/documentation/appkit/nscolor
