import Foundation
import Markdown

/// A block node representing an HTML `<details>` container.
public struct DetailsNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let isOpen: Bool
    public let summary: SummaryNode?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int

    public init(
        range: SourceRange?,
        isOpen: Bool,
        summary: SummaryNode?,
        children: [MarkdownNode]
    ) {
        self.range = range
        self.isOpen = isOpen
        self.summary = summary
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "DetailsNode",
            children: children
        ) { hasher in
            hasher.combine(isOpen)
            // Summary is a sibling node, not part of `children`, so we must
            // explicitly combine its fingerprint (read-only — never its children).
            hasher.combine(summary?.contentFingerprint)
        }
    }
}

/// A block node representing an HTML `<summary>` row.
public struct SummaryNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int

    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "SummaryNode",
            children: children
        )
    }
}
