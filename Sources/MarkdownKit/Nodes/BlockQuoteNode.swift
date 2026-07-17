import Foundation
import Markdown

/// A block node representing a blockquote (> prefix).
public struct BlockQuoteNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int
    internal let interactionFingerprint: Int?

    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "BlockQuoteNode",
            children: children
        )
        self.interactionFingerprint = _markdownNodeInteractionFingerprint(
            typeName: "BlockQuoteNode",
            children: children
        )
    }
}

extension BlockQuoteNode: _InteractionFingerprintProviding {}
