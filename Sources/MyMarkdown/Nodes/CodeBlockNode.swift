import Foundation
import Markdown

/// A block node representing a multi-line code block (e.g., ```swift ... ```).
public struct CodeBlockNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    
    /// The language identifier parsed from the markdown, if any (e.g., "swift", "python").
    public let language: String?
    
    /// The raw code content.
    public let code: String
    
    public var children: [MarkdownNode] {
        return [] // Code blocks are evaluated as raw text leaves
    }
    
    public init(range: SourceRange?, language: String?, code: String) {
        self.range = range
        self.language = language
        self.code = code
    }
}
