# RFC-002: Rendering Pipeline

- **Status**: Proposed
- **Date**: 2026-09-15
- **Author**: Architecture Team
- **Audience**: Engineering, Product
- **Related**: [RFC-001 Core Architecture](rfc-001-core-architecture.md), [Business Overview](../business/overview.md)

---

## 1. Summary

The rendering pipeline was designed for the framework generation that macOS 26
and Swift 6.4 opened: TextKit 2 gives the preview a first-class text surface,
Observation drives live updates, and Swift concurrency keeps the parse/render
pipeline serialized and race-free. This RFC defines how raw Markdown text
becomes the native preview and exported HTML. Parsing is decoupled from
presentation, so the preview, the exporter and the scripting bridge all share
one element tree produced by Apple's `swift-markdown` package.

## 2. Goals / Non-Goals

### 2.1 Goals

- **One parse path** for the native preview, HTML export and the AppleScript
  `html` property.
- **A presentation-neutral tree** (`MarkdownElement`) that describes *what* to
  show; themes decide *how* it looks.
- **A native preview**: TextKit 2 renders the document in-process; WebKit is
  isolated to blocks that genuinely need it (tables, MathJax formulas).
- **Self-contained exports**: the bundled template, stylesheets and renderer
  scripts travel with the output.
- **Deterministic output**: the test suite pins HTML output for every
  supported extension.

### 2.2 Non-Goals

- Incremental AST diffing in v1; the whole document is re-analyzed per render.
- Editing rendered HTML in place; the editor always edits Markdown source.
- A hidden browser as the general-purpose preview; WebKit is used only for
  table and math blocks.
- Remote rendering services; exports work offline with bundled resources.

## 3. Pipeline Overview

```
Input: Markdown text (String) + MarkdownParseOptions + Theme
        │
        ▼
Step 1  MarkdownParser: line-preserving preprocessing → swift-markdown
        │  Document → ParsedDocument([MarkdownElement], [DocumentAnchor])
        │  (Sendable values; the parser runs on the main actor)
        ▼
Step 2  [MarkdownElement] is the shared model for every output surface
        │
        ├──► Live preview (Step 3): AttributedRenderer → NSAttributedString
        │       → MarkdownPreviewSurface (TextKit 2, read-only)
        │       tables / MathJax → PreviewWebBlockView placeholders (WKWebView)
        │       fallback: MarkdownView renders the element tree in SwiftUI
        │
        ├──► Theme (Step 4) styles both preview paths and serializes CSS
        │
        └──► HTML export: Renderer → complete HTML document
                (Default.handlebars + Resources/Styles CSS)
                → ExportService: file / clipboard / print / PDF
        │
        ▼
Step 5  RenderService debounces text changes (300 ms) and publishes
        elements, anchors and the HTML fragment; ⌘R renders immediately
```

## 4. Inputs

The pipeline accepts a single `String` containing the full Markdown source of
one document, together with the active parse options (extension flags,
front-matter detection, math, TOC, highlighting) and the selected `Theme`.

```swift
public struct MarkdownParseOptions: Sendable, Hashable {
    public var enableTables: Bool
    public var enableFootnotes: Bool
    public var enableStrikethrough: Bool
    public var enableUnderline: Bool
    public var enableHighlight: Bool
    public var enableSuperscript: Bool
    public var enableQuote: Bool
    public var enableMath: Bool
    public var enableInlineMath: Bool
    public var enableTOC: Bool
    public var templateName: String
    // …plus the remaining flags honoured by MarkdownParser
}
```

There is no incremental parsing in v1; the whole document is re-analyzed on
each render, and the debounce in Step 5 keeps interactive editing responsive.

## 5. Step 1 — Parse to the Element Tree

Dependency: Apple's `swift-markdown` package for CommonMark and GFM blocks,
plus Yams for YAML front matter.

`MarkdownParser.parseDocument(_:options:)` performs line-preserving
preprocessing so `DocumentAnchor.line` always refers to a line in the source
document text, then walks the `swift-markdown` `Document`:

- **Front matter** is extracted with Yams and blanked from the body; the
  parsed values become a leading `.frontMatter` element.
- **Footnotes** are not part of `swift-markdown`; definitions are blanked and
  `[^id]` references are converted to numbered anchor links.
- **Math spans** (`\[…\]`, `\(…\)`, `$$…$$`, and `$…$` when enabled) are
  converted to fenced `math`/`math-inline` blocks, with a line map so anchors
  still point at the source lines.
- **Inline extensions** (underline, highlight, superscript, quote) are marked
  with sentinels before parsing and resolved during inline conversion.
- **Autolinks** are wrapped so `swift-markdown` recognizes bare URLs, and
  intra-word emphasis can be escaped to honour the preference.

```swift
public func parseDocument(_ text: String, options: MarkdownParseOptions) -> ParsedDocument {
    let body = preprocess(text, options: options)   // line-preserving
    let document = Document(parsing: body)
    var elements: [MarkdownElement] = []
    var anchors: [DocumentAnchor] = []
    for block in document.blockChildren {
        if let element = convertBlock(block, path: [elements.count], anchors: &anchors) {
            elements.append(element)
        }
    }
    return ParsedDocument(elements: elements, anchors: anchors)
}
```

- Runs synchronously on the main actor inside the debounced render window
  (RFC-001 §8); inputs and outputs are `Sendable` values.
- `ParsedDocument` carries the element tree plus the ordered scroll anchors;
  it performs no UI work.
- Errors are surfaced as render status (`RenderService.lastError`), never
  thrown through the view hierarchy.
- **HTML output contract**: the test suite pins HTML output for every
  supported extension, so a preprocessing change that alters exported markup
  fails tests instead of shipping silently.

## 6. Step 2 — The Element Tree and Anchors

`MarkdownElement` is the app's own presentation-neutral tree, produced by the
parser and consumed by both `AttributedRenderer` and `Renderer`:

```swift
public enum MarkdownElement: Sendable, Hashable {
    case heading(level: Int, text: String)
    case paragraph([InlineElement])
    case codeBlock(language: String?, code: String)
    case blockQuote([MarkdownElement])
    case unorderedList([ListItem])
    case orderedList([ListItem])
    case table(TableData)
    case thematicBreak
    case rawHTML(String)
    case image(url: String?, alt: String)
    case taskList([ListItem])
    case tableOfContents([TOCItem])
    case footnotes([FootnoteItem])
    case frontMatter(title: String?, entries: [FrontMatterEntry])
}
```

Inline content is a parallel enum (`text`, `emphasis`, `strong`, `code`,
`link`, `strikethrough`, `image`, `underline`, `highlight`, `superscript`,
`quote`, `lineBreak`, `inlineHTML`) so runs can be composed without re-parsing.

Every block and list item also emits a `DocumentAnchor` during the walk:

```swift
public struct DocumentAnchor: Sendable, Hashable {
    public var path: AnchorPath    // child-index path in the element tree
    public var line: Int           // 1-based line in the source document
}
```

- The walker is a pure function: `swift-markdown Document → ParsedDocument`,
  no side effects, unit-testable in isolation.
- Anchors are dense (one per block/list item) and ordered, so the editor and
  the preview measure the **same** sequence 1:1 for scroll sync (RFC-001 §5).
- Extension-sensitive parsing (tables, footnotes, Mermaid fences, math spans,
  TOC, task lists) is decided here, gated on `MarkdownParseOptions`.

## 7. Step 3 — Native Preview

The default preview path renders the element tree into one
`NSAttributedString` and shows it in a read-only TextKit 2 surface:

```
[MarkdownElement] ──► AttributedRenderer ──► NSAttributedString
                              │
                              ├─► MarkdownPreviewSurface (TextKit 2, selectable,
                              │     ⌘A, copy-with-HTML, measured anchors)
                              └─► PreviewWebBlockView (WKWebView) overlays for
                                  tables and MathJax formulas
```

```swift
struct MarkdownPreviewSurface: NSViewRepresentable {
    let elements: [MarkdownElement]
    var anchors: [DocumentAnchor] = []
    let theme: Theme
    // …
}
```

- Headings, paragraphs, lists, quotes, code, rules and front matter become
  attributed text with paragraph styles applied by `AttributedRenderer`.
- Tables and math formulas cannot be laid out by TextKit, so the renderer
  reserves a placeholder attachment for each; `MarkdownPreviewSurface` covers
  the placeholder with a `PreviewWebBlockView` and writes WebKit's measured
  height back into the attachment so surrounding text reflows to the real size.
- Web views are pooled and created only near the viewport, because each one is
  a web content process.
- Images are embedded as `NSTextAttachment`s; anchors are measured directly
  from the text layout, which keeps preview anchors paired with the editor's.
- A pure-SwiftUI element tree, `MarkdownView`, can render the same
  `[MarkdownElement]` as a fallback when the Text Surface preference is off.
  It is not the default path.

## 8. Step 4 — Theme

`Theme` is a `Sendable` Swift value — colors and code-token palettes — that is
the single model for both preview surfaces and for exported CSS:

```swift
public struct Theme: Sendable, Hashable, Identifiable {
    public var name: String
    public var displayName: String
    public var backgroundColor: Color
    public var textColor: Color
    public var linkColor: Color
    public var codeBackgroundColor: Color
    public var codeTextColor: Color
    public var codeKeywordColor: Color
    // …heading, blockquote, table, divider and task-list colors
}
```

- `AttributedRenderer` and `MarkdownView` apply the values directly to the
  native preview; elements never hard-code appearance.
- `Renderer` serializes the same values to CSS for HTML export.
- Bundled CSS files live in `MacMarkDown/Resources/Styles`; user-installable
  CSS stylesheets and `.style` editor themes are loaded at runtime.
- Dark mode follows the system appearance; the preview updates when the
  user switches variants.

## 9. Step 5 — Update Scheduling

The preview re-renders only when the source text, options or theme change,
guarded by `RenderService`'s debounce:

| Scenario | Delay | Behavior |
|----------|-------|----------|
| Live typing / paste (text change) | 300 ms | Cancel the pending work item; schedule a fresh parse; the last keystroke in the window wins |
| Manual render (⌘R, toolbar) | 0 ms (immediate) | `parseNow` bypasses the debounce and re-parses in full |
| Theme / extension / font change | 0 ms (immediate) | Re-render the current text with the new options |
| Manual Render preference enabled | — | Live parsing is suspended until the user renders explicitly |

- The debounce interval is `Constants.defaultDebounceInterval`, owned by
  `RenderService`; a new `scheduleRender` cancels the previous
  `DispatchWorkItem`, so work never stacks.
- `RenderService` publishes `elements`, `anchors` and `renderedHTML` as
  `@Observable` properties, so views update only when a render completes.
- During a parse the preview keeps the last good frame; `isRendering` drives
  the optional progress affordance.

## 10. HTML Export Path

The same element tree feeds every export surface, so preview and export can
never disagree about semantics:

```
[MarkdownElement] ──► Renderer (pure String builder, complete document)
                          │
                          ├─► bundled Default.handlebars template
                          ├─► Resources/Styles/*.css (or generated inline CSS)
                          ├─► code-highlighting CSS
                          └─► Mermaid / Graphviz / MathJax scripts (once)
                              │
                              ▼
                    ExportService
                     ├─► write .html file
                     ├─► NSPasteboard ("Copy HTML")
                     ├─► print
                     └─► print to PDF
```

```swift
let renderer = Renderer(parser: parser, theme: theme, options: options)
let html = renderer.renderToHTML(text, title: title, inlineStyles: true)
try html.write(to: url, atomically: true, encoding: .utf8)
```

- `Renderer` fills the `Default.handlebars` placeholders (`titleTag`,
  `styleTags`, `codeHighlightCSS`, `body`, `scriptTags`) and falls back to an
  inline document wrapper if the template is unavailable.
- Mermaid, Graphviz (Viz.js) and MathJax scripts are injected exactly once per
  document, inlined from bundled resources where available so exports work
  offline.
- Export HTML is covered by the test suite, which pins output for every
  supported extension.

## 11. Testing and Verification

- `MacMarkDownTests` links `MacMarkDownKit` and exercises parser, renderers,
  documents, editor behavior and scroll sync without a host app.
- HTML export is pinned per extension: tables, footnotes, front matter, TOC,
  task lists, math, code highlighting, hard wrap and inline extensions.
- Native rendering is verified against package fixtures: attributed output,
  anchor ranges, web-block placeholder heights and preview surface behavior.

## 12. Performance Budget

| Metric | Budget |
|--------|--------|
| Parse a 10k-line typical document | < 60 ms |
| Element + anchor sequence build | < 20 ms |
| SwiftUI/TextKit layout + first paint | < 120 ms after the debounce window |
| Memory for a 100 MB Markdown file | bounded; services hold no cycles across documents |
| Stale render cancellation latency | < 1 ms (work item cancel) |

## 13. Open Questions

1. Should v2 support incremental AST diffing so edits re-render only changed
   subtrees, or is whole-document re-parse within budget indefinitely?
2. When preview and HTML export diverge (for example, a browser-only math
   feature), which surface is authoritative — must the native preview match
   export exactly, or may it present a clearly labelled best-effort subset?
3. Is a shared declarative tree viable as the single output model for both the
   attributed preview and the HTML string, eliminating the two renderers'
   duplicated element walk?
