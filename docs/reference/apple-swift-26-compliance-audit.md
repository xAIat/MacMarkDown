# Apple Swift 26 Compliance Audit

**Project**: MacMarkDown  
**Swift Version**: 6.4  
**Target Platform**: macOS 26  
**Audit Date**: 2026-09-15  
**Auditor**: MacMarkDown Core Team  

---

## 1. Overview

macOS 26 and Swift 6.4 opened a new era for Apple's developer frameworks: SwiftUI, the Observation framework, TextKit 2 and Swift concurrency are mature enough to carry a complete writing tool, so MacMarkDown is written from scratch in pure Swift and SwiftUI. This document audits the codebase against Swift 6.4 requirements and best practices: strict concurrency, `Sendable` conformance, data-race safety, Observation usage, and the test strategy that keeps all of the above verifiable.

## 2. Strict Concurrency

### 2.1 Audit Items

| # | Check | Status | Notes |
|---|-------|--------|-------|
| SC-01 | All `@MainActor`-isolated types are correctly annotated | ✅ PASS | `MarkdownDocument`, `DocumentSession`, `Preferences`, `MarkdownParser`, `RenderService`, `FindController`, `ScrollSyncService`, `PlugInManager` and `MarkdownTextView` are explicitly annotated; `MarkdownEditorView` and `MarkdownPreviewSurface` inherit main-actor isolation from `NSViewRepresentable` |
| SC-02 | No mutable shared state without isolation | ✅ PASS | Every mutable store is either `@MainActor`-isolated or a `let` constant |
| SC-03 | `Sendable` closures passed to background tasks | ✅ PASS | The autosave `Task` in `MarkdownDocument` and the debounced work items in `RenderService` capture `@MainActor` state only weakly |
| SC-04 | `nonisolated(unsafe)` usage reviewed and justified | ⚠️ REVIEW | 6 instances: `NSCache` stores (`CodeSyntaxHighlighter`, `MarkdownView`), an Objective-C delegate forwarder (`UnsavedChangesGuard`) and notification-observer tokens (`MarkdownPreviewSurface`) |
| SC-05 | No `@preconcurrency import` without justification | ✅ PASS | No `@preconcurrency` imports exist; the AppKit boundary is `@MainActor`-isolated |
| SC-06 | Strict concurrency mode enabled in build settings | ✅ PASS | `SWIFT_STRICT_CONCURRENCY = complete` in every target |
| SC-07 | No compiler warnings related to concurrency | ✅ PASS | Clean build verified 2026-09-15 |
| SC-08 | `TaskLocal` values are `Sendable` | ✅ PASS | N/A — no `TaskLocal` usage |

### 2.2 Concurrency Isolation Map

```
┌──────────────────────────────────────────────────────────┐
│                        @MainActor                        │
│   MarkdownDocument   DocumentSession   Preferences       │
│   RenderService      MarkdownParser    MarkdownTextView  │
│   ScrollSyncService  FindController    PlugInManager     │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│                  Sendable Value Types                    │
│   MarkdownElement       ParsedDocument   DocumentAnchor  │
│   MarkdownParseOptions  EditorTheme      Theme           │
│   CodeHighlightTheme                                     │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│                 Nonisolated / Pure Helpers               │
│   FontResolver   StringExtensions   EditorFormatting     │
└──────────────────────────────────────────────────────────┘
```

## 3. Sendable Conformance

### 3.1 Audit Items

| # | Check | Status | Notes |
|---|-------|--------|-------|
| SE-01 | All model types conform to `Sendable` | ✅ PASS | `MarkdownElement`, `ParsedDocument`, `DocumentAnchor`, `MarkdownParseOptions`, `EditorTheme`, `Theme`, `CodeHighlightTheme` and `FrontMatter` all conform |
| SE-02 | Enum types with associated values are `Sendable` | ✅ PASS | `MarkdownElement`, `InlineElement` and `FrontMatterValue` carry only `Sendable` payloads |
| SE-03 | Struct types with `Sendable` properties are implicitly `Sendable` | ✅ PASS | Verified for all value types |
| SE-04 | `@Observable` classes have a documented `Sendable` strategy | ⚠️ REVIEW | `Preferences`, `MarkdownDocument`, `RenderService`, `FindController`, `ScrollSyncService` and `RecentDocumentsStore` are classes with shared state; they rely on `@MainActor` isolation instead of a `Sendable` conformance |
| SE-05 | `actor` types used where appropriate | ℹ️ INFO | No actors needed — every mutable store is `@MainActor`-isolated |
| SE-06 | `nonisolated` members on `@MainActor` types reviewed | ✅ PASS | Only pure helpers (`FontResolver`), the `MarkdownView` equality check and Objective-C callbacks are `nonisolated` |
| SE-07 | Closure captures in concurrent contexts are `Sendable` | ✅ PASS | Verified by the strict concurrency compiler checks |

### 3.2 Sendable Compliance Table

| Type | Kind | `Sendable` | Mechanism |
|------|------|------------|-----------|
| `MarkdownElement` | indirect enum | ✅ Yes | Explicit conformance; all payloads are value types |
| `ParsedDocument` | struct | ✅ Yes | Implicit (all stored properties are `Sendable`) |
| `DocumentAnchor` | struct | ✅ Yes | Implicit |
| `MarkdownParseOptions` | struct | ✅ Yes | Implicit |
| `EditorTheme` | struct | ✅ Yes | Implicit |
| `Theme` | struct | ✅ Yes | Implicit |
| `CodeHighlightTheme` | struct | ✅ Yes | Implicit |
| `FrontMatter` | struct | ✅ Yes | Implicit |
| `MarkdownDocument` | class | ✅ Yes | `@MainActor` isolated + `@Observable` |
| `Preferences` | class | ✅ Yes | `@MainActor` isolated + `@Observable` |
| `FindController` | class | ✅ Yes | `@MainActor` isolated + `@Observable` |
| `ScrollSyncService` | class | ✅ Yes | `@MainActor` isolated + `@Observable` |
| `MarkdownParser` | class | ✅ Yes | `@MainActor` isolated; `@unchecked Sendable`, synchronous and stateless between calls |
| `RenderService` | class | ✅ Yes | `@MainActor` isolated; `@unchecked Sendable`, debounced work runs on the main queue |
| `Renderer` | class | ✅ Yes | `@MainActor` isolated; `@unchecked Sendable`, output is assigned in one step |

## 4. Data Race Safety

### 4.1 Render Pipeline Analysis

```
User types text
       │
       ▼
┌──────────────────┐     ┌─────────────────┐     ┌────────────────┐
│ MarkdownDocument │────▶│ RenderService   │────▶│ MarkdownParser │
│   (MainActor)    │     │   (MainActor)   │     │  (MainActor)   │
└──────────────────┘     └─────────────────┘     └───────┬────────┘
                                                         │
                                                ParsedDocument
                                                         │
                        ┌────────────────────────────────┤
                        │                                │
                        ▼                                ▼
                ┌────────────────┐               ┌────────────────┐
                │  MarkdownView /│               │   Renderer     │
                │  Attributed-   │               │  (MainActor)   │
                │  Renderer      │               │  → export HTML │
                │  (MainActor)   │               └────────────────┘
                └───────┬────────┘
                        │ tables / math
                        ▼
                ┌────────────────┐
                │ PreviewWeb-    │
                │ BlockView      │
                │  (MainActor)   │
                └────────────────┘
```

### 4.2 Audit Items

| # | Check | Status | Notes |
|---|-------|--------|-------|
| DR-01 | No concurrent writes to shared mutable state | ✅ PASS | All writes occur on `@MainActor` |
| DR-02 | Parser is called from a `@MainActor` context | ✅ PASS | `MarkdownParser.parse(_:options:)` is synchronous and main-actor bound, so a parse cannot interleave with a UI update |
| DR-03 | HTML generation does not share mutable state across tasks | ✅ PASS | `Renderer` builds HTML from an immutable `ParsedDocument`; the finished string is assigned in one step |
| DR-04 | Preview pane update is single-threaded | ✅ PASS | `MarkdownView` and the TextKit 2 preview update on the main actor; WebKit block heights arrive through a `WKScriptMessageHandler` and are applied there |
| DR-05 | File I/O uses appropriate isolation | ⚠️ REVIEW | `MarkdownDocument.load(from:)` and `save(to:checkConflict:)` currently perform file I/O on the main actor; moving them to structured concurrency with `sending` values is planned |
| DR-06 | No unprotected access to attributed-text buffers | ✅ PASS | Attributed preview strings are built locally in `AttributedRenderer` and published by value |
| DR-07 | Undo manager integration is `@MainActor`-safe | ✅ PASS | `NSUndoManager` registration happens inside `MarkdownTextView` editing, on the main actor |

## 5. @Observable Macro Usage

### 5.1 Replacing KVO with Observation

MacMarkDown carries no Objective-C KVO bookkeeping. All shared UI state is expressed with Swift's `@Observable` macro (introduced with macOS 14 and Swift 5.9) and consumed directly by SwiftUI:

| Classic AppKit pattern | MacMarkDown pattern |
|------------------------|---------------------|
| `@objc dynamic var text: String` plus observers | `@Observable var text: String` in `MarkdownDocument` |
| `addObserver(_:forKeyPath:...)` | Automatic change tracking by SwiftUI |
| `observeValue(forKeyPath:...)` | `onChange(of:)` / `.task(id:)` where a side effect is required |
| Manual observer registration and removal | Observation lifetime scoped to the view body |

### 5.2 Audit Items

| # | Check | Status | Notes |
|---|-------|--------|-------|
| OB-01 | All observable state uses the `@Observable` macro | ✅ PASS | `Preferences`, `MarkdownDocument`, `RenderService`, `FindController`, `ScrollSyncService` and `RecentDocumentsStore`; no KVO registrations remain |
| OB-02 | No `@Published` usage | ✅ PASS | `@Published` is not used anywhere |
| OB-03 | `@Observable` classes are `@MainActor`-isolated | ✅ PASS | Every observable class is annotated |
| OB-04 | Fine-grained observation has no performance regressions | ⚠️ REVIEW | `RenderService` publishes several properties; `MarkdownView` is `Equatable` and applied with `.equatable()`, so scroll-only changes never rebuild the element tree |
| OB-05 | Observation consumers treat state as read-only | ✅ PASS | View bodies read state; mutations go through methods on `MarkdownDocument`, `Preferences` and `FindController` |
| OB-06 | No retain cycles in observation-driven callbacks | ✅ PASS | Services are owned by the document/view hierarchy; callbacks capture weakly |

### 5.3 @Observable State Inventory

```swift
@MainActor @Observable
public final class RenderService: @unchecked Sendable {
    public private(set) var elements: [MarkdownElement] = []   // Consumed by: MarkdownView / MarkdownPreviewSurface
    public private(set) var anchors: [DocumentAnchor] = []     // Consumed by: ScrollSyncCoordinator
    public private(set) var renderedHTML: String = ""          // Consumed by: HTML export / clipboard
    public private(set) var isRendering = false                // Consumed by: render status UI
    public private(set) var lastError: String?                 // Consumed by: render status UI
}
```

**Optimization note**: The preview element tree is a pure function of `[MarkdownElement]` and the theme. Because `MarkdownView` implements `Equatable` and is applied with `.equatable()`, changing only the scroll position re-evaluates the parent body but does not rebuild the element tree.

## 6. Test Strategy

### 6.1 Audit Items

| # | Check | Status | Notes |
|---|-------|--------|-------|
| ST-01 | Every unit test suite runs under XCTest with typed expectations | ✅ PASS | 29 test files under `MacMarkDown/Tests` |
| ST-02 | UI- and state-bound suites are `@MainActor`-isolated | ✅ PASS | e.g. `MarkdownTextViewTests`, `AttributedRendererTests`, `ScrollSyncServiceTests`, `FindControllerTests` |
| ST-03 | Tests build fresh fixtures and tear them down | ✅ PASS | Settings suites use dedicated `UserDefaults` suites; shared stores and queues are reset between cases |
| ST-04 | Environment-dependent tests skip instead of failing | ✅ PASS | `XCTSkip` guards missing fonts and headless window servers (`FontResolverTests`, `AttributedRendererTests`, `MarkdownTextViewTests`) |
| ST-05 | Parser and editor coverage includes edge cases | ✅ PASS | `MarkdownParserTests`, `FrontMatterTests`, `SyntaxHighlighterTests`, `EditorSmartEditingTests` |
| ST-06 | Scroll-sync mapping is covered in both directions | ✅ PASS | `ScrollSyncServiceTests` (forward mapping, clamping, proportional fallback) and `ScrollSyncCoordinatorTests` |
| ST-07 | Data-safety paths are covered | ✅ PASS | `MarkdownDocumentAutosaveTests`, `DocumentSessionTests`, `UnsavedChangesGuardTests`, `DocumentOpenQueueTests` |

### 6.2 Coverage Map

| Area | Suites |
|------|--------|
| Parsing | `MarkdownParserTests`, `FrontMatterTests`, `StringExtensionsTests` |
| Preview rendering | `AttributedRendererTests`, `InlineStyleRenderingTests`, `PreviewRenderingTests`, `PreviewSupportTests`, `TablePreviewHTMLTests`, `MathPreviewHTMLTests` |
| Editor | `MarkdownTextViewTests`, `MarkdownTextViewHostTests`, `MarkdownTextViewStandardEditingTests`, `MarkdownEditorCoordinatorTests`, `EditorFormattingTests`, `EditorOperationsTests`, `EditorSmartEditingTests`, `SyntaxHighlighterTests`, `FindControllerTests` |
| Documents and data safety | `MarkdownDocumentAutosaveTests`, `DocumentSessionTests`, `DocumentOpenQueueTests`, `RecentDocumentsStoreTests`, `UnsavedChangesGuardTests`, `ScriptableDocumentTests` |
| Scroll sync | `ScrollSyncServiceTests`, `ScrollSyncCoordinatorTests` |
| Themes and preferences | `EditorThemeStyleFileTests`, `PreferencesTests`, `FontResolverTests` |

## 7. Known Limitations

### 7.1 SwiftUI ↔ TextKit 2 Bridge

| ID | Limitation | Impact | Mitigation |
|----|-----------|--------|------------|
| NL-01 | `NSViewRepresentable` is the boundary between SwiftUI and the custom TextKit 2 editor (`MarkdownEditorView` hosting `MarkdownTextView`) | Medium | View and coordinator are `@MainActor`-isolated; callbacks hop back to the main actor |
| NL-02 | `updateNSView()` has no `sending` parameters | Low | State crosses the boundary as value types (`String`, `EditorTheme`, `NSRange`) |
| NL-03 | `makeNSView()` must return synchronously | Low | `MarkdownTextView` initializes entirely on the main actor; no async setup is required |
| NL-04 | `NSViewRepresentable` conforming types cannot be `Sendable` | Low | `@MainActor` isolation makes this a non-issue in practice |

### 7.2 WKWebView Integration

| ID | Limitation | Impact | Mitigation |
|----|-----------|--------|------------|
| NL-05 | Web-block height reporting is not `async`-safe by default | Medium | `PreviewWebBlockView` receives heights through a `WKScriptMessageHandler` and applies them on the main actor |
| NL-06 | Script and page injection require the main thread | Low | Web blocks are loaded once per content key from `@MainActor` code |

### 7.3 Rendering and Layout Performance

| ID | Limitation | Impact | Mitigation |
|----|-----------|--------|------------|
| NL-07 | Every edit re-parses the whole document | Medium | 300 ms debounce with cancellation in `RenderService`; viewport-only fragment layout in `MarkdownTextView` |
| NL-08 | Native text has no built-in code highlighting | High | `MarkdownSyntaxHighlighter` colors the editor text storage; `CodeSyntaxHighlighter` + `CodeHighlightTheme` color preview code blocks — pure Swift, no web view |
| NL-09 | TextKit 2 cannot lay out table grids or TeX | High | Sized placeholder attachments covered by `PreviewWebBlockView`; reported heights are fed back into the text layout |

### 7.4 macOS 26 API Availability

| ID | Limitation | Impact | Mitigation |
|----|-----------|--------|------------|
| NL-10 | TextKit 2 continues to evolve across OS releases | Medium | The editor owns its full text stack behind `MarkdownTextView`, isolating the rest of the app |
| NL-11 | Some `AttributedString` APIs require macOS 15+ | Low | The target is macOS 26 — no fallback paths are needed |
| NL-12 | Swift 6.4.x may add new strict-concurrency diagnostics | Medium | Track release notes and address them promptly |

## 8. Compliance Checklist Summary

### 8.1 Pass Items (30)

- SC-01 through SC-03, SC-05 through SC-08
- SE-01 through SE-03, SE-06, SE-07
- DR-01 through DR-04, DR-06, DR-07
- OB-01 through OB-03, OB-05, OB-06
- ST-01 through ST-07

### 8.2 Review Items (4)

- SC-04: `nonisolated(unsafe)` usage (6 instances, all justified)
- SE-04: `@MainActor` isolation strategy for `@Observable` classes
- DR-05: File I/O isolation strategy
- OB-04: Observation granularity for large documents

### 8.3 Info Items (1)

- SE-05: No actor types — main-actor isolation covers every mutable store

### 8.4 Fail Items (0)

No hard failures. All code compiles and passes with strict concurrency enabled.

## 9. Action Items

| # | Item | Priority | Owner | Target |
|---|------|----------|-------|--------|
| AI-01 | Comment the rationale for every `nonisolated(unsafe)` member | Low | Core Team | Sprint 2 |
| AI-02 | Move document load/save off the main actor with structured concurrency and `sending` values | Medium | Core Team | Sprint 3 |
| AI-03 | Add performance baselines for `MarkdownParser`, `MarkdownTextView` viewport layout and `MarkdownSyntaxHighlighter` | Medium | Core Team | Sprint 3 |
| AI-04 | Cover `PreviewWebBlockView` with layout tests and keep the WebKit surface limited to table/math blocks | Medium | Core Team | Sprint 3 |
| AI-05 | Add a CI check that treats new strict-concurrency diagnostics as failures | Low | Core Team | Sprint 4 |

## 10. Sources

- [Swift Evolution SE-0302: Sendable and @Sendable closures](https://github.com/apple/swift-evolution/blob/main/proposals/0302-sendable-and-sendable-closures.md)
- [Swift Evolution SE-0304: Structured Concurrency](https://github.com/apple/swift-evolution/blob/main/proposals/0304-structured-concurrency.md)
- [Apple Documentation: Adopting Swift concurrency](https://developer.apple.com/documentation/swift/adopting-swift-concurrency)
- [Apple Documentation: Observation](https://developer.apple.com/documentation/observation)
- [Apple Documentation: TextKit](https://developer.apple.com/documentation/appkit/textkit)

---

*This audit is a living document. It will be updated as the project progresses through development sprints.*

*Last updated: 2026-09-15*
