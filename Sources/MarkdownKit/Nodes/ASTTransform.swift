import Foundation

/// What an AST visitor wants `AST.transform` to do at a given node.
public enum ASTRewrite {
    /// Keep the original node, then recurse into its children.
    /// Identity is preserved: if all children also come back unchanged, the
    /// container's UUID and `contentFingerprint` survive the traversal.
    case unchanged

    /// Replace this node with a single new node.
    /// Recursion continues into the *replacement's* children so downstream
    /// transformations still apply.
    case replace(MarkdownNode)

    /// Splat this node into a sequence of sibling nodes.
    /// The returned list is **terminal** — no further recursion happens on
    /// the splatted items. Use this when the visitor has already produced the
    /// desired final shape (e.g. a TextNode broken into `[Text, Math, Text]`).
    case replaceMany([MarkdownNode])

    /// Use the replacement node as-is and skip recursion into its children.
    /// Use this when entering a subtree would re-trigger the visitor's logic
    /// undesirably (e.g. an autolink plugin must not re-process the inside of
    /// an existing `LinkNode`).
    case skipChildren(MarkdownNode)
}

/// Centralized AST rewrite utility. Replaces the ~80-line per-node `switch`
/// previously duplicated across every plugin.
///
/// The transform walks `nodes` in pre-order:
///
/// 1. Call `visit(node)`.
/// 2. For `.unchanged` / `.replace`: recurse into the node's children. If every
///    child came back unchanged (UUID match), the original node reference is
///    returned (struct value re-emitted with the same UUID + fingerprint).
///    Otherwise the container is rebuilt with the new child list.
/// 3. For `.replaceMany` / `.skipChildren`: emit the visitor's output verbatim.
///
/// Optionally, the caller can supply `postProcessSiblings` to reshape **every**
/// sibling list after per-node recursion (top level and inside every container).
/// `DetailsExtractionPlugin` uses this for its multi-node `<details>` open/close
/// merging.
///
/// Critically, **container rebuild happens in one place**: `rebuildContainer`.
/// New plugins do not need to enumerate every container type.
public enum AST {

    public static func transform(
        _ nodes: [MarkdownNode],
        postProcessSiblings: ([MarkdownNode]) -> [MarkdownNode] = { $0 },
        visit: (MarkdownNode) -> ASTRewrite
    ) -> [MarkdownNode] {
        var processed: [MarkdownNode] = []
        processed.reserveCapacity(nodes.count)
        for node in nodes {
            switch visit(node) {
            case .unchanged:
                processed.append(recurseAndMaybeRebuild(node, post: postProcessSiblings, visit: visit))
            case .replace(let replacement):
                processed.append(recurseAndMaybeRebuild(replacement, post: postProcessSiblings, visit: visit))
            case .replaceMany(let splat):
                processed.append(contentsOf: splat)
            case .skipChildren(let replacement):
                processed.append(replacement)
            }
        }
        return postProcessSiblings(processed)
    }

    /// Recurse into `node.children`. If the children come back unchanged, the
    /// original `node` is returned (UUID + fingerprint preserved). Otherwise
    /// `node` is rebuilt with the new child list.
    private static func recurseAndMaybeRebuild(
        _ node: MarkdownNode,
        post: ([MarkdownNode]) -> [MarkdownNode],
        visit: (MarkdownNode) -> ASTRewrite
    ) -> MarkdownNode {
        // `DetailsNode.summary` is a sibling-of-children that the protocol
        // doesn't expose via `children`. To keep traversal complete (e.g. the
        // math plugin needs to find `$...$` inside `<summary>` text), we recurse
        // it explicitly here.
        if let details = node as? DetailsNode {
            return rebuildDetailsRecursively(details, post: post, visit: visit)
        }

        let original = node.children
        guard !original.isEmpty else { return node }

        let transformed = transform(original, postProcessSiblings: post, visit: visit)
        if childrenIdentical(transformed, original) {
            return node
        }
        return rebuildContainer(node, withChildren: transformed)
    }

    private static func rebuildDetailsRecursively(
        _ details: DetailsNode,
        post: ([MarkdownNode]) -> [MarkdownNode],
        visit: (MarkdownNode) -> ASTRewrite
    ) -> MarkdownNode {
        let newChildren = transform(details.children, postProcessSiblings: post, visit: visit)
        let newSummary: SummaryNode?
        if let summary = details.summary {
            let newSummaryChildren = transform(summary.children, postProcessSiblings: post, visit: visit)
            if childrenIdentical(newSummaryChildren, summary.children) {
                newSummary = summary
            } else {
                newSummary = SummaryNode(range: summary.range, children: newSummaryChildren)
            }
        } else {
            newSummary = nil
        }

        let summaryUnchanged = newSummary?.id == details.summary?.id
        if summaryUnchanged, childrenIdentical(newChildren, details.children) {
            return details
        }
        return DetailsNode(
            range: details.range,
            isOpen: details.isOpen,
            summary: newSummary,
            children: newChildren
        )
    }

    /// Two child arrays are "identical" when they have the same length and
    /// every element's `id` matches positionally. UUID equality is the cheapest
    /// reliable identity check for value-type AST nodes.
    private static func childrenIdentical(
        _ lhs: [MarkdownNode],
        _ rhs: [MarkdownNode]
    ) -> Bool {
        guard lhs.count == rhs.count else { return false }
        for i in 0..<lhs.count where lhs[i].id != rhs[i].id {
            return false
        }
        return true
    }

    /// The single, centralized "copy this container with new children" switch.
    /// Plugins that previously duplicated 24 cases now stay free of this code.
    ///
    /// Leaf nodes (TextNode, CodeBlockNode, InlineCodeNode, ImageNode, MathNode,
    /// DiagramNode, ThematicBreakNode) have no children, so the original is
    /// returned unchanged. Any new container type added later must be added
    /// here.
    private static func rebuildContainer(
        _ node: MarkdownNode,
        withChildren children: [MarkdownNode]
    ) -> MarkdownNode {
        switch node {
        case let n as DocumentNode:
            return DocumentNode(range: n.range, children: children)
        case let n as ParagraphNode:
            return ParagraphNode(range: n.range, children: children)
        case let n as HeaderNode:
            return HeaderNode(range: n.range, level: n.level, children: children)
        case let n as BlockQuoteNode:
            return BlockQuoteNode(range: n.range, children: children)
        case let n as EmphasisNode:
            return EmphasisNode(range: n.range, children: children)
        case let n as StrongNode:
            return StrongNode(range: n.range, children: children)
        case let n as StrikethroughNode:
            return StrikethroughNode(range: n.range, children: children)
        case let n as LinkNode:
            return LinkNode(
                range: n.range,
                destination: n.destination,
                title: n.title,
                children: children
            )
        case let n as ListNode:
            return ListNode(range: n.range, isOrdered: n.isOrdered, children: children)
        case let n as ListItemNode:
            return ListItemNode(range: n.range, checkbox: n.checkbox, children: children)
        case let n as DetailsNode:
            // Summary is not part of `children`; preserve it verbatim. Plugins
            // that want to transform a summary should return `.replace(newDetails)`.
            return DetailsNode(
                range: n.range,
                isOpen: n.isOpen,
                summary: n.summary,
                children: children
            )
        case let n as SummaryNode:
            return SummaryNode(range: n.range, children: children)
        case let n as TableNode:
            return TableNode(
                range: n.range,
                columnAlignments: n.columnAlignments,
                children: children
            )
        case let n as TableHeadNode:
            return TableHeadNode(range: n.range, children: children)
        case let n as TableBodyNode:
            return TableBodyNode(range: n.range, children: children)
        case let n as TableRowNode:
            return TableRowNode(range: n.range, children: children)
        case let n as TableCellNode:
            return TableCellNode(range: n.range, children: children)
        default:
            // Leaf node (TextNode/CodeBlockNode/etc.) — has no children that
            // can have been transformed. Return unchanged.
            return node
        }
    }
}
