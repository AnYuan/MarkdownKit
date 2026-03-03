import Foundation
import Markdown

/// A visitor that traverses the `swift-markdown` syntax tree and converts Apple's C-backed
/// syntax structures into our highly stabilized, thread-safe, and asynchronous-ready `MarkdownNode` models.
public struct MarkdownKitVisitor: MarkupVisitor {
    public typealias Result = [MarkdownNode]
    
    /// The maximum allowed recursion depth to prevent Stack Overflow exploits
    private let maxDepth: Int
    private var currentDepth: Int = 0
    
    public init(maxDepth: Int = 50) {
        self.maxDepth = maxDepth
    }
    
    // MARK: - Core Entry Point
    
    public mutating func defaultVisit(_ markup: Markup) -> [MarkdownNode] {
        guard currentDepth < maxDepth else {
            // If depth exceeds limit, stop traversing and return a dummy node to prevent crash
            return []
        }
        
        currentDepth += 1
        var children: [MarkdownNode] = []
        for child in markup.children {
            children.append(contentsOf: visit(child))
        }
        currentDepth -= 1
        return children
    }
    
    public mutating func visitDocument(_ document: Document) -> [MarkdownNode] {
        let children = defaultVisit(document)
        let node = DocumentNode(range: document.range, children: children)
        return [node]
    }
    
    // MARK: - Basic Nodes
    
    public mutating func visitHeading(_ heading: Heading) -> [MarkdownNode] {
        HeadingMapper().map(heading, visitor: &self)
    }
    
    public mutating func visitParagraph(_ paragraph: Paragraph) -> [MarkdownNode] {
        ParagraphMapper().map(paragraph, visitor: &self)
    }
    
    public mutating func visitText(_ text: Markdown.Text) -> [MarkdownNode] {
        TextMapper().map(text, visitor: &self)
    }
    
    // MARK: - Complex Nodes
    
    public mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> [MarkdownNode] {
        CodeBlockMapper().map(codeBlock, visitor: &self)
    }
    
    public mutating func visitInlineCode(_ inlineCode: InlineCode) -> [MarkdownNode] {
        InlineCodeMapper().map(inlineCode, visitor: &self)
    }
    
    public mutating func visitImage(_ image: Markdown.Image) -> [MarkdownNode] {
        ImageMapper().map(image, visitor: &self)
    }
    
    public mutating func visitLink(_ link: Markdown.Link) -> [MarkdownNode] {
        LinkMapper().map(link, visitor: &self)
    }
    
    // MARK: - Lists
    
    public mutating func visitOrderedList(_ orderedList: OrderedList) -> [MarkdownNode] {
        OrderedListMapper().map(orderedList, visitor: &self)
    }
    
    public mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> [MarkdownNode] {
        UnorderedListMapper().map(unorderedList, visitor: &self)
    }
    
    public mutating func visitListItem(_ listItem: ListItem) -> [MarkdownNode] {
        ListItemMapper().map(listItem, visitor: &self)
    }
    
    // MARK: - Tables (GFM)
    
    public mutating func visitTable(_ table: Markdown.Table) -> [MarkdownNode] {
        TableMapper().map(table, visitor: &self)
    }
    
    public mutating func visitTableHead(_ tableHead: Markdown.Table.Head) -> [MarkdownNode] {
        TableHeadMapper().map(tableHead, visitor: &self)
    }
    
    public mutating func visitTableBody(_ tableBody: Markdown.Table.Body) -> [MarkdownNode] {
        TableBodyMapper().map(tableBody, visitor: &self)
    }
    
    public mutating func visitTableRow(_ tableRow: Markdown.Table.Row) -> [MarkdownNode] {
        TableRowMapper().map(tableRow, visitor: &self)
    }
    
    public mutating func visitTableCell(_ tableCell: Markdown.Table.Cell) -> [MarkdownNode] {
        TableCellMapper().map(tableCell, visitor: &self)
    }
    
    // MARK: - Inline Formatting

    public mutating func visitEmphasis(_ emphasis: Emphasis) -> [MarkdownNode] {
        EmphasisMapper().map(emphasis, visitor: &self)
    }

    public mutating func visitStrong(_ strong: Strong) -> [MarkdownNode] {
        StrongMapper().map(strong, visitor: &self)
    }

    public mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> [MarkdownNode] {
        StrikethroughMapper().map(strikethrough, visitor: &self)
    }

    // MARK: - Block Elements

    public mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> [MarkdownNode] {
        BlockQuoteMapper().map(blockQuote, visitor: &self)
    }

    public mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> [MarkdownNode] {
        ThematicBreakMapper().map(thematicBreak, visitor: &self)
    }

    public mutating func visitHTMLBlock(_ html: HTMLBlock) -> [MarkdownNode] {
        HTMLBlockMapper().map(html, visitor: &self)
    }

    public mutating func visitSoftBreak(_ softBreak: SoftBreak) -> [MarkdownNode] {
        SoftBreakMapper().map(softBreak, visitor: &self)
    }

    public mutating func visitLineBreak(_ lineBreak: LineBreak) -> [MarkdownNode] {
        LineBreakMapper().map(lineBreak, visitor: &self)
    }

    // MARK: - Math (Extensions)
    
    /// swift-markdown does not support native `Math` elements by default in standard CommonMark.
    /// To support ChatGPT parity (`$$` and `$`), our Custom AST Middleware will usually attach these later by finding specific `TextNode` string patterns.
    /// However, if an extension is added to `swift-markdown` or inline HTML block evaluates to math, we intercept it here.
    public mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> [MarkdownNode] {
        InlineHTMLMapper().map(inlineHTML, visitor: &self)
    }
}
