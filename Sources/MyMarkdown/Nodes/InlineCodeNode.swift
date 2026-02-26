import Foundation
import Markdown

/// An inline node representing a short snippet of code (e.g., `let x = 1`).
public struct InlineCodeNode: InlineNode {
    public let id = UUID()
    public let range: SourceRange?
    
    /// The raw code content.
    public let code: String
    
    public var children: [MarkdownNode] {
        return [] // Inline code blocks are evaluated as raw text leaves
    }
    
    public init(range: SourceRange?, code: String) {
        self.range = range
        self.code = code
    }
}
