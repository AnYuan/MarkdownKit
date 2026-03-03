import Markdown

struct HeadingMapper: ASTNodeMapper {
    func map(_ node: Heading, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        return [HeaderNode(range: node.range, level: node.level, children: children)]
    }
}

struct ParagraphMapper: ASTNodeMapper {
    func map(_ node: Paragraph, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        return [ParagraphNode(range: node.range, children: children)]
    }
}

struct TextMapper: ASTNodeMapper {
    func map(_ node: Markdown.Text, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        return [TextNode(range: node.range, text: node.string)]
    }
}

struct SoftBreakMapper: ASTNodeMapper {
    func map(_ node: SoftBreak, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        return [TextNode(range: node.range, text: " ")]
    }
}

struct LineBreakMapper: ASTNodeMapper {
    func map(_ node: LineBreak, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        return [TextNode(range: node.range, text: "\n")]
    }
}

struct ThematicBreakMapper: ASTNodeMapper {
    func map(_ node: ThematicBreak, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        return [ThematicBreakNode(range: node.range)]
    }
}
