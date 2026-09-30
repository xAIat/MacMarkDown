# RFC-003: Editor Integration Architecture

| Field       | Value                          |
|-------------|--------------------------------|
| RFC         | 003                            |
| Title       | Editor Integration Architecture|
| Author      | MacMarkDown Core Team          |
| Status      | Draft                          |
| Created     | 2026-09-15                     |
| Updated     | 2026-09-15                     |

---

## 1. Summary

This RFC defines the architecture of the MacMarkDown editor: the text surface itself,
the TextKit 2 layout stack behind it, the editing pipeline, formatting and smart
editing, IME/CJK input, selection, accessibility, plug-ins, and the way the editor is
hosted in SwiftUI and synchronized with the preview pane.

macOS 26 and Swift 6.4 opened a new era for Apple's developer frameworks: SwiftUI, the
Observation framework, TextKit 2 and Swift concurrency became mature enough to carry a
complete writing tool. MacMarkDown is written from scratch in pure Swift and SwiftUI,
and the editor is the component where that decision shows most clearly. It is not a
wrapped stock text control: it is a custom TextKit 2 view, `MarkdownTextView`, that
owns its `NSTextContentStorage`, layout manager and text container; renders through
`NSTextViewportLayoutController` with one view per visible layout fragment; handles
input, IME composition, selection, formatting, drag and drop, spell checking, read
aloud and accessibility; and is embedded in SwiftUI by `MarkdownEditorView`.

The application targets macOS 26 and is built against the macOS 27 SDK, so the editor
is designed directly on the current TextKit 2 surface rather than on compatibility
shims.

## 2. Motivation

A writing tool needs layout details that a declarative text control does not expose.
The editor has to resolve caret geometry on soft-wrapped lines, place a line-number
gutter, print invisible characters, measure scroll anchors for the preview, size
attachments and produce segment rectangles for a selection highlight. Owning the text
stack is the only way to expose all of that with one consistent coordinate space.

The other requirements that shaped the design:

- **Text input is not only typing.** Composition (IME) events, marked text, the
  candidate window, key bindings and the Services menu all arrive through AppKit's
  input and responder machinery. The editor implements `NSTextInputClient` and the
  relevant `NSResponder` actions directly, so Japanese, Chinese and Korean input is a
  first-class path rather than a fallback.
- **Large documents must stay cheap.** Layout is lazy and viewport-based: only the
  visible band plus a prefetch margin is laid out, and fragment views are cached and
  recycled. Content height is measured only when text or wrap width changes, and
  measurement is deferred while the user is live-scrolling or live-resizing.
- **Strict concurrency is the default.** All view state is `@MainActor`-isolated.
  AppKit's text protocols are not actor-isolated, so their conformances are declared
  isolated (SE-0466) and the compiler enforces the boundary.
- **One engine, two panes.** The preview uses the same read-only TextKit 2 surface, so
  whole-document selection, copy and anchor measurement come from the same layout
  engine as the editor.
- **Testability.** A protocol seam, `EditorTextViewHost`, lets smart-editing helpers
  and the SwiftUI coordinator run against the editor view or a plain `NSTextView`
  without a host application, and the editor can drive a full layout pass headlessly.

## 3. Architecture Overview

```
NSScrollView
└── MarkdownTextView (flipped NSView, the document view)
    └── contentView (CATiledLayer)
        ├── selectionView  ──  MarkdownSelectionHighlightView × n
        └── contentViewportView (CATiledLayer)
            └── MarkdownTextFragmentView per visible layout fragment
                └── attachment views (images, tables, web blocks)

TextKit 2 stack, owned by MarkdownTextView:

  NSTextContentStorage ──▶ MarkdownTextLayoutManager ──▶ NSTextContainer
        (NSTextStorage)          (NSTextLayoutManager)         (width tracks the view)
                                        │
                                        └── NSTextViewportLayoutController
                                            (visible band + prefetch)
```

| Component | Role |
|-----------|------|
| `MarkdownTextView` | `NSView` that owns the TextKit 2 stack and the entire editing surface |
| `NSTextContentStorage` | Document storage and `NSTextContentManager` |
| `MarkdownTextLayoutManager` | Custom `NSTextLayoutManager`; the seam for layout-time rendering work |
| `NSTextContainer` | Width tracks the view; zero line-fragment padding; unbounded height |
| `NSTextViewportLayoutController` | Lays out the visible band and asks for fragment views |
| `MarkdownTextFragmentView` | Draw surface for one layout fragment; hosts attachment views |
| `MarkdownTextLayoutFragment` | Fragment subclass that can draw invisible characters |
| `MarkdownContentView` / `MarkdownContentViewportView` | `CATiledLayer`-backed containers that keep redraw cost bounded |
| `MarkdownSelectionView` | Pooled highlight bands drawn below the glyphs |
| `MarkdownGutterView` | Line-number gutter in the document coordinate space |
| `MarkdownEditorView` | SwiftUI `NSViewRepresentable` host and coordinator |
| `EditorTextViewHost` | Protocol seam for the coordinator, smart editing and highlighting |
| `EditorFormatting` / `EditorOperations` | Pure formatting commands shared by the toolbar and the Format menu |
| `MarkdownSyntaxHighlighter` | Theme-driven syntax highlighting over the text storage |

## 4. The TextKit 2 Stack

### 4.1 Ownership and wiring

`MarkdownTextView` creates and owns every layer of the stack:

```swift
textLayoutManager.textContainer = textContainer
textContentStorage.addTextLayoutManager(textLayoutManager)
textContentStorage.primaryTextLayoutManager = textLayoutManager
textLayoutManager.textViewportLayoutController.delegate = self
```

`textContainer.widthTracksTextView = true` keeps the wrap width tied to the view's
width (minus the user's content insets), and `lineFragmentPadding` is set to zero so
the layout origin and the view's coordinate space agree exactly. The
`NSTextViewportLayoutController` delegate is the view itself: it creates, caches and
recycles one `MarkdownTextFragmentView` per `NSTextLayoutFragment`.

Owning the stack is what makes the rest of the editor possible. Layout-time behavior
can be changed by subclassing the layout manager or the layout fragment without the
host view knowing, and the view can drive `layoutViewport()`, relocate the viewport in
O(1), and run the same pipeline headlessly in unit tests.

### 4.2 Viewport layout and fragment views

The view lays out only what the user can see plus a prefetch band (half a viewport
above and below the visible area), so scrolling a long document stays linear in the
visible content, not in document size. Fragment views are held in a weak map keyed by
`NSTextLayoutFragment`; at the end of every viewport pass the views that were not
reused are removed and dropped from the map.

The containers are `CATiledLayer`-backed, which bounds the redraw cost of a very long
document. Two consequences are deliberate:

- The selection highlight lives in a dedicated, non-tiled view between the tiled
  container and the fragment views, because a tiled layer ignores ordinary
  `needsDisplay` invalidation. It pools small band views and rebuilds them from the
  layout manager's `.selection` segment frames.
- WebKit-backed blocks (tables and math) are placed in an overlay host on the document
  view rather than inside the tiled fragment host, because a hosted `WKWebView` does
  not composite reliably inside a tiled layer.

`MarkdownTextFragmentView` also lays out any `NSTextAttachmentViewProvider` views that
belong to its fragment, which is how images, tables and web blocks take part in the
normal text flow.

### 4.3 The layout manager as a rendering seam

`MarkdownTextLayoutManager` currently keeps the standard TextKit 2 pipeline (with
`usesFontLeading` enabled), but it exists to be the hook for a later rendering pass:
hiding emphasis markers, drawing inline image placeholders and softening hard wraps
can all be implemented at layout time without changing the host view. The custom
`MarkdownTextLayoutFragment` is the first consumer of that idea — when invisible
characters are enabled, it draws a symbol for each space, tab and line separator on
top of the laid-out text.

### 4.4 Content sizing and scrolling

The document view's height follows the layout:

- On a text or wrap-width change (`needsFullHeightMeasurement`), the view forces one
  full `ensureLayout` pass so the scrollable range is exact; a partial estimate that
  grows later would move every scroll anchor.
- On a pure scroll, the existing estimate is reused rather than re-laying out the
  whole document.
- While the user is live-scrolling or live-resizing, measurement is deferred so the
  frame does not jitter under the pointer.
- When "Scrolls past end" is enabled, one viewport-height of trailing space is kept
  below the last line, and when the document shrinks the scroll origin is clamped
  back into range.

Scrolling to a location first checks the current viewport; if the target is outside
it, the viewport anchor is relocated directly instead of laying out everything in
between, and the target segment frame is then brought into view. `centerSelectionInVisibleArea(_:)`
gives Find and go-to behavior a centered result without extra layout work.

## 5. Editing Pipeline

### 5.1 Mutation core and undo

Every edit — typing, IME commits, formatting commands, find/replace, drag and drop,
accessibility writes — funnels through a single replacement primitive:

```swift
func replaceCharacters(in range: NSTextRange, with replacement: NSAttributedString) {
    textContentStorage.performEditingTransaction {
        textStorage?.replaceCharacters(
            in: textContentStorage.range(from: range),
            with: replacement
        )
    }
    registerUndo(for: range, replacement: replacement)
    needsFullHeightMeasurement = true
    needsLayout = true
}
```

The replacement runs inside an editing transaction so the layout manager, the viewport
and `textSelections` stay consistent. Writes go through the backing `NSTextStorage`
rather than the content storage's whole-document replacement, which keeps empty and
non-empty documents on the same path under the macOS 27 SDK. Each edit registers an
undo action that replays the same primitive, and typing runs are coalesced so
`⌘Z`/`⇧⌘Z` walk back natural editing steps.

Two host hooks let the surrounding app intervene without knowing the text stack:

- `shouldChangeTextHandler` — offered every prospective edit; returning `false` vetoes
  it (used by smart editing and by the coordinator).
- `doCommandHandler` — consulted before the default `NSResponder` action runs.

When a document is loaded, saved-as or reverted, the coordinator bumps an
`undoResetGeneration`; the editor replaces the whole buffer and clears its undo
history instead of recording the load as an undoable diff. Edits driven by the model
(for example a Format command) are applied as minimal undoable replacements so they
behave like any other editing step.

### 5.2 Keyboard input and IME

Text input arrives through `interpretKeyEvents(_:)`, which the view routes to its
`NSResponder` actions; committed text arrives through the `NSTextInputClient`
conformance:

- `insertText(_:replacementRange:)` unmarks any composition, resolves the target
  ranges and applies the replacement through the mutation core.
- `setMarkedText(_:selectedRange:replacementRange:)`, `unmarkText()`,
  `markedRange()` and `hasMarkedText()` implement composition. Provisional text is
  stored separately from the committed selection so the input method can revise it in
  place; typed attributes are merged with the marked-text attributes
  (a single underline by default), and any invisible underline color supplied by the
  input method is removed before display.
- `firstRect(forCharacterRange:actualRange:)` and `characterIndex(for:)` place the
  candidate window and resolve screen points back to document offsets.
- `attributedSubstring(forProposedRange:actualRange:)`, `attributedString()` and
  `validAttributesForMarkedText()` complete the contract.

Undo registration is suppressed while composition is live, so a single undo step
covers a committed composition rather than each provisional revision. Matching-pair
completion is skipped inside marked ranges, which keeps IME input from being
auto-completed mid-composition.

### 5.3 Selection and insertion point

Selection state lives in the layout manager's `textSelections` as `NSTextSelection`
values and is driven by both the pointer and the keyboard:

- Click, drag, double-click, triple-click and shift-click update the selection through
  `NSTextSelectionNavigation`; an anchor is held for the duration of a pointer
  selection session.
- Pressing inside an existing selection only starts a drag-out session after the
  pointer is held past a short threshold; a quicker drag extends the selection instead.
- The highlight is rendered as post-processed bands under the text (see 4.2). The
  caret is an `NSTextInsertionIndicator` placed at the empty selection in content
  coordinates, so scrolling moves it for free.
- Keyboard navigation (arrows, word movement, Home/End, page movement) goes through
  the same navigation object, so movement semantics match the rest of the system.

### 5.4 Standard editing commands

Because the editor is an `NSView` rather than an `NSTextView`, AppKit's standard
editing actions are implemented explicitly:

- Clipboard: Cut, Copy, Paste, Delete, Select All, with copy writing plain text, RTF
  and HTML so pasting into rich targets keeps formatting.
- Navigation and deletion: `moveLeft/Right/Up/Down`, word and line variants,
  `deleteForward/Backward`, `deleteWordBackward`, page movement, and the other
  actions produced by `interpretKeyEvents(_:)`.
- Find actions surface to the surrounding document UI through `onFindAction`.
- Capitalization (`capitalizeWord`, `lowercaseWord`, `uppercaseWord`), the Fonts panel
  (`changeFont`), and `centerSelectionInVisibleArea(_:)` complete the responder
  surface.

## 6. Formatting Commands

Formatting is modelled as a closed set of commands, so the toolbar and the Format menu
can share one implementation:

```swift
public enum EditorFormatCommand: String, Sendable, CaseIterable {
    case paragraph, h1, h2, h3, h4, h5, h6
    case strong, emphasis, inlineCode, strikethrough
    case underline, highlight, comment
    case unorderedList, orderedList, blockquote, codeBlock
    case link, image
    case indent, unindent
    case newParagraph
}
```

`EditorFormatting.apply(_:to:selection:listMarker:tabPadding:)` is a pure function
over the plain text and a UTF-16 selection. It returns the new text and the selection
to restore, or `nil` for an invalid selection. Internally it calls `EditorOperations`,
a collection of string transformations that are testable without any text view:

- `toggleMarkup` — wraps or unwraps a selection with a prefix/suffix pair
  (`**`, `*`, `` ` ``, `~~`, `_`, `==`, `<!--`), inserting a placeholder for an empty
  selection (link text, image alt text).
- `toggleBlock` — toggles a line-level construct (unordered list, ordered list,
  blockquote) across every line of the selection.
- `setHeaderLevel` — sets or clears heading levels.
- `indentLines` / `unindentLines` — indentation with the user's tab padding.

The list marker (`* `, `- ` or `+ `) and the tab padding come from preferences, and
both the toolbar and the Format menu call the same entry point, so a command cannot
behave differently depending on where it is triggered. The SwiftUI host applies the
result as a minimal undoable replacement, restores the reported selection, scrolls it
into view and reapplies syntax highlighting.

## 7. Smart Editing

Smart editing runs in the coordinator between the text view and the input events. Each
behavior is individually controlled by a preference:

| Trigger | Behavior |
|---------|----------|
| Opening bracket, quote or CJK punctuation | Inserts the matching close character and moves the caret between the pair, when the caret sits at a word boundary |
| Closing character when the next character is already the matching close | Moves the caret past it instead of inserting a duplicate |
| Backspace between a matched pair | Deletes both characters at once |
| Typing an opener with a selection | Wraps the selection in the pair (`*text*`, `` `code` ``, `【text】`, …) |
| Typing `*`, `_`, `` ` ``, `=`, or `~~` (when enabled) with a selection | Wraps the selection in that marker |
| Tab | Advances to the next 4-column tab stop with spaces, or indents every selected line |
| Shift-Tab | Removes one indentation level from each selected line |
| Backspace after 2–4 leading spaces on a tab stop | Removes a whole tab step |
| Return in a list item | Continues the list marker; ordered lists auto-increment; an empty item ends the list |
| Return in a blockquote | Continues the `> ` marker |
| Return in an indented line | Preserves the leading whitespace |
| Home | Moves to the first non-whitespace character; when already there, falls back to the line start |

The matching-character table covers ASCII brackets and quotes —
`()[]{}<>'"` — plus the CJK pairs `（）`, `「」`, `『』`, `‘’`, `“”`, `‹›`, `«»`, `〈〉`
and `《》`. Because the checks are boundary-aware, they do not fire in the middle of a
word, and they never fire inside an IME marked range.

"Smart Home" has one extra rule: it resolves the current and target offsets to their
line fragments first, and falls back to the standard Home behavior when the two
offsets sit on different visual rows. This keeps Home from jumping between wrapped
rows while still skipping leading indentation.

## 8. Editor Affordances

### 8.1 Line-number gutter

The gutter is a subview in the document coordinate space, so it scrolls with the
content and needs no scroll observer beyond the existing layout pass. Line start
offsets are cached per text-mutation generation and resolved with a binary search;
the gutter reserves its width on the left of the content insets.

### 8.2 Invisible characters

When enabled, the custom `MarkdownTextLayoutFragment` draws a placeholder symbol for
spaces, tabs, line feeds, carriage returns and other Unicode whitespace at the
segment frame of each character, on top of the normal text.

### 8.3 Spell checking, read aloud and Services

- Spelling uses `NSSpellChecker` ranges and draws dotted red underlines. The
  attributes live only in memory, so they never reach the saved file.
- Read aloud speaks the selection, or the whole document when nothing is selected,
  through `AVSpeechSynthesizer`.
- The view participates in the Services menu and can both provide and accept text
  through the pasteboard.

### 8.4 Drag and drop and attachments

Text drops insert at the caret under the pointer. File drops are intercepted before
the window's SwiftUI drop handling: dropping a document opens it in the app, and
dropping an image file inlines it as base64 Markdown. Selections can be dragged out
to other applications. Attachments are first-class text content, so images, tables
and embedded web blocks occupy real layout space and are laid out by their fragment
views.

### 8.5 Syntax highlighting

`MarkdownSyntaxHighlighter` applies the current `EditorTheme` to the text storage:
heading, emphasis, code, quote, link and marker runs get their theme colors while
font and paragraph style are preserved. Highlighting is reapplied after user edits,
after theme or font changes, and after document loads; because it re-applies attributes
across the document, it also flags a full height re-measure so the scroll range stays
correct.

### 8.6 Plug-ins

The editor exposes a small event API (`MarkdownPlugin`): a plug-in is registered with
`setUp(textView:events:)` and can observe `shouldChange`, `didChange` and
`didLayoutViewport` events, with `shouldChange` able to veto an edit. Plug-ins are
torn down with `tearDown()`. This is an in-process extension point for editor
behaviour; app-level plug-in bundles are described in the business overview.

## 9. Accessibility

`MarkdownTextView` is a plain `NSView`, so VoiceOver would see nothing useful without
explicit work. The view exposes itself as a text area with the standard geometry:

- Role, role description, label ("Text Editor"), enabled state and value.
- Shared character range; number of characters; visible character range.
- Selected text, selected text ranges, insertion point line number.
- Line ↔ range conversion (`accessibilityLine(for:)`, `accessibilityRange(forLine:)`).
- Frame for a range and range for a point, resolved through the layout manager's
  segment frames and typographic bounds.
- Attributed substring access for a range.

Because these APIs read from the same layout manager as the rest of the editor, they
stay correct across wrapping, scrolling and viewport recycling.

## 10. SwiftUI Hosting and Preview Integration

### 10.1 MarkdownEditorView

`MarkdownEditorView` is an `NSViewRepresentable` that builds an `NSScrollView` around
`MarkdownTextView` and keeps the two in step through a `Coordinator`:

- Applies font, line spacing, editor theme, content insets, spell checking, line
  numbers and invisible-character settings.
- Mirrors the smart-editing preferences (Smart Home, tab conversion, prefix
  insertion, list auto-increment, pair completion, strikethrough wrapping).
- Bridges selection in both directions, reports text changes by observing the text
  storage, and forwards Find actions and dropped files.
- Applies model-driven text and selection changes as undoable edits, and resets the
  undo history when the document layer signals a load or revert.
- Reapplies syntax highlighting after edits, theme changes and document loads.

### 10.2 Preview and synchronized scrolling

The preview pane is a read-only instance of the same TextKit 2 surface. That gives it
whole-document selection and copy, and it lets scroll anchors be measured directly
from the text layout instead of from geometry probes.

`ScrollSyncService` pairs the editor and the preview with a dense, ordered anchor
list produced by the parser — one anchor per block and list item, in document order.
Both panes measure a Y position for the same list, so the arrays pair by index and the
scroll offset is interpolated between the two anchors that bracket it. Sync is
editor → preview by default; when the bidirectional preference is enabled, the reverse
mapping is used as well. The reverse map is the exact inverse of the forward one,
computed by bisection, so the two panes cannot chase each other.

## 11. Concurrency Model

- `MarkdownTextView`, its extensions, the `MarkdownEditorView` coordinator, the
  syntax highlighter, `ScrollSyncService` and `Preferences` are all
  `@MainActor`-isolated. No background thread ever touches the text buffer.
- AppKit's text protocols are not actor-isolated. Their conformances
  (`NSTextViewportLayoutControllerDelegate`, `NSTextLayoutManagerDelegate`,
  `NSTextInputClient`, `NSDraggingSource`, `NSServicesMenuRequestor`) are declared
  `@MainActor`-isolated following SE-0466, which lets the compiler verify that the
  callbacks only run on the main actor.
- Values that cross actor boundaries are immutable and `Sendable`:
  `EditorFormatCommand`, the formatting result, the parsed element/anchor tree,
  themes and style values.
- Parsing and rendering services accept plain values and return plain values on the
  main actor; the editor observes their results through the document model rather
  than sharing mutable state.
- The project builds with Swift 6.4 strict concurrency enabled.

## 12. Testing Strategy

| Area | Test coverage |
|------|---------------|
| Viewport layout, content height, fragment recycling, insertion point | `MarkdownTextViewTests` — drives the real viewport pipeline headlessly via `performFullLayoutForTesting()` |
| Editing and standard commands | `MarkdownTextViewStandardEditingTests` |
| Coordinator/host bridging, model edits, undo resets | `MarkdownEditorCoordinatorTests`, `MarkdownTextViewHostTests` |
| Smart editing (pairs, tab steps, Return continuation, Smart Home) | `EditorSmartEditingTests` |
| Formatting commands | `EditorFormattingTests`, `EditorOperationsTests` |
| Syntax highlighting | `SyntaxHighlighterTests` |
| IME marked-text handling | `MarkdownTextViewTests` (`setMarkedText`, `unmarkText`, marked ranges) |
| Accessibility geometry | `MarkdownTextViewTests` |
| Scroll sync and anchors | `ScrollSyncServiceTests`, `ScrollSyncCoordinatorTests` |
| Large-document performance | XCTest `measure` harness over 10k+ line documents (planned) |

Editor behavior tests run against the real `MarkdownTextView` and the
`EditorTextViewHost` seam, so the formatting and smart-editing transformations stay
independent of any particular text view while the integration tests exercise the real
TextKit 2 stack.

## 13. Alternatives Considered

1. **SwiftUI `TextEditor`** — rejected. It exposes a binding and key hooks, but not
   caret geometry, line fragments, line-number placement, attachment sizing or scroll
   anchors; building the editor on it would have meant fighting the abstraction for
   every feature in this document.
2. **Subclassing `NSTextView`** — rejected. `NSTextView` keeps large parts of its
   rendering pipeline opaque, and the features planned for the layout layer (marker
   hiding, custom fragments, web-block hosting) need an owned TextKit 2 stack rather
   than another layer of overrides.
3. **A web-based editor (CodeMirror-style) in a `WKWebView`** — rejected. It would
   make the core editing surface non-native, complicate IME and accessibility, and
   split input handling between two engines.
4. **A third-party native text view package** — rejected. The text surface is the
   product's core; owning it avoids dependency risk and keeps the strict-concurrency
   model under this project's control.

## 14. Open Questions

1. **Incremental height measurement** — can the document height be estimated from the
   viewport's usage bounds without a full layout pass while keeping the scroll range
   stable enough for synchronization?
2. **Layout-time marker rendering** — what is the right seam for hiding emphasis
   markers inside a layout fragment while keeping the underlying characters
   selectable and editable?
3. **IME edge cases** — composition that starts at a list marker, composition that
   overlaps an auto-paired range, IME combined with undo, and candidate-window
   placement across soft-wrapped lines. Which of these can be covered by tests, and
   which need a manual matrix of CJK input methods?
4. **Attachment measurement** — when a web block (table or math) reports a new height
   after layout, can invalidation be scoped to the affected fragment instead of
   forcing a full re-measure?
5. **Plug-in API stability** — what compatibility guarantees should the
   `MarkdownPlugin` event surface offer across releases?
6. **Bidirectional sync** — how should the reverse mapping behave during momentum
   scrolling and rubber-banding to avoid feedback between the two panes?
7. **Performance budget** — what is the largest document we target for fully
   interactive typing (for example 5 MB / 100k lines), and is a full-height
   measurement still acceptable at that size?

## 15. References

- [NSTextLayoutManager](https://developer.apple.com/documentation/appkit/nstextlayoutmanager)
- [NSTextViewportLayoutController](https://developer.apple.com/documentation/appkit/nstextviewportlayoutcontroller)
- [NSTextInputClient](https://developer.apple.com/documentation/appkit/nstextinputclient)
- [Accessibility for AppKit](https://developer.apple.com/documentation/appkit/accessibility-for-appkit)
- [SE-0466: Control default actor isolation](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md)
- [swift-markdown Repository](https://github.com/apple/swift-markdown)
- [Yams Repository](https://github.com/jpsim/Yams)
- [Apple Human Interface Guidelines — Text Input](https://developer.apple.com/design/human-interface-guidelines/text-input)

Editor sources referenced in this RFC:

- `MacMarkDown/UI/macOS/Editor/MarkdownTextView/` — the TextKit 2 view and its extensions
- `MacMarkDown/UI/macOS/Editor/MarkdownEditorView.swift` — the SwiftUI host and coordinator
- `MacMarkDown/Services/Editor/` — formatting commands, smart editing and highlighting

---

*This document is part of the MacMarkDown design RFC series. See [RFC-001](./rfc-001-core-architecture.md) for the core architecture and [RFC-002](./rfc-002-rendering-pipeline.md) for the rendering pipeline design.*
