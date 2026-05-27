import Foundation

/// An ASTPlugin that scans TextNode content for LaTeX math patterns
/// (`$...$` for inline, `$$...$$` for block) and replaces them with MathNode instances.
public struct MathExtractionPlugin: ASTPlugin {

    public init() {}

    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        // First pass: merge block math ($$..$$) that spans multiple top-level
        // paragraphs. This is a sibling-level operation only applicable at the
        // document root.
        let merged = mergeBlockMath(nodes)

        // Second pass: walk the tree, converting math fences and splitting
        // TextNodes whose content contains inline `$..$` or `$$..$$` math.
        // `AST.transform` centralizes the per-container recursion; the visitor
        // only describes the per-node decisions.
        return AST.transform(merged) { node in
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

    /// Scans top-level nodes for `$$` patterns that span across paragraphs.
    /// e.g., `Paragraph("$$"), Paragraph("\frac{1}{2}"), Paragraph("$$")` →
    /// a single `MathNode(.block)`.
    ///
    /// Two-pass O(N): the first pass classifies each node; the second pairs
    /// delimiter spans into block math, leaving unrelated nodes verbatim.
    /// The earlier inner-loop variant could degrade toward O(N²) when many
    /// unterminated `$$` opener paragraphs preceded long tails.
    private func mergeBlockMath(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
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
                result.append(MathNode(range: nil, style: .block, equation: equation))
                index += 1

            case .delimiter:
                // Look ahead for a closing `.delimiter`. Worst case still scans
                // forward, but we only do it once per opener (no
                // pre-classification overhead per look).
                var closer: Int? = nil
                var search = index + 1
                while search < nodes.count {
                    if case .delimiter = kinds[search] {
                        closer = search
                        break
                    }
                    search += 1
                }

                if let closer {
                    var equationParts: [String] = []
                    for inner in (index + 1)..<closer {
                        if case .interior(let text) = kinds[inner] {
                            equationParts.append(text)
                        } else {
                            // A non-interior between two delimiters — emit it
                            // verbatim so we don't lose content.
                            equationParts.append("")
                        }
                    }
                    let equation = equationParts.joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(MathNode(range: nil, style: .block, equation: equation))
                    index = closer + 1
                } else {
                    // No closer found: keep the opener verbatim, advance.
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

    /// Extracts all plain text from a node's inline children.
    private func extractPlainText(from node: MarkdownNode) -> String? {
        if let para = node as? ParagraphNode {
            return para.children.compactMap { child -> String? in
                if let text = child as? TextNode { return text.text }
                return nil
            }.joined()
        }
        return nil
    }

    private func extractInlineMath(from textNode: TextNode) -> [MarkdownNode] {
        // Fast path: no `$` ⇒ no math possible. Return the original instance
        // so `AST.transform` can preserve UUID + fingerprint and skip rebuild.
        guard textNode.text.contains("$") else { return [textNode] }

        let text = Array(textNode.text)
        guard !text.isEmpty else { return [] }

        var result: [MarkdownNode] = []
        var buffer = ""
        var idx = 0

        while idx < text.count {
            // Block math: $$...$$ within a paragraph (e.g. inside list items)
            if idx + 1 < text.count, text[idx] == "$", text[idx + 1] == "$", !isEscaped(text, at: idx),
               let close = findClosingDoubleDollar(in: text, startingAt: idx + 2) {
                let equation = String(text[(idx + 2)..<close])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !equation.isEmpty {
                    if !buffer.isEmpty {
                        result.append(TextNode(range: nil, text: buffer))
                        buffer.removeAll(keepingCapacity: true)
                    }
                    result.append(MathNode(range: nil, style: .block, equation: equation))
                    idx = close + 2
                    continue
                }
            }

            // Inline math: $...$
            if text[idx] == "$", !isEscaped(text, at: idx), !isDoubleDollar(text, at: idx),
               let close = findClosingDollar(in: text, startingAt: idx + 1) {
                let equation = String(text[(idx + 1)..<close])
                if isValidInlineEquation(equation) {
                    if !buffer.isEmpty {
                        result.append(TextNode(range: nil, text: buffer))
                        buffer.removeAll(keepingCapacity: true)
                    }
                    result.append(MathNode(range: nil, style: .inline, equation: equation))
                    idx = close + 1
                    continue
                }

                // If we found a matching pair but it doesn't look like a valid
                // equation, keep the whole segment literal to avoid re-parsing
                // the closing `$` as a new opener.
                buffer.append(contentsOf: String(text[idx...close]))
                idx = close + 1
                continue
            }
            buffer.append(text[idx])
            idx += 1
        }

        if !buffer.isEmpty {
            result.append(TextNode(range: nil, text: buffer))
        }
        return result
    }

    private func findClosingDoubleDollar(in text: [Character], startingAt start: Int) -> Int? {
        guard start < text.count else { return nil }
        var idx = start
        while idx + 1 < text.count {
            if text[idx] == "$", text[idx + 1] == "$", !isEscaped(text, at: idx) {
                return idx
            }
            idx += 1
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

    private func findClosingDollar(in text: [Character], startingAt start: Int) -> Int? {
        guard start < text.count else { return nil }
        var idx = start
        while idx < text.count {
            if text[idx] == "$", !isEscaped(text, at: idx), !isDoubleDollar(text, at: idx) {
                return idx
            }
            idx += 1
        }
        return nil
    }

    private func isEscaped(_ text: [Character], at index: Int) -> Bool {
        guard index > 0 else { return false }
        var slashCount = 0
        var idx = index - 1
        while idx >= 0, text[idx] == "\\" {
            slashCount += 1
            if idx == 0 { break }
            idx -= 1
        }
        return slashCount % 2 == 1
    }

    private func isDoubleDollar(_ text: [Character], at index: Int) -> Bool {
        let hasPrev = index > 0 && text[index - 1] == "$" && !isEscaped(text, at: index - 1)
        let hasNext = (index + 1) < text.count && text[index + 1] == "$" && !isEscaped(text, at: index + 1)
        return hasPrev || hasNext
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
