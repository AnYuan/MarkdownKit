import Foundation
import Markdown

/// An inline node representing plain, unstyled text.
public struct TextNode: InlineNode {
    public let id = UUID()
    public let range: SourceRange?
    public let text: String
    
    public var children: [MarkdownNode] {
        return [] // TextNode is a leaf and contains no children
    }
    
    public init(range: SourceRange?, text: String) {
        self.range = range
        self.text = text
    }
}
