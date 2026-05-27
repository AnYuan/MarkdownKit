import Foundation
import Markdown

/// An inline node representing strong (bold) text.
public struct StrongNode: InlineNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int

    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "StrongNode",
            children: children
        )
    }
}
