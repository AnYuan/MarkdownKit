import Foundation
import Markdown

/// The fundamental building block of the MyMarkdown AST.
///
/// This protocol represents any element parsed from a Markdown document.
/// It acts as the thread-safe, internal representation separate from Apple's `swift-markdown`
/// which ensures our Layout Engine and Rendering UI can operate asynchronously without locks.
public protocol MarkdownNode {
    /// The original source range in the raw markdown string, if available.
    var range: SourceRange? { get }
    
    /// Optional identifier for virtualized Diffing and UI mounting.
    var id: UUID { get }
    
    /// Any child nodes contained within this block.
    var children: [MarkdownNode] { get }
}
