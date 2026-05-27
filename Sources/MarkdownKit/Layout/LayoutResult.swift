//
//  LayoutResult.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A strictly immutable struct carrying the pre-calculated bounding box, sizing, and
/// rendering instructions for a specific Markdown Node.
///
/// This is heavily inspired by Texture's (AsyncDisplayKit) `ASLayout` node models.
/// By calculating this solely on a background thread, our Collection Views (iOS/macOS)
/// can query `.frame` instantaneously in `sizeForItem` without triggering TextKit
/// layout passes on the Main Thread.
public struct LayoutResult {
    /// The specific node this layout represents.
    public let node: MarkdownNode

    /// The exact, calculated dimensions `(width, height)`.
    public let size: CGSize

    /// The pre-calculated string properties if applicable (already styled with Themes).
    /// Rendering this string asynchronously off the main thread is Phase 3.
    public let attributedString: NSAttributedString?

    /// Any children layouts (e.g. nested lists).
    public let children: [LayoutResult]

    /// Optional custom drawing closure for nodes that bypass TextKit rendering
    /// (e.g. table cards drawn directly via CGContext). When present, `AsyncTextView`
    /// calls this instead of the default `NSLayoutManager` draw path.
    public let customDraw: (@Sendable (CGContext, CGSize) -> Void)?

    /// Stable cross-render identity used by diffable data sources to detect
    /// insert / delete / reuse across re-parses. Computed by `LayoutSolver` as
    /// it walks the document and assigns each layout its index path.
    public let stableIdentity: StableNodeIdentity

    /// Pre-computed accessibility metadata for `PlatformAccessibility`.
    /// Built once on the background layout thread so cell reconfigure on the
    /// main thread doesn't repeat `attributedString.enumerateAttribute(...)`
    /// for checkbox detection.
    public let accessibility: AccessibilityMetadata

    public init(
        node: MarkdownNode,
        size: CGSize,
        attributedString: NSAttributedString? = nil,
        children: [LayoutResult] = [],
        customDraw: (@Sendable (CGContext, CGSize) -> Void)? = nil,
        stableIdentity: StableNodeIdentity? = nil,
        accessibility: AccessibilityMetadata? = nil
    ) {
        self.node = node
        self.size = size
        self.attributedString = attributedString
        self.children = children
        self.customDraw = customDraw
        // Default to a top-level (empty-path) identity. `LayoutSolver` overrides
        // this with the actual index path when recursing the document tree.
        self.stableIdentity = stableIdentity
            ?? StableNodeIdentity(contentFingerprint: node.contentFingerprint, pathHash: 0)
        self.accessibility = accessibility
            ?? AccessibilityMetadata.make(for: node, attributedString: attributedString)
    }

    /// Returns a copy of this result with its `stableIdentity` replaced. Used
    /// by `LayoutSolver` to stamp the correct document-position hash onto
    /// otherwise-cached results.
    public func withStableIdentity(_ identity: StableNodeIdentity) -> LayoutResult {
        LayoutResult(
            node: node,
            size: size,
            attributedString: attributedString,
            children: children,
            customDraw: customDraw,
            stableIdentity: identity,
            accessibility: accessibility
        )
    }
}
