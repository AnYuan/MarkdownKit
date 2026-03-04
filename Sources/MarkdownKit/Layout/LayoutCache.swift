//
//  LayoutCache.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A thread-safe cache storing previously computed layout results.
/// The cache is keyed on a **content fingerprint** of the node rather than its UUID.
/// This enables cache hits during streaming scenarios where each call to `parser.parse()`
/// creates fresh AST nodes with new UUIDs, but unchanged paragraphs produce identical content.
public final class LayoutCache {

    // MARK: - Content Fingerprinting

    /// Computes a deterministic hash value from a node's semantic content.
    ///
    /// The fingerprint incorporates:
    /// - The concrete node type name (e.g. "ParagraphNode")
    /// - Leaf-level text content (TextNode.text, CodeBlockNode.code, etc.)
    /// - Type-specific properties (HeaderNode.level, ListNode.isOrdered, etc.)
    /// - Recursive children fingerprints
    ///
    /// This is intentionally **not** a cryptographic hash; it uses Swift's `Hasher`
    /// for speed since the only requirement is low collision within a single session.
    private static func contentFingerprint(of node: MarkdownNode) -> Int {
        var hasher = Hasher()
        feedContent(of: node, into: &hasher)
        return hasher.finalize()
    }

    /// Recursively feeds a node's semantic content into the provided hasher.
    private static func feedContent(of node: MarkdownNode, into hasher: inout Hasher) {
        // 1. Node type discriminator
        hasher.combine(String(describing: type(of: node)))

        // 2. Type-specific leaf content and properties
        switch node {
        case let text as TextNode:
            hasher.combine(text.text)
        case let code as CodeBlockNode:
            hasher.combine(code.language)
            hasher.combine(code.code)
        case let inlineCode as InlineCodeNode:
            hasher.combine(inlineCode.code)
        case let header as HeaderNode:
            hasher.combine(header.level)
        case let math as MathNode:
            hasher.combine(math.equation)
            hasher.combine(math.isInline)
        case let diagram as DiagramNode:
            hasher.combine(diagram.language.rawValue)
            hasher.combine(diagram.source)
        case let image as ImageNode:
            hasher.combine(image.source)
            hasher.combine(image.altText)
            hasher.combine(image.title)
        case let link as LinkNode:
            hasher.combine(link.destination)
            hasher.combine(link.title)
        case let list as ListNode:
            hasher.combine(list.isOrdered)
        case let listItem as ListItemNode:
            switch listItem.checkbox {
            case .checked:   hasher.combine("checked")
            case .unchecked: hasher.combine("unchecked")
            case .none:      hasher.combine("none")
            }
        case let details as DetailsNode:
            hasher.combine(details.isOpen)
            if let summary = details.summary {
                feedContent(of: summary, into: &hasher)
            }
        case let table as TableNode:
            for alignment in table.columnAlignments {
                hasher.combine(alignment.map { String(describing: $0) })
            }
        default:
            // BlockQuoteNode, ParagraphNode, DocumentNode, StrongNode, EmphasisNode,
            // StrikethroughNode, SummaryNode, ThematicBreakNode, TableHeadNode,
            // TableBodyNode, TableRowNode, TableCellNode — fully determined by
            // type name + children, which are handled below.
            break
        }

        // 3. Recurse into children
        hasher.combine(node.children.count)
        for child in node.children {
            feedContent(of: child, into: &hasher)
        }
    }

    // MARK: - Cache Key

    /// The internal key structure for NSCache, based on content fingerprint + width.
    private class CacheKey: NSObject {
        let contentHash: Int
        let width: Int

        init(contentHash: Int, width: CGFloat) {
            self.contentHash = contentHash
            // Hash and compare exact integer widths since floating point jitter
            // inside scroll views often breaks fuzzy hit rates.
            self.width = Int(width.rounded())
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(contentHash)
            hasher.combine(width)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? CacheKey else { return false }
            return self.contentHash == other.contentHash && self.width == other.width
        }
    }

    // MARK: - Storage

    private let cache = NSCache<CacheKey, LayoutResultWrapper>()

    // NSCache requires class objects, so we wrap the struct LayoutResult
    private class LayoutResultWrapper {
        let result: LayoutResult
        init(_ result: LayoutResult) {
            self.result = result
        }
    }

    public init(countLimit: Int = 100_000) {
        // Limit cache to prevent memory pressure on massive documents.
        // 100k layout models usually take single-digit megabytes since they are purely structs of CGRects.
        cache.countLimit = countLimit
    }

    // MARK: - Public API

    /// Retrieve a pre-calculated layout if it exists for the given node and container width.
    public func getLayout(for node: MarkdownNode, constrainedToWidth width: CGFloat) -> LayoutResult? {
        let key = CacheKey(contentHash: Self.contentFingerprint(of: node), width: width)
        return cache.object(forKey: key)?.result
    }

    /// Store a freshly computed layout frame.
    public func setLayout(_ result: LayoutResult, constrainedToWidth width: CGFloat) {
        let key = CacheKey(contentHash: Self.contentFingerprint(of: result.node), width: width)
        let wrapper = LayoutResultWrapper(result)
        cache.setObject(wrapper, forKey: key)
    }

    /// Clears all stored layouts (e.g. upon memory warning).
    public func clear() {
        cache.removeAllObjects()
    }
}
