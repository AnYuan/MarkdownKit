//
//  SplashHighlighter.swift
//  MarkdownKit
//

import Foundation
import Splash

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A thread-safe utility wrapper around the `Splash` syntax highlighter.
/// This executes efficiently on background queues to generate fully styled `NSAttributedString`s
/// before the LayoutSolver measures them.
public struct SplashHighlighter {

    /// Languages that Splash can tokenize correctly (Swift grammar only).
    public static let swiftFamilyLanguages: Set<String> = [
        "swift", "swift5", "swift6", "swiftlang"
    ]

    /// All languages with any highlighting support (Swift + generic keyword).
    public static let supportedLanguages: Set<String> = {
        var set = swiftFamilyLanguages
        set.formUnion(GenericKeywordHighlighter.supportedLanguages)
        return set
    }()

    private let highlighter: SyntaxHighlighter<AttributedStringOutputFormat>
    private let genericHighlighter: GenericKeywordHighlighter
    private let theme: Theme
    private var plainCodeAttributes: [NSAttributedString.Key: Any] {
        [
            .font: theme.typography.codeBlock.font,
            .foregroundColor: theme.colors.textColor.foreground
        ]
    }

    public init(theme: Theme = .default) {
        self.theme = theme

        // Map our global Theme's typography to Splash's specific Font format
        let splashFont = splashFontFrom(token: theme.typography.codeBlock)

        let syntaxColors = theme.syntaxColors

        // Define a custom Splash theme bridging our ColorTokens for Light/Dark mode parity
        let splashTheme = Splash.Theme(
            font: splashFont,
            plainTextColor: splashColor(from: theme.colors.textColor.foreground),
            tokenColors: [
                .keyword: splashColor(from: syntaxColors.keyword),
                .string: splashColor(from: syntaxColors.string),
                .type: splashColor(from: syntaxColors.type),
                .call: splashColor(from: syntaxColors.call),
                .number: splashColor(from: syntaxColors.number),
                .comment: splashColor(from: syntaxColors.comment),
                .property: splashColor(from: syntaxColors.property),
                .dotAccess: splashColor(from: syntaxColors.dotAccess),
                .preprocessing: splashColor(from: syntaxColors.preprocessing)
            ]
        )

        let format = AttributedStringOutputFormat(theme: splashTheme)
        self.highlighter = SyntaxHighlighter(format: format)
        self.genericHighlighter = GenericKeywordHighlighter(
            keywordColor: syntaxColors.keyword,
            stringColor: syntaxColors.string,
            commentColor: syntaxColors.comment,
            numberColor: syntaxColors.number,
            plainAttributes: { [
                .font: theme.typography.codeBlock.font,
                .foregroundColor: theme.colors.textColor.foreground
            ] }
        )
    }

    /// Returns a syntax-highlighted attributed string for the given code.
    /// - Parameters:
    ///   - code: The raw string of code.
    ///   - language: Optional language identifier (e.g. "swift").
    ///     Swift-family languages use Splash tokenization, known non-Swift languages
    ///     use generic keyword highlighting, and unknown languages fall back to plain styling.
    public func highlight(_ code: String, language: String? = nil) -> NSAttributedString {
        if isSwiftFamily(language) {
            return highlighter.highlight(code)
        }

        if let lang = normalizedLanguage(language),
           GenericKeywordHighlighter.supportedLanguages.contains(lang) {
            return genericHighlighter.highlight(code, language: lang)
        }

        return NSAttributedString(string: code, attributes: plainCodeAttributes)
    }

    private func isSwiftFamily(_ language: String?) -> Bool {
        guard let lang = normalizedLanguage(language) else {
            // Unlabeled code blocks should NOT default to Swift tokenization.
            // Applying Swift grammar to unknown code produces misleading highlights.
            return false
        }
        return Self.swiftFamilyLanguages.contains(lang)
    }

    private func normalizedLanguage(_ language: String?) -> String? {
        guard let language else { return nil }
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.lowercased()
    }
}

// MARK: - GenericKeywordHighlighter

/// A lightweight regex-based highlighter for non-Swift languages.
/// Applies keyword, string, comment, and number coloring.
struct GenericKeywordHighlighter {

    static let supportedLanguages: Set<String> = [
        "python", "py",
        "javascript", "js", "typescript", "ts", "jsx", "tsx",
        "ruby", "rb",
        "go", "golang",
        "rust", "rs",
        "c", "cpp", "c++", "objc", "objective-c",
        "java", "kotlin", "kt",
        "cs", "csharp", "c#",
        "bash", "sh", "shell", "zsh",
        "html", "css", "json", "yaml", "yml", "toml",
        "sql", "lua", "r", "php", "perl", "scala"
    ]

    private let keywordColor: Color
    private let stringColor: Color
    private let commentColor: Color
    private let numberColor: Color
    private let plainAttributesFn: () -> [NSAttributedString.Key: Any]
    private var plainAttributes: [NSAttributedString.Key: Any] { plainAttributesFn() }

    init(
        keywordColor: Color,
        stringColor: Color,
        commentColor: Color,
        numberColor: Color,
        plainAttributes: @escaping () -> [NSAttributedString.Key: Any]
    ) {
        self.keywordColor = keywordColor
        self.stringColor = stringColor
        self.commentColor = commentColor
        self.numberColor = numberColor
        self.plainAttributesFn = plainAttributes
    }

    func highlight(_ code: String, language: String) -> NSAttributedString {
        let result = NSMutableAttributedString(string: code, attributes: plainAttributes)
        let fullRange = NSRange(location: 0, length: result.length)

        // Track ranges already colored (higher-priority tokens first)
        var colored = IndexSet()

        // 1. Comments (highest priority)
        for pattern in commentPatterns(for: language) {
            applyPattern(pattern, to: result, in: fullRange, color: commentColor, colored: &colored)
        }

        // 2. Strings
        for pattern in stringPatterns() {
            applyPattern(pattern, to: result, in: fullRange, color: stringColor, colored: &colored)
        }

        // 3. Numbers
        applyPattern(numberPattern, to: result, in: fullRange, color: numberColor, colored: &colored)

        // 4. Keywords (lowest priority)
        let kwPattern = keywordPattern(for: language)
        if !kwPattern.isEmpty {
            applyPattern(kwPattern, to: result, in: fullRange, color: keywordColor, colored: &colored)
        }

        return result
    }

    // MARK: - Pattern Application

    private func applyPattern(
        _ pattern: String,
        to attrString: NSMutableAttributedString,
        in range: NSRange,
        color: Color,
        colored: inout IndexSet
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let matches = regex.matches(in: attrString.string, options: [], range: range)
        for match in matches {
            let matchRange = match.range
            let matchIndexRange = matchRange.location..<(matchRange.location + matchRange.length)
            // Skip if any part of this range is already colored
            if !colored.intersection(IndexSet(integersIn: matchIndexRange)).isEmpty { continue }
            attrString.addAttribute(.foregroundColor, value: color, range: matchRange)
            colored.formUnion(IndexSet(integersIn: matchIndexRange))
        }
    }

    // MARK: - Comment Patterns

    private func commentPatterns(for language: String) -> [String] {
        switch language {
        case "python", "py", "ruby", "rb", "bash", "sh", "shell", "zsh",
             "yaml", "yml", "toml", "r", "perl":
            return ["#[^\n]*"]
        case "html":
            return ["<!--[\\s\\S]*?-->"]
        case "css":
            return ["/\\*[\\s\\S]*?\\*/"]
        case "sql", "lua":
            return ["--[^\n]*", "/\\*[\\s\\S]*?\\*/"]
        default:
            // C-family: //, /* */
            return ["//[^\n]*", "/\\*[\\s\\S]*?\\*/"]
        }
    }

    // MARK: - String Patterns

    private func stringPatterns() -> [String] {
        [
            "\"\"\"[\\s\\S]*?\"\"\"",  // Triple-quoted strings
            "\"(?:[^\"\\\\]|\\\\.)*\"", // Double-quoted
            "'(?:[^'\\\\]|\\\\.)*'"     // Single-quoted
        ]
    }

    // MARK: - Number Pattern

    private let numberPattern = "\\b(?:0[xX][0-9a-fA-F]+|0[bB][01]+|[0-9]+\\.?[0-9]*(?:[eE][+-]?[0-9]+)?)\\b"

    // MARK: - Keyword Lists

    private func keywordPattern(for language: String) -> String {
        let keywords = keywords(for: language)
        guard !keywords.isEmpty else { return "" }
        let escaped = keywords.map { NSRegularExpression.escapedPattern(for: $0) }
        return "\\b(?:" + escaped.joined(separator: "|") + ")\\b"
    }

    // swiftlint:disable function_body_length
    private func keywords(for language: String) -> [String] {
        switch language {
        case "python", "py":
            return ["False", "None", "True", "and", "as", "assert", "async", "await",
                    "break", "class", "continue", "def", "del", "elif", "else", "except",
                    "finally", "for", "from", "global", "if", "import", "in", "is",
                    "lambda", "not", "or", "pass", "raise", "return", "try", "while",
                    "with", "yield"]
        case "javascript", "js", "jsx", "typescript", "ts", "tsx":
            return ["async", "await", "break", "case", "catch", "class", "const",
                    "continue", "default", "do", "else", "export", "extends", "false",
                    "finally", "for", "function", "if", "import", "in", "instanceof",
                    "let", "new", "null", "of", "return", "switch", "this", "throw",
                    "true", "try", "typeof", "undefined", "var", "void", "while", "yield"]
        case "go", "golang":
            return ["break", "case", "chan", "const", "continue", "default", "defer",
                    "else", "fallthrough", "for", "func", "go", "goto", "if", "import",
                    "interface", "map", "package", "range", "return", "select", "struct",
                    "switch", "type", "var"]
        case "rust", "rs":
            return ["as", "async", "await", "break", "const", "continue", "crate",
                    "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl",
                    "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref",
                    "return", "self", "static", "struct", "super", "trait", "true",
                    "type", "unsafe", "use", "where", "while"]
        case "java", "kotlin", "kt":
            return ["abstract", "boolean", "break", "byte", "case", "catch", "char",
                    "class", "continue", "default", "do", "double", "else", "enum",
                    "extends", "false", "final", "finally", "float", "for", "if",
                    "implements", "import", "instanceof", "int", "interface", "long",
                    "new", "null", "package", "private", "protected", "public", "return",
                    "short", "static", "super", "switch", "this", "throw", "true", "try",
                    "void", "while"]
        case "c", "cpp", "c++", "objc", "objective-c":
            return ["auto", "break", "case", "char", "const", "continue", "default",
                    "do", "double", "else", "enum", "extern", "float", "for", "goto",
                    "if", "include", "int", "long", "register", "return", "short",
                    "signed", "sizeof", "static", "struct", "switch", "typedef", "union",
                    "unsigned", "void", "volatile", "while",
                    "class", "namespace", "template", "typename", "virtual", "override",
                    "nullptr", "bool", "true", "false"]
        case "cs", "csharp", "c#":
            return ["abstract", "as", "base", "bool", "break", "byte", "case", "catch",
                    "char", "class", "const", "continue", "default", "do", "double",
                    "else", "enum", "false", "finally", "float", "for", "foreach", "if",
                    "in", "int", "interface", "internal", "is", "long", "namespace",
                    "new", "null", "out", "override", "private", "protected", "public",
                    "return", "static", "string", "struct", "switch", "this", "throw",
                    "true", "try", "typeof", "using", "var", "void", "while"]
        case "ruby", "rb":
            return ["alias", "and", "begin", "break", "case", "class", "def", "do",
                    "else", "elsif", "end", "ensure", "false", "for", "if", "in",
                    "module", "next", "nil", "not", "or", "redo", "rescue", "retry",
                    "return", "self", "super", "then", "true", "unless", "until",
                    "when", "while", "yield"]
        case "bash", "sh", "shell", "zsh":
            return ["case", "do", "done", "elif", "else", "esac", "fi", "for",
                    "function", "if", "in", "return", "then", "until", "while",
                    "export", "local", "readonly", "set", "unset"]
        case "sql":
            return ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "UPDATE", "DELETE",
                    "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "VIEW", "JOIN",
                    "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AND", "OR", "NOT",
                    "NULL", "AS", "ORDER", "BY", "GROUP", "HAVING", "LIMIT", "UNION",
                    "SET", "VALUES", "DISTINCT", "COUNT", "SUM", "AVG", "MAX", "MIN",
                    "select", "from", "where", "insert", "into", "update", "delete",
                    "create", "drop", "alter", "table", "join", "and", "or", "not",
                    "null", "as", "order", "by", "group", "having", "limit"]
        case "php":
            return ["abstract", "and", "as", "break", "case", "catch", "class",
                    "const", "continue", "default", "do", "echo", "else", "elseif",
                    "extends", "false", "final", "finally", "for", "foreach", "function",
                    "global", "if", "implements", "interface", "isset", "namespace",
                    "new", "null", "or", "private", "protected", "public", "return",
                    "static", "switch", "this", "throw", "true", "try", "use", "var",
                    "void", "while"]
        case "lua":
            return ["and", "break", "do", "else", "elseif", "end", "false", "for",
                    "function", "goto", "if", "in", "local", "nil", "not", "or",
                    "repeat", "return", "then", "true", "until", "while"]
        default:
            return []
        }
    }
    // swiftlint:enable function_body_length
}

// MARK: - Platform Helpers
private func splashFontFrom(token: TypographyToken) -> Splash.Font {
#if canImport(UIKit)
    return Splash.Font(size: token.font.pointSize)
#elseif canImport(AppKit)
    return Splash.Font(size: token.font.pointSize)
#endif
}

private func splashColor(from color: Color) -> Splash.Color {
#if canImport(UIKit)
    return color
#elseif canImport(AppKit)
    return color
#endif
}
