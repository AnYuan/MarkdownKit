import Foundation

/// An ASTPlugin that upgrades diagram-oriented fenced code blocks to `DiagramNode`.
///
/// Supported languages: mermaid, geojson, topojson, stl.
public struct DiagramExtractionPlugin: ASTPlugin {
    public init() {}

    public func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        nodes.map(transform)
    }

    private func transform(_ node: MarkdownNode) -> MarkdownNode {
        switch node {
        case let code as CodeBlockNode:
            guard let language = diagramLanguage(from: code.language) else {
                return code
            }
            return DiagramNode(range: code.range, language: language, source: code.code)

        case let paragraph as ParagraphNode:
            return ParagraphNode(range: paragraph.range, children: paragraph.children.map(transform))

        case let header as HeaderNode:
            return HeaderNode(range: header.range, level: header.level, children: header.children.map(transform))

        case let link as LinkNode:
            return LinkNode(
                range: link.range,
                destination: link.destination,
                title: link.title,
                children: link.children.map(transform)
            )

        case let emphasis as EmphasisNode:
            return EmphasisNode(range: emphasis.range, children: emphasis.children.map(transform))

        case let strong as StrongNode:
            return StrongNode(range: strong.range, children: strong.children.map(transform))

        case let strike as StrikethroughNode:
            return StrikethroughNode(range: strike.range, children: strike.children.map(transform))

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
            return TableCellNode(range: cell.range, children: cell.children.map(transform))

        case let details as DetailsNode:
            return DetailsNode(
                range: details.range,
                isOpen: details.isOpen,
                summary: details.summary.map {
                    SummaryNode(range: $0.range, children: $0.children.map(transform))
                },
                children: details.children.map(transform)
            )

        case let summary as SummaryNode:
            return SummaryNode(range: summary.range, children: summary.children.map(transform))

        default:
            return node
        }
    }

    private func diagramLanguage(from raw: String?) -> DiagramLanguage? {
        guard let raw else { return nil }
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return DiagramLanguage(rawValue: normalized)
    }
}
