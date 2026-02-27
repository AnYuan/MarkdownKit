import Foundation

/// An ASTPlugin that scans TextNode content for LaTeX math patterns
/// (`$...$` for inline, `$$...$$` for block) and replaces them with MathNode instances.
public struct MathExtractionPlugin: ASTPlugin {

    public init() {}

    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        var result: [MarkdownNode] = []
        for node in nodes {
            if let paragraph = node as? ParagraphNode {
                let newChildren = processInlineChildren(paragraph.children)
                result.append(ParagraphNode(range: paragraph.range, children: newChildren))
            } else if let header = node as? HeaderNode {
                let newChildren = processInlineChildren(header.children)
                result.append(HeaderNode(range: header.range, level: header.level, children: newChildren))
            } else {
                result.append(node)
            }
        }
        return result
    }

    private func processInlineChildren(_ children: [MarkdownNode]) -> [MarkdownNode] {
        var result: [MarkdownNode] = []
        for child in children {
            if let text = child as? TextNode {
                result.append(contentsOf: extractMath(from: text))
            } else {
                result.append(child)
            }
        }
        return result
    }

    private func extractMath(from textNode: TextNode) -> [MarkdownNode] {
        let text = textNode.text
        var result: [MarkdownNode] = []
        var remaining = text[text.startIndex...]

        while !remaining.isEmpty {
            // Look for block math first ($$...$$)
            if let blockRange = remaining.range(of: "$$") {
                // Add text before $$
                let prefix = remaining[remaining.startIndex..<blockRange.lowerBound]
                if !prefix.isEmpty {
                    result.append(TextNode(range: nil, text: String(prefix)))
                }

                let afterOpen = remaining[blockRange.upperBound...]
                if let closeRange = afterOpen.range(of: "$$") {
                    let equation = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    result.append(MathNode(range: nil, style: .block, equation: equation))
                    remaining = afterOpen[closeRange.upperBound...]
                    continue
                } else {
                    // No closing $$, treat as text
                    result.append(TextNode(range: nil, text: String(remaining)))
                    return result
                }
            }

            // Look for inline math ($...$)
            if let inlineRange = remaining.range(of: "$") {
                let prefix = remaining[remaining.startIndex..<inlineRange.lowerBound]
                if !prefix.isEmpty {
                    result.append(TextNode(range: nil, text: String(prefix)))
                }

                let afterOpen = remaining[inlineRange.upperBound...]
                if let closeRange = afterOpen.range(of: "$") {
                    let equation = String(afterOpen[afterOpen.startIndex..<closeRange.lowerBound])
                    if !equation.isEmpty && !equation.contains("\n") {
                        result.append(MathNode(range: nil, style: .inline, equation: equation))
                        remaining = afterOpen[closeRange.upperBound...]
                        continue
                    }
                }

                // No valid closing $, treat rest as text
                result.append(TextNode(range: nil, text: String(remaining)))
                return result
            }

            // No math found, add remaining as text
            result.append(TextNode(range: nil, text: String(remaining)))
            return result
        }

        return result
    }
}
