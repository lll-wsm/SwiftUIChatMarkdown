import Foundation
import SwiftUI

public enum ChatCodeTokenKind: Equatable, Sendable {
    case plain
    case keyword
    case string
    case comment
    case number
}

public struct ChatCodeToken: Equatable, Sendable {
    public let kind: ChatCodeTokenKind
    public let text: String

    public init(kind: ChatCodeTokenKind, text: String) {
        self.kind = kind
        self.text = text
    }
}

/// Minimal single-pass tokenizer for chat code blocks: keywords, strings,
/// comments, and numbers. Unknown languages pass through unstyled; correctness
/// of the source text is never altered, only colors are added.
public enum ChatCodeHighlighter {
    public struct Language: Sendable {
        public struct BlockComment: Sendable {
            public let open: String
            public let close: String

            public init(open: String, close: String) {
                self.open = open
                self.close = close
            }
        }

        public let keywords: Set<String>
        public let lineCommentPrefixes: [String]
        public let lineCommentNeedsBoundary: Bool
        public let blockComment: BlockComment?
        public let nestedBlockComments: Bool
        public let stringDelimiters: Set<Character>
        public let supportsTripleQuotes: Bool

        public init(
            keywords: Set<String>,
            lineCommentPrefixes: [String],
            lineCommentNeedsBoundary: Bool = false,
            blockComment: BlockComment?,
            nestedBlockComments: Bool = false,
            stringDelimiters: Set<Character>,
            supportsTripleQuotes: Bool)
        {
            self.keywords = keywords
            self.lineCommentPrefixes = lineCommentPrefixes
            self.lineCommentNeedsBoundary = lineCommentNeedsBoundary
            self.blockComment = blockComment
            self.nestedBlockComments = nestedBlockComments
            self.stringDelimiters = stringDelimiters
            self.supportsTripleQuotes = supportsTripleQuotes
        }
    }

    public static let maxHighlightedLines = 200
    public static let maxHighlightedBytes = 20000

    public static func language(for id: String?) -> Language? {
        switch id {
        case "swift": self.swift
        case "kotlin", "kt", "kts": self.kotlin
        case "typescript", "ts", "tsx", "javascript", "js", "jsx", "mjs", "cjs": self.typescript
        case "python", "py", "python3": self.python
        case "bash", "sh", "shell", "zsh", "console": self.bash
        case "json", "jsonc", "json5": self.json
        default: nil
        }
    }

    public static func attributedCode(_ code: String, languageId: String?, theme: SDKMarkdownTheme = .default) -> AttributedString {
        guard let language = self.language(for: languageId), self.isWithinHighlightLimits(code) else {
            return AttributedString(code)
        }
        var output = AttributedString()
        for token in self.tokens(code: code, language: language) {
            var piece = AttributedString(token.text)
            if let color = self.color(for: token.kind, theme: theme) {
                piece.foregroundColor = color
            }
            output += piece
        }
        return output
    }

    public static func tokens(code: String, language: Language) -> [ChatCodeToken] {
        let chars = Array(code)
        var tokens: [ChatCodeToken] = []
        var plain = ""
        var index = 0

        func flushPlain() {
            guard !plain.isEmpty else { return }
            tokens.append(ChatCodeToken(kind: .plain, text: plain))
            plain = ""
        }

        while index < chars.count {
            let character = chars[index]

            if let block = language.blockComment, self.matches(chars, at: index, block.open) {
                flushPlain()
                index = self.consumeBlockComment(
                    chars,
                    from: index,
                    block: block,
                    nested: language.nestedBlockComments,
                    into: &tokens)
                continue
            }

            let startsLineComment = language.lineCommentPrefixes.contains { prefix in
                self.matches(chars, at: index, prefix) &&
                    (!language.lineCommentNeedsBoundary || self.isLineCommentBoundary(chars, at: index))
            }
            if startsLineComment {
                flushPlain()
                var end = index
                while end < chars.count, !chars[end].isNewline {
                    end += 1
                }
                tokens.append(ChatCodeToken(kind: .comment, text: String(chars[index..<end])))
                index = end
                continue
            }

            if language.stringDelimiters.contains(character) {
                flushPlain()
                index = self.consumeString(chars, from: index, language: language, into: &tokens)
                continue
            }

            if character.isNumber {
                flushPlain()
                var end = index
                // Loose number scan (hex/exponent/separators); identifiers with
                // trailing digits never reach here because the identifier
                // branch below consumes them first.
                while end < chars.count,
                      chars[end].isHexDigit || chars[end] == "." || chars[end] == "_"
                      || chars[end] == "x" || chars[end] == "X" || chars[end] == "o"
                      || chars[end] == "b"
                {
                    end += 1
                }
                tokens.append(ChatCodeToken(kind: .number, text: String(chars[index..<end])))
                index = end
                continue
            }

            if character.isLetter || character == "_" || character == "$" || character == "@" {
                var end = index
                while end < chars.count,
                      chars[end].isLetter || chars[end].isNumber || chars[end] == "_" || chars[end] == "$"
                      || chars[end] == "@"
                {
                    end += 1
                }
                let word = String(chars[index..<end])
                if language.keywords.contains(word) {
                    flushPlain()
                    tokens.append(ChatCodeToken(kind: .keyword, text: word))
                } else {
                    plain += word
                }
                index = end
                continue
            }

            plain.append(character)
            index += 1
        }

        flushPlain()
        return tokens
    }

    // MARK: - Scanning helpers

    private static func consumeBlockComment(
        _ chars: [Character],
        from start: Int,
        block: Language.BlockComment,
        nested: Bool,
        into tokens: inout [ChatCodeToken]) -> Int
    {
        var depth = 1
        var end = start + block.open.count
        while end < chars.count {
            if nested, self.matches(chars, at: end, block.open) {
                depth += 1
                end += block.open.count
            } else if self.matches(chars, at: end, block.close) {
                depth -= 1
                end += block.close.count
                if depth == 0 { break }
            } else {
                end += 1
            }
        }
        tokens.append(ChatCodeToken(kind: .comment, text: String(chars[start..<end])))
        return end
    }

    private static func isLineCommentBoundary(_ chars: [Character], at index: Int) -> Bool {
        guard index > 0 else { return true }
        let previous = chars[index - 1]
        return previous.isWhitespace || ";&|()<>".contains(previous)
    }

    public static func isWithinHighlightLimits(_ code: String) -> Bool {
        guard code.utf8.count <= self.maxHighlightedBytes else { return false }
        let newlineCount = code.lazy.count(where: { $0.isNewline })
        let lineCount = code.isEmpty ? 0 : newlineCount + 1
        return lineCount <= self.maxHighlightedLines
    }

    private static func consumeString(
        _ chars: [Character],
        from start: Int,
        language: Language,
        into tokens: inout [ChatCodeToken]) -> Int
    {
        let quote = chars[start]
        let triple = language.supportsTripleQuotes
            && self.matches(chars, at: start, String(repeating: String(quote), count: 3))
        let delimiter = triple ? String(repeating: String(quote), count: 3) : String(quote)
        // Backtick templates (TS/JS) and triple quotes span lines; plain
        // quotes stop at the newline so a stray quote can't swallow the block.
        let multiline = triple || quote == "`"

        var end = start + delimiter.count
        while end < chars.count {
            if chars[end] == "\\" {
                end += 2
                continue
            }
            if self.matches(chars, at: end, delimiter) {
                end += delimiter.count
                break
            }
            if !multiline, chars[end].isNewline { break }
            end += 1
        }
        end = min(end, chars.count)
        tokens.append(ChatCodeToken(kind: .string, text: String(chars[start..<end])))
        return end
    }

    private static func matches(_ chars: [Character], at index: Int, _ needle: String) -> Bool {
        let needleChars = Array(needle)
        guard index + needleChars.count <= chars.count else { return false }
        for offset in 0..<needleChars.count where chars[index + offset] != needleChars[offset] {
            return false
        }
        return true
    }

    private static func color(for kind: ChatCodeTokenKind, theme: SDKMarkdownTheme) -> Color? {
        switch kind {
        case .plain: nil
        case .keyword: theme.keywordColor
        case .string: theme.stringColor
        case .comment: theme.commentColor
        case .number: theme.numberColor
        }
    }

    // MARK: - Language profiles

    private static let swift = Language(
        keywords: [
            "actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch",
            "class", "continue", "convenience", "default", "defer", "deinit", "do", "else", "enum",
            "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "guard",
            "if", "import", "in", "indirect", "init", "inout", "internal", "is", "lazy", "let",
            "mutating", "nil", "nonisolated", "open", "operator", "optional", "override", "private",
            "protocol", "public", "repeat", "required", "rethrows", "return", "self", "some",
            "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try",
            "typealias", "unowned", "var", "weak", "where", "while",
        ],
        lineCommentPrefixes: ["//"],
        blockComment: Language.BlockComment(open: "/*", close: "*/"),
        nestedBlockComments: true,
        stringDelimiters: ["\""],
        supportsTripleQuotes: true)

    private static let kotlin = Language(
        keywords: [
            "abstract", "as", "break", "by", "catch", "class", "companion", "constructor",
            "continue", "crossinline", "data", "do", "else", "enum", "false", "final", "finally",
            "for", "fun", "if", "import", "in", "init", "inline", "interface", "internal", "is",
            "lateinit", "null", "object", "open", "out", "override", "package", "private",
            "protected", "public", "reified", "return", "sealed", "super", "suspend", "this",
            "throw", "true", "try", "typealias", "val", "var", "vararg", "when", "where", "while",
        ],
        lineCommentPrefixes: ["//"],
        blockComment: Language.BlockComment(open: "/*", close: "*/"),
        nestedBlockComments: true,
        stringDelimiters: ["\""],
        supportsTripleQuotes: true)

    private static let typescript = Language(
        keywords: [
            "abstract", "any", "as", "async", "await", "boolean", "break", "case", "catch", "class",
            "const", "continue", "declare", "default", "delete", "do", "else", "enum", "export",
            "extends", "false", "finally", "for", "from", "function", "get", "if", "implements",
            "import", "in", "infer", "instanceof", "interface", "is", "keyof", "let", "namespace",
            "never", "new", "null", "number", "of", "private", "protected", "public", "readonly",
            "return", "set", "static", "string", "super", "switch", "symbol", "this", "throw",
            "true", "try", "type", "typeof", "undefined", "unknown", "var", "void", "while",
            "yield",
        ],
        lineCommentPrefixes: ["//"],
        blockComment: Language.BlockComment(open: "/*", close: "*/"),
        stringDelimiters: ["\"", "'", "`"],
        supportsTripleQuotes: false)

    private static let python = Language(
        keywords: [
            "False", "None", "True", "and", "as", "assert", "async", "await", "break", "case",
            "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from",
            "global", "if", "import", "in", "is", "lambda", "match", "nonlocal", "not", "or",
            "pass", "raise", "return", "self", "try", "while", "with", "yield",
        ],
        lineCommentPrefixes: ["#"],
        blockComment: nil,
        stringDelimiters: ["\""],
        supportsTripleQuotes: true)

    private static let bash = Language(
        keywords: [
            "alias", "case", "cd", "declare", "do", "done", "echo", "elif", "else", "esac",
            "exit", "export", "false", "fi", "for", "function", "if", "in", "local", "readonly",
            "return", "select", "set", "shift", "source", "then", "true", "unset", "until",
            "while",
        ],
        lineCommentPrefixes: ["#"],
        lineCommentNeedsBoundary: true,
        blockComment: nil,
        stringDelimiters: ["\"", "'"],
        supportsTripleQuotes: false)

    private static let json = Language(
        keywords: ["false", "null", "true"],
        lineCommentPrefixes: [],
        blockComment: nil,
        stringDelimiters: ["\""],
        supportsTripleQuotes: false)
}

/// Content-keyed memo so streaming re-renders reuse finished highlight work
/// instead of re-tokenizing every completed block on each delta tick.
/// Public so app file previews reuse the chat renderer's highlighting.
@MainActor
public enum ChatCodeHighlightCache {
    private static var cache: [String: AttributedString] = [:]
    // Bounded: wholesale reset past the cap keeps long sessions flat; a miss
    // just re-tokenizes one visible block, which is cheap.
    private static let capacity = 160

    public static func highlighted(code: String, languageId: String?, theme: SDKMarkdownTheme = .default) -> AttributedString {
        guard ChatCodeHighlighter.language(for: languageId) != nil,
              ChatCodeHighlighter.isWithinHighlightLimits(code)
        else {
            return AttributedString(code)
        }
        // Include theme properties in the key to avoid using cache when theme colors change
        let key = "\(languageId ?? "")\u{0}\(theme.keywordColor.description)\u{0}\(theme.stringColor.description)\u{0}\(theme.commentColor.description)\u{0}\(theme.numberColor.description)\u{0}\(code)"
        if let hit = self.cache[key] { return hit }
        let value = ChatCodeHighlighter.attributedCode(code, languageId: languageId, theme: theme)
        if self.cache.count >= self.capacity {
            self.cache.removeAll(keepingCapacity: true)
        }
        self.cache[key] = value
        return value
    }
}
