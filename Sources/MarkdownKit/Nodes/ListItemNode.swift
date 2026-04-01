//
//  ListItemNode.swift
//  MarkdownKit
//

import Foundation
import Markdown

/// The state of a task-list checkbox within a list item.
public enum CheckboxState: Sendable {
    /// A checked checkbox (`- [x]`).
    case checked
    /// An unchecked checkbox (`- [ ]`).
    case unchecked
    /// No checkbox — a regular list item.
    case none
}

/// A single item within an ordered or unordered list, optionally containing a task-list checkbox.
public struct ListItemNode: BlockNode {
    public let id = UUID()
    public let range: SourceRange?
    /// The checkbox state for task-list items, or `.none` for regular bullets.
    public let checkbox: CheckboxState
    public let children: [MarkdownNode]

    public init(range: SourceRange?, checkbox: CheckboxState = .none, children: [MarkdownNode]) {
        self.range = range
        self.checkbox = checkbox
        self.children = children
    }
}
