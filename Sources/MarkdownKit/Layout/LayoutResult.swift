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
    /// delete / reuse across re-parses. MarkdownKit preserves content
    /// discrimination until stamping the top-level position for collection use.
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

    /// Advisory retained-cost estimate used by `LayoutCache`.
    /// Computed once so cache insertion remains O(1).
    internal let estimatedCacheCost: Int

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
        let frozenAttributedString = attributedString.map(NSAttributedString.init(attributedString:))
        self.node = node
        self.size = size
        self.attributedString = frozenAttributedString
        self.children = children
        self.customDraw = customDraw
        // Standalone and cached results remain content-discriminated until a
        // collection boundary stamps their top-level position.
        self.stableIdentity = stableIdentity
            ?? StableNodeIdentity(unpositioned: node)
        self.accessibility = accessibility
            ?? AccessibilityMetadata.make(for: node, attributedString: frozenAttributedString)
        self.appearance = appearance
        self.renderFingerprint = renderFingerprint ?? node.contentFingerprint
        self.interactionFingerprint = node._interactionFingerprint
        self.estimatedCacheCost = LayoutCacheCostEstimator.estimate(
            attributedString: frozenAttributedString,
            children: children,
            size: size,
            hasCustomDraw: customDraw != nil
        )
    }

    private init(copying result: LayoutResult, stableIdentity: StableNodeIdentity) {
        node = result.node
        size = result.size
        attributedString = result.attributedString
        children = result.children
        customDraw = result.customDraw
        self.stableIdentity = stableIdentity
        accessibility = result.accessibility
        appearance = result.appearance
        renderFingerprint = result.renderFingerprint
        interactionFingerprint = result.interactionFingerprint
        estimatedCacheCost = result.estimatedCacheCost
    }

    /// Returns a copy with its module-owned diffable identity replaced.
    func withStableIdentity(_ identity: StableNodeIdentity) -> LayoutResult {
        guard stableIdentity != identity else { return self }
        return LayoutResult(copying: self, stableIdentity: identity)
    }

    func positionedAtTopLevel(index: Int) -> LayoutResult {
        withStableIdentity(.topLevel(node: node, index: index))
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

enum LayoutCacheCostEstimator {
    private static let baseEntryCost = 256
    private static let attributedStringUnitCost = 64
    private static let customDrawClosureCost = 1_024
    private static let customDrawSquarePointCost = 4

    static func estimate(
        attributedString: NSAttributedString?,
        children: [LayoutResult],
        size: CGSize,
        hasCustomDraw: Bool
    ) -> Int {
        var cost = baseEntryCost
        cost = saturatingAdd(
            cost,
            saturatingMultiply(attributedString?.length ?? 0, attributedStringUnitCost)
        )
        cost = saturatingAdd(
            cost,
            saturatingMultiply(children.count, MemoryLayout<LayoutResult>.stride)
        )
        // A parent independently retains its complete child tree even when the
        // solver also caches those children as separate entries. Charging the
        // overlap is deliberate: otherwise an evicted child entry could leave a
        // near-zero-cost root retaining the same subtree.
        for child in children {
            cost = saturatingAdd(cost, child.estimatedCacheCost)
        }

        if hasCustomDraw {
            cost = saturatingAdd(cost, customDrawClosureCost)
            cost = saturatingAdd(cost, customDrawGeometryCost(for: size))
        }
        return cost
    }

    static func saturatingAdd(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : value
    }

    static func saturatingMultiply(_ lhs: Int, _ rhs: Int) -> Int {
        let (value, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        return overflow ? .max : value
    }

    static func customDrawGeometryCost(for size: CGSize) -> Int {
        let width = Double(size.width)
        let height = Double(size.height)
        guard width.isFinite, height.isFinite, width >= 0, height >= 0 else {
            return .max
        }

        let area = width * height
        guard area.isFinite, area >= 0,
              let roundedSquarePoints = Int(exactly: area.rounded(.up)) else {
            return .max
        }
        return saturatingMultiply(roundedSquarePoints, customDrawSquarePointCost)
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

struct LayoutCollectionUpdatePlan {
    let layoutsByIdentity: [StableNodeIdentity: LayoutResult]
    let orderedIdentities: [StableNodeIdentity]
    let changedRetainedIdentities: [StableNodeIdentity]
    let hasRetainedSizeChange: Bool
    let requiresSnapshotApplication: Bool

    init(
        layouts: [LayoutResult],
        previousLayoutsByIdentity: [StableNodeIdentity: LayoutResult],
        currentOrderedIdentities: [StableNodeIdentity],
        hasMainSection: Bool
    ) {
        let positionedLayouts = LayoutResult.positionedTopLevelLayouts(layouts)
        var layoutsByIdentity: [StableNodeIdentity: LayoutResult] = [:]
        var orderedIdentities: [StableNodeIdentity] = []
        layoutsByIdentity.reserveCapacity(positionedLayouts.count)
        orderedIdentities.reserveCapacity(positionedLayouts.count)

        for layout in positionedLayouts {
            layoutsByIdentity[layout.stableIdentity] = layout
            orderedIdentities.append(layout.stableIdentity)
        }

        let retainedIdentities = Set(currentOrderedIdentities)
        let changedRetainedIdentities = LayoutResultVariantDiff.changedStableIdentities(
            previous: previousLayoutsByIdentity,
            next: positionedLayouts
        ).filter(retainedIdentities.contains)
        let hasRetainedSizeChange = changedRetainedIdentities.contains { identity in
            guard let previous = previousLayoutsByIdentity[identity],
                  let next = layoutsByIdentity[identity] else {
                return false
            }
            return previous.size != next.size
        }

        self.layoutsByIdentity = layoutsByIdentity
        self.orderedIdentities = orderedIdentities
        self.changedRetainedIdentities = changedRetainedIdentities
        self.hasRetainedSizeChange = hasRetainedSizeChange
        self.requiresSnapshotApplication = !hasMainSection
            || currentOrderedIdentities != orderedIdentities
            || !changedRetainedIdentities.isEmpty
    }
}
