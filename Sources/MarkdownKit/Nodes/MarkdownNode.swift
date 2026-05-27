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
