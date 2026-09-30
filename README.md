<div align="center">

<img src="Resources/AppIcon.png" alt="MacMarkDown" width="128" height="128">

# MacMarkDown

**A native Markdown editor for macOS, written from scratch in pure Swift and SwiftUI.**

<!-- Language switcher: keep this line in sync with README.zh.md -->
**English** · [简体中文](README.zh.md)

![Platform](https://img.shields.io/badge/platform-macOS%2026%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)
![UI](https://img.shields.io/badge/UI-SwiftUI-0A84FF)
![License](https://img.shields.io/badge/license-MIT-2ea44f)
![Tests](https://img.shields.io/badge/tests-414%20passing-2ea44f)

</div>

macOS 26 and Swift 6.4 opened a new era for Apple's developer frameworks:
SwiftUI, the Observation framework, TextKit 2 and Swift concurrency are finally
mature enough to carry an entire writing tool. **MacMarkDown** was written for
that era — a native macOS document app with no cross-platform runtime, no
interface-builder files and no third-party parsing engine. Just Swift, SwiftUI
and Apple's frameworks from top to bottom.

It gives you a custom TextKit 2 editor beside a live native preview, a complete
Markdown toolbox, and the automation and export features a professional writing
workflow expects — all in a fast, local-first app that never asks for an
account or a network connection.

---

## Table of Contents

- [Why MacMarkDown](#why-macmarkdown)
  - [By the numbers](#by-the-numbers)
- [Features](#features)
  - [Writing](#writing)
  - [Live preview](#live-preview)
  - [Markdown support](#markdown-support)
  - [Export and automation](#export-and-automation)
  - [Customization](#customization)
- [Requirements](#requirements)
- [Getting started](#getting-started)
  - [Open in Xcode](#open-in-xcode)
  - [Build from the command line](#build-from-the-command-line)
  - [Regenerate the project](#regenerate-the-project)
  - [Project scripts](#project-scripts)
- [Usage](#usage)
  - [Keyboard shortcuts](#keyboard-shortcuts)
  - [Command-line tool](#command-line-tool)
  - [URL scheme](#url-scheme)
  - [AppleScript](#applescript)
  - [Plug-ins](#plug-ins)
- [Architecture](#architecture)
- [Documentation](#documentation)
- [Localization](#localization)
- [Contributing](#contributing)
- [License](#license)
- [Acknowledgements](#acknowledgements)

---

## Why MacMarkDown

- **Native to the core.** A custom TextKit 2 editor and a native preview
  surface; WebKit appears only where it earns its place — tables and TeX
  formulas.
- **Fast on real documents.** Viewport-based layout renders only the visible
  band, so scrolling stays smooth in very long, CJK-heavy files.
- **Safe by construction.** Swift 6.4 strict concurrency is enabled across
  every target: editor state is main-actor isolated and parsed documents are
  immutable `Sendable` value types.
- **Local-first and private.** Parsing, highlighting, math and diagrams all
  travel with the app. No account, no network, no telemetry.
- **A first-class macOS citizen.** Multi-window documents, autosave, Finder
  integration, Services, Touch Bar, AppleScript, a URL scheme and a
  command-line tool.
- **Yours to shape.** 15 editor themes, 6 preview styles, selectable
  code-highlight palettes, HTML export templates and user-installable
  `.style` themes.

### By the numbers

| Metric | Value |
|--------|-------|
| Language | 100% Swift — 16,851 lines of app and framework code |
| Tests | 414 unit tests (6,316 lines) across 29 suites |
| Targets | 4 — app, framework, CLI and test bundle |
| Markdown engine | Apple's swift-markdown + Yams, wrapped by a native `MarkdownElement` tree |
| Themes | 15 editor themes · 6 preview styles |
| Localization | 21 locales, including Simplified and Traditional Chinese |
| Third-party Swift packages | 2 — swift-markdown and Yams |

---

## Features

### Writing

- A custom **TextKit 2 editor** with viewport-based layout, precise
  caret/selection geometry, line wrapping and scroll-past-end.
- **Formatting commands** for the whole Markdown toolbox — headings, emphasis,
  lists, quotes, links, images, code and rules — from the Format menu, the
  toolbar or the Touch Bar.
- **Smart editing**, each behavior individually configurable: matching-character
  completion (ASCII and CJK), list/quote continuation on Return, automatic
  ordered-list numbering, Tab-to-spaces, Smart Home, and more.
- **Find & replace** with case sensitivity, wrap-around and replace-all.
- **Spell checking** with the system dictionary and the standard macOS
  suggestions menu.
- **Word count** in words, characters, or characters without spaces.
- **Full keyboard editing** with undo/redo across typing, commands,
  find & replace and drag & drop.
- **IME composition** for Chinese, Japanese and Korean input.
- Line-number gutter, invisible-character display, read-aloud, and the Services
  menu.

### Live preview

- A **native preview surface** built on the same TextKit 2 engine as the
  editor: selectable text, ⌘A, and copy with formatting.
- **Synchronized scrolling** — editor → preview by default, optionally
  bidirectional — driven by dense block and list-item anchors.
- **Tables and TeX formulas** are laid out by WebKit for true CSS fidelity
  (MathJax typesets the formulas); everything else is native.
- **Preview zoom** relative to the editor's base font, plus
  follow-editor / system / custom font policies.
- **Front matter, task lists, tables of contents, footnotes and code
  highlighting** render in the preview and in exported HTML.

### Markdown support

Standard Markdown plus a deep set of extensions, each toggleable in
Settings → Markdown / HTML:

| Feature | Default | Feature | Default |
|---------|:-------:|---------|:-------:|
| Tables | On | Underline `_text_` | Off |
| Fenced code blocks | On | Highlight `==text==` | Off |
| Strikethrough | On | Superscript `^text^` | Off |
| Bare-URL autolinking | On | Quote `"text"` → `<q>` | Off |
| Footnotes | On | TeX math `\[…\]`, `$$…$$` | Off |
| Task lists | On | Inline math `$…$` | Off |
| Intra-word emphasis | On | Table of contents `[toc]` | Off |
| SmartyPants typography | On | Hard wrap | Off |
| YAML front matter | On | Line numbers in code blocks | Off |

### Export and automation

- **Export HTML** with the bundled template and stylesheet, optional inline
  styles and syntax highlighting.
- **Export PDF** through the macOS print pipeline, plus **Print** and
  **Page Setup**.
- **Copy HTML** to the clipboard.
- **AppleScript** — read and write a document's `text`, read its rendered
  `html`.
- **URL scheme** — `x-macmarkdown://open?url=…` opens a file from other apps
  and scripts.
- **Command-line tool** — `macmarkdown [files…]`, or pipe Markdown into it.
- **Plug-ins** — `.macmarkdown-plugin` bundles add their own menu items.

### Customization

- 15 editor themes (`.style`) and 6 preview styles (`.css`), switchable at
  runtime, plus user-installable themes.
- Selectable code-highlight palettes for fenced code.
- HTML export template selection.
- Five Settings panes — **General**, **Markdown**, **Editor**, **HTML** and
  **Terminal** — with a reset button on every slider.
- Editor on the left or right, adjustable insets, line spacing, maximum text
  width and 1:1 / 1:3 / 3:1 split ratios.

---

## Requirements

| Item | Minimum | Notes |
|------|---------|-------|
| macOS | 26.0 | Built and tested against the macOS 27 SDK |
| Xcode | 26.0 | Xcode 27 recommended |
| Swift | 6.4 | Strict concurrency enabled in every target |
| XcodeGen | 2.44+ | Only to regenerate the project from `project.yml` |

---

## Getting started

```bash
git clone https://github.com/xAIat/MacMarkDown.git
cd MacMarkDown
```

### Open in Xcode

```bash
open MacMarkDown.xcodeproj
```

> Open **`MacMarkDown.xcodeproj`**, not the repository folder. The project
> contains all four targets, so opening the folder cannot build a runnable app.

Then press **⌘R**. Xcode resolves the Swift Package dependencies
(`swift-markdown`, `Yams`) automatically on first open.

### Build from the command line

```bash
# Debug build
xcodebuild -project MacMarkDown.xcodeproj -scheme MacMarkDown \
           -configuration Debug build

# Release build
xcodebuild -project MacMarkDown.xcodeproj -scheme MacMarkDown \
           -configuration Release build
```

### Regenerate the project

`project.yml` is the source of truth for the Xcode project. After adding or
removing source files:

```bash
brew install xcodegen
xcodegen generate
```

### Project scripts

```bash
./scripts/build.sh              # build verification (debug or release)
./scripts/test.sh               # run the 414 unit tests
./scripts/test.sh --coverage    # …with code coverage
./scripts/lint.sh               # strict-concurrency and style checks
```

---

## Usage

### Keyboard shortcuts

| Action | Shortcut | Action | Shortcut |
|--------|----------|--------|----------|
| Strong | ⌘B | Paragraph | ⌘0 |
| Emphasize | ⌘I | Headings 1–6 | ⌘1 – ⌘6 |
| Inline code | ⌘K | Unordered list | ⌃⌘U |
| Strikethrough | ⌃⌘S | Ordered list | ⌃⌘O |
| Underline | ⌘U | Blockquote | ⌃⌘B |
| Highlight | ⇧⌘H | Indent / Unindent | ⌘] / ⌘[ |
| Comment | ⌥⌘/ | New paragraph | ⌘Return |
| Find | ⌘F | Render now | ⌘R |
| Export HTML | ⌘E | Export PDF | ⇧⌘E |
| Copy HTML | ⌥⌘C | Print | ⌘P |
| Toggle toolbar | ⌥⌘T | Page setup | ⇧⌘P |

### Command-line tool

Install `macmarkdown` into `/usr/local/bin` from
**Settings → Terminal → Install**, then:

```bash
macmarkdown notes.md            # open a file
macmarkdown a.md b.md           # open several files
cat notes.md | macmarkdown      # open piped input as a new document
macmarkdown --help
```

### URL scheme

```text
x-macmarkdown://open?url=file:///Users/you/notes.md
```

### AppleScript

MacMarkDown ships a scripting definition (`Resources/MacMarkDown.sdef`) with
the standard suite plus a document class:

```applescript
tell application "MacMarkDown"
    set theText of document 1 to "# Hello"
    get html of document 1
end tell
```

### Plug-ins

Drop a `.macmarkdown-plugin` bundle into
`~/Library/Application Support/MacMarkDown/PlugIns`. The bundle's principal
class implements `name` and `run(_:)`, and each plug-in gets an item in the
**Plug-ins** menu. Choose **Plug-ins → Reload Plug-ins** after adding or
removing one.

---

## Architecture

MacMarkDown is a single Xcode project generated by XcodeGen, with a thin app
shell around a framework that holds all core logic.

| Target | Product | Sources |
|--------|---------|---------|
| `MacMarkDown` | `MacMarkDown.app` | `MacMarkDown/Application` |
| `MacMarkDownKit` | `MacMarkDownKit.framework` | `MacMarkDown/` (core) |
| `MacMarkDownCLI` | `macmarkdown-cli` | `CLI/` |
| `MacMarkDownTests` | Unit-test bundle | `MacMarkDown/Tests/` |

| Dependency | Role |
|------------|------|
| [swift-markdown](https://github.com/apple/swift-markdown) | CommonMark parsing and the AST foundation |
| [Yams](https://github.com/jpsim/Yams) | YAML front matter |
| MathJax (bundled) | TeX → SVG for the preview and exported HTML |
| Mermaid (bundled) | Diagrams in exported HTML |
| Viz.js / Graphviz (bundled) | Diagrams in exported HTML |
| Sparkle (placeholder) | Update feed configuration, opt-in |

```text
MacMarkDown/
├── Application/        # @main shell, app delegate, menus
├── Document/           # Document model, sessions, front matter, scripting
├── Markdown/           # Parser, AST, parse options, anchors
├── Services/           # Editor, Preview, Export, ScrollSync, PlugIn
├── Stores/             # Observable preferences
├── Theme/              # Editor themes, preview styles, code palettes
├── Tools/              # Constants, resource loading, utilities
├── UI/                 # Shared + macOS SwiftUI views and the TextKit 2 editor
├── Resources/          # Styles, Themes, Templates, bundled web engines
└── Tests/              # 414 unit tests
CLI/                    # macmarkdown command-line tool
Resources/              # App icon, string catalog, help, scripting definition
docs/                   # Bilingual technical documentation
scripts/                # build.sh · test.sh · lint.sh
```

Design decisions are documented as ADRs and RFCs — see
[Documentation](#documentation).

---

## Documentation

Every document — including this README — is published in English and Chinese.
The language switcher at the top and bottom of this file links the two
translations together:

| Document | English | 中文 |
|----------|---------|------|
| Documentation index | [docs/index.md](docs/index.md) | [docs/index.zh.md](docs/index.zh.md) |
| Product overview | [overview.md](docs/business/overview.md) | [overview.zh.md](docs/business/overview.zh.md) |
| Development guide | [guide.md](docs/guide/guide.md) | [guide.zh.md](docs/guide/guide.zh.md) |
| Contributing guide | [contributing.md](docs/guide/contributing.md) | [contributing.zh.md](docs/guide/contributing.zh.md) |
| Core architecture (RFC-001) | [rfc-001](docs/design/rfc-001-core-architecture.md) | [rfc-001](docs/design/rfc-001-core-architecture.zh.md) |
| Rendering pipeline (RFC-002) | [rfc-002](docs/design/rfc-002-rendering-pipeline.md) | [rfc-002](docs/design/rfc-002-rendering-pipeline.zh.md) |
| Editor integration (RFC-003) | [rfc-003](docs/design/rfc-003-editor-integration.md) | [rfc-003](docs/design/rfc-003-editor-integration.zh.md) |
| Pure SwiftUI (ADR-001) | [adr-001](docs/architecture/adr-001-pure-swiftui.md) | [adr-001](docs/architecture/adr-001-pure-swiftui.zh.md) |
| Swift Markdown parser (ADR-002) | [adr-002](docs/architecture/adr-002-swift-markdown.md) | [adr-002](docs/architecture/adr-002-swift-markdown.zh.md) |
| Native preview (ADR-003) | [adr-003](docs/architecture/adr-003-native-preview.md) | [adr-003](docs/architecture/adr-003-native-preview.zh.md) |
| Editor themes (ADR-004) | [adr-004](docs/architecture/adr-004-editor-themes.md) | [adr-004](docs/architecture/adr-004-editor-themes.zh.md) |
| Swift 26 compliance audit | [audit](docs/reference/apple-swift-26-compliance-audit.md) | [audit](docs/reference/apple-swift-26-compliance-audit.zh.md) |
| Field incidents | [postmortem](docs/postmortems/2026-09-field-incidents.md) | [postmortem](docs/postmortems/2026-09-field-incidents.zh.md) |

The app also ships a hands-on user manual, which doubles as a rendering test
page: [Resources/help.md](Resources/help.md).

---

## Localization

The interface is localized in 21 languages:

Arabic, Czech, Danish, German, Spanish, Estonian, Finnish, French, Icelandic,
Italian, Japanese, Korean, Norwegian (Bokmål), Dutch, Portuguese (Brazil),
Russian, Slovak, Swedish, Turkish, Simplified Chinese and Traditional Chinese.

Translations live in [`Resources/Localizable.xcstrings`](Resources/Localizable.xcstrings)
and are edited with Xcode's String Catalog editor.

---

## Contributing

Contributions are welcome — code, documentation and translations alike. Start
with the [contributing guide](docs/guide/contributing.md), then:

```bash
git clone https://github.com/xAIat/MacMarkDown.git
cd MacMarkDown
./scripts/test.sh && ./scripts/lint.sh
```

- Keep Swift 6.4 strict concurrency clean; the lint script fails on new
  warnings.
- `project.yml` is the source of truth — run `xcodegen generate` after adding
  files.
- Documentation is bilingual: update both `*.md` and `*.zh.md`.

---

## License

MacMarkDown is released under the [MIT License](LICENSE).

---

## Acknowledgements

MacMarkDown stands on excellent open-source work:

- [swift-markdown](https://github.com/apple/swift-markdown) and the Swift
  community for the parsing foundation.
- [Yams](https://github.com/jpsim/Yams) for YAML front matter.
- [MathJax](https://www.mathjax.org), [Mermaid](https://mermaid.js.org) and
  [Viz.js](https://github.com/mdaines/viz.js) for the bundled rendering
  engines.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for full license details.

---

<div align="center">

**English** · [简体中文](README.zh.md)

Made for the new era of Swift and SwiftUI on macOS.

</div>
