# ADR-001: Use Pure SwiftUI for All UI

## Status

**Accepted** — September 2026

## Context

macOS 26 and Swift 6.4 opened a new era for Apple's developer frameworks: SwiftUI, the Observation framework, TextKit 2 and Swift concurrency became mature enough to carry a complete writing tool, so MacMarkDown was written from scratch in pure Swift and SwiftUI, targeting macOS 26 and later only.

That foundation leaves one question open for the UI layer: where should the boundary between SwiftUI and AppKit sit? On macOS 26 the answer is no longer dictated by compatibility constraints. Scenes, windows, toolbars, menus, settings, and layout all have complete SwiftUI expressions, so AppKit is only justified where SwiftUI has no comparable surface at all.

Two surfaces in a Markdown editor meet that bar:

- The **editor surface** needs text layout and editing control that SwiftUI's built-in `TextEditor` does not expose: per-token syntax highlighting, line numbers, fine-grained selection and scrolling, drag-and-drop, spelling, and smart-editing hooks.
- The **preview text surface** needs a read-only text view with whole-document selection, Copy HTML, and text-layout positions that scroll sync can measure directly.

Both require a TextKit 2 text view, which is an AppKit view.

## Decision

All UI in MacMarkDown is implemented in **pure SwiftUI**. Concretely:

- **No XIB or NIB files** exist in the project; the Interface Builder pipeline is not part of the build.
- **No view-controller-based window layout.** Windows and panes are SwiftUI scenes and views, not controller hierarchies.
- **Scenes** use `WindowGroup` for document windows and the `Settings` scene for preferences; application menus are declared with the `.commands { }` modifier.
- **The toolbar** is declared with the `.toolbar { }` modifier and `ToolbarItemGroup`.
- **State binding** uses `@State`, `@Environment`, `@Bindable`, and `@Observable` classes from the Observation framework. There are no outlets or actions.
- **The split layout** is composed in SwiftUI: two panes in an `HStack` with a draggable divider, plus preferences for side-by-side placement, pane visibility, and split ratios.

### Deliberate AppKit bridge

The text surfaces are the one place where AppKit is used on purpose:

- The editor is `MarkdownTextView`, a TextKit 2 text view hosted through `MarkdownEditorView`, an `NSViewRepresentable`.
- The preview's text surface is `MarkdownPreviewSurface`, built on the same TextKit 2 text view and bridged the same way.

Everything around those text surfaces — window chrome, pane layout and divider, toolbar, menu bar, find bar, and settings — is SwiftUI.

### View architecture

```
MacMarkDownApp (SwiftUI App)
├── WindowGroup("MacMarkDown")
│   └── ContentView → DocumentView
│       ├── Editor pane   → MarkdownEditorView → MarkdownTextView (NSViewRepresentable)
│       ├── Pane divider  → SwiftUI drag gesture
│       └── Preview pane  → MarkdownPreviewSurface (NSViewRepresentable, TextKit 2)
│                         → MarkdownView (SwiftUI element tree, preference-gated)
├── Settings scene        → SettingsView
└── .commands             → File / Edit / Format / Plug-ins menus
```

### State management

State lives in `@Observable` classes and is injected through the SwiftUI environment:

- `MarkdownDocument` owns the document text, file URL, save state, and child services (`MarkdownParser`, `RenderService`).
- `Preferences` owns editor, preview, and rendering settings.
- Views read and write state through `@State`, `@Environment`, and `@Bindable`; Observation tracking propagates model changes without manual notification plumbing.

## Alternatives Considered

### 1. AppKit with Storyboard/XIB
Keep the UI in AppKit and Interface Builder files. **Rejected**: XIB merge conflicts are costly, broken outlets fail at runtime rather than at compile time, and the approach forgoes the declarative, reactive model that macOS 26 makes fully viable.

### 2. Programmatic AppKit without XIB
Build every screen with `NSStackView`, Auto Layout constraints, and controller classes. **Rejected**: it removes XIB merge conflicts but keeps the controller boilerplate and offers no compile-time binding safety. SwiftUI expresses the same screens with less code and reactive updates.

### 3. SwiftUI with a broad AppKit fallback
Adopt SwiftUI but bridge AppKit for split views, toolbars, and menus as well. **Rejected**: on macOS 26 SwiftUI covers all of those surfaces, so a broad fallback would maintain two UI paradigms without a current API gap. Only the text surfaces need AppKit.

### 4. SwiftUI-only text editing (`TextEditor`)
Use SwiftUI's `TextEditor` for the editor pane. **Rejected**: `TextEditor` does not expose the layout, styling, and event control a Markdown editor needs. A TextKit 2 view behind `NSViewRepresentable` is the narrow bridge that keeps the application shell in SwiftUI.

## Consequences

### Positive

- **Declarative UI** — Views are composable functions of state; adding a preference or a view variant is usually a small, local change.
- **Compile-time safety** — Bindings are type-checked; there are no connection failures to discover at runtime.
- **Less boilerplate** — A screen that needs a controller class plus several lifecycle callbacks in AppKit is typically a fraction of that code in SwiftUI.
- **Live previews** — SwiftUI Previews let UI work iterate without launching the full application.
- **A single state model** — Observation classes and SwiftUI property wrappers give one consistent way to read and mutate application state.
- **Theming for free** — Dark/light adaptation and Dynamic Type come from the SwiftUI color and font systems (`.foregroundStyle(.primary)`, `.background(.background)`), with app-specific themes layered on top.

### Negative

- **Text-surface bridge complexity** — `MarkdownEditorView` and `MarkdownPreviewSurface` need coordinators that synchronize text storage, selection, highlighting, and scroll metrics between the AppKit text system and SwiftUI state. This is the most intricate part of the UI layer.
- **Feature coordination** — Advanced editing features (line-number gutter, find bar, scroll sync, drop targeting) require explicit coordination between the text system and SwiftUI state.
- **Debugging opacity** — When layout problems appear, SwiftUI's update and diffing pipeline is harder to reason about than explicit AppKit layout code.

### Risks

- SwiftUI's API surface evolves between macOS releases. Targeting macOS 26 bounds the initial exposure, but future releases may require adaptation.
- The `NSViewRepresentable` text surfaces are a long-lived interop boundary. If Apple ships an editing API with comparable control, the bridge should be re-evaluated.

## References

- Apple SwiftUI documentation: https://developer.apple.com/documentation/swiftui
- Observation framework: https://developer.apple.com/documentation/observation
- TextKit 2: https://developer.apple.com/documentation/textkit
- WWDC 2025 session "What's new in SwiftUI"
- Application code: `MacMarkDown/Application/MacMarkDownApp.swift`, `MacMarkDown/UI/Shared/Document/DocumentView.swift`, `MacMarkDown/UI/macOS/Editor/MarkdownEditorView.swift`, `MacMarkDown/UI/macOS/Editor/MarkdownTextView/MarkdownTextView.swift`, `MacMarkDown/UI/macOS/Preview/MarkdownPreviewSurface.swift`
