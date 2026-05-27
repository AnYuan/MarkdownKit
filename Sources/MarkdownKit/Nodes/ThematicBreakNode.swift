import Foundation
import Markdown

/// A block node representing a thematic break / horizontal rule (---).
public struct ThematicBreakNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let contentFingerprint: Int

    public var children: [MarkdownNode] { [] }

    public init(range: SourceRange?) {
        self.range = range
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "ThematicBreakNode",
            children: []
        )
    }
}
