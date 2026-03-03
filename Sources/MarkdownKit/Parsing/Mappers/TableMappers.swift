import Markdown

struct TableMapper: ASTNodeMapper {
    func map(_ node: Markdown.Table, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        let alignments = node.columnAlignments.map { alignment -> TableAlignment? in
            switch alignment {
            case .left: return .left
            case .right: return .right
            case .center: return .center
            case .none: return .none
            @unknown default: return .none
            }
        }
        return [TableNode(range: node.range, columnAlignments: alignments, children: children)]
    }
}

struct TableHeadMapper: ASTNodeMapper {
    func map(_ node: Markdown.Table.Head, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        return [TableHeadNode(range: node.range, children: children)]
    }
}

struct TableBodyMapper: ASTNodeMapper {
    func map(_ node: Markdown.Table.Body, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        return [TableBodyNode(range: node.range, children: children)]
    }
}

struct TableRowMapper: ASTNodeMapper {
    func map(_ node: Markdown.Table.Row, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        return [TableRowNode(range: node.range, children: children)]
    }
}

struct TableCellMapper: ASTNodeMapper {
    func map(_ node: Markdown.Table.Cell, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        return [TableCellNode(range: node.range, children: children)]
    }
}
