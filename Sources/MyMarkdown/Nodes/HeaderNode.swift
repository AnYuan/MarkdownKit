import Foundation
import Markdown

/// A block node representing a heading (e.g., `# H1`, `## H2`).
public struct HeaderNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let level: Int
    public let children: [MarkdownNode]
    
    public init(range: SourceRange?, level: Int, children: [MarkdownNode]) {
        self.range = range
        self.level = level
        self.children = children
    }
}
