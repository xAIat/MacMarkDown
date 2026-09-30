# ADR-002: Use Apple's swift-markdown as the Markdown Parser

## Status

**Accepted** — September 2026

## Context

macOS 26 and Swift 6.4 opened a new era for Apple's developer frameworks, and MacMarkDown was written from scratch in pure Swift and SwiftUI. Within that foundation, the parser has a central role: a single parse of each document must serve the live preview, scroll sync, and every export path, without re-parsing or re-rendering for each consumer.

That calls for a parser with specific properties:

- It must produce a **structured, Swift-native tree** for block and inline content, not an HTML string and not a rendered attributed string.
- It must be **pure Swift** so it can participate in strict concurrency checking (`SWIFT_STRICT_CONCURRENCY = complete`) and pass `Sendable` values across actors.
- It must cover **CommonMark and GitHub Flavored Markdown** (tables, task lists, strikethrough, autolinks).
- It must be **maintained upstream**, since the document model built on it is long-lived.
- It must be **extensible**, because the app's syntax goes beyond CommonMark/GFM (math, `[toc]`, footnotes, front matter, inline extras).

### Parsing pipeline

1. The editor reports text changes; `RenderService` debounces them before parsing.
2. `MarkdownParser` prepares the source with line-preserving transforms (front matter and footnote definitions are blanked in place, math and inline extensions are marked, bare URLs are wrapped for autolink), then parses with `Document(parsing:options:)`.
3. The swift-markdown tree is converted into `[MarkdownElement]` — a `Sendable`, renderer-agnostic tree — together with `DocumentAnchor`s that pair editor and preview scroll positions by line.
4. The preview layer renders those elements natively (ADR-003); `Renderer` walks the same elements to produce HTML for Export, Print, and Copy HTML.
5. YAML front matter is parsed with Yams and becomes a `.frontMatter` element rendered as a nested table.

## Decision

Use Apple's **swift-markdown** as the Markdown parser, declared through Swift Package Manager as package `swift-markdown`, product `Markdown`, with **Yams** for YAML front matter.

### Why swift-markdown

- **Apple-maintained, open source** library with a Swift-native API.
- **Typed AST** — parsing produces a `Document` whose `Markup` nodes cover blocks and inlines; `MarkupWalker` makes AST traversal explicit, and the conversion layer transforms nodes as it walks.
- **CommonMark plus GFM extensions** — tables, task list checkboxes, strikethrough, and angle-bracket autolinks are handled by the library.
- **Sendable values** — the parse result can be produced and consumed under Swift concurrency without data races.
- **No C interop** — no bridging headers, no module maps, no C build products in the dependency.
- **Proven scope for the app** — the library's node set maps cleanly onto `MarkdownElement`, so the conversion layer stays small and testable.

### Integration

- The package is declared in `project.yml` and linked into the `MacMarkDownKit` framework; Yams is declared the same way.
- `MarkdownParser` is the single entry point for parsing in the app. Both the native preview (`MarkdownView`/`MarkdownPreviewSurface`) and the HTML exporter (`Renderer`) consume its output.
- No C code, bridging headers, or module maps exist in the parsing layer.

### Parsing flow

```
Source Markdown
  → MarkdownParser (line-preserving preparation, then Document(parsing:options:))
  → swift-markdown AST (Document / Markup)
  → [MarkdownElement] + [DocumentAnchor]
      → preview layer          native rendering (ADR-003)
      → Renderer               HTML for export, print, and Copy HTML
YAML front matter
  → Yams
  → .frontMatter element (rendered as a table)
```

### Extensions beyond CommonMark/GFM

swift-markdown models core Markdown and the common GFM extensions. The app layers its additional syntax around the library rather than forking it:

- Front matter is extracted with Yams before parsing.
- Footnote definitions are blanked line-preservingly and references are converted to anchors; the definitions become a `.footnotes` element.
- Math spans (`\[…\]`, `\(…\)`, `$$…$$`, and optionally `$…$`) are converted to `math`/`math-inline` fences for the web-block pipeline.
- Underline, highlight, superscript, and quote spans are marked with private-use sentinels that the element converter resolves.
- `[toc]`, autolink wrapping, smart-punctuation opt-out, and intra-word emphasis handling are applied as options around the parse.

Every transform is line-preserving so that `DocumentAnchor.line` still refers to a line in the source document; this keeps scroll sync exact.

## Alternatives Considered

### 1. cmark-gfm (C library)
cmark-gfm is GitHub's C implementation of GFM and would give complete extension coverage. **Rejected**: calling it from Swift requires a C interop layer, its node tree is a C-pointer API rather than Swift values, and it does not participate in Swift's strict concurrency model (node values are not `Sendable`). The app would maintain a wrapper plus a parallel Swift document model anyway, with a memory-unsafe boundary in the parsing path.

### 2. Ink (pure Swift)
Ink is a Swift-native Markdown parser with a friendly API. **Rejected**: it is community-maintained with a narrower extension story and no Apple backing. For a document model this central and this long-lived, the smaller maintenance risk of an Apple-maintained library outweighs Ink's lighter footprint.

### 3. Hand-written parser
Implement CommonMark/GFM in the app. **Rejected**: specification compliance is a large and permanent test burden (thousands of cases), and parser work would displace editor and preview features. Building on a maintained library is the better division of effort.

### 4. NSAttributedString-based parsing
Treat attributed text — for example, Markdown imported into an `NSAttributedString` — as the document model. **Rejected**: attributed strings describe presentation runs, not document structure. There is no heading/list/table hierarchy to drive the outline, table layout, scroll anchors, or export, and styling decisions would be mixed into the parse step.

## Consequences

### Positive

- **Swift-native document model** — All consumers work with `MarkdownElement`, a typed, `Sendable` tree; no C pointers or string-based HTML cross the parsing boundary.
- **One parse, every consumer** — The same tree feeds native preview rendering, scroll anchors, and HTML export, so the preview and exports cannot disagree about structure.
- **Strict concurrency** — Values crossing actors are `Sendable`; parsing is isolated (`@MainActor` in the app) and the model can run on a background actor if needed.
- **No C interop** — The build has no bridging headers or module maps, and the project stays in one language.
- **CommonMark + GFM coverage** — Tables, task lists, strikethrough, and autolinks come from the library rather than app code.
- **Active maintenance** — swift-markdown is maintained by Apple and updated alongside the toolchain.

### Negative

- **No HTML renderer included** — The library produces an AST, not HTML. `Renderer` walks `MarkdownElement` and emits HTML for export and print; that is app code to maintain.
- **Extensions need preprocessing** — Footnotes, math, `[toc]`, front matter, and inline extras are handled by app passes around the parse; each new extension must respect the line-preserving contract.
- **A second dependency** — YAML front matter requires Yams, because swift-markdown does not parse front matter.
- **Release cadence** — swift-markdown is released on Apple's schedule, which may be slower than a community project for urgent fixes.
- **API evolution** — The library is still evolving; major-version upgrades need a review of `Document(parsing:)`, `ParseOptions`, and node APIs.

### Risks

- Preprocessing passes that change line counts (currently only math, which carries a line map) would break scroll-anchor accuracy. New transforming extensions must be line-preserving or provide their own map.
- swift-markdown's node API and GFM behavior can change between releases; the conversion layer in `MarkdownParser` is the single place to adapt.

## References

- Apple swift-markdown: https://github.com/apple/swift-markdown
- CommonMark specification: https://spec.commonmark.org/
- GitHub Flavored Markdown specification: https://github.github.com/gfm/
- Yams: https://github.com/jpsim/Yams
- Application code: `MacMarkDown/Markdown/MarkdownParser.swift`, `MacMarkDown/Markdown/MarkdownElement.swift`, `MacMarkDown/Document/FrontMatter.swift`, `project.yml`
