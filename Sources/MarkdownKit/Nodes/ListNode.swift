//
//  ListNode.swift
//  MarkdownKit
//

import Foundation
import Markdown

/// A block node representing an ordered (`1. …`) or unordered (`- …`) list.
/// Children are always ``ListItemNode`` instances.
public struct ListNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    /// `true` for ordered (numbered) lists, `false` for bullet lists.
    public let isOrdered: Bool
    public let children: [MarkdownNode]
    
    public init(range: SourceRange?, isOrdered: Bool, children: [MarkdownNode]) {
        self.range = range
        self.isOrdered = isOrdered
        self.children = children
    }
}
