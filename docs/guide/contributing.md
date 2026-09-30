# Contributing to MacMarkDown

Thank you for your interest in contributing to MacMarkDown. MacMarkDown is a native macOS Markdown editor written from scratch in pure Swift and SwiftUI for the macOS 26 era; this guide outlines the standards and processes for all contributions.

---

## 1. Code Style

### 1.1 Swift 6.4 Strict Concurrency

MacMarkDown is built with the Swift 6.4 toolchain in Swift 6 language mode,
with complete strict concurrency checking. All code must comply:

- **No data races**: All mutable shared state must be `@MainActor`-isolated or `Sendable`.
- **Explicit isolation**: Use `@MainActor`, `@Sendable`, and `sending` parameters where appropriate.
- **No `@preconcurrency` unless unavoidable**: Only use for system framework bridges (e.g., `NSViewRepresentable`).
- **Strict mode enabled** in Xcode build settings (`project.yml`):

```yaml
# project.yml
settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
```

### 1.2 Formatting

- Use **4 spaces** for indentation (no tabs).
- Maximum line length: **120 characters**.
- Keep formatting consistent across the codebase; run `swift-format` (default
  style) over the Swift sources:

```bash
swift-format format --in-place MacMarkDown/ CLI/
```

- Follow [Swift API Design Guidelines](https://www.swift.org/api-design-guidelines/).
- Use `guard` for early returns.
- Prefer `let` over `var` where possible.

### 1.3 Naming Conventions

| Element            | Convention          | Example                     |
|--------------------|---------------------|-----------------------------|
| Types              | UpperCamelCase      | `EditorFormatting`          |
| Functions/Methods  | lowerCamelCase      | `toggleMarkup(...)`         |
| Properties         | lowerCamelCase      | `editorBaseFontSize`        |
| Constants          | lowerCamelCase      | `defaultEditorFontSize`     |
| Enum cases         | lowerCamelCase      | `.strong`                   |
| Protocols          | UpperCamelCase      | `Theme`                     |
| Files              | UpperCamelCase      | `EditorFormatting.swift`    |
| Test files         | UpperCamelCase + Tests | `EditorFormattingTests.swift` |

### 1.4 Documentation Comments

All public API must have documentation comments. Use `///` style:

```swift
/// Toggles a Markdown prefix/suffix pair around the selected text.
///
/// If the selection is already wrapped, the markers are removed; an empty
/// selection inserts the wrapper with `placeholder` and selects it.
///
/// - Parameters:
///   - text: The string buffer to modify.
///   - selectedRange: The current selection.
///   - prefix: The marker inserted before the selection.
///   - suffix: The marker inserted after the selection.
///   - placeholder: Text inserted when the selection is empty.
/// - Returns: The new text and the range to select.
public static func toggleMarkup(
    in text: String,
    selectedRange range: Range<String.Index>,
    prefix: String,
    suffix: String,
    placeholder: String = ""
) -> (text: String, newRange: Range<String.Index>) {
    // ...
}
```

### 1.5 Module Organization

The app target is a thin shell; everything reusable lives in the
`MacMarkDownKit` framework. Each folder has a clear responsibility:

| Folder      | Responsibility                          |
|-------------|------------------------------------------|
| `Application` | Application entry, menu commands, app delegate |
| `Document`  | File I/O, document lifecycle, sessions, front matter |
| `Markdown`  | swift-markdown parsing, element model, parse options |
| `Theme`     | Preview themes, editor themes, code highlighting |
| `Stores`    | Observable app state (preferences)      |
| `Services`  | Editor operations, preview rendering, export, scroll sync, plug-ins |
| `UI`        | SwiftUI views plus the TextKit 2 editor and preview surfaces |
| `Tools`/`Extensions` | Shared helpers (constants, resource loading, extensions) |

Do not create cross-module circular dependencies. Dependencies flow inward:
`Application → UI → Services → Document/Markdown/Theme/Stores → Tools/Extensions`.
`MacMarkDown/Application` only imports `MacMarkDownKit`; the framework never
imports the app shell, and the CLI target talks to the app through the shared
`UserDefaults` handoff suite (`Constants.cliHandoffSuiteName`).

## 2. Branch Naming

Use the following branch naming conventions:

| Type         | Format                   | Example                        |
|--------------|--------------------------|--------------------------------|
| Feature      | `feature/<short-desc>`   | `feature/toggle-bold-shortcut` |
| Bug fix      | `fix/<short-desc>`       | `fix/line-prefix-empty-list`   |
| Hotfix       | `hotfix/<short-desc>`    | `hotfix/crash-on-empty-doc`    |
| Refactor     | `refactor/<short-desc>`  | `refactor/format-engine-split` |
| Documentation| `docs/<short-desc>`      | `docs/update-contributing-zh`  |
| Test         | `test/<short-desc>`      | `test/add-auto-complete-tests` |

- Use lowercase and kebab-case.
- Keep descriptions short but descriptive (2-5 words).
- Do not use issue numbers in branch names (put them in commit messages instead).

## 3. Pull Request Requirements

### 3.1 PR Template

Every PR must include:

```markdown
## Summary
Brief description of the change.

## Related Issue
Closes #<issue-number>

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Refactoring
- [ ] Documentation
- [ ] Test
- [ ] Other: ___

## Changes
- Bullet list of specific changes

## Testing
- [ ] All existing tests pass
- [ ] New tests added (if applicable)
- [ ] Manual testing completed (if UI changes)

## Checklist
- [ ] Code follows project style guidelines
- [ ] Self-review completed
- [ ] Documentation updated (EN + ZH)
- [ ] No new warnings introduced
- [ ] Concurrency model compliance verified
```

### 3.2 PR Rules

1. **One PR per logical change.** Do not bundle unrelated changes.
2. **Title format**: `<type>: <description>` (e.g., `feat: add highlight shortcut`).
3. **No force pushes** to `main`. Use feature branches.
4. **Require at least 1 approval** before merge.
5. **CI must pass** (build + test + lint).
6. **Resolve all review comments** before merge.
7. **Squash merge** into `main` to keep history clean.

### 3.3 Code Review

Reviewers should check:

- [ ] Correctness of logic
- [ ] Concurrency safety (`@MainActor` isolation, `Sendable` conformance)
- [ ] Test coverage for new code
- [ ] Documentation completeness (EN + ZH)
- [ ] Performance implications (especially for editor operations)
- [ ] Accessibility compliance
- [ ] No secrets or credentials committed

## 4. Test Requirements

### 4.1 Coverage Targets

| Area        | Minimum Coverage |
|-------------|------------------|
| `Editor`    | 90%              |
| `Markdown` (parser) | 95%      |
| `Preview`   | 80%              |
| `Document`  | 85%              |
| `Tools`/`Extensions` | 90%      |
| Overall     | 85%              |

### 4.2 Test Organization

The `MacMarkDownTests` target keeps its tests flat: one file per area, named
after the type or feature under test.

```
MacMarkDown/Tests/
├── MarkdownParserTests.swift      # Parsing and the element model
├── EditorFormattingTests.swift    # Format commands
├── EditorOperationsTests.swift    # String-level transformations
├── AttributedRendererTests.swift  # Native preview rendering
├── PreviewRenderingTests.swift    # Renderer output and stylesheets
├── DocumentSessionTests.swift     # Document lifecycle
├── PreferencesTests.swift         # Preference persistence
└── …                              # One file per area
```

### 4.3 Test Naming

```swift
func testToggleMarkup_wrappedInMarkers_removesMarkers() { ... }
func testToggleMarkup_plainSelection_addsMarkers() { ... }
func testIndentLines_orderedList_incrementsIndent() { ... }
```

Pattern: `<method>_<condition>_<expectedBehavior>`

### 4.4 What to Test

- **All format operations**: Every `EditorFormatCommand` case with both add and remove scenarios.
- **All key handling paths**: Every shortcut and edge case.
- **Auto-complete**: All matching character pairs and conflict resolution.
- **Line prefix**: All prefix types (ordered, unordered, blockquote, task) and the empty-list-end case.
- **Parser extensions**: Every custom syntax extension in both valid and invalid inputs.
- **Error paths**: Invalid file operations, corrupt document handling.

### 4.5 Performance Tests

For editor operations, add XCTest performance tests:

```swift
func testPerformanceToggleMarkupLargeDocument() {
    let largeText = String(repeating: "Hello world. ", count: 100_000)
    let selection = largeText.startIndex..<largeText.index(largeText.startIndex, offsetBy: 11)

    measure {
        for _ in 0..<100 {
            _ = EditorOperations.toggleMarkup(
                in: largeText, selectedRange: selection, prefix: "**", suffix: "**"
            )
        }
    }
}
```

Target: Toggle formatting on a 100K-word document in under 50ms.

## 5. Documentation Requirements

### 5.1 Bilingual Documentation

All documentation must be written in both **English** and **Chinese (Simplified)**.

| File                  | EN Path                    | ZH Path                      |
|-----------------------|----------------------------|------------------------------|
| Design docs (RFCs)    | `docs/design/rfc-*.md`     | `docs/design/rfc-*.zh.md`    |
| Guides                | `docs/guide/guide.md`      | `docs/guide/guide.zh.md`     |
| Contributing guide    | `docs/guide/contributing.md` | `docs/guide/contributing.zh.md` |
| Reference docs        | `docs/reference/*.md`      | `docs/reference/*.zh.md`     |
| Postmortems           | `docs/postmortems/*.md`    | `docs/postmortems/*.zh.md`   |

### 5.2 Documentation Standards

- Use clear, concise language.
- Include code examples for all technical concepts.
- Keep examples up-to-date with the current API.
- Use tables for structured data.
- Include the date of last update at the bottom of each file.
- Cross-reference related documents.

### 5.3 API Documentation

All public types and methods must have doc comments. Internal implementation details may use regular comments. The documentation should explain:

- **What** the API does
- **When** to use it
- **Parameters** and their meaning
- **Return value** description
- **Throws** conditions (if applicable)
- **Example** usage (for complex APIs)

## 6. Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/) format:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `ci`

Examples:

```
feat(editor): add highlight shortcut
fix(preview): keep scroll sync anchored on nested lists
docs(guide): update Chinese translation for setup section
test(editor): add auto-complete conflict resolution tests
refactor(markdown): extract inline marker handling in MarkdownParser
```

## 7. Getting Help

- **Issues**: Open a GitHub issue for bugs or feature requests.
- **Discussions**: Use GitHub Discussions for questions and design conversations.
- **Code review**: Mention the maintainers in your pull request, or open an issue to request a review.

## 8. Version Control

- **Local model configs stay untracked**: `opencode.jsonc` and the `Opencode/` templates hold machine-local model and endpoint settings; both are listed in `.gitignore` and must never be committed.
- **`project.yml` is the source of truth** for targets, sources and build settings; `MacMarkDown.xcodeproj` is generated from it by XcodeGen. Run `xcodegen generate` after editing it and commit both files together.
- Build products (`.derived/`, `build/`, `DerivedData/`) are never committed.

---

*Last updated: 2026-09-15*
