import Foundation
import Markdown

/// An ASTPlugin that upgrades raw HTML details tags into dedicated AST nodes.
///
/// Supported structure:
/// `<details [open]>`
/// `<summary>...</summary>` or `<summary>` ... `</summary>`
/// `...body markdown...`
/// `</details>`
public struct DetailsExtractionPlugin: ASTPlugin {
    public init() {}

    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        rewriteSiblings(nodes)
    }

    private func rewriteSiblings(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        let rewritten = nodes.map(rewriteNodeChildren)
        let expanded = expandDetailsHTMLTagNodes(in: rewritten)
        return mergeDetails(in: expanded)
    }

    private func rewriteNodeChildren(_ node: MarkdownNode) -> MarkdownNode {
        switch node {
        case let paragraph as ParagraphNode:
            return ParagraphNode(range: paragraph.range, children: rewriteSiblings(paragraph.children))

        case let header as HeaderNode:
            return HeaderNode(range: header.range, level: header.level, children: rewriteSiblings(header.children))

        case let link as LinkNode:
            return LinkNode(
                range: link.range,
                destination: link.destination,
                title: link.title,
                children: rewriteSiblings(link.children)
            )

        case let emphasis as EmphasisNode:
            return EmphasisNode(range: emphasis.range, children: rewriteSiblings(emphasis.children))

        case let strong as StrongNode:
            return StrongNode(range: strong.range, children: rewriteSiblings(strong.children))

        case let strike as StrikethroughNode:
            return StrikethroughNode(range: strike.range, children: rewriteSiblings(strike.children))

        case let quote as BlockQuoteNode:
            return BlockQuoteNode(range: quote.range, children: rewriteSiblings(quote.children))

        case let list as ListNode:
            return ListNode(range: list.range, isOrdered: list.isOrdered, children: rewriteSiblings(list.children))

        case let item as ListItemNode:
            return ListItemNode(
                range: item.range,
                checkbox: item.checkbox,
                children: rewriteSiblings(item.children)
            )

        case let table as TableNode:
            return TableNode(
                range: table.range,
                columnAlignments: table.columnAlignments,
                children: rewriteSiblings(table.children)
            )

        case let head as TableHeadNode:
            return TableHeadNode(range: head.range, children: rewriteSiblings(head.children))

        case let body as TableBodyNode:
            return TableBodyNode(range: body.range, children: rewriteSiblings(body.children))

        case let row as TableRowNode:
            return TableRowNode(range: row.range, children: rewriteSiblings(row.children))

        case let cell as TableCellNode:
            return TableCellNode(range: cell.range, children: rewriteSiblings(cell.children))

        case let details as DetailsNode:
            return DetailsNode(
                range: details.range,
                isOpen: details.isOpen,
                summary: details.summary.map {
                    SummaryNode(range: $0.range, children: rewriteSiblings($0.children))
                },
                children: rewriteSiblings(details.children)
            )

        case let summary as SummaryNode:
            return SummaryNode(range: summary.range, children: rewriteSiblings(summary.children))

        default:
            return node
        }
    }

    private func mergeDetails(in nodes: [MarkdownNode]) -> [MarkdownNode] {
        var result: [MarkdownNode] = []
        var index = 0

        while index < nodes.count {
            guard let opener = parseDetailsOpenTag(from: nodes[index]) else {
                result.append(nodes[index])
                index += 1
                continue
            }

            guard let closeIndex = findMatchingDetailsClose(in: nodes, startAt: index + 1) else {
                // Malformed HTML details block, keep original nodes untouched.
                result.append(nodes[index])
                index += 1
                continue
            }

            let innerNodes = Array(nodes[(index + 1)..<closeIndex])
            let extracted = extractSummaryAndBody(from: innerNodes)

            let detailsNode = DetailsNode(
                range: opener.range,
                isOpen: opener.isOpen,
                summary: extracted.summary,
                children: extracted.body
            )
            result.append(detailsNode)
            index = closeIndex + 1
        }

        return result
    }

    private func findMatchingDetailsClose(in nodes: [MarkdownNode], startAt start: Int) -> Int? {
        var depth = 1
        var index = start

        while index < nodes.count {
            if parseDetailsOpenTag(from: nodes[index]) != nil {
                depth += 1
            } else if isDetailsCloseTag(nodes[index]) {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index += 1
        }

        return nil
    }

    private func extractSummaryAndBody(from nodes: [MarkdownNode]) -> (summary: SummaryNode?, body: [MarkdownNode]) {
        guard let first = nodes.first else {
            return (nil, [])
        }

        if let summaryText = inlineSummaryText(from: first) {
            let summary = SummaryNode(
                range: first.range,
                children: summaryChildren(from: summaryText)
            )
            let bodyNodes = Array(nodes.dropFirst())
            return (summary, rewriteSiblings(bodyNodes))
        }

        if isSummaryOpenTag(first), let closeIndex = findSummaryClose(in: nodes, startAt: 1) {
            let rawSummaryNodes = Array(nodes[1..<closeIndex])
            let bodyNodes = Array(nodes[(closeIndex + 1)...])

            let summary = SummaryNode(
                range: first.range,
                children: normalizedSummaryChildren(from: rawSummaryNodes)
            )
            return (summary, rewriteSiblings(bodyNodes))
        }

        return (nil, rewriteSiblings(nodes))
    }

    private func findSummaryClose(in nodes: [MarkdownNode], startAt start: Int) -> Int? {
        var index = start
        while index < nodes.count {
            if isSummaryCloseTag(nodes[index]) {
                return index
            }
            index += 1
        }
        return nil
    }

    private func normalizedSummaryChildren(from nodes: [MarkdownNode]) -> [MarkdownNode] {
        if nodes.count == 1, let paragraph = nodes[0] as? ParagraphNode {
            return rewriteSiblings(paragraph.children)
        }
        return rewriteSiblings(nodes)
    }

    private func summaryChildren(from text: String) -> [MarkdownNode] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return [TextNode(range: nil, text: trimmed)]
    }

    private func parseDetailsOpenTag(from node: MarkdownNode) -> (isOpen: Bool, range: SourceRange?)? {
        guard let text = rawHTMLTagText(from: node), isMatch(Self.detailsOpenRegex, text: text) else {
            return nil
        }

        let isOpen = text.range(
            of: #"\bopen\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
        return (isOpen, node.range)
    }

    private func isDetailsCloseTag(_ node: MarkdownNode) -> Bool {
        guard let text = rawHTMLTagText(from: node) else { return false }
        return isMatch(Self.detailsCloseRegex, text: text)
    }

    private func isSummaryOpenTag(_ node: MarkdownNode) -> Bool {
        guard let text = rawHTMLTagText(from: node) else { return false }
        return isMatch(Self.summaryOpenRegex, text: text)
    }

    private func isSummaryCloseTag(_ node: MarkdownNode) -> Bool {
        guard let text = rawHTMLTagText(from: node) else { return false }
        return isMatch(Self.summaryCloseRegex, text: text)
    }

    private func inlineSummaryText(from node: MarkdownNode) -> String? {
        guard let text = rawHTMLTagText(from: node) else { return nil }
        guard let match = firstMatch(Self.summaryInlineRegex, text: text) else { return nil }
        guard let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }

    private func rawHTMLTagText(from node: MarkdownNode) -> String? {
        if let text = node as? TextNode {
            return text.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let paragraph = node as? ParagraphNode {
            var fragments: [String] = []
            for child in paragraph.children {
                guard let text = child as? TextNode else { return nil }
                fragments.append(text.text)
            }
            return fragments.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return nil
    }

    private func expandDetailsHTMLTagNodes(in nodes: [MarkdownNode]) -> [MarkdownNode] {
        var result: [MarkdownNode] = []

        for node in nodes {
            guard let textNode = node as? TextNode else {
                result.append(node)
                continue
            }

            let raw = textNode.text
            guard raw.contains(where: \.isNewline), looksLikeDetailsMarkup(raw) else {
                result.append(node)
                continue
            }

            let lines = raw
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if lines.isEmpty {
                continue
            }

            if lines.count == 1 {
                result.append(TextNode(range: textNode.range, text: lines[0]))
                continue
            }

            for line in lines {
                result.append(TextNode(range: textNode.range, text: line))
            }
        }

        return result
    }

    private func looksLikeDetailsMarkup(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("<details")
            || lower.contains("</details>")
            || lower.contains("<summary")
            || lower.contains("</summary>")
    }

    private func isMatch(_ regex: NSRegularExpression, text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return false
        }
        return match.range.location == 0 && match.range.length == range.length
    }

    private func firstMatch(_ regex: NSRegularExpression, text: String) -> NSTextCheckingResult? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        guard match.range.location == 0, match.range.length == range.length else {
            return nil
        }
        return match
    }

    // swiftlint:disable force_try — patterns are compile-time string literals; failure is a programmer error.
    private static let detailsOpenRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^<details(?:\s+[^>]*)?>$"#) else {
            fatalError("Invalid regex pattern for detailsOpenRegex")
        }
        return regex
    }()

    private static let detailsCloseRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^</details>$"#) else {
            fatalError("Invalid regex pattern for detailsCloseRegex")
        }
        return regex
    }()

    private static let summaryOpenRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^<summary(?:\s+[^>]*)?>$"#) else {
            fatalError("Invalid regex pattern for summaryOpenRegex")
        }
        return regex
    }()

    private static let summaryCloseRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)^</summary>$"#) else {
            fatalError("Invalid regex pattern for summaryCloseRegex")
        }
        return regex
    }()

    private static let summaryInlineRegex: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)^<summary(?:\s+[^>]*)?>(.*?)</summary>$"#) else {
            fatalError("Invalid regex pattern for summaryInlineRegex")
        }
        return regex
    }()
    // swiftlint:enable force_try
}
