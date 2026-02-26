import Foundation
import Markdown

/// A protocol that represents inline markdown elements.
/// Inline elements do not force a new line and are contained within block elements.
/// Examples: Text, Strong, Emphasis, InlineCode, Link.
public protocol InlineNode: MarkdownNode {
    // Shared logical grouping for inline text modifiers
}
