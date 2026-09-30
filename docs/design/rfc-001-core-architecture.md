# RFC-001: Core Architecture

- **Status**: Proposed
- **Date**: 2026-09-15
- **Author**: Architecture Team
- **Audience**: Engineering, Product
- **Related**: [RFC-002 Rendering Pipeline](rfc-002-rendering-pipeline.md), [Business Overview](../business/overview.md)

---

## 1. Summary

macOS 26 and Swift 6.4 opened a new era for Apple's developer frameworks:
SwiftUI, the Observation framework, TextKit 2 and Swift concurrency became
mature enough to carry a complete writing tool, so MacMarkDown was written from
scratch in pure Swift and SwiftUI.

This RFC defines the core architecture of MacMarkDown: layer separation, key
components, the data flow between editor and preview, and the concurrency
strategy under Swift 6.4 strict concurrency. The XcodeGen project
(`project.yml`) produces four targets:

| Target | Source root | Role |
|--------|-------------|------|
| `MacMarkDown` | `MacMarkDown/Application` | SwiftUI app: `WindowGroup`, `Settings` scene, menu commands, app delegate |
| `MacMarkDownKit` | `MacMarkDown/` | Framework: document model, Markdown pipeline, services, stores, themes, UI |
| `macmarkdown-cli` | `CLI/` | `macmarkdown` command-line companion |
| `MacMarkDownTests` | `MacMarkDown/Tests` | Unit tests for parser, renderers, documents, editor and scroll sync |

## 2. Goals / Non-Goals

### 2.1 Goals

- **One source of truth.** `MarkdownDocument` owns the text; the editor, the
  preview, the scripting bridge and the exporters all read from it.
- **One Markdown path.** A single `MarkdownParser` produces one element tree
  that both the native preview and the HTML exporter consume (RFC-002).
- **A native preview.** TextKit 2 and SwiftUI render the document in-process;
  WebKit is used only for blocks that genuinely need it (tables, MathJax).
- **Compile-time data-race safety.** `SWIFT_STRICT_CONCURRENCY = complete`
  keeps actor isolation mechanical and reviewable.
- **A small, scriptable surface.** AppleScript, the CLI and Finder opens all
  funnel through the same document session.

### 2.2 Non-Goals

- Incremental parsing in v1; the whole document is re-analyzed on each render.
- Cross-platform targets; the codebase is macOS-only by design.
- Third-party Markdown engines; Apple's `swift-markdown` is the only parser.
- XIB/NIB files or view-controller-driven UI; SwiftUI is the UI stack.

## 3. System Diagram

```
┌──────────────────────────────────────────────────────────────────────┐
│                             APP LAYER                                │
│  ┌───────────────────┐        ┌───────────────────────────────────┐  │
│  │ MacMarkDownApp    │───────▶│ Settings scene → SettingsView     │  │
│  │ (@main, SwiftUI)  │        │ General · Markdown · Editor ·     │  │
│  │ WindowGroup       │        │ HTML · Terminal                   │  │
│  │ Commands / menus  │        └───────────────────────────────────┘  │
│  └─────────┬─────────┘                                               │
│            │ creates                                                 │
│            ▼                                                         │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                          VIEW LAYER                          │    │
│  │  ┌───────────────────────────────┐  ┌──────────────────────┐ │    │
│  │  │ DocumentView                  │  │ ToolbarView          │ │    │
│  │  │ split layout · find bar ·     │◀─│ format actions ·     │ │    │
│  │  │ word count · scroll sync      │  │ lists · blockquote   │ │    │
│  │  ├───────────────┬───────────────┤  └──────────────────────┘ │    │
│  │  │ Markdown      │ PreviewPane   │      ┌───────────────┐     │    │
│  │  │ EditorView    │ MarkdownPreview│     │ WordCountBar  │     │    │
│  │  │ (TextKit 2)   │ Surface + web │      └───────────────┘     │    │
│  │  │               │ blocks        │                            │    │
│  │  └───────────────┴───────────────┘                            │    │
│  └───────────────────────┬──────────────────────────────────────┘    │
│                          │ observes / commands                       │
│                          ▼                                           │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                        DOCUMENT LAYER                        │    │
│  │  MarkdownDocument · DocumentSession · DocumentOpenQueue      │    │
│  │  RecentDocumentsStore · ScriptableDocument                   │    │
│  │  UnsavedChangesGuard · FrontMatter                           │    │
│  └──────────────────────────┬───────────────────────────────────┘    │
│                             ▼                                        │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                        SERVICE LAYER                         │    │
│  │  RenderService · AttributedRenderer · Renderer               │    │
│  │  ExportService · ScrollSyncService/Coordinator               │    │
│  │  MarkdownSyntaxHighlighter · CodeSyntaxHighlighter           │    │
│  │  FindController · PlugInManager                              │    │
│  └──────────────────────────┬───────────────────────────────────┘    │
│                             ▼                                        │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                 MARKDOWN / THEME / STORES LAYER              │    │
│  │  MarkdownParser · MarkdownElement · DocumentAnchor           │    │
│  │  Theme · EditorTheme · Preferences                           │    │
│  └──────────────────────────┬───────────────────────────────────┘    │
│                             ▼                                        │
│  ┌──────────────────────────────────────────────────────────────┐    │
│  │                       UTILITY LAYER                          │    │
│  │  Constants · FontResolver · ResourceLoader · TerminalUtility │    │
│  │  StringExtensions · Bundled resources (styles, themes,       │    │
│  │  templates)                                                  │    │
│  └──────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────┘
```

## 4. Layer Separation

Dependencies flow one way: **App → UI → Document → Services →
Markdown/Theme/Stores → Tools/Extensions**. A layer may depend on its own level
or anything below it. `Document` may compose `Services` for its per-document
pipelines; `Services` never import `UI` or `Document`.

| Layer | Responsibility | Allowed deps |
|-------|----------------|--------------|
| App | Composition root: scenes, commands/menus, app delegate, settings window | all below |
| UI (`UI/Shared`, `UI/macOS`) | Document chrome, editor and preview panes, toolbar, find bar, settings UI | Document, Services, Stores, Theme |
| Document | File lifecycle, session registry, open queue, recents, scripting, unsaved-changes guard, front matter | Services, Markdown, Theme, Stores, Tools |
| Services | Render pipeline, attributed rendering, export, scroll sync, syntax highlighting, plug-ins | Markdown, Theme, Stores, Tools/Extensions |
| Markdown / Theme / Stores | Element tree and parsing; theme values; defaults-backed preferences | Tools/Extensions, swift-markdown, Yams |
| Tools / Extensions | Stateless helpers: constants, font resolution, resource loading, terminal install, string helpers | — |

### 4.1 Rationale

- **Testing**: the Markdown layer and the services stay UI-free and
  unit-testable without a host app; `MacMarkDownTests` links `MacMarkDownKit`
  directly.
- **SwiftUI reactivity**: `@Observable` models notify UI views directly, so UI
  never needs imperative refresh calls.
- **Strict concurrency**: keeping all mutable state on `@MainActor` makes
  `Sendable` requirements fall out of the layer boundaries instead of being
  retrofitted.

## 5. Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `MacMarkDownApp` | `Application/` | `@main`; `WindowGroup`, `Settings` scene, menu commands |
| `MarkdownDocument` | `Document/` | `@Observable` source of truth: `text`, `fileURL`, `lastSavedText`, `isEdited`, autosave |
| `DocumentSession` | `Document/` | Registry of open windows/documents that menu actions act on |
| `DocumentOpenQueue` | `Document/` | Buffers Finder/CLI file opens until a window is ready |
| `RecentDocumentsStore` | `Document/` | Open Recent menu |
| `ScriptableDocument` | `Document/` | AppleScript bridge (`MacMarkDown.sdef`) |
| `UnsavedChangesGuard` | `Document/` | Protects unsaved edits on window close or quit |
| `FrontMatter` | `Document/` | YAML front matter extraction via Yams |
| `DocumentView` | `UI/Shared/Document` | Split layout, toolbar, find bar, word count, scroll-sync coordination |
| `MarkdownEditorView` | `UI/macOS/Editor` | TextKit 2 editing surface (layout fragments, gutter, smart editing) |
| `MarkdownPreviewSurface` | `UI/macOS/Preview` | Read-only TextKit 2 preview over `AttributedRenderer` output |
| `PreviewWebBlockView` | `UI/macOS/Preview` | `WKWebView` block for tables and MathJax formulas |
| `MarkdownView` | `UI/Shared/Preview` | Pure-SwiftUI element-tree preview (fallback path) |
| `Preferences` | `Stores/` | `@Observable`, `UserDefaults`-backed settings for all five panes |
| `RenderService` | `Services/Preview` | Debounced parse/render coordinator; publishes elements, anchors, HTML fragment |
| `ScrollSyncService` / `ScrollSyncCoordinator` | `Services/ScrollSync` | Pair editor and preview anchors and map offsets |
| `ExportService` | `Services/Export` | File, clipboard, print and PDF export |
| `PlugInManager` | `Services/PlugIn` | Loads `.macmarkdown-plugin` bundles into the Plug-ins menu |
| `TerminalUtility` | `Tools/` | Installs the `macmarkdown` CLI into `/usr/local/bin` |

## 6. Data Flow

The canonical editor→preview path:

```
User types character
        │
        ▼
MarkdownEditorView.onTextChange
        │ writes
        ▼
MarkdownDocument.updateText(_:)  ◀──────────── (single source of truth)
        │ unless Manual Render is on
        ▼
RenderService.scheduleRender(text:options:)   (debounced 300 ms; cancels stale work)
        │
        ▼
MarkdownParser.parseDocument → ParsedDocument([MarkdownElement], [DocumentAnchor])
        │ observed
        ▼
PreviewPane
        ├─► MarkdownPreviewSurface: AttributedRenderer → NSAttributedString → TextKit 2
        └─► PreviewWebBlockView overlays for tables and MathJax formulas
        │
        ▼
Preview shows the updated document
```

- `MarkdownEditorView` is a write-through surface: keystrokes land in
  `MarkdownDocument.text` immediately; nothing is rendered from transient
  editor-local state.
- All cross-pane synchronization (scroll positions at minimum) passes through
  `ScrollSyncCoordinator`, never through shared globals.
- Preferences flow one way into rendering: `Preferences` → `RenderService`
  options and `Theme` → preview and export; the preview never mutates settings.
- Export reads the same parser output through `ExportService` (RFC-002 §9).

## 7. State Management with @Observable

Conform models to SwiftUI Observation; never use `ObservableObject`/`@Published`:

```swift
import Observation

@MainActor
@Observable
public final class MarkdownDocument: Identifiable {
    public let id = UUID()
    public var text: String = ""
    public var fileURL: URL?
    public private(set) var lastSavedText: String = ""

    public let preferences: Preferences
    public let parser: MarkdownParser
    public let renderService: RenderService

    /// Derived, so undo back to the saved content clears the modified state.
    public var isEdited: Bool { text != lastSavedText }
}
```

Change notifications are emitted per property, so `DocumentView` re-renders only
the affected subviews; the preview observes `renderService.elements` while the
word-count bar observes a derived count without dragging the whole view tree.
`Preferences` is an `@Observable` class whose properties write through to
`UserDefaults`, so the settings window and the document panes observe the same
values.

## 8. Swift 6.4 Strict Concurrency

### 8.1 Isolation policy

| Category | Isolation | Rationale |
|----------|-----------|-----------|
| UI views (`DocumentView`, `MarkdownPreviewSurface`, `MarkdownView`) | `@MainActor` | All UI mutations must be on the main actor |
| `MarkdownDocument`, `Preferences`, `RenderService`, `ScrollSyncService` | `@MainActor` (`@Observable`) | Mutable app state is written by the UI and read by views |
| `AttributedRenderer`, `Renderer`, `ExportService` | `@MainActor` | They build AppKit/HTML output from model values |
| `MarkdownElement`, `InlineElement`, `DocumentAnchor`, `ParsedDocument`, `Theme`, `EditorTheme`, `MarkdownParseOptions` | `Sendable` value types | Immutable data that can be handed across isolation boundaries |
| Tools/Extensions | `Sendable` structs / free functions | Stateless |

### 8.2 Concurrency rules

1. **No shared mutable state** — anything written from multiple contexts is an
   immutable value type or main-actor state.
2. **Main-actor serialization** — parsing and render publication form one
   serialized pipeline; the parser emits `Sendable` values that observers can
   copy without locking.
3. **Cancellation-first** — a new render cancels the previous scheduled work
   item rather than queuing unbounded work; manual render bypasses the queue.
4. **Compile-time enforcement** — the project builds with
   `SWIFT_STRICT_CONCURRENCY = complete`; CI blocks on warnings.

```swift
@MainActor
@Observable
public final class RenderService: @unchecked Sendable {
    public private(set) var elements: [MarkdownElement] = []
    public private(set) var anchors: [DocumentAnchor] = []

    private var workItem: DispatchWorkItem?

    /// Manual render (⌘R): parse immediately, no debounce.
    public func parseNow(text: String, options: MarkdownParseOptions) { … }

    /// Live typing: cancel the pending parse and schedule a fresh one.
    public func scheduleRender(text: String, options: MarkdownParseOptions) {
        workItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.parseNow(text: text, options: options)
        }
        workItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Constants.defaultDebounceInterval,
            execute: work
        )
    }
}
```

### 8.3 Threading contract

- Editor input, parsing, theme application and preview updates happen on the
  main actor, in document order; the debounce window bounds how often the
  whole document is re-analyzed.
- Value types crossing an isolation boundary are `Sendable` copies; there is
  no sharing of reference types across threads.
- Off-main work is reserved for system frameworks (WebKit height measurement,
  file I/O), which report back on the main thread.

## 9. Open Questions

1. Should `MarkdownDocument` adopt SwiftUI's `FileDocument` value semantics, or
   keep the `@Observable` session model with the explicit open/save pipeline
   that `DocumentSession` and `UnsavedChangesGuard` rely on?
2. Should the editor keep the TextKit 2 `NSTextView` bridge for caret and
   anchor coordinates, or can a fully SwiftUI editing surface provide the
   measurement precision scroll sync needs?
3. Is whole-document re-parse within budget indefinitely (see RFC-002 §10), or
   should v2 introduce incremental parsing?
4. Should `Preferences` batch writes for multi-window live updates, or is
   immediate `UserDefaults` write-through sufficient at the target document
   sizes?
