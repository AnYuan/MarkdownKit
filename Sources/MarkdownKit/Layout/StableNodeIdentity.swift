//
//  StableNodeIdentity.swift
//  MarkdownKit
//
//  An item ID for `NSDiffableDataSourceSnapshot` that survives re-parsing.
//  `MarkdownNode.id` is a fresh `UUID` per parse, so it cannot be used —
//  diffable would see the whole list as new on every keystroke and degrade
//  into a full reload. `StableNodeIdentity` combines the node's exact dynamic
//  concrete type with either its content or its top-level position, which:
//
//  * stays stable when the user appends new content at the end (the top-level
//    index of every leading block is unchanged);
//  * keeps standalone and cached layouts distinct when their content differs;
//  * keeps a top-level row stable when same-type content changes;
//  * disambiguates two structurally identical blocks at different positions
//    (e.g. two empty `> ` blockquotes).
//

import Foundation

struct StableNodeIdentity: Hashable, Sendable {
    private enum Position: Hashable, Sendable {
        case unpositioned(contentFingerprint: Int)
        case topLevel(index: Int)
    }

    private let concreteNodeType: ObjectIdentifier
    private let position: Position

    init(unpositioned node: MarkdownNode) {
        self.init(
            node: node,
            position: .unpositioned(contentFingerprint: node.contentFingerprint)
        )
    }

    static func topLevel(node: MarkdownNode, index: Int) -> StableNodeIdentity {
        StableNodeIdentity(node: node, position: .topLevel(index: index))
    }

    private init(node: MarkdownNode, position: Position) {
        concreteNodeType = ObjectIdentifier(type(of: node))
        self.position = position
    }
}
