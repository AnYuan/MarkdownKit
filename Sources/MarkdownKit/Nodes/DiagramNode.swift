import Foundation
import Markdown

public enum DiagramLanguage: String, CaseIterable, Sendable {
    case mermaid
    case geojson
    case topojson
    case stl
}

/// A block node representing a diagram-oriented fenced code block.
public struct DiagramNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let language: DiagramLanguage
    public let source: String
    public let children: [MarkdownNode] = []
    public let contentFingerprint: Int

    public init(range: SourceRange?, language: DiagramLanguage, source: String) {
        self.range = range
        self.language = language
        self.source = source
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "DiagramNode",
            children: []
        ) { hasher in
            hasher.combine(language.rawValue)
            hasher.combine(source)
        }
    }
}
