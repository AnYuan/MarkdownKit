import Foundation
import Markdown

/// A block node representing a standard paragraph of text.
public struct ParagraphNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    
    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
    }
}
