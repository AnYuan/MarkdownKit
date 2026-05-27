//
//  TableNode.swift
//  MarkdownKit
//

import Foundation
import Markdown

/// The text alignment of a table column, as specified by the Markdown separator row (e.g. `:---`, `:---:`, `---:`).
public enum TableAlignment: Sendable {
    case left, right, center
}

/// A block node representing a GFM table.
/// Children are ``TableHeadNode`` and ``TableBodyNode``.
public struct TableNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    /// Per-column alignment directives parsed from the separator row. `nil` means unspecified (defaults to left).
    public let columnAlignments: [TableAlignment?]
    public let contentFingerprint: Int

    public init(range: SourceRange?, columnAlignments: [TableAlignment?], children: [MarkdownNode]) {
        self.range = range
        self.columnAlignments = columnAlignments
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "TableNode",
            children: children
        ) { hasher in
            for alignment in columnAlignments {
                // Mirror LayoutCache.feedContent's prior `String(describing:)` form.
                hasher.combine(alignment.map { String(describing: $0) })
            }
        }
    }
}

/// The header section of a table. Contains a single ``TableRowNode``.
public struct TableHeadNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int

    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "TableHeadNode",
            children: children
        )
    }
}

/// The body section of a table. Contains one or more ``TableRowNode`` instances.
public struct TableBodyNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int

    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "TableBodyNode",
            children: children
        )
    }
}

/// A single row within a table head or body. Children are ``TableCellNode`` instances.
public struct TableRowNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int

    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "TableRowNode",
            children: children
        )
    }
}

/// A single cell within a table row. Children are inline nodes (text, code, links, etc.).
public struct TableCellNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    public let children: [MarkdownNode]
    public let contentFingerprint: Int

    public init(range: SourceRange?, children: [MarkdownNode]) {
        self.range = range
        self.children = children
        self.contentFingerprint = _markdownNodeFingerprint(
            typeName: "TableCellNode",
            children: children
        )
    }
}
