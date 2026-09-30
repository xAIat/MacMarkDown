import XCTest
@testable import MacMarkDownKit

final class MarkdownParserTests: XCTestCase {

    @MainActor
    func testParseHeadingsAndParagraphs() {
        let parser = MarkdownParser()
        let elements = parser.parse("# Title\n\nSome **bold** text.")
        XCTAssertGreaterThanOrEqual(elements.count, 2)

        let heading = elements.first
        if case .heading(let level, let text) = heading {
            XCTAssertEqual(level, 1)
            XCTAssertEqual(text, "Title")
        } else {
            XCTFail("Expected heading element")
        }
    }

    @MainActor
    func testParseCodeBlock() {
        let parser = MarkdownParser()
        let elements = parser.parse("```swift\nlet x = 1\n```")
        XCTAssertTrue(elements.contains { element in
            if case .codeBlock(let language, _) = element {
                return language == "swift"
            }
            return false
        })
    }

    @MainActor
    func testParseUnorderedList() {
        let parser = MarkdownParser()
        let elements = parser.parse("- item one\n- item two")
        XCTAssertTrue(elements.contains { element in
            if case .unorderedList(_) = element { return true }
            return false
        })
    }

    @MainActor
    func testParseEmptyDocument() {
        let parser = MarkdownParser()
        let elements = parser.parse("")
        XCTAssertTrue(elements.isEmpty)
    }

    // MARK: - Extension options

    @MainActor
    func testParseImageInline() {
        let parser = MarkdownParser()
        let elements = parser.parse("![alt text](https://example.com/a.png)")
        guard case let .paragraph(inlines) = elements.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertTrue(inlines.contains {
            if case .image(let url, let alt) = $0 {
                return url == "https://example.com/a.png" && alt == "alt text"
            }
            return false
        })
    }

    @MainActor
    func testParseTaskListWhenEnabled() {
        let parser = MarkdownParser()
        let elements = parser.parse("- [x] done\n- [ ] todo")
        guard case let .taskList(items) = elements.first else {
            return XCTFail("Expected task list")
        }
        XCTAssertEqual(items.map(\.isChecked), [true, false])
    }

    @MainActor
    func testParseTaskListDisabledFallsBackToList() {
        let parser = MarkdownParser()
        let options = MarkdownParseOptions(enableTaskList: false)
        let elements = parser.parse("- [x] done\n- [ ] todo", options: options)
        XCTAssertTrue(elements.contains {
            if case .unorderedList = $0 { return true }
            return false
        })
    }

    @MainActor
    func testParseTablesDisabledFallsBackToParagraph() {
        let parser = MarkdownParser()
        let options = MarkdownParseOptions(enableTables: false)
        let elements = parser.parse("| a | b |\n|---|---|\n| 1 | 2 |", options: options)
        guard case .paragraph = elements.first else {
            return XCTFail("Expected paragraph when tables are disabled")
        }
    }

    @MainActor
    func testParseStrikethroughDisabledFallsBackToText() {
        let parser = MarkdownParser()
        let options = MarkdownParseOptions(enableStrikethrough: false)
        let elements = parser.parse("~~gone~~", options: options)
        guard case let .paragraph(inlines) = elements.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertFalse(inlines.contains {
            if case .strikethrough = $0 { return true }
            return false
        })
        XCTAssertTrue(inlines.contains {
            if case .text(let text) = $0 { return text.contains("gone") }
            return false
        })
    }

    @MainActor
    func testParseFencedCodeDisabledFallsBackToParagraph() {
        let parser = MarkdownParser()
        let options = MarkdownParseOptions(enableFencedCode: false)
        let elements = parser.parse("```swift\nlet x = 1\n```", options: options)
        guard case .paragraph = elements.first else {
            return XCTFail("Expected paragraph when fenced code is disabled")
        }
    }

    @MainActor
    func testSmartyPantsOptionControlsQuotes() {
        let parser = MarkdownParser()
        let smart = parser.parse("\"quoted\"", options: MarkdownParseOptions(enableSmartyPants: true))
        let plain = parser.parse("\"quoted\"", options: MarkdownParseOptions(enableSmartyPants: false))
        XCTAssertTrue(plainText(of: smart).contains("\u{201C}"))
        XCTAssertTrue(plainText(of: plain).contains("\""))
    }

    private func plainText(of elements: [MarkdownElement]) -> String {
        elements.compactMap { element in
            if case let .paragraph(inlines) = element {
                return inlines.compactMap { inline in
                    if case .text(let text) = inline { return text }
                    return nil
                }.joined()
            }
            return nil
        }.joined()
    }
}
// MARK: - Footnotes (P6, custom parsing)

extension MarkdownParserTests {

    @MainActor
    func testFootnotesExtractAndNumber() {
        let parser = MarkdownParser()
        let text = "First[^b] and second[^a].\n\n[^a]: Alpha note\n[^b]: Beta note"
        let elements = parser.parse(text, options: MarkdownParseOptions(enableFootnotes: true))

        guard let footnotes = elements.first(where: {
            if case .footnotes = $0 { return true }
            return false
        }), case let .footnotes(items) = footnotes else {
            return XCTFail("Expected footnotes element")
        }
        // Numbered by first reference: b, then a.
        XCTAssertEqual(items.map(\.id), ["b", "a"])
        XCTAssertEqual(items.map(\.text), ["Beta note", "Alpha note"])

        // References became anchor links.
        guard case let .paragraph(inlines) = elements.first else {
            return XCTFail("Expected paragraph")
        }
        let destinations = inlines.compactMap { inline -> String? in
            if case .link(let url, _) = inline { return url }
            return nil
        }
        XCTAssertEqual(destinations, ["#fn-b", "#fn-a"])
    }

    @MainActor
    func testFootnoteDefinitionsRemovedFromBody() {
        let parser = MarkdownParser()
        let text = "Text[^1]\n\n[^1]: Note body"
        let elements = parser.parse(text, options: MarkdownParseOptions(enableFootnotes: true))
        let paragraphs = elements.compactMap { element -> [InlineElement]? in
            if case let .paragraph(inlines) = element { return inlines }
            return nil
        }
        // Only the body paragraph remains; the definition is not rendered as
        // its own paragraph.
        XCTAssertEqual(paragraphs.count, 1)
    }

    @MainActor
    func testFootnotesDisabledLeaveTextUntouched() {
        let parser = MarkdownParser()
        let text = "Text[^1]\n\n[^1]: Note body"
        let elements = parser.parse(text, options: MarkdownParseOptions(enableFootnotes: false))
        XCTAssertFalse(elements.contains {
            if case .footnotes = $0 { return true }
            return false
        })
    }

    @MainActor
    func testHTMLFootnotesRender() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(enableFootnotes: true)
        )
        let html = renderer.renderToHTML("Text[^1]\n\n[^1]: Note body")
        XCTAssertTrue(html.contains("id=\"fn-1\""))
        XCTAssertTrue(html.contains("class=\"footnotes\""))
        XCTAssertTrue(html.contains("Note body"))
    }
}

// MARK: - Inline extensions (P6, custom parsing)

extension MarkdownParserTests {

    @MainActor
    private func inlines(_ text: String, options: MarkdownParseOptions) -> [InlineElement] {
        let elements = MarkdownParser().parse(text, options: options)
        guard case let .paragraph(result) = elements.first else { return [] }
        return result
    }

    @MainActor
    func testUnderlineExtension() {
        let result = inlines("_under_", options: MarkdownParseOptions(enableUnderline: true))
        XCTAssertTrue(result.contains {
            if case .underline = $0 { return true }
            return false
        })
    }

    @MainActor
    func testDoubleUnderscoreStaysStrongWithUnderlineEnabled() {
        for text in ["__bold__", "__foo_bar__"] {
            let result = inlines(text, options: MarkdownParseOptions(enableUnderline: true))
            XCTAssertTrue(result.contains {
                if case .strong = $0 { return true }
                return false
            }, "\(text) should stay strong")
            XCTAssertFalse(result.contains {
                if case .underline = $0 { return true }
                return false
            }, "\(text) must not become underline")
        }
    }

    @MainActor
    func testUnderlineDisabledRendersEmphasis() {
        let result = inlines("_under_", options: MarkdownParseOptions(enableUnderline: false))
        XCTAssertTrue(result.contains {
            if case .emphasis = $0 { return true }
            return false
        })
        XCTAssertFalse(result.contains {
            if case .underline = $0 { return true }
            return false
        })
    }

    @MainActor
    func testUnderlineSkipsEscapedIntraWordUnderscores() {
        // With NO_INTRA_EMPHASIS the escape pass turns `_` into `\_`; the
        // underline extension must not resurrect them as markup.
        let result = inlines(
            "foo_bar_baz",
            options: MarkdownParseOptions(enableIntraEmphasis: false, enableUnderline: true)
        )
        XCTAssertFalse(result.contains {
            if case .underline = $0 { return true }
            return false
        })
    }

    @MainActor
    func testUnderlineKeepsEscapedUnderscoresInsideSpan() {
        // The escaped inner `_` must not close the span early; the run keeps
        // its literal underscore.
        let result = inlines(
            "_foo_bar_",
            options: MarkdownParseOptions(enableIntraEmphasis: false, enableUnderline: true)
        )
        guard let underline = result.first(where: {
            if case .underline = $0 { return true }
            return false
        }), case let .underline(children) = underline else {
            return XCTFail("Expected underline")
        }
        XCTAssertEqual(children.count, 1)
        guard case let .text(content) = children[0] else {
            return XCTFail("Expected text content")
        }
        XCTAssertEqual(content, "foo_bar")
    }

    @MainActor
    func testUnderlineSpansLineBreakWithinParagraph() {
        // The Underline command wraps the raw selection, so a two-line
        // selection becomes `_line one\nline two_`; the soft break belongs
        // inside the underlined run.
        let result = inlines("_line one\nline two_", options: MarkdownParseOptions(enableUnderline: true))
        XCTAssertFalse(result.contains {
            if case .emphasis = $0 { return true }
            return false
        })
        guard let underline = result.first(where: {
            if case .underline = $0 { return true }
            return false
        }), case let .underline(children) = underline else {
            return XCTFail("Expected underline")
        }
        let text = children.compactMap { child -> String? in
            if case let .text(value) = child { return value }
            return nil
        }.joined()
        XCTAssertEqual(text, "line one line two")
    }

    @MainActor
    func testUnderlineDoesNotSpanBlankLines() {
        let elements = MarkdownParser().parse(
            "_line one\n\nline two_",
            options: MarkdownParseOptions(enableUnderline: true)
        )
        for case let .paragraph(inlines) in elements {
            XCTAssertFalse(inlines.contains {
                if case .underline = $0 { return true }
                return false
            })
            let leaked = inlines.contains { inline in
                if case let .text(value) = inline {
                    return value.unicodeScalars.contains { (0xE000...0xE007).contains($0.value) }
                }
                return false
            }
            XCTAssertFalse(leaked, "markers must not leak into paragraphs")
        }
    }

    @MainActor
    func testHeadingDropsExtensionMarkers() {
        let elements = MarkdownParser().parse("# _title_", options: MarkdownParseOptions(enableUnderline: true))
        guard case let .heading(_, text) = elements.first else {
            return XCTFail("Expected heading")
        }
        XCTAssertEqual(text, "title")
    }

    @MainActor
    func testHighlightExtension() {
        let result = inlines("==marked==", options: MarkdownParseOptions(enableHighlight: true))
        XCTAssertTrue(result.contains {
            if case .highlight = $0 { return true }
            return false
        })
    }

    @MainActor
    func testSuperscriptExtension() {
        let result = inlines("E = mc^2^", options: MarkdownParseOptions(enableSuperscript: true))
        XCTAssertTrue(result.contains {
            if case .superscript = $0 { return true }
            return false
        })
    }

    @MainActor
    func testQuoteExtension() {
        let result = inlines("\"hello\" world", options: MarkdownParseOptions(enableQuote: true))
        XCTAssertTrue(result.contains {
            if case .quote = $0 { return true }
            return false
        })
    }

    @MainActor
    func testQuoteExtensionDisabled() {
        let result = inlines("\"hello\" world", options: MarkdownParseOptions(enableQuote: false))
        XCTAssertFalse(result.contains {
            if case .quote = $0 { return true }
            return false
        })
    }

    @MainActor
    func testEmphasisAndStrongParsing() {
        let parsed = MarkdownParser().parseDocument("*i* and **b**")
        guard case let .paragraph(inlines) = parsed.elements.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertTrue(inlines.contains { if case .emphasis = $0 { return true }; return false })
        XCTAssertTrue(inlines.contains { if case .strong = $0 { return true }; return false })
    }

    @MainActor
    func testIntraWordEmphasisDisabled() {
        let parser = MarkdownParser()
        let elements = parser.parse("foo*bar*baz", options: MarkdownParseOptions(enableIntraEmphasis: false))
        guard case let .paragraph(inlines) = elements.first else { return XCTFail("paragraph") }
        XCTAssertFalse(inlines.contains { if case .emphasis = $0 { return true }; return false })
    }

    @MainActor
    func testIntraWordEmphasisEnabled() {
        let parser = MarkdownParser()
        let elements = parser.parse("foo*bar*baz", options: MarkdownParseOptions(enableIntraEmphasis: true))
        guard case let .paragraph(inlines) = elements.first else { return XCTFail("paragraph") }
        XCTAssertTrue(inlines.contains { if case .emphasis = $0 { return true }; return false })
    }

    @MainActor
    func testAutolinkWrapsBareURL() {
        let parser = MarkdownParser()
        let elements = parser.parse("See https://example.com now", options: MarkdownParseOptions(enableAutolink: true))
        guard case let .paragraph(inlines) = elements.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertTrue(inlines.contains {
            if case .link(let url, _) = $0 { return url == "https://example.com" }
            return false
        })
    }

    @MainActor
    func testAutolinkDisabledLeavesURLAsText() {
        let parser = MarkdownParser()
        let elements = parser.parse("See https://example.com now", options: MarkdownParseOptions(enableAutolink: false))
        guard case let .paragraph(inlines) = elements.first else {
            return XCTFail("Expected paragraph")
        }
        XCTAssertFalse(inlines.contains {
            if case .link = $0 { return true }
            return false
        })
    }

    @MainActor
    func testExtensionMarkersSkipFencedCode() {
        // `_x_` inside a fence must not become underline markup.
        let parser = MarkdownParser()
        let elements = parser.parse("```\n_x_\n```", options: MarkdownParseOptions(enableUnderline: true))
        guard case let .codeBlock(_, code) = elements.first else {
            return XCTFail("Expected code block")
        }
        XCTAssertEqual(code, "_x_\n")
    }

    @MainActor
    func testInlineExtensionsDisabledLeaveMarkers() {
        let result = inlines("_under_", options: MarkdownParseOptions(enableUnderline: false))
        XCTAssertFalse(result.contains {
            if case .underline = $0 { return true }
            return false
        })
    }

    @MainActor
    func testExtensionMarkersSkipAutolinks() {
        let result = inlines(
            "https://example.com/a_b_c",
            options: MarkdownParseOptions(enableAutolink: true, enableUnderline: true)
        )
        guard let link = result.first(where: {
            if case .link = $0 { return true }
            return false
        }), case let .link(url, children) = link else {
            return XCTFail("Expected a link")
        }
        XCTAssertEqual(url, "https://example.com/a_b_c")
        XCTAssertFalse(children.contains {
            if case .underline = $0 { return true }
            return false
        })
    }

    @MainActor
    func testExtensionMarkersSkipInlineHTMLTags() {
        let result = inlines(
            "<span data-note=\"a_b_c\">text</span>",
            options: MarkdownParseOptions(enableUnderline: true, enableQuote: true)
        )
        guard let html = result.first(where: {
            if case .inlineHTML = $0 { return true }
            return false
        }), case let .inlineHTML(raw) = html else {
            return XCTFail("Expected inline HTML")
        }
        XCTAssertEqual(raw, "<span data-note=\"a_b_c\">")
    }

    @MainActor
    func testHTMLInlineExtensions() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(
                enableUnderline: true,
                enableHighlight: true,
                enableSuperscript: true
            )
        )
        let html = renderer.renderToHTML("_u_ ==h== x^2^")
        XCTAssertTrue(html.contains("<u>u</u>"))
        XCTAssertTrue(html.contains("<mark>h</mark>"))
        XCTAssertTrue(html.contains("<sup>2</sup>"))
    }

    @MainActor
    func testHTMLUnderlineSpansLineBreak() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(enableUnderline: true)
        )
        let html = renderer.renderToHTML("_line one\nline two_")
        XCTAssertTrue(html.contains("<u>line one line two</u>"))
    }
}

// MARK: - Scroll anchors (Phase 10)

extension MarkdownParserTests {

    @MainActor
    func testAnchorsForHeadingsParagraphsAndListItems() {
        let text = "# A\n\npara\n\n- one\n- two"
        let parsed = MarkdownParser().parseDocument(text)
        let lines = parsed.anchors.map(\.line)
        let paths = parsed.anchors.map(\.path)
        // heading(1), paragraph(3), list(5), then per item: the item and its
        // paragraph child (dense, list-item granularity).
        XCTAssertEqual(lines, [1, 3, 5, 5, 5, 6, 6])
        XCTAssertEqual(paths, [[0], [1], [2], [2, 0], [2, 0, 0], [2, 1], [2, 1, 0]])
    }

    @MainActor
    func testAnchorsAlignAfterFrontMatter() {
        let text = "---\ntitle: x\n---\n# A"
        let parsed = MarkdownParser().parseDocument(text)
        // Front matter occupies lines 1-3; the heading is on line 4 and its
        // path is shifted right by the inserted front-matter element.
        XCTAssertEqual(parsed.elements.count, 2)
        XCTAssertEqual(parsed.anchors.count, 1)
        XCTAssertEqual(parsed.anchors.first?.line, 4)
        XCTAssertEqual(parsed.anchors.first?.path, [1])
    }

    @MainActor
    func testFootnoteDefinitionDoesNotCreateAnchor() {
        let text = "Text[^1]\n\n[^1]: note"
        let parsed = MarkdownParser().parseDocument(text, options: MarkdownParseOptions(enableFootnotes: true))
        // Only the body paragraph is anchored; the blanked definition line is
        // not a paragraph.
        XCTAssertEqual(parsed.anchors.count, 1)
        XCTAssertEqual(parsed.anchors.first?.line, 1)
    }

    @MainActor
    func testInlineMathKeepsFollowingAnchorLine() {
        let text = "a $x$ b\n\nc"
        let parsed = MarkdownParser().parseDocument(text, options: MarkdownParseOptions(enableInlineMath: true))
        // The paragraph after the inline-math expansion must still report its
        // original line (3), not the shifted parsed line.
        XCTAssertEqual(parsed.anchors.last?.line, 3)
    }

    // MARK: - Math

    /// Every supported TeX-like delimiter becomes a math block so the web
    /// block pipeline can run MathJax on it.
    @MainActor
    func testMathDelimitersRewriteToMathBlocks() {
        let options = MarkdownParseOptions(enableMath: true, enableInlineMath: true)
        let parser = MarkdownParser()

        func mathCode(_ text: String) -> (language: String, code: String)? {
            for element in parser.parse(text, options: options) {
                if case .codeBlock(let language, let code) = element {
                    return (language ?? "", code.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
            return nil
        }

        XCTAssertEqual(mathCode("\\[a_n=\\frac{1}{n(n+1)}\\]")?.language, "math")
        XCTAssertEqual(mathCode("\\[a_n=\\frac{1}{n(n+1)}\\]")?.code, "a_n=\\frac{1}{n(n+1)}")
        XCTAssertEqual(mathCode("\\\\[A^T_S = B\\\\]")?.language, "math")
        XCTAssertEqual(mathCode("$$E = mc^2$$")?.language, "math")
        XCTAssertEqual(mathCode("$$E = mc^2$$")?.code, "E = mc^2")
        XCTAssertEqual(mathCode("Energy is \\(E = mc^2\\) here")?.language, "math-inline")
        XCTAssertEqual(mathCode("Energy is \\(E = mc^2\\) here")?.code, "E = mc^2")
        XCTAssertEqual(mathCode("Energy is $E = mc^2$ here")?.language, "math-inline")
    }

    /// A display span may cross lines (the reported document uses `\[` on its
    /// own line), and the lines after it must still map to their original
    /// source lines.
    @MainActor
    func testMultiLineDisplayMathKeepsFollowingAnchorLine() {
        let text = """
        \\[
        a_n=\\frac{1}{n(n+1)}
        \\]
        列为：$x$
        """
        let parsed = MarkdownParser().parseDocument(
            text,
            options: MarkdownParseOptions(enableMath: true, enableInlineMath: true)
        )
        guard case let .codeBlock(language, code)? = parsed.elements.first else {
            return XCTFail("the display span must become a math block")
        }
        XCTAssertEqual(language, "math")
        XCTAssertEqual(code.trimmingCharacters(in: .whitespacesAndNewlines), "a_n=\\frac{1}{n(n+1)}")

        // The `列为：` paragraph is the last anchor and sits on source line 4.
        XCTAssertEqual(parsed.anchors.last?.line, 4)
    }

    /// With the preference off, the delimiters stay literal text (the
    /// single-backslash forms keep their CommonMark escape meaning).
    @MainActor
    func testMathDisabledLeavesDelimitersAsText() {
        let parser = MarkdownParser()
        for text in ["\\[x\\]", "$$x$$", "\\(x\\)"] {
            let elements = parser.parse(text)
            XCTAssertFalse(elements.contains {
                if case .codeBlock(let language, _) = $0 { return language == "math" || language == "math-inline" }
                return false
            }, "\(text) must not become math with the preference off")
        }
    }

    /// Math-looking text inside inline code spans and fenced code blocks is
    /// never rewritten.
    @MainActor
    func testMathInsideCodeIsUntouched() {
        let options = MarkdownParseOptions(enableMath: true, enableInlineMath: true)
        let parser = MarkdownParser()

        let inline = parser.parse("Use `$HOME` and `\\[x\\]` here", options: options)
        XCTAssertFalse(inline.contains {
            if case .codeBlock(let language, _) = $0 { return language == "math" || language == "math-inline" }
            return false
        }, "inline code must not be rewritten as math")

        let fenced = parser.parse("```text\n$HOME\n\\[x\\]\n```", options: options)
        XCTAssertTrue(fenced.contains {
            if case .codeBlock(let language, let code) = $0 {
                return language == "text" && code.contains("$HOME")
            }
            return false
        }, "fenced code must not be rewritten as math")
    }

    /// A span that is never closed stays as written instead of swallowing the
    /// rest of the document.
    @MainActor
    func testUnclosedMathSpanIsLeftAlone() {
        let text = "before \\[ never closed\n\nparagraph two"
        let parsed = MarkdownParser().parseDocument(text, options: MarkdownParseOptions(enableMath: true))
        XCTAssertFalse(parsed.elements.contains {
            if case .codeBlock = $0 { return true }
            return false
        })
        XCTAssertEqual(parsed.anchors.last?.line, 3)
    }

    /// Math delimiters inside a table row stay in the cell: a fence cannot live
    /// in a row, so rewriting them would tear the table apart.
    @MainActor
    func testMathInsideATableRowStaysInTheCell() {
        let text = """
        | 公式 | 结果 |
        | --- | --- |
        | \\(E = mc^2\\) | 质能方程 |
        """
        let parsed = MarkdownParser().parseDocument(
            text,
            options: MarkdownParseOptions(enableMath: true, enableInlineMath: true)
        )
        guard case let .table(table)? = parsed.elements.first else {
            return XCTFail("the fixture must stay a table")
        }
        XCTAssertEqual(table.rows.count, 1)
        XCTAssertTrue(
            table.rows[0][0].contains("E = mc^2"),
            "the cell text must stay in the cell, not become a fence"
        )
    }

    /// The reported document writes display math inside list items. The
    /// rewritten fence keeps the line's continuation indent, so it stays in the
    /// item instead of splitting the list.
    @MainActor
    func testDisplayMathInsideAListItemStaysInTheItem() {
        let text = """
        1. 首项
           说明文字
           \\[
           a_n=\\frac{1}{n(n+1)}
           \\]
           后文
        """
        let parsed = MarkdownParser().parseDocument(text, options: MarkdownParseOptions(enableMath: true))
        guard case let .orderedList(items)? = parsed.elements.first,
              let children = items.first?.children else {
            return XCTFail("the fixture must parse as an ordered list")
        }
        let math = children.compactMap { element -> (String, String)? in
            if case let .codeBlock(language, code) = element { return (language ?? "", code) }
            return nil
        }.first
        XCTAssertEqual(math?.0, "math", "the fence must stay inside the list item")
        XCTAssertEqual(
            math?.1.trimmingCharacters(in: .whitespacesAndNewlines),
            "a_n=\\frac{1}{n(n+1)}"
        )
        XCTAssertEqual(parsed.anchors.last?.line, 6)
    }

    @MainActor
    func testNestedBlockquoteAnchorPaths() {
        let text = "> # Quoted"
        let parsed = MarkdownParser().parseDocument(text)
        // blockquote at [0]; its heading child at [0, 0].
        XCTAssertEqual(parsed.anchors.map(\.path), [[0], [0, 0]])
        XCTAssertEqual(parsed.anchors.map(\.line), [1, 1])
    }
}
