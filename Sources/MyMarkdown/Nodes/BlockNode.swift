import Foundation
import Markdown

/// A protocol that represents block-level markdown elements.
/// Block elements typically start on a new line and can contain other blocks or inline elements.
/// Examples: Paragraph, Header, CodeBlock, Blockquote.
public protocol BlockNode: MarkdownNode {
    // Shared layout properties for blocks could go here in the future
}
