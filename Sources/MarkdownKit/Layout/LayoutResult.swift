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
    /// (e.g. table cards drawn directly via CGContext). Rendering hosts call
    /// this instead of the default attributed-string draw path.
    public let customDraw: (@Sendable (CGContext, CGSize) -> Void)?

    /// Internal diffable identity used by render hosts to detect insert /
    /// delete / reuse across re-parses. MarkdownKit stamps the content and
    /// top-level position before a result enters a collection-view snapshot.
    let stableIdentity: StableNodeIdentity

    /// Internal accessibility metadata cached for platform hosts. Built once on
    /// the background layout thread so cell reconfigure on the main thread
    /// doesn't repeat `attributedString.enumerateAttribute(...)` for checkbox
    /// detection.
    let accessibility: AccessibilityMetadata

    /// The explicit appearance under which this layout was produced.
    /// `.light` by default for results created outside a `LayoutSolver`.
    public let appearance: MarkdownAppearance

    /// Internal redraw/cache fingerprint. Solver output combines node content
    /// with its render variant; publicly constructed payloads derive a
    /// conservative fingerprint from their immutable render inputs.
    let renderFingerprint: Int

    /// Range-sensitive identity for interaction payloads embedded in the
    /// attributed string. Kept separate from pixel-only rendering identity.
    internal let interactionFingerprint: Int?

    /// Creates a host-supplied render payload. MarkdownKit derives diff and
    /// redraw metadata internally; opaque custom drawing closures are
    /// conservatively treated as a fresh render variant on each construction.
    public init(
        node: MarkdownNode,
        size: CGSize,
        attributedString: NSAttributedString? = nil,
        children: [LayoutResult] = [],
        customDraw: (@Sendable (CGContext, CGSize) -> Void)? = nil,
        appearance: MarkdownAppearance = .light
    ) {
        let renderFingerprint = Self.makePublicRenderFingerprint(
            node: node,
            size: size,
            attributedString: attributedString,
            children: children,
            customDraw: customDraw,
            appearance: appearance
        )
        self.init(
            node: node,
            size: size,
            attributedString: attributedString,
            children: children,
            customDraw: customDraw,
            stableIdentity: nil,
            accessibility: nil,
            appearance: appearance,
            renderFingerprint: renderFingerprint
        )
    }

    init(
        node: MarkdownNode,
        size: CGSize,
        attributedString: NSAttributedString? = nil,
        children: [LayoutResult] = [],
        customDraw: (@Sendable (CGContext, CGSize) -> Void)? = nil,
        stableIdentity: StableNodeIdentity? = nil,
        accessibility: AccessibilityMetadata? = nil,
        appearance: MarkdownAppearance = .light,
        renderFingerprint: Int? = nil
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
        self.appearance = appearance
        self.renderFingerprint = renderFingerprint ?? node.contentFingerprint
        self.interactionFingerprint = node._interactionFingerprint
    }

    /// Returns a copy with its module-owned diffable identity replaced.
    func withStableIdentity(_ identity: StableNodeIdentity) -> LayoutResult {
        guard stableIdentity != identity else { return self }
        return LayoutResult(
            node: node,
            size: size,
            attributedString: attributedString,
            children: children,
            customDraw: customDraw,
            stableIdentity: identity,
            accessibility: accessibility,
            appearance: appearance,
            renderFingerprint: renderFingerprint
        )
    }

    func positionedAtTopLevel(index: Int) -> LayoutResult {
        withStableIdentity(Self.topLevelStableIdentity(for: node.contentFingerprint, index: index))
    }

    static func positionedTopLevelLayouts(_ layouts: [LayoutResult]) -> [LayoutResult] {
        var positionedLayouts: [LayoutResult]?

        for (index, layout) in layouts.enumerated() {
            let positionedLayout = layout.positionedAtTopLevel(index: index)
            guard positionedLayouts != nil || positionedLayout.stableIdentity != layout.stableIdentity else {
                continue
            }

            if positionedLayouts == nil {
                positionedLayouts = Array(layouts[..<index])
                positionedLayouts?.reserveCapacity(layouts.count)
            }
            positionedLayouts?.append(positionedLayout)
        }

        return positionedLayouts ?? layouts
    }

    private static func topLevelStableIdentity(for contentFingerprint: Int, index: Int) -> StableNodeIdentity {
        StableNodeIdentity(
            contentFingerprint: contentFingerprint,
            pathHash: StableNodeIdentity.pathHash(for: [index])
        )
    }

    private static func makePublicRenderFingerprint(
        node: MarkdownNode,
        size: CGSize,
        attributedString: NSAttributedString?,
        children: [LayoutResult],
        customDraw: (@Sendable (CGContext, CGSize) -> Void)?,
        appearance: MarkdownAppearance
    ) -> Int {
        var hasher = Hasher()
        hasher.combine(node.contentFingerprint)
        hasher.combine(appearance)
        hasher.combine(size.width)
        hasher.combine(size.height)

        if let attributedString {
            hasher.combine(true)
            hash(attributedString: attributedString, into: &hasher)
        } else {
            hasher.combine(false)
        }

        hasher.combine(children.count)
        for child in children {
            hasher.combine(child.renderFingerprint)
            hasher.combine(child.appearance)
        }

        if customDraw != nil {
            hasher.combine(true)
            // Closures are not hashable, so each public construction with a
            // drawing closure gets a fresh render variant.
            hasher.combine(UUID())
        } else {
            hasher.combine(false)
        }

        return hasher.finalize()
    }

    private static func hash(attributedString: NSAttributedString, into hasher: inout Hasher) {
        hasher.combine(attributedString.string)
        hasher.combine(attributedString.length)
        let range = NSRange(location: 0, length: attributedString.length)
        attributedString.enumerateAttributes(in: range) { attributes, runRange, _ in
            hasher.combine(runRange.location)
            hasher.combine(runRange.length)
            for key in attributes.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                hasher.combine(key.rawValue)
                hash(attributeValue: attributes[key] as Any, into: &hasher)
            }
        }
    }

    private static func hash(attributeValue value: Any, into hasher: inout Hasher) {
        switch value {
        case let number as NSNumber:
            hasher.combine(number)
        case let string as NSString:
            hasher.combine(string)
        #if canImport(UIKit)
        case let color as UIColor:
            hasher.combine(color)
        case let font as UIFont:
            hasher.combine(font.fontName)
            hasher.combine(font.pointSize)
        #elseif canImport(AppKit)
        case let color as NSColor:
            hasher.combine(color)
        case let font as NSFont:
            hasher.combine(font.fontName)
            hasher.combine(font.pointSize)
        #endif
        case let paragraphStyle as NSParagraphStyle:
            hasher.combine(paragraphStyle)
            hasher.combine(paragraphStyle.alignment.rawValue)
            hasher.combine(paragraphStyle.lineBreakMode.rawValue)
            hasher.combine(paragraphStyle.lineSpacing)
            hasher.combine(paragraphStyle.paragraphSpacing)
            hasher.combine(paragraphStyle.paragraphSpacingBefore)
            hasher.combine(paragraphStyle.firstLineHeadIndent)
            hasher.combine(paragraphStyle.headIndent)
            hasher.combine(paragraphStyle.tailIndent)
            hasher.combine(paragraphStyle.minimumLineHeight)
            hasher.combine(paragraphStyle.maximumLineHeight)
            hasher.combine(paragraphStyle.baseWritingDirection.rawValue)
            hasher.combine(paragraphStyle.defaultTabInterval)
        case let shadow as NSShadow:
            hasher.combine(shadow)
            hasher.combine(shadow.shadowOffset.width)
            hasher.combine(shadow.shadowOffset.height)
            hasher.combine(shadow.shadowBlurRadius)
            if let shadowColor = shadow.shadowColor {
                hash(attributeValue: shadowColor, into: &hasher)
            }
        case let object as NSObject:
            hasher.combine(String(reflecting: type(of: object)))
            hasher.combine(object.hash)
        default:
            hasher.combine(String(reflecting: type(of: value)))
            hasher.combine(String(describing: value))
        }
    }
}

enum LayoutResultVariantDiff {
    static func changedStableIdentities(
        previous: [StableNodeIdentity: LayoutResult],
        next: [LayoutResult]
    ) -> [StableNodeIdentity] {
        next.compactMap { layout in
            guard let oldLayout = previous[layout.stableIdentity],
                  oldLayout.renderFingerprint != layout.renderFingerprint
                   || oldLayout.appearance != layout.appearance
                   || oldLayout.size != layout.size
                   || oldLayout.interactionFingerprint != layout.interactionFingerprint else {
                return nil
            }
            return layout.stableIdentity
        }
    }
}
