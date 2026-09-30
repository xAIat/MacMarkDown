import SwiftUI
import XCTest

@testable import MacMarkDownKit

final class PreviewRenderingTests: XCTestCase {

    // MARK: - Code highlighter

    func testSwiftKeywordsAndStrings() {
        let code = #"let name = "MacMarkDown" // comment"#
        let tokens = CodeSyntaxHighlighter.tokenize(code, language: "swift")
        let ns = code as NSString
        XCTAssertTrue(tokens.contains {
            $0.kind == .keyword && ns.substring(with: $0.range) == "let"
        })
        XCTAssertTrue(tokens.contains {
            $0.kind == .string && ns.substring(with: $0.range) == "\"MacMarkDown\""
        })
        XCTAssertTrue(tokens.contains { $0.kind == .comment })
    }

    func testPythonCommentsUseHash() {
        let code = "def f():\n    return 1  # done"
        let tokens = CodeSyntaxHighlighter.tokenize(code, language: "python")
        let ns = code as NSString
        XCTAssertTrue(tokens.contains {
            $0.kind == .comment && ns.substring(with: $0.range).contains("done")
        })
    }

    func testUnknownLanguageReturnsNoTokens() {
        XCTAssertTrue(CodeSyntaxHighlighter.tokenize("anything", language: "brainfuck").isEmpty)
    }

    func testExpandedLanguageCoverage() {
        let samples: [(String, String, String)] = [
            ("go", "func main() {}", "func"),
            ("rust", "fn main() {}", "fn"),
            ("ruby", "def foo\nend", "def"),
            ("php", "<?php function f() {}", "function"),
            ("sql", "SELECT * FROM t", "SELECT"),
            ("yaml", "enabled: true", "true"),
            ("docker", "FROM swift:latest", "FROM"),
            ("bash", "if true; then echo hi; fi", "if"),
            ("powershell", "function Get-Thing {}", "function"),
            ("haskell", "module Main where", "module"),
            ("elixir", "defmodule Foo do\nend", "defmodule"),
            ("kotlin", "fun main() {}", "fun"),
            ("scala", "def main(): Unit = {}", "def"),
            ("graphql", "query Q { id }", "query"),
            ("protobuf", "message Foo {}", "message"),
            ("wasm", "(module (func))", "module"),
            ("latex", "\\begin{document}", "begin"),
            ("vim", "set number", "set"),
        ]
        for (language, code, keyword) in samples {
            let tokens = CodeSyntaxHighlighter.tokenize(code, language: language)
            let ns = code as NSString
            XCTAssertTrue(
                tokens.contains { $0.kind == .keyword && ns.substring(with: $0.range) == keyword },
                "\(language) did not highlight '\(keyword)'"
            )
        }
    }

    func testLanguageAliases() {
        XCTAssertFalse(CodeSyntaxHighlighter.tokenize("if true; then fi", language: "sh").isEmpty)
        XCTAssertFalse(CodeSyntaxHighlighter.tokenize("k: true", language: "yml").isEmpty)
        XCTAssertFalse(CodeSyntaxHighlighter.tokenize("fn f() {}", language: "rs").isEmpty)
    }

    func testKeywordInsideStringIsNotHighlighted() {
        let code = #""let x = 1""#
        let tokens = CodeSyntaxHighlighter.tokenize(code, language: "swift")
        XCTAssertFalse(tokens.contains { $0.kind == .keyword })
    }

    // MARK: - Image URL resolution

    func testRelativeImageResolvesAgainstDocumentDirectory() {
        let base = URL(fileURLWithPath: "/tmp/docs")
        let resolved = PreviewImageView.resolve(url: "img/pic.png", baseURL: base)
        XCTAssertEqual(resolved?.path, "/tmp/docs/img/pic.png")
    }

    func testAbsoluteImageURLPassesThrough() {
        let resolved = PreviewImageView.resolve(
            url: "https://example.com/a.png",
            baseURL: URL(fileURLWithPath: "/tmp/docs")
        )
        XCTAssertEqual(resolved?.absoluteString, "https://example.com/a.png")
    }

    func testMissingImageURLIsNil() {
        XCTAssertNil(PreviewImageView.resolve(url: nil, baseURL: nil))
        XCTAssertNil(PreviewImageView.resolve(url: "", baseURL: nil))
    }

    // MARK: - Bundled stylesheet pipeline

    func testBundledStyleSheetsAreAvailable() {
        XCTAssertTrue(ResourceLoader.availableStyleNames.contains("Clearness"))
        XCTAssertTrue(ResourceLoader.availableStyleNames.contains("GitHub"))
    }

    @MainActor
    func testThemeResolvesToBundledCSS() {
        let renderer = Renderer(parser: MarkdownParser(), theme: .clearness)
        let html = renderer.renderToHTML("# Hi", title: "T")
        // A rule from the bundled Clearness.css, not the generated fallback.
        XCTAssertTrue(html.contains("blockquote:before"))
    }

    /// Chinese text must render in PingFang SC in both the bundled stylesheets
    /// and the generated fallback, matching the native preview.
    @MainActor
    func testExportedCSSPrefersPingFangForChinese() {
        for theme in [Theme.clearness, .night] {
            let html = Renderer(parser: MarkdownParser(), theme: theme).renderToHTML("# Hi", title: "T")
            XCTAssertTrue(html.contains("\"PingFang SC\""), "\(theme.name) must ask for PingFang SC")
        }
    }

    @MainActor
    func testUnknownThemeFallsBackToGeneratedCSS() {
        let renderer = Renderer(parser: MarkdownParser(), theme: .night)
        let html = renderer.renderToHTML("# Hi", title: "T")
        XCTAssertTrue(html.contains("-apple-system"))
    }

    // MARK: - TOC / hard wrap through the parser

    @MainActor
    func testTOCPlaceholderExpandsWhenEnabled() {
        let parser = MarkdownParser()
        let options = MarkdownParseOptions(enableTOC: true)
        let elements = parser.parse("# One\n\n[toc]\n\n## Two", options: options)
        guard let toc = elements.first(where: {
            if case .tableOfContents = $0 { return true }
            return false
        }), case let .tableOfContents(items) = toc else {
            return XCTFail("Expected table of contents")
        }
        XCTAssertEqual(items.map(\.text), ["One", "Two"])
        XCTAssertEqual(items.map(\.level), [1, 2])
    }

    @MainActor
    func testTOCPlaceholderStaysTextWhenDisabled() {
        let parser = MarkdownParser()
        let elements = parser.parse("# One\n\n[toc]", options: MarkdownParseOptions(enableTOC: false))
        XCTAssertFalse(elements.contains {
            if case .tableOfContents = $0 { return true }
            return false
        })
    }

    @MainActor
    func testHardWrapTurnsSoftBreaksIntoLineBreaks() {
        let parser = MarkdownParser()
        let wrapped = parser.parse("a\nb", options: MarkdownParseOptions(enableHardWrap: true))
        guard case let .paragraph(inlines) = wrapped.first else { return XCTFail("paragraph") }
        XCTAssertTrue(inlines.contains { if case .lineBreak = $0 { return true }; return false })

        let soft = parser.parse("a\nb", options: MarkdownParseOptions(enableHardWrap: false))
        guard case let .paragraph(softInlines) = soft.first else { return XCTFail("paragraph") }
        XCTAssertFalse(softInlines.contains { if case .lineBreak = $0 { return true }; return false })
    }

    // MARK: - HTML output

    @MainActor
    func testHTMLTableAlignment() {
        let renderer = Renderer(parser: MarkdownParser(), theme: .clearness)
        let html = renderer.renderToHTML("| a | b |\n|:--|--:|\n| 1 | 2 |")
        XCTAssertTrue(html.contains("text-align: left"))
        XCTAssertTrue(html.contains("text-align: right"))
    }

    @MainActor
    func testHTMLTOCAnchors() {
        let parser = MarkdownParser()
        let renderer = Renderer(
            parser: parser,
            theme: .clearness,
            options: MarkdownParseOptions(enableTOC: true)
        )
        let html = renderer.renderToHTML("# One\n\n[toc]")
        XCTAssertTrue(html.contains("id=\"toc_0\""))
        XCTAssertTrue(html.contains("class=\"toc\""))
    }

    @MainActor
    func testHTMLTOCDisabledByOptions() {
        let renderer = Renderer(parser: MarkdownParser(), theme: .clearness)
        let html = renderer.renderToHTML("# One\n\n[toc]")
        XCTAssertFalse(html.contains("class=\"toc\""))
    }

    @MainActor
    func testFrontMatterRendersAsTable() {
        let parser = MarkdownParser()
        let renderer = Renderer(parser: parser, theme: .clearness)
        let html = renderer.renderToHTML("---\ntitle: Hello\nauthor: Me\n---\n\nBody")
        XCTAssertTrue(html.contains("class=\"front-matter\""))
        XCTAssertTrue(html.contains("<th>title</th>"))
        XCTAssertTrue(html.contains("<td>Hello</td>"))
        XCTAssertTrue(html.contains("<th>author</th>"))
        XCTAssertTrue(html.contains("Body"))
    }

    @MainActor
    func testFrontMatterDetectionDisabledOmitsTable() {
        let parser = MarkdownParser()
        let renderer = Renderer(
            parser: parser,
            theme: .clearness,
            options: MarkdownParseOptions(enableFrontMatter: false)
        )
        let html = renderer.renderToHTML("---\ntitle: Hello\n---\n\nBody")
        XCTAssertFalse(html.contains("class=\"front-matter\""))
        XCTAssertTrue(html.contains("title: Hello"))
    }

    @MainActor
    func testNoFrontMatterOmitsTable() {
        let renderer = Renderer(parser: MarkdownParser(), theme: .clearness)
        let html = renderer.renderToHTML("Just body")
        XCTAssertFalse(html.contains("class=\"front-matter\""))
    }

    @MainActor
    func testHTMLHardWrap() {
        let parser = MarkdownParser()
        let elements = parser.parse("a\nb", options: MarkdownParseOptions(enableHardWrap: true))
        XCTAssertTrue(elements.contains {
            if case let .paragraph(inlines) = $0 {
                return inlines.contains { if case .lineBreak = $0 { return true }; return false }
            }
            return false
        })
    }
}
// MARK: - HTML export: highlighting and web blocks (P6)

@MainActor
final class HTMLExportEnhancementTests: XCTestCase {

    func testCodeHighlightSpansInExport() {
        let renderer = Renderer(parser: MarkdownParser(), theme: .clearness)
        let html = renderer.renderToHTML("```swift\nlet x = \"a\" // c\n```")
        XCTAssertTrue(html.contains("tok-keyword"))
        XCTAssertTrue(html.contains("tok-string"))
        XCTAssertTrue(html.contains("tok-comment"))
        XCTAssertTrue(html.contains(".tok-keyword"))
    }

    func testCodeHighlightingCanBeDisabled() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(enableSyntaxHighlighting: false)
        )
        let html = renderer.renderToHTML("```swift\nlet x = 1\n```")
        XCTAssertFalse(html.contains("tok-keyword"))
        XCTAssertTrue(html.contains("let x = 1"))
    }

    func testMermaidBlockEmitsScriptAndMarkup() {
        let renderer = Renderer(parser: MarkdownParser(), theme: .clearness)
        let html = renderer.renderToHTML("```mermaid\ngraph TD; A-->B;\n```")
        XCTAssertTrue(html.contains("<pre class=\"mermaid\">"))
        XCTAssertTrue(html.contains("mermaid.initialize"))
    }

    func testGraphvizBlockEmitsScriptAndMarkup() {
        let renderer = Renderer(parser: MarkdownParser(), theme: .clearness)
        let html = renderer.renderToHTML("```dot\ndigraph { a -> b }\n```")
        XCTAssertTrue(html.contains("class=\"graphviz\""))
        XCTAssertTrue(html.contains("renderSVGElement"))
    }

    func testMathBlockEmitsMathJax() {
        let renderer = Renderer(parser: MarkdownParser(), theme: .clearness)
        let html = renderer.renderToHTML("```math\nE = mc^2\n```")
        XCTAssertTrue(html.contains("class=\"math-block\""))
        XCTAssertTrue(html.contains("mathjax"))
    }

    /// The reported document's `\[ … \]` display math must survive the export
    /// as a MathJax block, not as escaped prose brackets.
    @MainActor
    func testDisplayMathDelimitersExportAsMathBlocks() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(enableMath: true)
        )
        let html = renderer.renderToHTML("\\[E = mc^2\\]")
        XCTAssertTrue(html.contains("class=\"math-block\""), html)
        XCTAssertTrue(html.contains("\\[E = mc^2\\]"), html)
        XCTAssertTrue(html.contains("MathJax"), html)
    }

    /// Some generators write the delimiters with escaped backslashes
    /// (`\\[ … \\]`); that form must export as math too.
    @MainActor
    func testDoubleBackslashMathDelimitersExportAsMathBlocks() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(enableMath: true)
        )
        let html = renderer.renderToHTML("\\\\[A^T_S = B\\\\]")
        XCTAssertTrue(html.contains("class=\"math-block\""), html)
        XCTAssertTrue(html.contains("MathJax"), html)
    }

    @MainActor
    func testInlineMathRewritesToBlock() {
        let parser = MarkdownParser()
        let elements = parser.parse(
            "Energy is $E = mc^2$ here",
            options: MarkdownParseOptions(enableInlineMath: true)
        )
        XCTAssertTrue(elements.contains {
            if case .codeBlock(let language, let code) = $0 {
                return language == "math-inline" && code.contains("E = mc^2")
            }
            return false
        })
    }

    @MainActor
    func testInlineMathDisabledLeavesDollarText() {
        let parser = MarkdownParser()
        let elements = parser.parse(
            "Energy is $E = mc^2$ here",
            options: MarkdownParseOptions(enableInlineMath: false)
        )
        XCTAssertFalse(elements.contains {
            if case .codeBlock(let language, _) = $0 { return language == "math-inline" }
            return false
        })
    }

    @MainActor
    func testInlineMathHTMLUsesInlineDelimiters() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(enableInlineMath: true)
        )
        let html = renderer.renderToHTML("Energy is $E = mc^2$ here")
        XCTAssertTrue(html.contains("class=\"math-inline\""), html)
        XCTAssertTrue(html.contains("\\(E = mc^2\\)"), html)
    }

    func testCJKDetectionForSyntheticItalic() {
        XCTAssertTrue(InlineRenderer.containsCJK("中文"))
        XCTAssertTrue(InlineRenderer.containsCJK("日本語"))
        XCTAssertTrue(InlineRenderer.containsCJK("한국어"))
        XCTAssertTrue(InlineRenderer.containsCJK("混合 text 中文"))
        XCTAssertFalse(InlineRenderer.containsCJK("plain latin text"))
        XCTAssertFalse(InlineRenderer.containsCJK("café — naïve"))
    }

    func testBundledOfflineAssetsExist() {
        XCTAssertNotNil(ResourceLoader.text(named: "mermaid.min.js", in: Constants.extensionsDirectoryName))
        XCTAssertNotNil(ResourceLoader.text(named: "viz.js", in: Constants.extensionsDirectoryName))
        XCTAssertNotNil(ResourceLoader.text(named: "mathjax-tex-svg.js", in: Constants.extensionsDirectoryName))
    }

    @MainActor
    func testMathExportInlinesBundledScript() {
        let renderer = Renderer(parser: MarkdownParser(), theme: .clearness)
        let html = renderer.renderToHTML("```math\nE = mc^2\n```")
        // The bundled distribution is inlined rather than linked from the CDN.
        XCTAssertTrue(html.contains("MathJax"))
        XCTAssertFalse(html.contains("cdn.jsdelivr.net/npm/mathjax"))
    }

    @MainActor
    func testHighlightingThemeChangesTokenColor() {
        let defaultRenderer = Renderer(parser: MarkdownParser(), theme: .clearness)
        let monokai = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(highlightingThemeName: "Monokai")
        )
        let code = "```swift\nlet x = 1\n```"
        let defaultHTML = defaultRenderer.renderToHTML(code)
        let monokaiHTML = monokai.renderToHTML(code)
        XCTAssertNotEqual(defaultHTML, monokaiHTML)
        XCTAssertTrue(monokaiHTML.contains(".tok-keyword"))
    }

    @MainActor
    func testCodeBlockLineNumbersInExport() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(enableLineNumbers: true)
        )
        let html = renderer.renderToHTML("```swift\nlet a = 1\nlet b = 2\n```")
        XCTAssertTrue(html.contains("class=\"line-numbers\""))
        XCTAssertTrue(html.contains("class=\"code-block\""))
    }

    @MainActor
    func testCodeBlockAccessoryLanguageName() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(codeBlockAccessory: 1)
        )
        let html = renderer.renderToHTML("```swift\nlet a = 1\n```")
        XCTAssertTrue(html.contains("class=\"code-language\">swift"))
    }

    @MainActor
    func testCodeBlockAccessoryCustom() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(codeBlockAccessory: 2)
        )
        let html = renderer.renderToHTML("```\nplain\n```")
        XCTAssertTrue(html.contains("class=\"code-language\">Code"))
    }

    @MainActor
    func testCodeBlockAccessoryNone() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(codeBlockAccessory: 0)
        )
        let html = renderer.renderToHTML("```swift\nlet a = 1\n```")
        XCTAssertFalse(html.contains("class=\"code-language\">"))
    }

    func testDefaultTemplateIsBundled() {
        XCTAssertNotNil(ResourceLoader.template(named: "Default"))
        XCTAssertTrue(ResourceLoader.availableTemplateNames.contains("Default"))
    }

    @MainActor
    func testRendererUsesBundledTemplate() {
        let renderer = Renderer(
            parser: MarkdownParser(),
            theme: .clearness,
            options: MarkdownParseOptions(templateName: "Default")
        )
        let html = renderer.renderToHTML("Body", title: "T")
        XCTAssertTrue(html.contains("<title>T</title>"))
        XCTAssertTrue(html.contains("Body"))
    }
}
