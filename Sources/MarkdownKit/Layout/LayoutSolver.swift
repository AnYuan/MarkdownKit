//
//  LayoutSolver.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A solver that traverses a structured `MarkdownNode` tree and calculates
/// exact visual styling and bounding frames for each element.
///
/// - Important: Must only be executed on a background queue.
public final class LayoutSolver: @unchecked Sendable {
    
    private let textCalculator: TextKitCalculator
    private let arithmeticCalculator: ArithmeticTextCalculator
    private let cache: LayoutCache
    private let builder: AttributedStringBuilder
    private let cacheVariantHash: Int
    private let syncCacheVariantHash: Int
    /// The explicit appearance this solver was initialised with. Stored so that
    /// every `LayoutResult` it creates carries the correct appearance value.
    private let appearance: MarkdownAppearance
    
    public init(
        theme: Theme = .default,
        cache: LayoutCache = LayoutCache(),
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        mathAdapter: (any MathRenderingAdapter)? = nil,
        imageLoadingPolicy: ImageLoadingPolicy = .default,
        appearance: MarkdownAppearance = .light
    ) {
        self.textCalculator = TextKitCalculator()
        self.arithmeticCalculator = ArithmeticTextCalculator()
        self.cache = cache
        self.appearance = appearance
        // Resolve every appearance-sensitive color in the theme once, up front.
        // Downstream builders and the highlighter receive only concrete colors so
        // no ambient UITraitCollection / NSAppearance state is read during layout.
        let resolvedTheme = theme.resolved(for: appearance)
        let resolvedMathAdapter = mathAdapter ?? DefaultMathRenderingAdapter()
        let cacheVariantHash = Self.makeCacheVariantHash(
            theme: resolvedTheme,
            diagramRegistry: diagramRegistry,
            mathAdapter: resolvedMathAdapter,
            imageLoadingPolicy: imageLoadingPolicy,
            appearance: appearance
        )
        self.cacheVariantHash = cacheVariantHash
        var syncHasher = Hasher()
        syncHasher.combine(cacheVariantHash)
        syncHasher.combine("synchronous-layout")
        self.syncCacheVariantHash = syncHasher.finalize()
        let highlighter = SplashHighlighter(theme: resolvedTheme)
        self.builder = AttributedStringBuilder(
            theme: resolvedTheme,
            highlighter: highlighter,
            diagramRegistry: diagramRegistry,
            mathAdapter: resolvedMathAdapter,
            imageLoadingPolicy: imageLoadingPolicy
        )
    }
    
    private static func makeCacheVariantHash(
        theme: Theme,
        diagramRegistry: DiagramAdapterRegistry,
        mathAdapter: any MathRenderingAdapter,
        imageLoadingPolicy: ImageLoadingPolicy,
        appearance: MarkdownAppearance
    ) -> Int {
        // `appearance` is included explicitly so a dark-appearance solver never
        // reuses entries produced by a light-appearance solver, even when the
        // resolved theme colors happen to be identical (e.g. static color themes).
        var hasher = Hasher()
        theme.cacheFingerprint(into: &hasher)
        diagramRegistry.cacheFingerprint(into: &hasher)
        mathAdapter.cacheFingerprint(into: &hasher)
        imageLoadingPolicy.cacheFingerprint(into: &hasher)
        hasher.combine(appearance)
        return hasher.finalize()
    }

    /// Combines the node's content fingerprint with the solver's cache-variant
    /// hash to produce a rendering fingerprint for use in `LayoutResult`.
    private func makeRenderFingerprint(for node: MarkdownNode, variantHash: Int) -> Int {
        var hasher = Hasher()
        hasher.combine(node.contentFingerprint)
        hasher.combine(variantHash)
        return hasher.finalize()
    }

    /// Recursively calculates the layout for a node and all its children.
    ///
    /// - Parameters:
    ///   - node: The root AST node.
    ///   - maxWidth: The maximum layout boundaries (e.g. view width).
    /// - Returns: A fully calculated `LayoutResult` tree holding sizes and attributed strings.
    public func solve(node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) async -> LayoutResult {
        // Yield to the system to keep scroll rendering incredibly smooth for giant files
        // This is the cooperative multitasking layer
        await Task.yield()

        // Return instantly if we already calculated this specific layout at this width
        if let cached = cache.getLayout(for: node, constrainedToWidth: maxWidth, variantHash: cacheVariantHash) {
            return cached
        }

        #if canImport(UIKit) && !os(watchOS)
        // Card-style table rendering on iOS: bypass TextKit, draw directly via CGContext
        if let table = node as? TableNode {
            let result = solveTableCard(
                table: table,
                constrainedToWidth: maxWidth,
                variantHash: cacheVariantHash
            )
            if !Task.isCancelled {
                cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: cacheVariantHash)
            }
            return result
        }

        // Thematic break: draw a hairline matching legacy DividerAttachment
        if node is ThematicBreakNode {
            let result = solveThematicBreak(
                node: node,
                constrainedToWidth: maxWidth,
                variantHash: cacheVariantHash
            )
            if !Task.isCancelled {
                cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: cacheVariantHash)
            }
            return result
        }
        #endif


        // 1. Convert AST to styled NSAttributedString based on Theme
        let rawString: NSAttributedString
        var size: CGSize

        // Special handling for nodes that have internal padding in their UI representation
        if let code = node as? CodeBlockNode {
            rawString = builder.buildCodeBlockAttributedString(from: code)

            // TextKit needs to know that we inset the container 8pts horizontally by the UI view
            // to accurately wrap the string if it's too long.
            let totalInset = builder.theme.codeBlock.layoutTotalInset
            let insets = CGSize(width: totalInset, height: totalInset)
            size = textCalculator.calculateSize(
                for: rawString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height

        } else if let diagram = node as? DiagramNode {
            rawString = await builder.buildDiagramAttributedString(from: diagram)

            let totalInset = builder.theme.codeBlock.layoutTotalInset
            let insets = CGSize(width: totalInset, height: totalInset)
            size = textCalculator.calculateSize(
                for: rawString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height

        } else {
            rawString = await builder.buildString(for: node, constrainedToWidth: maxWidth)
            
            if shouldUseArithmeticLayout(for: node, styledString: rawString) {
                size = arithmeticCalculator.calculateSize(for: rawString, constrainedToWidth: maxWidth)
            } else {
                size = textCalculator.calculateSize(for: rawString, constrainedToWidth: maxWidth)
            }
        }

        // Resolve any remaining dynamic colors (e.g. platform secondary-label
        // used for code-block language labels, or colors from math/diagram adapters)
        // to concrete values for the explicit appearance.
        let styledString = AppearanceColorResolver.resolveColors(in: rawString, for: appearance)

        // 3. Recurse down children (if they represent separate visual block elements)
        // For basic implementation, we assume paragraphs/headers handle their own inline children.
        // But for Documents, we must layout all top-level blocks.
        var childLayouts: [LayoutResult] = []

        if let doc = node as? DocumentNode {
            for (index, child) in doc.children.enumerated() {
                let childResult = await solve(node: child, constrainedToWidth: maxWidth)
                childLayouts.append(Self.applyTopLevelIdentity(childResult, index: index))
            }
        }

        // strictly immutable frame container
        let result = LayoutResult(
            node: node,
            size: size,
            attributedString: styledString,
            children: childLayouts,
            appearance: appearance,
            renderFingerprint: makeRenderFingerprint(for: node, variantHash: cacheVariantHash)
        )

        // Memoize the result
        if !Task.isCancelled {
            cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: cacheVariantHash)
        }

        return result
    }

    /// Synchronous variant of `solve` that avoids Swift concurrency entirely.
    /// Uses `buildStringSync` (cached math / fallback text, no async rendering).
    /// Safe to call from the main thread without RunLoop polling.
    public func solveSync(node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) -> LayoutResult {
        if let cached = cache.getLayout(
            for: node,
            constrainedToWidth: maxWidth,
            variantHash: syncCacheVariantHash
        ) {
            return cached
        }

        #if canImport(UIKit) && !os(watchOS)
        if let table = node as? TableNode {
            let result = solveTableCard(
                table: table,
                constrainedToWidth: maxWidth,
                variantHash: syncCacheVariantHash
            )
            cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: syncCacheVariantHash)
            return result
        }

        if node is ThematicBreakNode {
            let result = solveThematicBreak(
                node: node,
                constrainedToWidth: maxWidth,
                variantHash: syncCacheVariantHash
            )
            cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: syncCacheVariantHash)
            return result
        }
        #endif

        let rawString: NSAttributedString
        var size: CGSize

        if let code = node as? CodeBlockNode {
            rawString = builder.buildCodeBlockAttributedString(from: code)
            let totalInset = builder.theme.codeBlock.layoutTotalInset
            let insets = CGSize(width: totalInset, height: totalInset)
            size = textCalculator.calculateSize(
                for: rawString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height
        } else {
            rawString = builder.buildStringSync(for: node, constrainedToWidth: maxWidth)
            
            if shouldUseArithmeticLayout(for: node, styledString: rawString) {
                size = arithmeticCalculator.calculateSize(for: rawString, constrainedToWidth: maxWidth)
            } else {
                size = textCalculator.calculateSize(for: rawString, constrainedToWidth: maxWidth)
            }
        }

        let styledString = AppearanceColorResolver.resolveColors(in: rawString, for: appearance)

        var childLayouts: [LayoutResult] = []
        if let doc = node as? DocumentNode {
            for (index, child) in doc.children.enumerated() {
                let childResult = solveSync(node: child, constrainedToWidth: maxWidth)
                childLayouts.append(Self.applyTopLevelIdentity(childResult, index: index))
            }
        }

        let result = LayoutResult(
            node: node,
            size: size,
            attributedString: styledString,
            children: childLayouts,
            appearance: appearance,
            renderFingerprint: makeRenderFingerprint(for: node, variantHash: syncCacheVariantHash)
        )
        cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: syncCacheVariantHash)
        return result
    }

    /// Stamps a top-level document-position identity onto the layout. Used by
    /// both `solve` and `solveSync` so the returned `LayoutResult` carries the
    /// `(contentFingerprint, pathHash)` pair the diffable data source needs.
    /// Cache returns are also re-stamped: a cached entry for a paragraph
    /// previously at index 0 must be re-identified when it appears at index 5.
    private static func applyTopLevelIdentity(_ layout: LayoutResult, index: Int) -> LayoutResult {
        let identity = StableNodeIdentity(
            contentFingerprint: layout.node.contentFingerprint,
            pathHash: StableNodeIdentity.pathHash(for: [index])
        )
        return layout.withStableIdentity(identity)
    }

    // MARK: - Thematic Break Layout (iOS only)

    #if canImport(UIKit) && !os(watchOS)
    private func solveThematicBreak(
        node: MarkdownNode,
        constrainedToWidth maxWidth: CGFloat,
        variantHash: Int
    ) -> LayoutResult {
        let paddingTop = builder.theme.thematicBreak.paddingTop
        let paddingBottom = builder.theme.thematicBreak.paddingBottom
        let dividerHeight = builder.theme.thematicBreak.dividerHeight
        let totalHeight = paddingTop + dividerHeight + paddingBottom
        let totalSize = CGSize(width: maxWidth, height: totalHeight)

        // The theme was resolved for the explicit appearance in init, so .cgColor
        // is already a concrete value — no ambient trait collection is read here.
        let resolvedColor = builder.theme.colors.thematicBreakColor.foreground.cgColor

        let customDraw: @Sendable (CGContext, CGSize) -> Void = { context, size in
            context.saveGState()
            // Actual hairline
            context.setFillColor(resolvedColor)
            context.fill(CGRect(x: 0, y: paddingTop, width: size.width, height: dividerHeight))
            context.restoreGState()
        }

        return LayoutResult(
            node: node,
            size: totalSize,
            attributedString: nil,
            children: [],
            customDraw: customDraw,
            appearance: appearance,
            renderFingerprint: makeRenderFingerprint(for: node, variantHash: variantHash)
        )
    }
    #endif

    // MARK: - Table Card Layout (iOS only)

    #if canImport(UIKit) && !os(watchOS)
    /// Produces a `LayoutResult` for a table node that uses CGContext card rendering
    /// instead of TextKit. The `customDraw` closure captures the pre-computed layout
    /// and resolved colors so that rasterization is fully thread-safe.
    private func solveTableCard(
        table: TableNode,
        constrainedToWidth maxWidth: CGFloat,
        variantHash: Int
    ) -> LayoutResult {
        let layout = TableCardRenderer.computeLayout(
            from: table,
            theme: builder.theme,
            constrainedToWidth: maxWidth
        )

        // The theme stored in `builder` was resolved for the explicit appearance in init,
        // so every color token already contains concrete RGB values — no ambient trait
        // collection is read here.
        let resolvedColors = TableCardRenderer.ResolvedColors.resolve(from: builder.theme)

        let customDraw: @Sendable (CGContext, CGSize) -> Void = { context, size in
            TableCardRenderer.draw(
                layout: layout,
                resolvedColors: resolvedColors,
                in: context,
                size: size
            )
        }

        return LayoutResult(
            node: table,
            size: layout.totalSize,
            attributedString: nil,
            children: [],
            customDraw: customDraw,
            appearance: appearance,
            renderFingerprint: makeRenderFingerprint(for: table, variantHash: variantHash)
        )
    }
    #endif

    // MARK: - Routing Helpers

    /// Determines if a node is a simple text block that can be safely routed
    /// to the lock-free `ArithmeticTextCalculator`.
    private func shouldUseArithmeticLayout(for node: MarkdownNode, styledString: NSAttributedString) -> Bool {
        isPureTextBlock(node) && arithmeticCalculator.profile(for: styledString).supportsArithmeticLayout
    }

    private func isPureTextBlock(_ node: MarkdownNode) -> Bool {
        // Only route paragraph and header nodes for now
        guard node is ParagraphNode || node is HeaderNode else {
            return false
        }
        
        var hasAttachments = false
        
        func traverse(_ n: MarkdownNode) {
            if hasAttachments { return }
            
            // If we find any of these, we must use TextKit for accurate layout
            if n is ImageNode || 
               n is MathNode || 
               n is DiagramNode || 
               n is TableNode || 
               n is CodeBlockNode ||
               n is DetailsNode {
                hasAttachments = true
                return
            }
            
            for child in n.children {
                traverse(child)
            }
        }
        
        traverse(node)
        return !hasAttachments
    }
}
