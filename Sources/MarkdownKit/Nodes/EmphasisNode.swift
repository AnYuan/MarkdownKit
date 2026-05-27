import Foundation
import Markdown

/// An inline node representing emphasized (italic) text.
public struct EmphasisNode: InlineNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int

    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "EmphasisNode",
            children: children
        )
    }
}
