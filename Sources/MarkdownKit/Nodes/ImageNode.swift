import Foundation
import Markdown

/// An inline node representing an image.
public struct ImageNode: InlineNode {
    public let id = UUID()
    public let range: SourceRange?

    /// The URL or local path of the image.
    public let source: String?

    /// The alternative text for the image.
    public let altText: String?

    /// The optional title of the image.
    public let title: String?

    public let contentFingerprint: Int

    public var children: [MarkdownNode] {
        return [] // Images are leaves
    }

    public init(range: SourceRange?, source: String?, altText: String?, title: String?) {
        let sanitizedSource = URLSanitizer.sanitize(source)
        self.range = range
        self.source = sanitizedSource
        self.altText = altText
        self.title = title
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "ImageNode",
            children: []
        ) { hasher in
            hasher.combine(sanitizedSource)
            hasher.combine(altText)
            hasher.combine(title)
        }
    }
}
