//
//  StableNodeIdentity.swift
//  MarkdownKit
//
//  An item ID for `NSDiffableDataSourceSnapshot` that survives re-parsing.
//  `MarkdownNode.id` is a fresh `UUID` per parse, so it cannot be used —
//  diffable would see the whole list as new on every keystroke and degrade
//  into a full reload. `StableNodeIdentity` combines the node's content
//  fingerprint with its position path in the document, which:
//
//  * stays stable when the user appends new content at the end (path of every
//    leading block is unchanged);
//  * changes when content changes (fingerprint differs);
//  * disambiguates two structurally identical blocks at different positions
//    (e.g. two empty `> ` blockquotes).
//

import Foundation

public struct StableNodeIdentity: Hashable, Sendable {
    /// The node's content fingerprint (type + own props + children fingerprints).
    public let contentFingerprint: Int

    /// A hash of the index path from the document root to this node.
    /// A leading top-level block has `pathHash` derived from `[i]`; a nested
    /// block has `pathHash` derived from `[i, j, …]`. The exact integers don't
    /// leak via the public API — we only expose the final folded hash.
    public let pathHash: Int

    public init(contentFingerprint: Int, pathHash: Int) {
        self.contentFingerprint = contentFingerprint
        self.pathHash = pathHash
    }

    /// Folds an `[Int]` index path into a single hash. Use during recursive
    /// layout building.
    public static func pathHash(for indexPath: [Int]) -> Int {
        var hasher = Hasher()
        for index in indexPath {
            hasher.combine(index)
        }
        return hasher.finalize()
    }
}
