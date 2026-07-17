import Foundation
import Markdown

/// The fundamental building block of the MarkdownKit AST.
///
/// This protocol represents any element parsed from a Markdown document.
/// It acts as the thread-safe, internal representation separate from Apple's `swift-markdown`
/// which ensures our Layout Engine and Rendering UI can operate asynchronously without locks.
public protocol MarkdownNode: Sendable {
    /// The original source range in the raw markdown string, if available.
    var range: SourceRange? { get }

    /// Optional identifier for virtualized Diffing and UI mounting.
    var id: UUID { get }

    /// Any child nodes contained within this block.
    var children: [MarkdownNode] { get }

    /// A deterministic hash derived from this node's semantic content
    /// (type, own fields, and children's fingerprints).
    ///
    /// Required, not defaulted: every conformer must compute its own value at
    /// init time so `LayoutCache` lookups stay O(1). Two structural invariants
    /// every implementer must follow:
    ///
    /// 1. **Never** combine `id: UUID`. The fingerprint must be stable across
    ///    re-parses of the same source so the cache survives streaming updates.
    /// 2. **Never** recurse into `child.children` from your init. Only read
    ///    `child.contentFingerprint`. Otherwise the cache fingerprint becomes
    ///    O(N²) again, which is the whole reason this property exists.
    var contentFingerprint: Int { get }
}

/// Helper used by every `MarkdownNode` conformer to compute its
/// `contentFingerprint` in a single place. Combines the type tag, the node's
/// own-property hash supplied by `extras`, and the children's pre-computed
/// fingerprints.
///
/// - Parameters:
///   - typeName: A stable type discriminator. Use a literal string per type
///     (e.g. `"ParagraphNode"`) rather than `String(describing:)` so the value
///     is independent of module renames.
///   - children: The node's direct children. Only their `contentFingerprint` is
///     read — never their `children`.
///   - extras: Closure that combines any non-children fields onto the hasher.
@inlinable
internal func _markdownNodeFingerprint(
    typeName: String,
    children: [MarkdownNode],
    extras: (inout Hasher) -> Void = { _ in }
) -> Int {
    var hasher = Hasher()
    hasher.combine(typeName)
    extras(&hasher)
    hasher.combine(children.count)
    for child in children {
        hasher.combine(child.contentFingerprint)
    }
    return hasher.finalize()
}

internal protocol _InteractionFingerprintProviding {
    var interactionFingerprint: Int? { get }
}

internal extension MarkdownNode {
    var _interactionFingerprint: Int? {
        (self as? any _InteractionFingerprintProviding)?.interactionFingerprint
    }
}

internal func _markdownSourceRangeInteractionFingerprint(
    typeName: String,
    discriminator: String? = nil,
    range: SourceRange?
) -> Int? {
    guard let range else { return nil }

    var hasher = Hasher()
    hasher.combine(typeName)
    hasher.combine(discriminator)
    hasher.combine(range.lowerBound.line)
    hasher.combine(range.lowerBound.column)
    hasher.combine(range.lowerBound.source)
    hasher.combine(range.upperBound.line)
    hasher.combine(range.upperBound.column)
    hasher.combine(range.upperBound.source)
    return hasher.finalize()
}

internal func _markdownRenderedSourceRangesInteractionFingerprint(
    typeName: String,
    ownRange: SourceRange?,
    summary: MarkdownNode?,
    children: [MarkdownNode],
    includesChildren: Bool
) -> Int? {
    var hasher = Hasher()
    hasher.combine(typeName)
    var hasSourceRange = false

    func combineRange(_ range: SourceRange?, marker: String, index: Int? = nil) {
        guard let fingerprint = _markdownSourceRangeInteractionFingerprint(
            typeName: "RenderedSourceRange",
            range: range
        ) else {
            return
        }
        hasSourceRange = true
        hasher.combine(marker)
        hasher.combine(index)
        hasher.combine(fingerprint)
    }

    func combineNode(_ node: MarkdownNode, marker: String, index: Int? = nil) {
        combineRange(node.range, marker: marker, index: index)
        if let details = node as? DetailsNode {
            if let summary = details.summary {
                combineNode(summary, marker: "summary")
            }
            guard details.isOpen else { return }
        }
        for (childIndex, child) in node.children.enumerated() {
            combineNode(child, marker: "child", index: childIndex)
        }
    }

    combineRange(ownRange, marker: "own")
    if let summary {
        combineNode(summary, marker: "summary")
    }
    if includesChildren {
        for (index, child) in children.enumerated() {
            combineNode(child, marker: "child", index: index)
        }
    }

    return hasSourceRange ? hasher.finalize() : nil
}

internal func _markdownNodeInteractionFingerprint(
    typeName: String,
    ownFingerprint: Int? = nil,
    children: [MarkdownNode]
) -> Int? {
    var hasher = Hasher()
    hasher.combine(typeName)
    var hasInteraction = false
    if let ownFingerprint {
        hasInteraction = true
        hasher.combine("own")
        hasher.combine(ownFingerprint)
    }
    for (index, child) in children.enumerated() {
        guard let fingerprint = child._interactionFingerprint else { continue }
        hasInteraction = true
        hasher.combine("child")
        hasher.combine(index)
        hasher.combine(fingerprint)
    }
    return hasInteraction ? hasher.finalize() : nil
}
