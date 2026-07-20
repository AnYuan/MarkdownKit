import Foundation

/// Internal opt-in for built-in `ASTPlugin`s whose entire transformation is
/// conditioned on markup that must appear verbatim in the original, pre-plugin
/// source text.
///
/// Conforming to this protocol lets `MarkdownParser` skip invoking a plugin
/// outright when `BuiltInPluginSourceHints` prove the source cannot contain
/// syntax the plugin cares about — avoiding a full AST traversal for plugins
/// that would end up doing nothing.
///
/// This is intentionally **not** part of the public `ASTPlugin` API: it is a
/// closed, internal optimization contract. In production it is adopted only by
/// `DetailsExtractionPlugin`, `DiagramExtractionPlugin`, and
/// `MathExtractionPlugin`, whose transformations are each fully gated on
/// details markers, fenced-code languages, or `$`. CommonMark entity references
/// are conservatively treated as relevant to every built-in because they are
/// decoded before plugins inspect the native AST.
///
/// `MarkdownParser` only trusts a "skip" from this protocol while no earlier
/// plugin — built-in or custom — has actually executed in the same parse.
/// Once any plugin runs, its output could introduce syntax absent from the
/// original source (e.g. a custom plugin injecting a `MathNode`-worthy
/// `TextNode`), so every later plugin (including preflight-capable ones) must
/// execute normally for the remainder of that parse.
protocol BuiltInSourcePreflightPlugin {
    /// Returns `true` if `hints` — computed once from the original source text
    /// before any plugin has run — indicate this plugin might have something
    /// to do. May return false positives (over-inclusive) but must never
    /// return a false negative, or a plugin that would have made a change
    /// could be silently skipped.
    static func mightApply(given hints: BuiltInPluginSourceHints) -> Bool
}

extension DetailsExtractionPlugin: BuiltInSourcePreflightPlugin {
    static func mightApply(given hints: BuiltInPluginSourceHints) -> Bool {
        hints.mayContainDetailsMarkup
    }
}

extension DiagramExtractionPlugin: BuiltInSourcePreflightPlugin {
    static func mightApply(given hints: BuiltInPluginSourceHints) -> Bool {
        hints.mayContainDiagramFence
    }
}

extension MathExtractionPlugin: BuiltInSourcePreflightPlugin {
    static func mightApply(given hints: BuiltInPluginSourceHints) -> Bool {
        hints.mayContainMathSyntax
    }
}

/// Immutable, conservative hints about whether the original (pre-plugin)
/// source text could possibly contain markup relevant to one of
/// MarkdownKit's built-in `ASTPlugin`s.
///
/// Every predicate here is intentionally over-inclusive: it may say "yes"
/// for source that ultimately contains no matching syntax (a false
/// positive, which only costs a redundant plugin execution), but it must
/// never say "no" for source that does (a false negative, which would
/// silently drop real syntax). Computed once per parse — lazily, and only
/// if a `BuiltInSourcePreflightPlugin` is actually encountered — and reused
/// across every built-in plugin considered for that same parse.
struct BuiltInPluginSourceHints {
    /// `true` if the source contains one of the details markers or any entity
    /// reference that CommonMark could decode into plugin-visible text.
    let mayContainDetailsMarkup: Bool

    /// `true` if the source contains a supported diagram fence or any entity
    /// reference that CommonMark could decode inside a fence info string.
    let mayContainDiagramFence: Bool

    /// `true` if the source contains `$`, a supported math fence, or any entity
    /// reference that CommonMark could decode into plugin-visible text.
    let mayContainMathSyntax: Bool

    init(source: String) {
        let syntaxHints = Self.sourceSyntaxHints(in: source)
        if syntaxHints.mayContainEntityReference {
            mayContainDetailsMarkup = true
            mayContainDiagramFence = true
            mayContainMathSyntax = true
            return
        }

        mayContainDetailsMarkup = DetailsExtractionPlugin.looksLikeDetailsMarkup(source)
        mayContainDiagramFence = syntaxHints.mayContainDiagramFence
        mayContainMathSyntax = syntaxHints.mayContainMathSyntax
    }

    /// Conservatively scans `source` for fenced-code language candidates,
    /// without depending on `swift-markdown`'s exact `CodeBlock.language`
    /// representation or requiring a fence to start a line.
    ///
    /// Any run of 3+ backticks or tildes anywhere in the source is treated as
    /// a possible fence marker (real CommonMark fences may be preceded by
    /// blockquote/list markers, indentation, or nesting; matching anywhere is
    /// a superset of that, so it never misses a real fence). The remainder of
    /// that line is captured as the candidate "info string": both its fully
    /// normalized (trimmed, lowercased) form and its first whitespace-delimited
    /// token are recorded, since a real language token may be followed by
    /// extra info-string content (e.g. ` ```mermaid theme=dark`) and we must
    /// not depend on which shape `CodeBlock.language` ultimately exposes.
    ///
    /// This intentionally also matches non-fence occurrences (e.g. an inline
    /// span of 3+ backticks, or a closing fence's now-empty info string) —
    /// those only ever add extra, harmless candidates. Bare prose containing a
    /// diagram/math keyword (e.g. "STL container") is never captured, because
    /// no backtick/tilde run precedes it.
    ///
    /// Implemented as a single manual `Unicode.Scalar` pass (mirroring the
    /// scanning style already used by `MathExtractionPlugin`'s inline-math
    /// scanner) rather than `NSRegularExpression`, so this stays a cheap O(n)
    /// preflight step instead of adding backtracking-regex overhead on top of
    /// a full source scan.
    private static func sourceSyntaxHints(
        in source: String
    ) -> (
        mayContainEntityReference: Bool,
        mayContainDiagramFence: Bool,
        mayContainMathSyntax: Bool
    ) {
        var mayContainDiagramFence = false
        var mayContainMathSyntax = false
        let scalars = source.unicodeScalars
        let backtick: Unicode.Scalar = "`"
        let tilde: Unicode.Scalar = "~"
        let newline: Unicode.Scalar = "\n"
        let dollar: Unicode.Scalar = "$"
        let ampersand: Unicode.Scalar = "&"

        func recordFenceCandidate(_ candidate: String) {
            if !mayContainDiagramFence {
                mayContainDiagramFence = DiagramExtractionPlugin.diagramLanguage(from: candidate) != nil
            }
            if !mayContainMathSyntax {
                mayContainMathSyntax = MathExtractionPlugin.isMathFence(language: candidate)
            }
        }

        var idx = scalars.startIndex
        while idx < scalars.endIndex {
            let scalar = scalars[idx]
            if scalar == ampersand {
                return (true, true, true)
            }
            if scalar == dollar {
                mayContainMathSyntax = true
            }

            guard scalar == backtick || scalar == tilde else {
                idx = scalars.index(after: idx)
                continue
            }

            var runEnd = idx
            var runLength = 0
            while runEnd < scalars.endIndex, scalars[runEnd] == scalar {
                runLength += 1
                runEnd = scalars.index(after: runEnd)
            }

            guard runLength >= 3 else {
                idx = runEnd
                continue
            }

            var lineEnd = runEnd
            while lineEnd < scalars.endIndex, scalars[lineEnd] != newline {
                lineEnd = scalars.index(after: lineEnd)
            }

            let suffix = String(scalars[runEnd..<lineEnd])
            let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !trimmed.isEmpty {
                recordFenceCandidate(trimmed)
                if let firstToken = trimmed.split(whereSeparator: \.isWhitespace).first {
                    let token = String(firstToken)
                    if token != trimmed {
                        recordFenceCandidate(token)
                    }
                }
            }

            idx = runEnd
        }

        return (false, mayContainDiagramFence, mayContainMathSyntax)
    }
}
