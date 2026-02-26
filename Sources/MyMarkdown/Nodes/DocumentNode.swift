import Foundation
import Markdown

/// The root node representing the entire parsed markdown document.
public struct DocumentNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    
    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
    }
}
