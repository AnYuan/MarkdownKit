import Markdown

struct EmphasisMapper: ASTNodeMapper {
    func map(_ node: Emphasis, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        return [EmphasisNode(range: node.range, children: children)]
    }
}

struct StrongMapper: ASTNodeMapper {
    func map(_ node: Strong, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        return [StrongNode(range: node.range, children: children)]
    }
}

struct StrikethroughMapper: ASTNodeMapper {
    func map(_ node: Strikethrough, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        return [StrikethroughNode(range: node.range, children: children)]
    }
}

struct InlineCodeMapper: ASTNodeMapper {
    func map(_ node: InlineCode, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        return [InlineCodeNode(range: node.range, code: node.code)]
    }
}

struct LinkMapper: ASTNodeMapper {
    func map(_ node: Markdown.Link, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        let children = visitor.defaultVisit(node)
        return [LinkNode(range: node.range,
                         destination: node.destination,
                         title: node.title,
                         children: children)]
    }
}

struct ImageMapper: ASTNodeMapper {
    func map(_ node: Markdown.Image, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        return [ImageNode(range: node.range,
                          source: node.source,
                          altText: node.plainText,
                          title: node.title)]
    }
}

struct InlineHTMLMapper: ASTNodeMapper {
    func map(_ node: InlineHTML, visitor: inout MarkdownKitVisitor) -> [MarkdownNode] {
        // Simple fallback to convert raw HTML into a Text Node for now.
        return [TextNode(range: node.range, text: node.rawHTML)]
    }
}
