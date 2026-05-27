import Foundation
import Markdown

/// An inline node representing strikethrough text (GFM extension).
public struct StrikethroughNode: InlineNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int

    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "StrikethroughNode",
            children: children
        )
    }
}
