# ADR-003: Native Preview on a TextKit 2 Text Surface with WebKit Block Overlays

## Status

**Accepted** — September 2026

**Amended** — September 2026: the default preview surface is a read-only TextKit 2
text view (`MarkdownPreviewSurface`) that displays one `NSAttributedString`
produced by `AttributedRenderer`, not the SwiftUI element tree. Rendering into a
single attributed string gives the preview whole-document selection, ⌘A and
copy-with-HTML, and lets scroll-sync anchors be measured directly from
`NSTextLayoutManager` instead of `GeometryReader` probes. The element tree
remains available behind `preferences.previewUsesTextSurface`, whose default is
`true`.

**Amended** — September 2026: tables and TeX math in the text surface are laid
out by WebKit as sized overlays. `AttributedRenderer` reserves one placeholder
attachment per block and `MarkdownPreviewSurface` positions a transparent,
non-scrolling `PreviewWebBlockView` over it; the block's page reports its height
through a `height` script message and the host grows the placeholder to match,
so content after a block never lands underneath it. Tables render the same
`<table>` markup and bundled stylesheet that the HTML export uses; math is
typeset by the bundled MathJax 3 distribution, so the preview keeps working
offline. Diagram fences stay code in the text surface.

## Context

macOS 26 and Swift 6.4 opened a new era for Apple's developer frameworks:
SwiftUI, the Observation framework, TextKit 2 and Swift concurrency became
mature enough to carry a complete writing tool, so MacMarkDown was written from
scratch in pure Swift and SwiftUI. The preview pane is where that decision is
most visible. The parser (ADR-002) already produces a typed `[MarkdownElement]`
tree, and hosting HTML in a `WKWebView` would add a second rendering engine — a
separate web content process, IPC on every keystroke, a DOM/CSSOM/JavaScript
runtime, CSS-based theming outside Swift, and a smaller accessibility surface —
for content the app already owns as Swift values.

The preview must satisfy the following:

- **Whole-document text interaction.** Writers select the preview and copy it;
  ⌘A and copy-with-HTML must behave as they do in a text pane.
- **Layout-true scroll sync.** Anchor positions must come from the layout the
  user actually sees, not from probes layered on top of it.
- **Swift theming.** Preview appearance comes from `Theme` values (ADR-004),
  not from CSS strings assembled at runtime.
- **Offline by default.** Math must render without a network connection.
- **One source of truth for blocks.** A table or formula in the preview must
  match the same table or formula in the exported HTML.

Two block kinds resist a pure text layout. TextKit 2 ignores
`NSTextBlock`/`NSTextTable` entirely, and on macOS 27 even a TextKit 1
`NSTextView` lays table cells out as ordinary tabbed paragraphs, so the columns
do not line up. TeX math needs MathJax, which is JavaScript. A plain-text table
grid is not an answer either: the system monospaced font's Latin advance is
0.618 em while a CJK glyph is a full em, so a single wrapped Chinese cell shifts
every column after it. Drawing a table with Core Text and Core Graphics into an
attachment image was tried and abandoned: the raster must match the pane width
exactly or TextKit 2 clips it, its text cannot be selected, and it amounts to
building a layout engine again.

## Decision

Render the preview natively. The parsed element tree becomes a single
attributed string displayed in a read-only TextKit 2 surface; WebKit is used
only as a sized overlay for the two block kinds TextKit cannot lay out.

### Pipeline

```
Markdown source
  → MarkdownParser (swift-markdown, ADR-002)
  → [MarkdownElement]
  → AttributedRenderer.render(_:)
        one NSAttributedString: block styles, inline traits, image attachments
        sized placeholders for tables and math
  → MarkdownPreviewSurface
        read-only MarkdownTextView (TextKit 2)
        PreviewWebBlockView overlays for tables and math
```

### Text surface

`AttributedRenderer` walks the element tree once and appends to a single
`NSMutableAttributedString`: headings, paragraphs, ordered/unordered/task lists,
block quotes, fenced and inline code, rules, footnotes, front matter, raw HTML
placeholders, and inline traits (emphasis, strong, strikethrough, underline,
highlight, superscript). Images are embedded as `NSTextAttachment`s.

`MarkdownPreviewSurface` is an `NSViewRepresentable` around an `NSScrollView`
and a read-only `MarkdownTextView` — the same TextKit 2 text view the editor
uses. The surface re-renders only when an input that affects rendering changes
(`RenderInputs` is `Equatable`), so a caret-only update in the editor does not
replace the text storage or invalidate the layout.

`DocumentView` defaults `usesTextSurface` to `true`; Settings → Rendering
exposes the same switch as "Selectable Preview (Text Surface)".

### Tables

`AttributedRenderer` emits a sized placeholder for each `.table` element and
records a `TableBlock` (anchor path, placeholder range, `TableData`,
attachment). `MarkdownPreviewSurface` positions a `PreviewWebBlockView` over the
placeholder and loads `TablePreviewHTML.page(markup:theme:zoom:)`. The markup
comes from `TablePreviewHTML.tableMarkup`, shared with the HTML export, and the
page uses the same bundled stylesheet, so a preview table and an exported table
cannot differ.

The page reports its content height with a `height` script message. The
coordinator writes the measured height into the attachment's bounds, invalidates
the placeholder range and relays out, so the text after the table starts below
it. Measured heights are replayed into later renders so the layout does not jump
back to an estimate. `PreviewWebBlockView`s are recycled through a small idle
pool (maximum 2) and are created only for blocks intersecting the viewport plus
one viewport-height margin; each one is a web content process, and a document
with many blocks must not start them all at once.

### Math

The parse layer converts TeX spans into fenced `math`/`math-inline` blocks before
the element tree is built (`MarkdownParser.applyMath`). It recognizes
`\\[ … \\]`, `\\( … \\)`, `\[ … \]`, `\( … \)` and `$$ … $$` under the TeX math
preference, plus `$ … $` under the inline-dollar option. Fenced code and inline
code spans are skipped, and an unclosed span is left as written.

`AttributedRenderer` gives each math block the same placeholder treatment as a
table; the formula is typeset by the bundled MathJax 3 distribution in
`MathPreviewHTML.page(tex:isDisplay:theme:zoom:)`, which falls back to the CDN
only when the bundled resource is missing. The placeholder attachment carries
the TeX source, so copying a selection yields the formula instead of a
placeholder character.

### Diagrams

Mermaid, Graphviz and other diagram fences stay plain code in the text surface;
only tables and math use block overlays there. The element-tree fallback can
still render diagram fences through `WebBlockView` when the corresponding
preferences are enabled.

### Element-tree fallback

`MarkdownView` renders the same `[MarkdownElement]` tree as SwiftUI views (with
`WebBlockView` for math and diagram fences when enabled). It remains selectable
behind `preferences.previewUsesTextSurface` and shares the parser output, the
`Theme` values and the scroll-sync anchors with the text surface.

### Export

HTML export is separate from the live preview. `Renderer` serializes the element
tree to a complete HTML document for Copy HTML, Export to File and Print. It
reuses `TablePreviewHTML.tableMarkup`, the bundled stylesheets and the bundled
MathJax resource, which is why a preview block and its exported form stay
consistent without the preview going through the export path.

### Scroll sync

`MarkdownPreviewSurface.Coordinator` measures each anchor with
`NSTextLayoutManager.typographicBounds(in:)` and reports the Y positions; the
scroll-sync service interpolates between the editor's and the preview's anchors.
When WebKit reports a block height the placeholder grows or shrinks, so the
coordinator re-reports metrics and anchors once the layout has settled, keeping
the panes from drifting apart.

## Alternatives Considered

### 1. HTML preview hosted in WKWebView

Parse → generate an HTML string → `WKWebView.loadHTMLString`. **Rejected.** It
adds a second rendering engine and a separate web content process, pays IPC on
every preview update, carries a DOM/CSSOM/JavaScript runtime for a text
document, needs JavaScript for scroll sync, moves theming into CSS strings
outside the Swift type system, enlarges the attack surface for untrusted
Markdown, limits accessibility integration, and can print differently from what
is on screen.

### 2. SwiftUI element tree as the only surface

Render every element with SwiftUI views. **Kept as a fallback, not the
default.** `Text` views do not provide whole-document selection with ⌘A,
copy-with-HTML would need separate plumbing, a view per element is heavier than
appending attributes into one string, and scroll anchors had to be reported from
`GeometryReader` probes rather than from the real text layout.

### 3. TextKit-native tables

Lay tables out with `NSTextTable`/`NSTextBlock`, or as tabbed paragraphs in a
TextKit 1 text view. **Rejected.** TextKit 2 ignores the table APIs, the
TextKit 1 path does not line the columns up, and a plain text grid breaks on
mixed CJK/Latin content because the Latin advance of the system monospaced font
is 0.618 em against a full-em CJK glyph.

### 4. Hand-drawn tables through Core Text

Rasterize or draw each table into an attachment image. **Rejected.** The drawing
must track the pane width exactly or it is clipped, the table text cannot be
selected, and the approach rebuilds a layout engine.

### 5. PDF-based preview

Render the document to a PDF and show it in a `PDFView`. **Rejected.** PDF
output is not reflowable or selectable the way a text surface is, it needs a
large Core Graphics path, and it does not fit a live preview workflow.

## Consequences

### Positive

- **Whole-document selection.** ⌘A, drag selection and copy-with-HTML behave
  like a text pane; placeholder attachments carry their table or TeX content
  into the copy path.
- **Layout-true anchors.** Scroll-sync anchor positions come from TextKit 2's
  own layout, so they do not drift from the rendered text.
- **Native accessibility and appearance.** The surface is a real text view;
  VoiceOver and system appearance work without a web accessibility bridge.
- **Cheap steady state.** One attributed-string render per input change;
  identical renders are skipped entirely, so a caret click does not re-lay the
  preview.
- **Bounded web usage.** Only tables and formulas near the viewport hold a web
  view, and idle views are pooled.
- **Consistent export.** The preview and `Renderer` share table markup,
  stylesheets and the MathJax resource.
- **Offline.** The bundled MathJax typesets formulas without network access.

### Negative

- **Two surfaces to maintain.** The text surface is the default and the SwiftUI
  element tree is the fallback; both consume the same element tree and theme,
  but changes that affect both must be made in both.
- **Not WebView-free for every block.** Each visible table or math block is a
  web content process, and the text inside it is selected by WebKit rather than
  by the surrounding TextKit selection.
- **Height estimates.** A block occupies an estimated height until the page
  reports the measured one; measured heights are replayed to keep later renders
  stable.
- **Diagram fences are code.** Mermaid and Graphviz fences do not render as
  diagrams in the text surface; they are shown as code blocks.

### Risks

- **Very large documents.** The whole document is one attributed string.
  Mitigations: skip unchanged renders, TextKit 2's viewport-based layout, and
  lazy block-view creation.
- **Many tables or formulas on screen.** Every near-viewport block holds a web
  content process. Mitigations: the idle pool, the one-viewport margin, and
  recycling when a block scrolls away; the number of live views is bounded by
  what is visible rather than by document size.
- **Attachment-backed copy.** Copying a selection that contains a table or
  formula relies on the attachment carrying its content. This is covered by
  `AttributedRendererTests`, `TablePreviewHTMLTests` and `MathPreviewHTMLTests`.

## References

- `MarkdownPreviewSurface` — MacMarkDown/UI/macOS/Preview/MarkdownPreviewSurface.swift
- `PreviewWebBlockView` — MacMarkDown/UI/macOS/Preview/PreviewWebBlockView.swift
- `AttributedRenderer` — MacMarkDown/Services/Preview/AttributedRenderer.swift
- Table and math pages — MacMarkDown/Services/Preview/TablePreviewHTML.swift, MathPreviewHTML.swift
- HTML export — MacMarkDown/Services/Preview/Renderer.swift
- Apple swift-markdown MarkupWalker — https://github.com/apple/swift-markdown/blob/main/Sources/Markdown/MarkupWalker.swift
- Apple TextKit 2 — https://developer.apple.com/documentation/appkit/textkit
- MathJax — https://www.mathjax.org
