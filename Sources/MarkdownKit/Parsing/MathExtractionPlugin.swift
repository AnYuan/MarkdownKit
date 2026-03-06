import Foundation

/// An ASTPlugin that scans TextNode content for LaTeX math patterns
/// (`$...$` for inline, `$$...$$` for block) and replaces them with MathNode instances.
public struct MathExtractionPlugin: ASTPlugin {

    public init() {}

    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        // First pass: merge block math ($$..$$) that spans multiple nodes
        let merged = mergeBlockMath(nodes)

        // Second pass: convert fenced math code blocks and extract inline math.
        return merged.map(transform)
    }

    /// Scans top-level nodes for $$ patterns that span across paragraphs.
    /// e.g., Paragraph("$$"), Paragraph("\frac{1}{2}"), Paragraph("$$") → MathNode(.block)
    private func mergeBlockMath(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        var result: [MarkdownNode] = []
        var index = 0

        while index < nodes.count {
            let node = nodes[index]

            // Check if this paragraph starts with $$
            if let text = extractPlainText(from: node), text.trimmingCharacters(in: .whitespaces).hasPrefix("$$") {
                let fullText = text.trimmingCharacters(in: .whitespacesAndNewlines)

                // Case 1: $$ equation $$ all in one paragraph
                if fullText.hasPrefix("$$") && fullText.hasSuffix("$$") && fullText.count > 4 {
                    let equation = String(fullText.dropFirst(2).dropLast(2))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(MathNode(range: nil, style: .block, equation: equation))
                    index += 1
                    continue
                }

                // Case 2: $$ on its own line, equation on next line(s), $$ closing
                if fullText == "$$" {
                    var equationParts: [String] = []
                    var searchIdx = index + 1
                    var found = false

                    while searchIdx < nodes.count {
                        let nextText = extractPlainText(from: nodes[searchIdx])?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if nextText == "$$" {
                            let equation = equationParts.joined(separator: "\n")
                                .trimmingCharacters(in: .whitespacesAndNewlines)
                            result.append(MathNode(range: nil, style: .block, equation: equation))
                            index = searchIdx + 1
                            found = true
                            break
                        }
                        equationParts.append(nextText)
                        searchIdx += 1
                    }

                    if found { continue }
                }
            }

            result.append(node)
            index += 1
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

    private func processInlineChildren(_ children: [MarkdownNode]) -> [MarkdownNode] {
        var result: [MarkdownNode] = []
        for child in children {
            if let text = child as? TextNode {
                result.append(contentsOf: extractInlineMath(from: text))
            } else {
                result.append(transform(child))
            }
        }
        return result
    }

    private func extractInlineMath(from textNode: TextNode) -> [MarkdownNode] {
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

    private func transform(_ node: MarkdownNode) -> MarkdownNode {
        switch node {
        case let paragraph as ParagraphNode:
            return ParagraphNode(range: paragraph.range, children: processInlineChildren(paragraph.children))

        case let header as HeaderNode:
            return HeaderNode(range: header.range, level: header.level, children: processInlineChildren(header.children))

        case let link as LinkNode:
            return LinkNode(
                range: link.range,
                destination: link.destination,
                title: link.title,
                children: processInlineChildren(link.children)
            )

        case let emphasis as EmphasisNode:
            return EmphasisNode(range: emphasis.range, children: processInlineChildren(emphasis.children))

        case let strong as StrongNode:
            return StrongNode(range: strong.range, children: processInlineChildren(strong.children))

        case let strike as StrikethroughNode:
            return StrikethroughNode(range: strike.range, children: processInlineChildren(strike.children))

        case let quote as BlockQuoteNode:
            return BlockQuoteNode(range: quote.range, children: quote.children.map(transform))

        case let list as ListNode:
            return ListNode(range: list.range, isOrdered: list.isOrdered, children: list.children.map(transform))

        case let item as ListItemNode:
            return ListItemNode(range: item.range, checkbox: item.checkbox, children: item.children.map(transform))

        case let table as TableNode:
            return TableNode(
                range: table.range,
                columnAlignments: table.columnAlignments,
                children: table.children.map(transform)
            )

        case let head as TableHeadNode:
            return TableHeadNode(range: head.range, children: head.children.map(transform))

        case let body as TableBodyNode:
            return TableBodyNode(range: body.range, children: body.children.map(transform))

        case let row as TableRowNode:
            return TableRowNode(range: row.range, children: row.children.map(transform))

        case let cell as TableCellNode:
            return TableCellNode(range: cell.range, children: processInlineChildren(cell.children))

        case let details as DetailsNode:
            return DetailsNode(
                range: details.range,
                isOpen: details.isOpen,
                summary: details.summary.map { summary in
                    SummaryNode(
                        range: summary.range,
                        children: processInlineChildren(summary.children)
                    )
                },
                children: details.children.map(transform)
            )

        case let summary as SummaryNode:
            return SummaryNode(range: summary.range, children: processInlineChildren(summary.children))

        case let code as CodeBlockNode:
            guard isMathFence(language: code.language) else { return code }
            let equation = code.code.trimmingCharacters(in: .whitespacesAndNewlines)
            return MathNode(range: code.range, style: .block, equation: equation)

        default:
            return node
        }
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
