import Foundation
import Markdown

/// An inline node representing a hyperlink.
public struct LinkNode: InlineNode {
    public let id = UUID()
    public let range: SourceRange?
    
    /// The destination URL.
    public let destination: String?
    
    /// The title of the link, if provided.
    public let title: String?
    
    /// The inner elements forming the text of the link.
    public let children: [MarkdownNode]
    
    public init(range: SourceRange?, destination: String?, title: String?, children: [MarkdownNode]) {
        self.range = range
        self.destination = destination
        self.title = title
        self.children = children
    }
}
