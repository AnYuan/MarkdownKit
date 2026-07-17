import Foundation

/// A utility that extracts a heading-based table of contents from a `DocumentNode`.
struct TableOfContentsBuilder {

    /// A single entry in the table of contents.
    struct Entry: Sendable {
        /// The heading level (1–6).
        let level: Int
        /// The plain-text content of the heading.
        let text: String
    }

    /// Walks the document's top-level children and extracts all `HeaderNode` entries
    /// in document order.
    ///
    /// - Parameter document: The root document node to scan.
    /// - Returns: An ordered list of heading entries.
    static func build(from document: DocumentNode) -> [Entry] {
        var entries: [Entry] = []
        for child in document.children {
            collectHeadings(from: child, into: &entries)
        }
        return entries
    }

    private static func collectHeadings(from node: MarkdownNode, into entries: inout [Entry]) {
        if let header = node as? HeaderNode {
            let text = flattenText(from: header)
            entries.append(Entry(level: header.level, text: text))
        }
        for child in node.children {
            collectHeadings(from: child, into: &entries)
        }
    }

    private static func flattenText(from node: MarkdownNode) -> String {
        if let text = node as? TextNode {
            return text.text
        }
        if let code = node as? InlineCodeNode {
            return code.code
        }
        return node.children.map { flattenText(from: $0) }.joined()
    }
}
