# MacMarkDown — Business Overview

- **Status**: Draft
- **Date**: 2026-09-15
- **Audience**: Engineering, Product, Management
- **Companion docs**: [RFC-001 Core Architecture](../design/rfc-001-core-architecture.md), [RFC-002 Rendering Pipeline](../design/rfc-002-rendering-pipeline.md), [RFC-003 Editor Integration](../design/rfc-003-editor-integration.md)

---

## 1. Product

MacMarkDown is a native Markdown editor for macOS, written from scratch in pure Swift
and SwiftUI. It targets writers, developers and technical communicators who want a
fast, local-first, distraction-free writing tool with a live preview, deep formatting
support and first-class export — without leaving native macOS.

macOS 26 and Swift 6.4 opened a new era for Apple's developer frameworks: SwiftUI, the
Observation framework, TextKit 2 and Swift concurrency became mature enough to carry a
complete writing tool. That is the foundation MacMarkDown is built on:

- **TextKit 2** provides viewport-based layout, so a custom editor can render only the
  visible band of a long document and still offer precise caret, selection, gutter and
  scroll-anchor geometry.
- **SwiftUI and Observation** give the app a declarative window, settings and toolbar
  story with per-property change tracking, so the preview, status bar and settings
  update only where state actually changed.
- **Swift 6.4 strict concurrency** makes data-race safety a compile-time property:
  editor state is main-actor-isolated, parsed documents and formatting commands are
  immutable `Sendable` values, and the compiler enforces the boundaries.
- **Native text input** — including input methods for Japanese, Chinese and Korean —
  is implemented directly on the editor's text view, so composition, the candidate
  window and key bindings behave exactly as macOS users expect.

The result is a native multi-window document editor: files stay on disk, documents open from
Finder, the `macmarkdown` CLI or the `x-macmarkdown://` URL scheme, the split layout
puts the editor and the preview side by side, and themes, styles, templates and
plug-ins can all be extended from the app's data directory.

## 2. Target Architecture

| Attribute | Value |
|-----------|-------|
| Language | Swift 6.4, strict concurrency enabled |
| Minimum OS | macOS 26 (built against the macOS 27 SDK) |
| UI framework | SwiftUI; AppKit only behind thin `NSViewRepresentable` wrappers for the text surfaces and web blocks |
| Editor | Custom TextKit 2 view (`MarkdownTextView`): `NSTextContentStorage` → custom layout manager → `NSTextContainer`, viewport layout with per-fragment views, IME, selection, formatting, smart editing, accessibility |
| Preview | Read-only instance of the same TextKit 2 surface, plus isolated per-block `WKWebView`s for tables and MathJax formulas; native code syntax highlighting |
| Markdown parsing | `swift-markdown` (Apple) for the document tree; one parse tree feeds preview, export and scroll anchors |
| Front matter | `Yams` |
| State management | Observation (`@Observable`, `@MainActor`); `Preferences` backed by `UserDefaults` |
| Settings | SwiftUI `Settings` scene with five panes: General, Markdown, Editor, HTML, Terminal |
| Document model | `MarkdownDocument` owns text, front matter and dirty state; a session registry routes each document to its own window; opt-in debounced auto-save |
| Export | AST → HTML renderer; HTML, PDF (print pipeline), print, copy HTML |
| Scroll sync | Anchor-based `ScrollSyncService`; editor → preview by default, optional bidirectional mode |
| CLI | `macmarkdown` companion tool (`/usr/local/bin`), installable from Settings ▸ Terminal |
| URL scheme | `x-macmarkdown://open?url=…` |
| Scripting | AppleScript via the bundled `MacMarkDown.sdef` (`text` read/write, `html` read-only) |
| Plug-ins | Bundles in `~/Library/Application Support/MacMarkDown/PlugIns` implementing `MacMarkDownPlugIn` |
| Look and feel | Editor themes (`*.style`), preview styles (`*.css`), HTML templates |
| Bundle identifier | `com.xaiat.MacMarkDown` |
| Localization | 21 locales, including Simplified (`zh-Hans`) and Traditional (`zh-Hant`) Chinese |

## 3. Feature Scope

### 3.1 Editing

- Custom TextKit 2 editor: fast viewport-based layout, smooth scrolling and O(1)
  jumps in long documents, line wrapping, scroll-past-end.
- Split editor + live preview; editor on the left or right; resizable panes; optional
  maximum text width.
- Formatting toolbar and Format menu: paragraph and H1–H6, bold, italic, inline code,
  strikethrough, underline, highlight, comment, unordered/ordered lists, blockquote,
  code block, link, image, indent/unindent, new paragraph.
- Smart editing, each behavior individually configurable: matching-character
  completion for ASCII brackets/quotes and CJK punctuation pairs, selection wrapping,
  paired-character deletion, list/blockquote/indented-line continuation on Return,
  auto-incrementing ordered lists, Tab-to-spaces, indent/outdent of selected lines,
  Smart Home.
- Live syntax highlighting with selectable editor themes.
- Line-number gutter, invisible-character display, spell checking, read aloud
  (selection or whole document), Services menu, find & replace.
- Status-bar word count (words, characters, or characters excluding spaces).
- Drag and drop: text inserts at the drop location, dropped image files inline as
  base64 Markdown, dropped documents open in the app.
- Undo/redo across typing, formatting commands, find & replace and drag and drop;
  opening or reverting a document resets history cleanly.
- Full keyboard navigation through the standard macOS key bindings, plus IME
  composition for CJK input.

### 3.2 Markdown support

- `swift-markdown` parser with one parse tree for preview, HTML export and scroll
  anchors.
- Extension toggles: intra-word emphasis, tables, fenced code blocks, autolink,
  strikethrough, underline, highlight, superscript, footnotes, blockquote and
  SmartyPants; manual render mode when the author wants to control when rendering
  happens.
- YAML front matter detection (parsed with Yams), optionally hidden from the preview.
- TeX math (fenced and inline `$…$`), Mermaid diagrams and Graphviz diagrams.
- Task lists, hard wrap, table of contents generation, footnotes, code-block
  accessories and line numbers in the rendered output.

### 3.3 Preview and rendering

- Live native preview of the parsed document, using the same TextKit 2 surface for
  selectable text and whole-document copy.
- Synchronized scrolling: editor → preview by default, with an optional bidirectional
  mode; dense block/list-item anchors keep the panes in step.
- Tables and MathJax formulas rendered in isolated per-block web views that report
  their height back to the layout; Mermaid and Graphviz diagrams render in exported
  HTML.
- Native code syntax highlighting with selectable palettes.
- Front matter hiding, TOC rendering, preview font policy (follow editor / system /
  custom) and zoom relative to the base font size.
- Link handling: open existing targets and create missing files, per preference.

### 3.4 Export and printing

- Export HTML, optionally with inline styles and code highlighting.
- Export PDF through the print pipeline; print.
- Copy rendered HTML to the clipboard.

### 3.5 Settings

Five panes, all stored in `UserDefaults` and observed through `Preferences`:

- **General** — launch behavior, update preferences (including the pre-release
  channel), link-target creation.
- **Markdown** — manual render, extension toggles.
- **Editor** — font and size, theme, layout (width limit, editor side, line spacing,
  insets), behavior (word count and type, sync scrolling, bidirectional sync, Smart
  Home, tab conversion, prefix insertion, auto-increment, pair completion, list
  marker, scroll past end, newline at EOF, auto save, spell checking, line numbers,
  invisible characters).
- **HTML** — stylesheet, template, selectable preview, front matter, task lists, hard
  wrap, TOC, syntax highlighting and palette, line numbers, code-block accessory,
  MathJax and inline math, Mermaid, Graphviz, preview font, zoom, default directory
  for relative links.
- **Terminal** — install or remove the `macmarkdown` command-line tool.

### 3.6 Extensibility and automation

- Plug-in bundles in the app's `PlugIns` directory that adopt the
  `MacMarkDownPlugIn` protocol and appear as menu commands.
- AppleScript support through the bundled scripting definition: the focused
  document's `text` (read/write) and `html` (read-only), plus the standard suite.
- `x-macmarkdown://open?url=…` URL scheme for other apps and tools.
- `macmarkdown` CLI: opens files, or reads piped stdin into a new document, on the
  app's next launch.
- 21-locale localization (`.xcstrings`), including Simplified and Traditional Chinese.

## 4. Roadmap — 5 Phases

| Phase | Name | Scope | Exit criterion |
|-------|------|-------|----------------|
| 1 | Foundation | Project scaffold, app/window/document model, split `DocumentView`, editor and preview surfaces, basic parse → render, open/save/auto-save | A Markdown file opens, edits, saves, and shows a live preview |
| 2 | Rendering | Full rendering pipeline (RFC-002), extension toggles, themes/styles/templates, MathJax/Mermaid/Graphviz blocks, export | Every supported Markdown extension and block type is covered by rendering tests, and the preview and HTML export agree on the same parse tree |
| 3 | Editor | TextKit 2 surface: viewport layout, selection, IME, undo, standard editing commands, accessibility, gutter, invisibles | The editor passes its behavior suites (editing, IME, selection, accessibility) and remains responsive on 10k+ line documents |
| 4 | Advanced | Formatting toolbar and commands, smart editing, syntax highlighting, word count, find & replace, drag and drop, scroll sync, export UI, Settings panes | The complete daily editing workflow is available, and every formatting command and smart-editing behavior has unit tests |
| 5 | Polish | CLI, URL scheme, AppleScript, plug-ins, 21-locale localization, performance passes, documentation | The app is ready for daily use as a primary Markdown editor |

Each phase ends when its own acceptance tests and documented criteria pass.

## 5. Scope and Success Criteria

- **In scope**: a native macOS application for writing and reading Markdown — split
  editor and live preview, the formatting and smart-editing feature set above, export,
  settings, automation and localization.
- **Out of scope for the first release**: non-macOS platforms, cloud accounts or
  sync services, real-time collaboration, and a hosted plug-in marketplace.
- **Success**:
  - Every feature listed under Feature Scope is implemented and covered by automated
    tests.
  - Every supported Markdown extension and block type is covered by parser and
    rendering tests.
  - The app builds cleanly under Swift 6.4 strict concurrency.
  - Editing stays responsive: typing latency remains flat on typical documents, and
    10k+ line documents remain usable.
  - Malformed Markdown degrades gracefully; large documents do not crash the app.
  - Localization is complete across all 21 locales, including Simplified and
    Traditional Chinese.

## 6. Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| TextKit 2 viewport or layout regressions during rapid edits | High | The real viewport pipeline is exercised headlessly in `MarkdownTextViewTests`; content measurement is deferred during live scroll and resize (RFC-003) |
| IME composition edge cases in a custom text view | High | Marked-text handling is implemented in `MarkdownTextView+InputClient` and covered by tests; pair completion skips marked ranges; a CJK input-method pass is part of release QA |
| `swift-markdown` does not cover app-specific extensions (footnotes, underline, highlight, superscript, quote) | Medium | Extensions are implemented as line-preserving parser transformations; each has parser and rendering tests; the parser is the single entry point for preview, export and anchors |
| Scroll-sync drift between editor and preview | Medium | Both panes consume the same ordered anchor list from one parse tree; `ScrollSyncService` has unit tests, and bidirectional mode uses the exact inverse mapping to avoid feedback |
| Theme, style or template format regressions | Low | File formats are parsed by this project's theme/style readers and covered by fixture tests |
| Strict-concurrency friction with AppKit callbacks | Medium | `@MainActor` isolation, SE-0466 isolated conformances for AppKit protocols, and `Sendable` value types at actor boundaries (RFC-001, RFC-003) |
