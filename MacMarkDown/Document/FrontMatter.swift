import Foundation
import Yams

/// A parsed YAML front-matter value. Supports scalars, sequences and nested
/// mappings so front matter renders as nested tables.
public indirect enum FrontMatterValue: Sendable, Hashable {
    case scalar(String)
    case list([FrontMatterValue])
    case map([FrontMatterEntry])

    /// A single-line rendering used for titles, link resolution and the
    /// flattened `data` accessor.
    public var displayString: String {
        switch self {
        case .scalar(let value):
            return value
        case .list(let items):
            return items.map(\.displayString).joined(separator: ", ")
        case .map(let entries):
            return entries.map { "\($0.key): \($0.value.displayString)" }.joined(separator: ", ")
        }
    }
}

/// One key/value pair in a front-matter mapping, preserving key order.
public struct FrontMatterEntry: Sendable, Hashable {
    public var key: String
    public var value: FrontMatterValue

    public init(key: String, value: FrontMatterValue) {
        self.key = key
        self.value = value
    }
}

/// Parses YAML front matter from the top of a Markdown document.
///
/// Front matter is delimited by `---` lines at the very start of the file and
/// parsed with Yams, so nested mappings, sequences and quoted/typed scalars are
/// all supported.
public struct FrontMatter: Sendable, Equatable {
    public var title: String?
    public var entries: [FrontMatterEntry]
    public var body: String
    /// Number of source lines consumed by the front-matter block (including
    /// the `---` delimiters). Used to keep parser line numbers aligned with the
    /// original document.
    public var consumedLineCount: Int

    public init(title: String?, entries: [FrontMatterEntry], body: String, consumedLineCount: Int = 0) {
        self.title = title
        self.entries = entries
        self.body = body
        self.consumedLineCount = consumedLineCount
    }

    /// Flattened `key → display string` view, kept for callers that only need
    /// a simple dictionary (e.g. title fallback and legacy tests).
    public var data: [String: String] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value.displayString) })
    }

    /// Attempt to extract front matter from raw Markdown text.
    public static func extract(from text: String) -> FrontMatter? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 2 else { return nil }
        guard lines[0].trimmingCharacters(in: .whitespaces) == "---" else { return nil }

        var closingIndex: Int?
        for index in 1..<lines.count
        where lines[index].trimmingCharacters(in: .whitespaces) == "---" {
            closingIndex = index
            break
        }
        guard let closingIndex else { return nil }

        let yaml = lines[1..<closingIndex].joined(separator: "\n")
        let bodyLines = lines[(closingIndex + 1)...]
        var body = bodyLines.joined(separator: "\n")
        body = String(body.drop(while: { $0.isNewline }))

        let entries = parseEntries(yaml)
        let title = entries.first { $0.key == "title" }?.value.displayString
        return FrontMatter(
            title: title,
            entries: entries,
            body: body,
            consumedLineCount: closingIndex + 1
        )
    }

    /// Detect whether the text begins with front matter, for the "Detect Front
    /// Matter" preference gate.
    public static func hasFrontMatter(_ text: String) -> Bool {
        extract(from: text) != nil
    }

    // MARK: - YAML conversion

    private static func parseEntries(_ yaml: String) -> [FrontMatterEntry] {
        guard let object = try? Yams.load(yaml: yaml) else { return [] }
        guard let mapping = object as? [String: Any] else { return [] }
        return mapping.keys.sorted().map { key in
            FrontMatterEntry(key: key, value: value(from: mapping[key]!))
        }
    }

    private static func value(from object: Any) -> FrontMatterValue {
        if let mapping = object as? [String: Any] {
            return .map(mapping.keys.sorted().map { key in
                FrontMatterEntry(key: key, value: value(from: mapping[key]!))
            })
        }
        if let mapping = object as? [AnyHashable: Any] {
            let pairs = mapping.map { (String(describing: $0.key), $0.value) }
                .sorted { $0.0 < $1.0 }
            return .map(pairs.map { FrontMatterEntry(key: $0.0, value: value(from: $0.1)) })
        }
        if let array = object as? [Any] {
            return .list(array.map(value(from:)))
        }
        if let bool = object as? Bool {
            return .scalar(bool ? "true" : "false")
        }
        return .scalar(String(describing: object))
    }
}
