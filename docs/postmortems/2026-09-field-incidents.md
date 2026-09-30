# Field Incident Report — September 2026

**Project**: MacMarkDown  
**Report Date**: 2026-09-15  
**Report Type**: Proactive Risk Assessment (pre-implementation and early implementation)  
**Status**: Living risk register  
**Author**: MacMarkDown Core Team  

---

## 1. Executive Summary

macOS 26 and Swift 6.4 opened a new era for Apple's developer frameworks: SwiftUI, the Observation framework, TextKit 2 and Swift concurrency are mature enough to carry a complete writing tool, and MacMarkDown is written from scratch in pure Swift and SwiftUI for that era. This document is a proactive risk assessment written before and during the first implementation sprints. It records the field incidents most likely to occur while building the application, and every entry carries a severity, a likelihood, the affected component and a concrete mitigation that has been designed — and, where possible, already exercised — in the codebase.

**Overall Risk Level**: MEDIUM  
**Mitigation Confidence**: HIGH (every mitigation maps to a component that ships with tests)

## 2. Incident Catalog

### Incident 1: The Custom TextKit 2 Editor Is the Highest-Complexity Component

| Field         | Value                                |
|---------------|--------------------------------------|
| ID            | FI-2026-001                          |
| Severity      | HIGH                                 |
| Likelihood    | CERTAIN (design constraint)          |
| Component     | `MarkdownTextView` / `MarkdownEditorView` |
| Status        | ✅ MITIGATION IMPLEMENTED            |

#### Description

SwiftUI's `TextEditor` exposes a plain string binding and cannot apply Markdown-specific attributes, own the viewport or intercept file drops. A Markdown-aware writing surface therefore needs its own TextKit 2 stack: `MarkdownTextView` owns `NSTextContentStorage`, `MarkdownTextLayoutManager` and `NSTextContainer`, and implements display, selection, IME, drag & drop and smart editing on top of them. This is the largest and most failure-prone component in the app; a subtle bug in selection or text layout lands directly in the core writing experience.

**Impact**: If the custom view proves fragile or slow, the whole product feels fragile or slow — no amount of polish elsewhere compensates for a text editor that drops keystrokes or stutters while scrolling.

#### Mitigation

**Primary strategy: a dedicated view behind a narrow, testable surface**

The editor is isolated behind `MarkdownEditorView` (`NSViewRepresentable`) and the `EditorTextViewHost` protocol. The smart-editing helpers run against plain `NSTextView` in tests as well as against `MarkdownTextView` in the app, so behavior can be verified without a window.

```swift
@MainActor
final class MarkdownTextView: NSView {
    let textContentStorage = NSTextContentStorage()
    let textLayoutManager: NSTextLayoutManager = MarkdownTextLayoutManager()
    let textContainer = NSTextContainer()
}
```

**Viewport discipline**: fragments are created per visible `NSTextLayoutFragment` by `NSTextViewportLayoutController`; only the visible band is laid out and retained, so a long document scrolls as cheaply as a short one.

**Syntax highlighting stays out of the view**: `MarkdownSyntaxHighlighter` colors the text storage from the selected `EditorTheme`, so the highlight logic is a pure transformer with its own tests.

**Test coverage**: `MarkdownTextViewTests`, `MarkdownTextViewHostTests`, `MarkdownTextViewStandardEditingTests`, `MarkdownEditorCoordinatorTests`, `EditorSmartEditingTests`, `SyntaxHighlighterTests`.

#### Timeline

| Milestone                                                          | Target Date |
|--------------------------------------------------------------------|-------------|
| Text stack prototype (`NSTextContentStorage` → layout manager → container) | Sprint 1 |
| Viewport fragment caching                                          | Sprint 2    |
| Host and coordinator test suites                                   | Sprint 2    |
| Selection / IME / drag & drop hardening                            | Sprint 3    |
| Production release                                                 | Sprint 5    |

---

### Incident 2: Preview Fidelity for Tables, Math and CJK Typography

| Field         | Value                                      |
|---------------|--------------------------------------------|
| ID            | FI-2026-002                                |
| Severity      | MEDIUM                                     |
| Likelihood    | LIKELY                                     |
| Component     | `AttributedRenderer` / `MarkdownView` / `PreviewWebBlockView` |
| Status        | ✅ MITIGATION IMPLEMENTED                  |

#### Description

A fully native preview cannot render everything a Markdown document can contain. TextKit 2 has no table layout and no TeX engine, so tables and formulas collapse into approximations; CJK font families generally ship no italic face, so emphasis on Chinese text could silently render upright while Latin text slants; and handing the entire preview to a web view would abandon the native, SwiftUI-first rendering model. Each gap is visible to the user as wrong or inconsistent output between the preview and the exported HTML.

**Impact**: Documents with tables, formulas or CJK emphasis render incorrectly, or render differently in the preview and the export — exactly the content a technical writing tool is judged on.

#### Mitigation

**Strategy: native first, WebKit as a scalpel**

1. **Tables and math become placeholders.** `AttributedRenderer` reserves a sized `NSTextAttachment` for each table and formula. `PreviewWebBlockView` (a `WKWebView`) draws the real block over the placeholder and reports its content height back through a script message, so the text layout reserves the exact space. Table and math HTML comes from `TablePreviewHTML` and `MathPreviewHTML`, which reuse the export markup and the bundled MathJax, so preview and export share one source of truth.

```swift
@MainActor
final class PreviewWebBlockView: NSView {
    private let webView: WKWebView
    var onHeightChange: ((CGFloat) -> Void)?
}
```

2. **WebKit is limited to blocks that need it.** Every other element — headings, paragraphs, lists, quotes, code, images — is drawn natively by `MarkdownView` or `AttributedRenderer`. Diagram fences use the same web-block approach through `WebBlockView`.

3. **CJK emphasis gets a synthetic oblique.** When a family has no italic face, `FontResolver.syntheticItalic` shears it (about 12°, matching browser behavior). Both the SwiftUI preview (`MarkdownView`) and the attributed path (`AttributedRenderer`) apply it, so emphasis looks the same everywhere and line breaking is unaffected.

4. **Code highlighting is native.** `CodeSyntaxHighlighter` tokenizes source with cached regular expressions and `CodeHighlightTheme` supplies the palette; no JavaScript highlighter is loaded for the preview or the export.

5. **Tests pin the behavior**: `AttributedRendererTests`, `TablePreviewHTMLTests`, `MathPreviewHTMLTests`, `InlineStyleRenderingTests`, `PreviewRenderingTests`, `PreviewSupportTests`.

#### Timeline

| Milestone                                     | Target Date |
|-----------------------------------------------|-------------|
| Native renderer for block elements            | Sprint 1    |
| Table / math web blocks with height reporting | Sprint 2    |
| Synthetic italic for CJK emphasis             | Sprint 2    |
| Diagram web blocks                            | Sprint 3    |
| Preview/export consistency suite              | Sprint 3    |

---

### Incident 3: Scroll Sync Precision Across Heterogeneous Content

| Field         | Value                                      |
|---------------|--------------------------------------------|
| ID            | FI-2026-003                                |
| Severity      | MEDIUM                                     |
| Likelihood    | LIKELY                                     |
| Component     | `ScrollSyncService` / `ScrollSyncCoordinator` |
| Status        | ✅ MITIGATION IMPLEMENTED                  |

#### Description

The editor and the preview expand the same source text at very different rates: a ten-line code block may be shorter in the editor than in the preview, an image or table occupies preview pixels with no editor counterpart, and the preview's lazily measured heights settle only after the first layout pass. A naive line-to-pixel ratio therefore drifts, and a document whose measured height changes mid-scroll can make the preview jump or even reverse.

**Impact**: In long documents the preview lands on the wrong passage, which makes synchronized scrolling worse than no synchronization at all.

#### Mitigation

**Strategy: dense anchors with bracket interpolation**

1. `MarkdownParser` emits one `DocumentAnchor` per block and list item, in document order. Both panes measure the same ordered list — the editor from the text layout, the preview from its rendered surface — so the two arrays pair 1:1 by index.

2. A scroll offset is expressed as a percentage between the two anchors that bracket it and mapped onto the matching bracket in the other pane; past the last in-range anchor the mapping interpolates to the true end of the document.

3. During a live scroll gesture the coordinator freezes its mapping inputs (anchors and content heights) and re-measures only when the gesture ends, so a settling layout cannot move the target under the user's fingers.

4. Bidirectional sync, when enabled, is the exact inverse of the forward map (found by bisection) and programmatic echoes are suppressed, so the panes never fight.

```swift
public func previewOffset(forEditorOffset editorY: CGFloat,
                          editorContentHeight: CGFloat,
                          editorVisibleHeight: CGFloat,
                          previewContentHeight: CGFloat,
                          previewVisibleHeight: CGFloat) -> CGFloat
```

**Performance target**: scroll-sync latency below 30 ms (two frames at 60 fps), verified by `ScrollSyncServiceTests` and `ScrollSyncCoordinatorTests`.

#### Timeline

| Milestone                                   | Target Date |
|---------------------------------------------|-------------|
| Dense anchor emission in the parser         | Sprint 1    |
| Bracket interpolation and edge taper        | Sprint 2    |
| Live-gesture freezing                       | Sprint 2    |
| Bidirectional inverse and echo suppression  | Sprint 3    |
| Long-document testing                       | Sprint 3    |

---

### Incident 4: Large-Document Performance and Memory Churn

| Field         | Value                                      |
|---------------|--------------------------------------------|
| ID            | FI-2026-004                                |
| Severity      | HIGH                                       |
| Likelihood    | LIKELY (documents above ~200 KB)           |
| Component     | `RenderService` / `MarkdownTextView` / `@Observable` state |
| Status        | ✅ MITIGATION IMPLEMENTED                  |

#### Description

Every debounced edit re-parses the whole document in `RenderService`, rebuilding `[MarkdownElement]`, the anchor array and the attributed preview. `@Observable` then notifies every consumer of those properties. If the editor retained layout fragments for the entire document, or if scroll-position changes invalidated the preview's element tree, book-length documents would pay the full cost on every keystroke and every scroll tick — visible as typing lag, stutter and memory growth.

**Impact**: Typing latency and scroll stutter make large files (a novel chapter, a technical book) unpleasant or impossible to edit, and unbounded fragment retention turns scrolling into memory churn.

#### Mitigation

**Strategy: debounce, viewport-only layout, equatable views**

1. **Debounced rendering.** `RenderService.scheduleRender` waits 300 ms (`Constants.defaultDebounceInterval`) and cancels any in-flight work; a new keystroke restarts the window.

2. **Viewport-only layout.** `MarkdownTextView` lays out and caches fragments only for the visible band via `NSTextViewportLayoutController`; the rest of the document stays in text storage.

3. **Equatable render inputs.** `MarkdownView` implements `Equatable` and is applied with `.equatable()`, so changing only the scroll position re-evaluates the parent body but does not rebuild the element tree.

4. **Heights stay cached.** `AttributedRenderer` keeps the last height WebKit reported for each table and formula (`tableHeights`, `mathHeights`), so a re-render does not jump the layout back to an estimate.

5. **Performance budgets with tests and benchmarks.**

| Document Size | Max Keystroke Latency | Max Scroll Latency | Max Preview Update |
|---------------|-----------------------|--------------------|--------------------|
| < 50 KB       | 16 ms (1 frame)       | 16 ms              | 100 ms             |
| 50–200 KB     | 33 ms (2 frames)      | 33 ms              | 300 ms             |
| 200 KB–1 MB   | 50 ms (3 frames)      | 50 ms              | 500 ms             |
| > 1 MB        | 100 ms (degraded mode) | 100 ms            | 1000 ms            |

#### Timeline

| Milestone                                   | Target Date |
|---------------------------------------------|-------------|
| Debounced render scheduling                 | Sprint 1    |
| Viewport fragment caching                   | Sprint 1    |
| Equatable preview inputs                    | Sprint 2    |
| Height caching for web blocks               | Sprint 2    |
| Large-document benchmark suite              | Sprint 3    |
| Optimization pass for > 200 KB documents    | Sprint 4    |

---

### Incident 5: Autosave and Unsaved-Changes Data Safety

| Field         | Value                                      |
|---------------|--------------------------------------------|
| ID            | FI-2026-005                                |
| Severity      | HIGH                                       |
| Likelihood    | POSSIBLE                                   |
| Component     | `MarkdownDocument` / `DocumentSession` / `UnsavedChangesGuard` |
| Status        | ✅ MITIGATION IMPLEMENTED                  |

#### Description

A desktop editor owns the user's only copy of a file between saves. Three situations can lose or corrupt work: a pending edit lost on quit or crash; an autosave overwriting a file that another program has changed; and a close/quit prompt that cannot be answered synchronously because SwiftUI alerts are asynchronous. Multi-window editing adds a fourth: a guard or command acting on the wrong window's document.

**Impact**: Losing even a paragraph of a user's work is the most damaging failure a writing tool can have — far worse than any rendering glitch.

#### Mitigation

**Strategy: atomic writes, explicit autosave, synchronous guards**

1. `MarkdownDocument.save(to:checkConflict:)` writes atomically and, for manual saves, compares the on-disk contents with the last saved text; an external change throws `SaveError.fileChangedExternally` instead of overwriting it.

2. Autosave is opt-in and debounced with a cancellable `Task`; `DocumentSession.flushAutosave()` persists pending edits when the app quits, so the debounce window is never the difference between saved and lost.

3. `UnsavedChangesGuard` answers window close and app quit synchronously as the window delegate, while `DocumentSession` tracks the key document so the guard always inspects the right buffer.

4. Finder opens and URL-scheme opens are serialized through `DocumentOpenQueue`; recent documents are pruned by `RecentDocumentsStore` so a missing file never traps startup.

5. **Tests**: `MarkdownDocumentAutosaveTests`, `UnsavedChangesGuardTests`, `DocumentSessionTests`, `DocumentOpenQueueTests`, `RecentDocumentsStoreTests`, `ScriptableDocumentTests`.

#### Timeline

| Milestone                                   | Target Date |
|---------------------------------------------|-------------|
| Atomic save with conflict detection         | Sprint 1    |
| Close / quit guard                          | Sprint 1    |
| Debounced opt-in autosave                   | Sprint 2    |
| Quit-time flush and open queue              | Sprint 2    |
| Data-safety test hardening                  | Sprint 3    |

---

## 3. Risk Matrix

| ID  | Incident                                 | Severity | Likelihood | Risk Level | Mitigation Confidence |
|-----|------------------------------------------|----------|------------|------------|-----------------------|
| 001 | Custom TextKit 2 editor complexity       | HIGH     | CERTAIN    | 🔴 HIGH    | HIGH                  |
| 002 | Preview fidelity (tables / math / CJK)   | MEDIUM   | LIKELY     | 🟡 MEDIUM  | HIGH                  |
| 003 | Scroll-sync precision                    | MEDIUM   | LIKELY     | 🟡 MEDIUM  | HIGH                  |
| 004 | Large-document performance and memory    | HIGH     | LIKELY     | 🔴 HIGH    | HIGH                  |
| 005 | Autosave and unsaved-changes safety      | HIGH     | POSSIBLE   | 🟠 ELEVATED | HIGH                 |

## 4. Cross-Incident Dependencies

```
Incident 1 (editor complexity) ──┐
                                 ├──▶ shared constraint: viewport-only layout
Incident 4 (large documents) ────┘

Incident 2 (preview fidelity) ──▶ block heights ──▶ Incident 3 (scroll sync)

Incident 5 (data safety) ── independent ──▶ document layer, lands in Sprint 1
```

## 5. Implementation Order

Based on dependencies and criticality:

1. **Sprint 1**: Incident 4 foundations (debounced rendering, viewport layout) and Incident 5 (atomic save, close/quit guard)
2. **Sprint 2**: Incident 1 primary (text stack, fragment caching) and Incident 3 primary (dense anchors, bracket interpolation)
3. **Sprint 3**: Incident 2 mitigations (web blocks, CJK synthetic italic) and Incident 1 hardening (selection / IME / drag & drop)
4. **Sprint 4**: Cross-cutting performance pass for Incidents 1, 3 and 4
5. **Sprint 5**: Integration testing, edge cases and release readiness

## 6. Monitoring and Alerting

Once the application is in beta, we will monitor:

| Metric                        | Threshold          | Alert Action                  |
|-------------------------------|--------------------|-------------------------------|
| Keystroke-to-display latency  | > 50 ms            | Open performance investigation |
| Scroll-sync offset            | > 5 lines          | Open scroll-sync investigation |
| Preview render time           | > 500 ms           | Open preview investigation     |
| Memory usage (> 500 KB file)  | > 200 MB           | Open memory investigation      |
| Code highlight time           | > 100 ms           | Open highlighting investigation |

## 7. Lessons Learned (Anticipated)

These are the lessons we expect the implementation to confirm; they will be refined with real measurements:

1. **A plain `TextEditor` is not a Markdown writing surface.** Owning the TextKit 2 stack is the price of a first-class editor — and it must be isolated behind a narrow protocol so it can be tested.
2. **Observation needs equatable inputs.** Without `Equatable` view inputs, a scroll tick invalidates far more than the scroll position.
3. **WebKit is most valuable as a scalpel.** Tables, math and diagrams justify a web view; everything else is cheaper and more consistent when drawn natively.
4. **Dense anchors turn sync scrolling into a mapping problem** instead of a guessing game; heuristics should be the fallback, not the foundation.
5. **Data safety belongs in Sprint 1.** Atomic writes and close/quit guards are cheap to add early and very expensive to retrofit after users trust the app with their work.
6. **Performance budgets must be measured from the first sprint.** Waiting until the end makes every optimization a redesign.

---

*This document is a living risk register. It will be updated with actual measurements and, if an incident does occur, with a separate postmortem.*

*Last updated: 2026-09-15*
