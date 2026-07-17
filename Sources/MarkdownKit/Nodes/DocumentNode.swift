import Foundation
import Markdown

/// The root node representing the entire parsed markdown document.
public struct DocumentNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int
    internal let interactionFingerprint: Int?

    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "DocumentNode",
            children: children
        )
        self.interactionFingerprint = _markdownNodeInteractionFingerprint(
            typeName: "DocumentNode",
            children: children
        )
    }
}

extension DocumentNode: _InteractionFingerprintProviding {}
