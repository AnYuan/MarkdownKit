import Foundation
import Markdown

/// An inline node representing an image.
public struct ImageNode: InlineNode {
    public let id = UUID()
    public let range: SourceRange?
    
    /// The URL or local path of the image.
    public let source: String?
    
    /// The alternative text for the image.
    public let altText: String?
    
    /// The optional title of the image.
    public let title: String?
    
    public var children: [MarkdownNode] {
        return [] // Images are leaves
    }
    
    public init(range: SourceRange?, source: String?, altText: String?, title: String?) {
        self.range = range
        self.source = source
        self.altText = altText
        self.title = title
    }
}
