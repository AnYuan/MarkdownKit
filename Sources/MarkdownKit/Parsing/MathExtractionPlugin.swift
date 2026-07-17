import Foundation

/// An ASTPlugin that scans TextNode content for LaTeX math patterns
/// (`$...$` for inline, `$$...$$` for block) and replaces them with MathNode instances.
public struct MathExtractionPlugin: ASTPlugin {

    public init() {}

    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        // First pass: merge document-root siblings, converting a same-paragraph
        // standalone `$$..$$` directly into a `MathNode` sibling (no wrapping
        // ParagraphNode). This is the pre-Q09 root behavior and must not
        // change: top-level `$$x$$` has always become a direct MathNode.
        let rootMerged = mergeBlockMath(nodes, mergeStandalone: true)

        // Second pass: recurse into every *nested* sibling list (list items,
        // blockquotes, details bodies, table cells, etc.), merging
        // multi-paragraph delimiter/interior/delimiter spans there too.
        // Standalone same-paragraph `$$x$$` nested inside a container is
        // intentionally left as a ParagraphNode here — that shape has always
        // flowed through `extractInlineMath`'s "block math within a paragraph"
        // branch below (see e.g. inside list items), preserving
        // `container -> ParagraphNode -> MathNode` and its paragraph spacing.
        // Running with a no-op per-node visitor lets `AST.transform` drive
        // the recursion; this postprocessor also runs once more at the root,
        // which is a no-op there since root standalone spans were already
        // converted above.
        let blockMerged = AST.transform(
            rootMerged,
            postProcessSiblings: { self.mergeBlockMath($0, mergeStandalone: false) },
            visit: { _ in .unchanged }
        )

        // Third pass: walk the block-merged tree, converting math fences and
        // splitting TextNodes whose content contains inline `$..$` or
        // same-paragraph `$$..$$` math. `AST.transform` centralizes the
        // per-container recursion; the visitor only describes the per-node
        // decisions.
        return AST.transform(blockMerged) { node in
            if let code = node as? CodeBlockNode, isMathFence(language: code.language) {
                let equation = code.code.trimmingCharacters(in: .whitespacesAndNewlines)
                return .replace(MathNode(range: code.range, style: .block, equation: equation))
            }
            if let text = node as? TextNode {
                let extracted = extractInlineMath(from: text)
                // Preserve identity (UUID + fingerprint) when no math was found
                // — `extractInlineMath` returns the original node for that case.
                if extracted.count == 1, extracted[0].id == text.id {
                    return .unchanged
                }
                return .replaceMany(extracted)
            }
            return .unchanged
        }
    }

    /// Scans a sibling list for `$$` patterns that span across paragraphs.
    /// e.g., `Paragraph("$$"), Paragraph("\frac{1}{2}"), Paragraph("$$")` →
    /// a single `MathNode(.block)`. Called directly at the document root, and
    /// also runs as `AST.transform`'s `postProcessSiblings` hook so it fires
    /// on every *nested* sibling list in the tree (blockquotes, list items,
    /// details bodies, table cells, etc).
    ///
    /// Two-pass O(N): the first pass classifies each node; the second pairs
    /// delimiter spans into block math, leaving unrelated nodes verbatim.
    /// The earlier inner-loop variant could degrade toward O(N²) when many
    /// unterminated `$$` opener paragraphs preceded long tails.
    ///
    /// Pairing is strict: only a contiguous run of plain-text `.interior`
    /// paragraphs between two `.delimiter` markers is mergeable. Encountering
    /// `.other` (a non-plain-text node) or `.standalone` (a self-contained
    /// `$$..$$` paragraph) while searching for a closer aborts that match —
    /// the opener is preserved verbatim and the interrupting node is left for
    /// normal processing, so no content is ever silently dropped.
    ///
    /// `mergeStandalone` controls whether a `.standalone` single-paragraph
    /// `$$..$$` is converted directly into a `MathNode` sibling (`true`, used
    /// only for the document root, matching pre-Q09 behavior) or left as the
    /// original `ParagraphNode` (`false`, used for every nested sibling list,
    /// so `container -> ParagraphNode -> MathNode` is preserved and
    /// `extractInlineMath`'s same-paragraph block-math branch handles it).
    private func mergeBlockMath(_ nodes: [MarkdownNode], mergeStandalone: Bool) -> [MarkdownNode] {
        guard nodes.contains(where: { $0 is ParagraphNode }) else { return nodes }

        // --- Pass 1: classify ---
        enum Kind {
            case other                            // not a math delimiter
            case standalone(String)               // a single-paragraph $$..$$ block
            case delimiter                        // a bare $$ marker (opener or closer)
            case interior(String)                 // a plain-text paragraph between two delimiters
        }

        var kinds: [Kind] = []
        kinds.reserveCapacity(nodes.count)

        for node in nodes {
            guard let raw = extractPlainText(from: node) else {
                kinds.append(.other)
                continue
            }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed == "$$" {
                kinds.append(.delimiter)
            } else if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count > 4 {
                let equation = String(trimmed.dropFirst(2).dropLast(2))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                kinds.append(.standalone(equation))
            } else {
                // A plain-text paragraph between two `$$` delimiters becomes
                // part of the equation body. We don't know yet whether it
                // *is* between delimiters — that's decided in pass 2.
                kinds.append(.interior(trimmed))
            }
        }

        // --- Pass 2: pair delimiters and emit ---
        var result: [MarkdownNode] = []
        result.reserveCapacity(nodes.count)
        var index = 0

        while index < nodes.count {
            switch kinds[index] {
            case .standalone(let equation):
                if mergeStandalone {
                    result.append(MathNode(range: nil, style: .block, equation: equation))
                } else {
                    // Nested standalone `$$x$$`: leave the ParagraphNode as-is
                    // so `extractInlineMath` converts it below, keeping the
                    // node wrapped in its original ParagraphNode container.
                    result.append(nodes[index])
                }
                index += 1

            case .delimiter:
                // Look ahead for a closing `.delimiter`, but only through a
                // contiguous run of `.interior` entries. Worst case still
                // scans forward once per opener (no pre-classification
                // overhead per look), and aborts immediately on `.other` or
                // `.standalone` so we never lose their content.
                var closer: Int? = nil
                var equationParts: [String] = []
                var search = index + 1
                searchLoop: while search < nodes.count {
                    switch kinds[search] {
                    case .interior(let text):
                        equationParts.append(text)
                        search += 1
                    case .delimiter:
                        closer = search
                        break searchLoop
                    case .other, .standalone:
                        break searchLoop
                    }
                }

                if let closer {
                    let equation = equationParts.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(MathNode(range: nil, style: .block, equation: equation))
                    index = closer + 1
                } else {
                    // No valid closer found — either the end of the sibling
                    // list was reached, or a non-plain-text node interrupted
                    // the span. Keep the opener verbatim; the interrupting
                    // node (if any) is emitted normally on a later iteration.
                    result.append(nodes[index])
                    index += 1
                }

            case .interior, .other:
                result.append(nodes[index])
                index += 1
            }
        }

        return result
    }

    /// Extracts all plain text from a node's inline children. Returns `nil`
    /// unless the node is a `ParagraphNode` whose children are *all*
    /// `TextNode`s — any formatting (e.g. `StrongNode`) or non-paragraph
    /// container makes the node ineligible for delimiter/interior
    /// classification, so `mergeBlockMath` treats it as `.other` rather than
    /// silently discarding its structure.
    private func extractPlainText(from node: MarkdownNode) -> String? {
        guard let para = node as? ParagraphNode else { return nil }
        var fragments: [String] = []
        fragments.reserveCapacity(para.children.count)
        for child in para.children {
            guard let textNode = child as? TextNode else { return nil }
            fragments.append(textNode.text)
        }
        return fragments.joined()
    }

    private func extractInlineMath(from textNode: TextNode) -> [MarkdownNode] {
        // Fast path: no `$` ⇒ no math possible. Return the original instance
        // so `AST.transform` can preserve UUID + fingerprint and skip rebuild.
        guard textNode.text.contains("$") else { return [textNode] }

        // Scanning happens at the `Unicode.Scalar` level — every meaningful
        // delimiter (`$`, `\`) is a single ASCII scalar, so we never split
        // inside a grapheme cluster. The previous `Array(text)` (Character)
        // materialized an entire grapheme array per text node; iterating the
        // `UnicodeScalarView` directly is allocation-free.
        let text = textNode.text
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return [] }

        let dollar: Unicode.Scalar = "$"

        var result: [MarkdownNode] = []
        var buffer = ""
        var idx = scalars.startIndex

        while idx < scalars.endIndex {
            let scalar = scalars[idx]
            let next = scalars.index(after: idx)

            // Block math: $$...$$ within a paragraph (e.g. inside list items)
            if scalar == dollar,
               next < scalars.endIndex,
               scalars[next] == dollar,
               !isEscaped(scalars: scalars, at: idx),
               let close = findClosingDoubleDollar(
                   scalars: scalars,
                   startingAt: scalars.index(after: next)
               ) {
                let equation = String(text[scalars.index(after: next)..<close])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !equation.isEmpty {
                    if !buffer.isEmpty {
                        result.append(TextNode(range: nil, text: buffer))
                        buffer.removeAll(keepingCapacity: true)
                    }
                    result.append(MathNode(range: nil, style: .block, equation: equation))
                    idx = scalars.index(close, offsetBy: 2)
                    continue
                }
            }

            // Inline math: $...$
            if scalar == dollar,
               !isEscaped(scalars: scalars, at: idx),
               !isDoubleDollar(scalars: scalars, at: idx),
               let close = findClosingDollar(scalars: scalars, startingAt: next) {
                let equation = String(text[next..<close])
                if isValidInlineEquation(equation) {
                    if !buffer.isEmpty {
                        result.append(TextNode(range: nil, text: buffer))
                        buffer.removeAll(keepingCapacity: true)
                    }
                    result.append(MathNode(range: nil, style: .inline, equation: equation))
                    idx = scalars.index(after: close)
                    continue
                }

                // If we found a matching pair but it doesn't look like a valid
                // equation, keep the whole segment literal to avoid re-parsing
                // the closing `$` as a new opener.
                buffer.append(contentsOf: text[idx...close])
                idx = scalars.index(after: close)
                continue
            }
            buffer.unicodeScalars.append(scalar)
            idx = next
        }

        if !buffer.isEmpty {
            result.append(TextNode(range: nil, text: buffer))
        }
        return result
    }

    private func findClosingDoubleDollar(
        scalars: String.UnicodeScalarView,
        startingAt start: String.UnicodeScalarView.Index
    ) -> String.UnicodeScalarView.Index? {
        guard start < scalars.endIndex else { return nil }
        let dollar: Unicode.Scalar = "$"
        var idx = start
        while idx < scalars.endIndex {
            let next = scalars.index(after: idx)
            if scalars[idx] == dollar,
               next < scalars.endIndex,
               scalars[next] == dollar,
               !isEscaped(scalars: scalars, at: idx) {
                return idx
            }
            idx = next
        }
        return nil
    }

    private func isMathFence(language: String?) -> Bool {
        guard let language else { return false }
        switch language.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "math", "latex", "tex":
            return true
        default:
            return false
        }
    }

    private func findClosingDollar(
        scalars: String.UnicodeScalarView,
        startingAt start: String.UnicodeScalarView.Index
    ) -> String.UnicodeScalarView.Index? {
        guard start < scalars.endIndex else { return nil }
        let dollar: Unicode.Scalar = "$"
        var idx = start
        while idx < scalars.endIndex {
            if scalars[idx] == dollar,
               !isEscaped(scalars: scalars, at: idx),
               !isDoubleDollar(scalars: scalars, at: idx) {
                return idx
            }
            idx = scalars.index(after: idx)
        }
        return nil
    }

    private func isEscaped(
        scalars: String.UnicodeScalarView,
        at index: String.UnicodeScalarView.Index
    ) -> Bool {
        guard index > scalars.startIndex else { return false }
        let backslash: Unicode.Scalar = "\\"
        var slashCount = 0
        var idx = scalars.index(before: index)
        while scalars[idx] == backslash {
            slashCount += 1
            if idx == scalars.startIndex { break }
            idx = scalars.index(before: idx)
        }
        return slashCount % 2 == 1
    }

    private func isDoubleDollar(
        scalars: String.UnicodeScalarView,
        at index: String.UnicodeScalarView.Index
    ) -> Bool {
        let dollar: Unicode.Scalar = "$"
        let prevHasDollar: Bool
        if index > scalars.startIndex {
            let prev = scalars.index(before: index)
            prevHasDollar = scalars[prev] == dollar && !isEscaped(scalars: scalars, at: prev)
        } else {
            prevHasDollar = false
        }
        let next = scalars.index(after: index)
        let nextHasDollar = next < scalars.endIndex
            && scalars[next] == dollar
            && !isEscaped(scalars: scalars, at: next)
        return prevHasDollar || nextHasDollar
    }

    private func isValidInlineEquation(_ equation: String) -> Bool {
        let trimmed = equation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !equation.contains("\n") else { return false }

        // After CommonMark unescapes `\$...$`, we can no longer distinguish it from
        // intentional math. Avoid obvious false positives like `$notMath$`.
        if trimmed.count > 1 && trimmed.allSatisfy(\.isLetter) {
            return false
        }

        return true
    }
}
