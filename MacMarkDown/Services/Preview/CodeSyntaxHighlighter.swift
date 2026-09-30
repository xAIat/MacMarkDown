import SwiftUI

/// A small, dependency-free code tokenizer for the native preview. It is not a
/// full parser: it recognizes comments, strings, numbers and keywords for a
/// broad set of common fence languages, which is enough to make code blocks
/// readable without shipping a JavaScript highlighter.
///
/// Language coverage follows the language list offered in the Rendering
/// preferences. Tokenization is regex-based, so exotic syntax (heredocs,
/// nested templates, macros) may not highlight perfectly.
public enum CodeSyntaxHighlighter {

    public enum TokenKind: Sendable, Hashable {
        case keyword
        case string
        case comment
        case number
    }

    public struct Token: Sendable, Hashable {
        public var range: NSRange
        public var kind: TokenKind
    }

    /// Tokenizes `code` for `language` (case-insensitive, aliases included).
    /// Unknown languages return no tokens (plain text).
    public static func tokenize(_ code: String, language: String?) -> [Token] {
        guard let language else { return [] }
        let grammar = Grammar.forLanguage(language)
        guard !grammar.keywords.isEmpty || grammar.supportsStrings else { return [] }

        var tokens: [Token] = []
        let ns = code as NSString
        let fullRange = NSRange(location: 0, length: ns.length)

        // Comments first so strings/keywords inside them are not highlighted.
        for pattern in grammar.commentPatterns {
            tokens.append(contentsOf: matches(of: pattern, in: code, range: fullRange).map {
                Token(range: $0, kind: .comment)
            })
        }
        let commentRanges = tokens.map(\.range)
        tokens.append(contentsOf: matches(of: grammar.stringPattern, in: code, range: fullRange)
            .filter { !overlaps($0, commentRanges) }
            .map { Token(range: $0, kind: .string) })
        let stringRanges = tokens.filter { $0.kind == .string }.map(\.range)

        let occupied = commentRanges + stringRanges
        if !grammar.keywords.isEmpty {
            let keywordPattern = "\\b(" + grammar.keywords.joined(separator: "|") + ")\\b"
            let options: NSRegularExpression.Options = grammar.caseInsensitiveKeywords
                ? [.anchorsMatchLines, .caseInsensitive]
                : [.anchorsMatchLines]
            tokens.append(contentsOf: matches(of: keywordPattern, in: code, range: fullRange, options: options)
                .filter { !overlaps($0, occupied) }
                .map { Token(range: $0, kind: .keyword) })
        }
        tokens.append(contentsOf: matches(of: grammar.numberPattern, in: code, range: fullRange)
            .filter { !overlaps($0, occupied) }
            .map { Token(range: $0, kind: .number) })

        return tokens.sorted { $0.range.location < $1.range.location }
    }

    /// Everything a highlight result depends on, for the memoization cache.
    private struct HighlightKey: Hashable {
        var code: String
        var language: String?
        var baseColor: Color
        var keywordColor: Color
        var stringColor: Color
        var commentColor: Color
        var numberColor: Color
    }

    /// Box so an `AttributedString` (a value type) can live in an `NSCache`.
    private final class HighlightEntry {
        let key: HighlightKey
        let value: AttributedString
        init(key: HighlightKey, value: AttributedString) {
            self.key = key
            self.value = value
        }
    }

    /// Memoized highlight results. The preview re-evaluates on scroll-driven
    /// updates, and rebuilding every code block's `AttributedString` (and
    /// re-tokenizing it) each time was pure churn. Bounded by `countLimit`.
    /// `NSCache` is thread-safe, hence `nonisolated(unsafe)`.
    private nonisolated(unsafe) static let highlightCache: NSCache<NSString, HighlightEntry> = {
        let cache = NSCache<NSString, HighlightEntry>()
        cache.countLimit = 256
        return cache
    }()

    /// Builds an attributed string with the theme's token colors.
    @MainActor
    public static func highlight(
        _ code: String,
        language: String?,
        baseColor: Color,
        keywordColor: Color,
        stringColor: Color,
        commentColor: Color,
        numberColor: Color
    ) -> AttributedString {
        let key = HighlightKey(
            code: code,
            language: language,
            baseColor: baseColor,
            keywordColor: keywordColor,
            stringColor: stringColor,
            commentColor: commentColor,
            numberColor: numberColor
        )
        let cacheKey = String(key.hashValue) as NSString
        // The hash key can collide; verify the full key before reusing.
        if let entry = highlightCache.object(forKey: cacheKey), entry.key == key {
            return entry.value
        }

        var attributed = AttributedString(code)
        attributed.foregroundColor = baseColor
        for token in tokenize(code, language: language) {
            guard let stringRange = Range(token.range, in: code),
                  let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attributed)
            else { continue }
            let color: Color = switch token.kind {
            case .keyword: keywordColor
            case .string: stringColor
            case .comment: commentColor
            case .number: numberColor
            }
            attributed[lower..<upper].foregroundColor = color
        }
        highlightCache.setObject(HighlightEntry(key: key, value: attributed), forKey: cacheKey)
        return attributed
    }

    // MARK: - Helpers

    /// Compiled regexes, keyed by pattern + options. `NSRegularExpression`
    /// compilation is comparatively expensive and this method runs for every
    /// token kind on every code block, so recompiling per call (as before)
    /// dominated preview updates. `NSCache` is thread-safe, hence
    /// `nonisolated(unsafe)`.
    private nonisolated(unsafe) static let regexCache: NSCache<NSString, NSRegularExpression> = {
        let cache = NSCache<NSString, NSRegularExpression>()
        cache.countLimit = 128
        return cache
    }()

    private static func matches(
        of pattern: String,
        in text: String,
        range: NSRange,
        options: NSRegularExpression.Options = [.anchorsMatchLines]
    ) -> [NSRange] {
        let key = "\(options.rawValue)\u{1F}\(pattern)" as NSString
        let regex: NSRegularExpression
        if let cached = regexCache.object(forKey: key) {
            regex = cached
        } else {
            guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
                return []
            }
            regexCache.setObject(compiled, forKey: key)
            regex = compiled
        }
        return regex.matches(in: text, range: range).map(\.range)
    }

    private static func overlaps(_ range: NSRange, _ others: [NSRange]) -> Bool {
        others.contains { NSIntersectionRange($0, range).length > 0 }
    }

    // MARK: - Grammars

    private struct Grammar {
        var keywords: [String]
        var commentPatterns: [String]
        var stringPattern: String
        var numberPattern: String
        var supportsStrings = true
        /// SQL/Docker/etc. treat keywords case-insensitively.
        var caseInsensitiveKeywords = false

        static let numberPattern = #"\b\d+(\.\d+)?([eE][+-]?\d+)?\b"#
        static let doubleQuoted = #""(?:\\.|[^"\\])*""#
        static let singleDouble = #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#
        static let tripleDouble = #""""[\s\S]*?"""|'''[\s\S]*?'''|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'"#
        static let backtick = #""(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`"#

        static let slashComments = [#"//.*$"#, #"/\*[\s\S]*?\*/"#]
        static let hashComments = [#"#.*$"#]
        static let dashComments = [#"--.*$"#]
        static let percentComments = [#"%.*$"#]
        static let semicolonComments = [#";.*$"#]
        static let htmlComments = [#"<!--[\s\S]*?-->"#]
        static let batchComments = [#"^\s*rem\b.*$"#, #"^\s*::.*$"#]
        static let none: [String] = []

        /// Language aliases → canonical grammar key.
        static let aliases: [String: String] = [
            "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
            "ts": "typescript", "tsx": "typescript",
            "py": "python", "python3": "python",
            "rb": "ruby", "sh": "bash", "shell": "bash", "zsh": "bash", "ksh": "bash",
            "yml": "yaml", "c++": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp",
            "cs": "csharp", "objc": "objectivec", "objective-c": "objectivec",
            "kt": "kotlin", "rs": "rust", "golang": "go", "ps1": "powershell",
            "dockerfile": "docker", "make": "makefile", "tex": "latex", "md": "markdown",
            "gql": "graphql", "proto": "protobuf", "hs": "haskell", "ex": "elixir",
            "erl": "erlang", "clj": "clojure", "ml": "ocaml", "fs": "fsharp",
            "bat": "batch", "cmd": "batch", "text": "plaintext", "txt": "plaintext",
            "less": "css", "sass": "css", "scss": "css", "htm": "html", "xhtml": "html",
            "patch": "diff", "wat": "wasm",
        ]

        static func forLanguage(_ language: String) -> Grammar {
            let key = aliases[language.lowercased()] ?? language.lowercased()
            return table[key] ?? plaintext
        }

        static let plaintext = Grammar(
            keywords: [], commentPatterns: none,
            stringPattern: doubleQuoted, numberPattern: numberPattern, supportsStrings: false
        )

        static let cFamilyKeywords: [String] = [
            "int", "long", "short", "double", "float", "char", "void", "bool", "if", "else",
            "return", "for", "while", "do", "switch", "case", "default", "break", "continue",
            "class", "struct", "enum", "union", "interface", "public", "private", "protected",
            "static", "final", "const", "new", "delete", "try", "catch", "throw", "throws",
            "package", "import", "using", "namespace", "template", "typename", "virtual",
            "override", "abstract", "synchronized", "volatile", "unsigned", "signed", "typedef",
            "sizeof", "goto", "inline", "operator", "this", "super", "true", "false", "null",
            "nullptr", "auto", "var", "readonly", "sealed", "async", "await", "yield", "in",
            "out", "ref", "where", "extends", "implements", "instanceof", "boolean", "string",
        ]

        static let table: [String: Grammar] = [
            "swift": Grammar(keywords: [
                "func", "let", "var", "if", "else", "guard", "return", "class", "struct",
                "enum", "protocol", "extension", "import", "init", "deinit", "self", "Self",
                "nil", "true", "false", "for", "while", "switch", "case", "default", "break",
                "continue", "throws", "try", "catch", "async", "await", "public", "private",
                "internal", "fileprivate", "open", "static", "final", "override", "some", "any",
                "where", "in", "defer", "typealias", "actor", "mutating", "associatedtype",
                "indirect", "convenience", "required", "lazy", "weak", "unowned", "willSet",
                "didSet", "subscript", "inout", "is", "as", "rethrows", "nonisolated",
            ], commentPatterns: slashComments, stringPattern: tripleDouble, numberPattern: numberPattern),

            "objectivec": Grammar(keywords: [
                "int", "long", "double", "float", "char", "void", "BOOL", "if", "else", "return",
                "for", "while", "switch", "case", "default", "break", "continue", "class",
                "struct", "enum", "interface", "implementation", "protocol", "property",
                "synthesize", "dynamic", "import", "include", "public", "private", "protected",
                "static", "const", "id", "nil", "YES", "NO", "self", "super", "nonatomic",
                "strong", "weak", "copy", "retain", "assign", "readonly", "readwrite", "typedef",
                "in", "out", "inout", "bycopy", "oneway", "instancetype", "nullable",
            ], commentPatterns: slashComments, stringPattern: doubleQuoted, numberPattern: numberPattern),

            "c": Grammar(keywords: cFamilyKeywords, commentPatterns: slashComments,
                         stringPattern: doubleQuoted, numberPattern: numberPattern),
            "cpp": Grammar(keywords: cFamilyKeywords, commentPatterns: slashComments,
                           stringPattern: doubleQuoted, numberPattern: numberPattern),
            "csharp": Grammar(keywords: cFamilyKeywords, commentPatterns: slashComments,
                              stringPattern: doubleQuoted, numberPattern: numberPattern),
            "java": Grammar(keywords: cFamilyKeywords, commentPatterns: slashComments,
                            stringPattern: doubleQuoted, numberPattern: numberPattern),
            "kotlin": Grammar(keywords: [
                "fun", "val", "var", "class", "object", "interface", "enum", "data", "sealed",
                "if", "else", "when", "for", "while", "do", "return", "try", "catch", "finally",
                "throw", "import", "package", "private", "public", "internal", "protected",
                "override", "open", "abstract", "suspend", "inline", "operator", "companion",
                "init", "constructor", "this", "super", "null", "true", "false", "is", "as",
                "in", "out", "by", "lazy", "lateinit", "const", "typealias", "where", "reified",
            ], commentPatterns: slashComments, stringPattern: tripleDouble, numberPattern: numberPattern),
            "scala": Grammar(keywords: [
                "def", "val", "var", "class", "object", "trait", "case", "match", "if", "else",
                "for", "while", "do", "return", "import", "package", "private", "protected",
                "override", "abstract", "sealed", "implicit", "final", "lazy", "new", "this",
                "super", "null", "true", "false", "extends", "with", "yield", "type", "given",
            ], commentPatterns: slashComments, stringPattern: tripleDouble, numberPattern: numberPattern),
            "groovy": Grammar(keywords: [
                "def", "class", "interface", "enum", "if", "else", "for", "while", "return",
                "import", "package", "private", "public", "static", "final", "new", "try",
                "catch", "finally", "throw", "true", "false", "null", "this", "super", "in",
            ], commentPatterns: slashComments, stringPattern: tripleDouble, numberPattern: numberPattern),

            "go": Grammar(keywords: [
                "package", "import", "func", "var", "const", "type", "struct", "interface", "map",
                "chan", "if", "else", "for", "range", "return", "switch", "case", "default",
                "break", "continue", "go", "defer", "select", "goto", "fallthrough", "nil",
                "true", "false", "iota", "make", "new", "len", "cap", "append", "copy", "delete",
                "panic", "recover", "string", "int", "int64", "float64", "bool", "byte", "rune",
            ], commentPatterns: slashComments, stringPattern: backtick, numberPattern: numberPattern),

            "rust": Grammar(keywords: [
                "fn", "let", "mut", "const", "static", "struct", "enum", "trait", "impl", "pub",
                "use", "mod", "match", "if", "else", "for", "while", "loop", "return", "break",
                "continue", "where", "self", "Self", "crate", "super", "as", "async", "await",
                "move", "dyn", "ref", "unsafe", "extern", "type", "true", "false", "in", "box",
            ], commentPatterns: slashComments, stringPattern: doubleQuoted, numberPattern: numberPattern),

            "dart": Grammar(keywords: [
                "class", "void", "int", "double", "String", "bool", "var", "final", "const", "if",
                "else", "for", "while", "do", "switch", "case", "default", "return", "import",
                "library", "part", "export", "abstract", "extends", "implements", "mixin", "with",
                "async", "await", "yield", "new", "this", "super", "null", "true", "false",
                "static", "late", "required", "factory", "enum", "typedef", "dynamic", "is", "as",
            ], commentPatterns: slashComments, stringPattern: tripleDouble, numberPattern: numberPattern),

            "python": Grammar(keywords: [
                "def", "class", "if", "elif", "else", "return", "import", "from", "as", "for",
                "while", "break", "continue", "try", "except", "finally", "with", "lambda",
                "None", "True", "False", "and", "or", "not", "in", "is", "pass", "raise",
                "yield", "async", "await", "global", "nonlocal", "assert", "del", "match",
                "case", "self",
            ], commentPatterns: hashComments, stringPattern: tripleDouble, numberPattern: numberPattern),

            "ruby": Grammar(keywords: [
                "def", "end", "class", "module", "if", "elsif", "else", "unless", "while", "until",
                "for", "do", "return", "yield", "require", "include", "extend", "attr_reader",
                "attr_writer", "attr_accessor", "nil", "true", "false", "self", "begin", "rescue",
                "ensure", "raise", "lambda", "proc", "then", "case", "when", "and", "or", "not",
                "module_function", "private", "public", "protected", "new", "super",
            ], commentPatterns: hashComments, stringPattern: tripleDouble, numberPattern: numberPattern),

            "php": Grammar(keywords: [
                "function", "class", "interface", "trait", "extends", "implements", "public",
                "private", "protected", "static", "const", "if", "else", "elseif", "for",
                "foreach", "while", "do", "switch", "case", "default", "return", "echo", "print",
                "require", "require_once", "include", "include_once", "namespace", "use", "new",
                "try", "catch", "finally", "throw", "true", "false", "null", "this", "as",
            ], commentPatterns: slashComments + hashComments, stringPattern: singleDouble, numberPattern: numberPattern),

            "perl": Grammar(keywords: [
                "sub", "my", "our", "local", "if", "elsif", "else", "unless", "while", "until",
                "for", "foreach", "do", "return", "use", "package", "require", "scalar", "print",
                "die", "warn", "last", "next", "and", "or", "not", "eq", "ne", "true", "false",
            ], commentPatterns: hashComments, stringPattern: singleDouble, numberPattern: numberPattern),

            "lua": Grammar(keywords: [
                "function", "local", "if", "then", "elseif", "else", "end", "while", "do", "for",
                "repeat", "until", "return", "nil", "true", "false", "and", "or", "not", "in",
                "break", "goto",
            ], commentPatterns: dashComments, stringPattern: singleDouble, numberPattern: numberPattern),

            "r": Grammar(keywords: [
                "function", "if", "else", "for", "while", "repeat", "break", "next", "return",
                "TRUE", "FALSE", "NULL", "NA", "NaN", "Inf", "library", "require", "in",
            ], commentPatterns: hashComments, stringPattern: singleDouble, numberPattern: numberPattern),

            "julia": Grammar(keywords: [
                "function", "end", "if", "else", "elseif", "for", "while", "return", "struct",
                "mutable", "module", "using", "import", "begin", "let", "do", "try", "catch",
                "finally", "true", "false", "nothing", "where", "in", "const", "abstract", "type",
            ], commentPatterns: hashComments, stringPattern: tripleDouble, numberPattern: numberPattern),

            "haskell": Grammar(keywords: [
                "module", "where", "import", "data", "type", "newtype", "class", "instance", "let",
                "in", "do", "case", "of", "if", "then", "else", "deriving", "default", "foreign",
                "infix", "infixl", "infixr", "forall",
            ], commentPatterns: dashComments + [#"\{-[\s\S]*?-\}"#], stringPattern: doubleQuoted, numberPattern: numberPattern),

            "elixir": Grammar(keywords: [
                "def", "defmodule", "defp", "defmacro", "do", "end", "if", "else", "unless",
                "case", "cond", "when", "fn", "for", "while", "true", "false", "nil", "and",
                "or", "not", "in", "use", "import", "alias", "require", "defstruct", "defprotocol",
            ], commentPatterns: hashComments, stringPattern: tripleDouble, numberPattern: numberPattern),

            "erlang": Grammar(keywords: [
                "module", "export", "import", "if", "case", "of", "end", "fun", "let", "true",
                "false", "receive", "after", "try", "catch", "when", "begin",
            ], commentPatterns: percentComments, stringPattern: doubleQuoted, numberPattern: numberPattern),

            "clojure": Grammar(keywords: [
                "def", "defn", "defmacro", "let", "fn", "if", "do", "loop", "recur", "ns",
                "require", "import", "true", "false", "nil", "cond", "when", "case", "and", "or",
                "not", "quote", "var", "set!",
            ], commentPatterns: semicolonComments, stringPattern: doubleQuoted, numberPattern: numberPattern),

            "ocaml": Grammar(keywords: [
                "let", "in", "rec", "and", "module", "struct", "sig", "end", "type", "match",
                "with", "if", "then", "else", "fun", "function", "begin", "open", "val", "class",
                "object", "method", "inherit", "mutable", "true", "false", "as",
            ], commentPatterns: [#"\(\*[\s\S]*?\*\)"#], stringPattern: doubleQuoted, numberPattern: numberPattern),

            "fsharp": Grammar(keywords: [
                "let", "in", "rec", "and", "module", "namespace", "type", "member", "match",
                "with", "if", "then", "else", "elif", "fun", "function", "begin", "end", "open",
                "mutable", "true", "false", "do", "yield", "return", "async", "task",
            ], commentPatterns: slashComments + [#"\(\*[\s\S]*?\*\)"#], stringPattern: doubleQuoted, numberPattern: numberPattern),

            "sql": Grammar(keywords: [
                "select", "from", "where", "insert", "into", "values", "update", "set", "delete",
                "create", "table", "drop", "alter", "join", "inner", "left", "right", "outer",
                "full", "cross", "on", "group", "by", "order", "having", "limit", "offset",
                "union", "all", "as", "and", "or", "not", "null", "primary", "key", "foreign",
                "references", "index", "distinct", "count", "sum", "avg", "min", "max", "case",
                "when", "then", "else", "end", "in", "like", "between", "exists", "asc", "desc",
            ], commentPatterns: dashComments + [#"/\*[\s\S]*?\*/"#], stringPattern: singleDouble, numberPattern: numberPattern, caseInsensitiveKeywords: true),

            "yaml": Grammar(keywords: ["true", "false", "null", "yes", "no", "on", "off"],
                            commentPatterns: hashComments, stringPattern: singleDouble,
                            numberPattern: numberPattern, supportsStrings: false),
            "toml": Grammar(keywords: ["true", "false"], commentPatterns: hashComments,
                            stringPattern: singleDouble, numberPattern: numberPattern, supportsStrings: false),
            "ini": Grammar(keywords: [], commentPatterns: semicolonComments + hashComments,
                           stringPattern: singleDouble, numberPattern: numberPattern, supportsStrings: false),

            "docker": Grammar(keywords: [
                "from", "run", "cmd", "entrypoint", "copy", "add", "env", "expose", "volume",
                "workdir", "user", "arg", "label", "maintainer", "healthcheck", "shell", "onbuild",
                "stopsignal", "as",
            ], commentPatterns: hashComments, stringPattern: singleDouble, numberPattern: numberPattern, caseInsensitiveKeywords: true),

            "makefile": Grammar(keywords: [
                "include", "define", "endef", "ifeq", "ifneq", "ifdef", "ifndef", "else", "endif",
                "export", "unexport", "override", "vpath",
            ], commentPatterns: hashComments, stringPattern: doubleQuoted,
               numberPattern: numberPattern, supportsStrings: false),

            "cmake": Grammar(keywords: [
                "cmake_minimum_required", "project", "add_executable", "add_library", "target_link_libraries",
                "set", "if", "else", "elseif", "endif", "foreach", "endforeach", "function",
                "endfunction", "macro", "endmacro", "include", "find_package", "target_include_directories",
            ], commentPatterns: hashComments, stringPattern: doubleQuoted,
               numberPattern: numberPattern, supportsStrings: false),

            "bash": Grammar(keywords: [
                "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case",
                "esac", "function", "return", "export", "local", "readonly", "declare", "echo",
                "cd", "set", "unset", "source", "alias", "in", "select", "time", "eval", "exec",
            ], commentPatterns: hashComments, stringPattern: singleDouble, numberPattern: numberPattern),

            "powershell": Grammar(keywords: [
                "function", "param", "if", "else", "elseif", "foreach", "for", "while", "do",
                "switch", "return", "try", "catch", "finally", "throw", "begin", "process",
                "end", "in", "filter", "class", "enum", "true", "false", "null", "new",
            ], commentPatterns: hashComments + [#"<#[\s\S]*?#>"#], stringPattern: singleDouble, numberPattern: numberPattern),

            "batch": Grammar(keywords: [
                "if", "else", "for", "in", "do", "goto", "call", "set", "setlocal", "endlocal",
                "echo", "rem", "exit", "not", "exist", "defined", "equ", "neq", "lss", "leq",
                "gtr", "geq",
            ], commentPatterns: batchComments, stringPattern: doubleQuoted,
               numberPattern: numberPattern, supportsStrings: false, caseInsensitiveKeywords: true),

            "javascript": Grammar(keywords: [
                "var", "let", "const", "function", "class", "extends", "return", "if", "else",
                "for", "while", "do", "switch", "case", "default", "break", "continue", "new",
                "this", "null", "undefined", "true", "false", "typeof", "instanceof", "of", "in",
                "try", "catch", "finally", "throw", "import", "export", "from", "async", "await",
                "yield", "delete", "void", "super", "static", "get", "set", "interface", "type",
                "enum", "implements", "public", "private", "protected", "readonly", "declare",
            ], commentPatterns: slashComments, stringPattern: backtick, numberPattern: numberPattern),
            "typescript": Grammar(keywords: [
                "var", "let", "const", "function", "class", "extends", "implements", "interface",
                "type", "enum", "namespace", "module", "declare", "return", "if", "else", "for",
                "while", "do", "switch", "case", "default", "break", "continue", "new", "this",
                "null", "undefined", "true", "false", "typeof", "instanceof", "of", "in", "try",
                "catch", "finally", "throw", "import", "export", "from", "async", "await", "yield",
                "delete", "void", "super", "static", "get", "set", "public", "private", "protected",
                "readonly", "abstract", "keyof", "infer", "satisfies", "as",
            ], commentPatterns: slashComments, stringPattern: backtick, numberPattern: numberPattern),

            "json": Grammar(keywords: ["true", "false", "null"], commentPatterns: [],
                            stringPattern: doubleQuoted, numberPattern: numberPattern, supportsStrings: true),

            "css": Grammar(keywords: [], commentPatterns: [#"/\*[\s\S]*?\*/"#],
                           stringPattern: singleDouble, numberPattern: #"\b\d+(\.\d+)?(px|em|rem|%|s|ms|vh|vw|pt|deg)?\b"#,
                           supportsStrings: false),

            "html": Grammar(keywords: [], commentPatterns: htmlComments,
                            stringPattern: singleDouble, numberPattern: numberPattern, supportsStrings: false),
            "xml": Grammar(keywords: [], commentPatterns: htmlComments,
                           stringPattern: singleDouble, numberPattern: numberPattern, supportsStrings: false),
            "svg": Grammar(keywords: [], commentPatterns: htmlComments,
                           stringPattern: singleDouble, numberPattern: numberPattern, supportsStrings: false),

            "markdown": Grammar(keywords: [], commentPatterns: htmlComments,
                                stringPattern: doubleQuoted, numberPattern: numberPattern, supportsStrings: false),

            "latex": Grammar(keywords: [
                "documentclass", "usepackage", "begin", "end", "section", "subsection",
                "subsubsection", "paragraph", "label", "ref", "cite", "item", "textbf", "textit",
                "emph", "frac", "sqrt", "sum", "int", "alpha", "beta", "gamma", "delta", "infty",
            ], commentPatterns: percentComments, stringPattern: doubleQuoted,
               numberPattern: numberPattern, supportsStrings: false),

            "graphql": Grammar(keywords: [
                "query", "mutation", "subscription", "fragment", "on", "type", "schema", "input",
                "enum", "interface", "union", "scalar", "directive", "extend", "implements", "true",
                "false", "null",
            ], commentPatterns: hashComments, stringPattern: tripleDouble, numberPattern: numberPattern),

            "diff": Grammar(keywords: [], commentPatterns: [],
                            stringPattern: doubleQuoted, numberPattern: numberPattern, supportsStrings: false),

            "protobuf": Grammar(keywords: [
                "syntax", "package", "import", "option", "message", "enum", "service", "rpc",
                "returns", "repeated", "optional", "required", "oneof", "map", "reserved", "extend",
                "true", "false",
            ], commentPatterns: slashComments, stringPattern: singleDouble, numberPattern: numberPattern),

            "wasm": Grammar(keywords: [
                "module", "func", "param", "result", "local", "global", "memory", "table", "export",
                "import", "type", "start", "elem", "data", "mut", "i32", "i64", "f32", "f64",
            ], commentPatterns: [#";;.*$"#], stringPattern: doubleQuoted,
               numberPattern: numberPattern, supportsStrings: false, caseInsensitiveKeywords: true),

            "nginx": Grammar(keywords: [
                "server", "location", "upstream", "events", "http", "listen", "server_name",
                "root", "index", "proxy_pass", "try_files", "return", "rewrite", "include",
                "worker_processes", "error_log", "access_log", "gzip", "ssl_certificate",
            ], commentPatterns: hashComments, stringPattern: singleDouble,
               numberPattern: numberPattern, supportsStrings: false, caseInsensitiveKeywords: true),

            "vim": Grammar(keywords: [
                "set", "let", "if", "else", "elseif", "endif", "function", "endfunction",
                "command", "map", "nmap", "vmap", "imap", "autocmd", "syntax", "highlight",
                "return", "call", "while", "endwhile", "for", "endfor", "try", "catch", "finally",
            ], commentPatterns: [#""".*$"#], stringPattern: singleDouble,
               numberPattern: numberPattern, supportsStrings: false),
        ]
    }
}
