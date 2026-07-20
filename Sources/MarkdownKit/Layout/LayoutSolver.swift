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

    private enum ImmediateLayoutRecipe {
        #if canImport(UIKit) && !os(watchOS)
        case table(TableNode)
        case thematicBreak
        #endif
        case codeBlock(CodeBlockNode)
    }

    private enum ShallowLayoutRecipe {
        case immediate(ImmediateLayoutRecipe)
        case diagram(DiagramNode)
        case attributed(MarkdownNode)
    }

    private enum TextMeasurement {
        case standard
        case codeBlockInset
    }

    private struct ShallowLayoutOutput {
        let size: CGSize
        let attributedString: NSAttributedString?
        let customDraw: (@Sendable (CGContext, CGSize) -> Void)?

        init(
            size: CGSize,
            attributedString: NSAttributedString? = nil,
            customDraw: (@Sendable (CGContext, CGSize) -> Void)? = nil
        ) {
            self.size = size
            self.attributedString = attributedString
            self.customDraw = customDraw
        }
    }

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
            imageLoadingPolicy: imageLoadingPolicy,
            appearance: appearance
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
        await Task<Never, Never>.yield()
        var cooperation = LayoutCooperationState()
        return await solveTotal(
            node: node,
            constrainedToWidth: maxWidth,
            cooperation: &cooperation
        )
    }

    private func solveTotal(
        node: MarkdownNode,
        constrainedToWidth maxWidth: CGFloat,
        cooperation: inout LayoutCooperationState
    ) async -> LayoutResult {
        if cooperation.shouldYield(after: .solver) {
            await Task<Never, Never>.yield()
        }

        // Return instantly if we already calculated this specific layout at this width
        if let cached = cache.getLayout(for: node, constrainedToWidth: maxWidth, variantHash: cacheVariantHash) {
            return cached
        }

        let recipe = makeRecipe(for: node)
        let output = await executeAsync(
            recipe,
            constrainedToWidth: maxWidth
        )

        // 3. Recurse down children (if they represent separate visual block elements)
        // For basic implementation, we assume paragraphs/headers handle their own inline children.
        // But for Documents, we must layout all top-level blocks.
        var childLayouts: [LayoutResult] = []

        if let doc = node as? DocumentNode {
            for (index, child) in doc.children.enumerated() {
                let childResult = await solveTotal(
                    node: child,
                    constrainedToWidth: maxWidth,
                    cooperation: &cooperation
                )
                childLayouts.append(childResult.positionedAtTopLevel(index: index))
            }
        }

        let result = makeLayoutResult(
            node: node,
            output: output,
            children: childLayouts,
            variantHash: cacheVariantHash
        )

        // Memoize the result
        if !Task.isCancelled {
            cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: cacheVariantHash)
        }

        return result
    }

    func solveCancellable(
        node: MarkdownNode,
        constrainedToWidth maxWidth: CGFloat
    ) async -> LayoutResult? {
        var cooperation = LayoutCooperationState()
        var writeBatch = cache.makeWriteBatch()

        guard let result = await solveCancellable(
            node: node,
            constrainedToWidth: maxWidth,
            cooperation: &cooperation,
            writeBatch: &writeBatch
        ) else {
            return nil
        }

        guard !Task.isCancelled else { return nil }
        writeBatch.commit()
        return result
    }

    private func solveCancellable(
        node: MarkdownNode,
        constrainedToWidth maxWidth: CGFloat,
        cooperation: inout LayoutCooperationState,
        writeBatch: inout LayoutCache.WriteBatch
    ) async -> LayoutResult? {
        guard !Task.isCancelled else { return nil }
        if cooperation.shouldYield(after: .solver) {
            await Task<Never, Never>.yield()
            guard !Task.isCancelled else { return nil }
        }

        if let cached = writeBatch.getLayout(
            for: node,
            constrainedToWidth: maxWidth,
            variantHash: cacheVariantHash
        ) {
            guard !Task.isCancelled else { return nil }
            return cached
        }

        let recipe = makeRecipe(for: node)
        guard let output = await executeCancellable(
            recipe,
            constrainedToWidth: maxWidth,
            cooperation: &cooperation
        ) else {
            return nil
        }

        var childLayouts: [LayoutResult] = []
        if let doc = node as? DocumentNode {
            childLayouts.reserveCapacity(doc.children.count)
            for (index, child) in doc.children.enumerated() {
                guard let childResult = await solveCancellable(
                    node: child,
                    constrainedToWidth: maxWidth,
                    cooperation: &cooperation,
                    writeBatch: &writeBatch
                ) else {
                    return nil
                }
                guard !Task.isCancelled else { return nil }
                childLayouts.append(childResult.positionedAtTopLevel(index: index))
            }
        }

        guard !Task.isCancelled else { return nil }
        let result = makeLayoutResult(
            node: node,
            output: output,
            children: childLayouts,
            variantHash: cacheVariantHash
        )
        guard !Task.isCancelled else { return nil }
        writeBatch.stage(
            result,
            constrainedToWidth: maxWidth,
            variantHash: cacheVariantHash
        )
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

        let recipe = makeRecipe(for: node)
        let output = executeSync(
            recipe,
            constrainedToWidth: maxWidth
        )

        var childLayouts: [LayoutResult] = []
        if let doc = node as? DocumentNode {
            for (index, child) in doc.children.enumerated() {
                let childResult = solveSync(node: child, constrainedToWidth: maxWidth)
                childLayouts.append(childResult.positionedAtTopLevel(index: index))
            }
        }

        let result = makeLayoutResult(
            node: node,
            output: output,
            children: childLayouts,
            variantHash: syncCacheVariantHash
        )
        cache.setLayout(result, constrainedToWidth: maxWidth, variantHash: syncCacheVariantHash)
        return result
    }

    private func makeRecipe(for node: MarkdownNode) -> ShallowLayoutRecipe {
        #if canImport(UIKit) && !os(watchOS)
        if let table = node as? TableNode {
            return .immediate(.table(table))
        }
        if node is ThematicBreakNode {
            return .immediate(.thematicBreak)
        }
        #endif
        if let codeBlock = node as? CodeBlockNode {
            return .immediate(.codeBlock(codeBlock))
        }
        if let diagram = node as? DiagramNode {
            return .diagram(diagram)
        }
        return .attributed(node)
    }

    private func executeAsync(
        _ recipe: ShallowLayoutRecipe,
        constrainedToWidth maxWidth: CGFloat
    ) async -> ShallowLayoutOutput {
        switch recipe {
        case let .immediate(immediate):
            return executeImmediate(immediate, constrainedToWidth: maxWidth)
        case let .diagram(diagram):
            return makeTextOutput(
                attributedString: await builder.buildDiagramAttributedString(from: diagram),
                node: diagram,
                constrainedToWidth: maxWidth,
                measurement: .codeBlockInset
            )
        case let .attributed(node):
            return makeTextOutput(
                attributedString: await builder.buildString(for: node, constrainedToWidth: maxWidth),
                node: node,
                constrainedToWidth: maxWidth,
                measurement: .standard
            )
        }
    }

    private func executeCancellable(
        _ recipe: ShallowLayoutRecipe,
        constrainedToWidth maxWidth: CGFloat,
        cooperation: inout LayoutCooperationState
    ) async -> ShallowLayoutOutput? {
        guard !Task.isCancelled else { return nil }

        switch recipe {
        case let .immediate(immediate):
            return executeImmediateCancellable(
                immediate,
                constrainedToWidth: maxWidth
            )

        case let .diagram(diagram):
            guard let attributedString = await builder.buildDiagramAttributedStringCancellable(
                from: diagram
            ) else {
                return nil
            }
            guard !Task.isCancelled else { return nil }
            return makeTextOutputCancellable(
                attributedString: attributedString,
                node: diagram,
                constrainedToWidth: maxWidth,
                measurement: .codeBlockInset
            )

        case let .attributed(node):
            guard let attributedString = await builder.buildStringCancellable(
                for: node,
                constrainedToWidth: maxWidth,
                cooperation: &cooperation
            ) else {
                return nil
            }
            guard !Task.isCancelled else { return nil }
            return makeTextOutputCancellable(
                attributedString: attributedString,
                node: node,
                constrainedToWidth: maxWidth,
                measurement: .standard
            )
        }
    }

    private func executeSync(
        _ recipe: ShallowLayoutRecipe,
        constrainedToWidth maxWidth: CGFloat
    ) -> ShallowLayoutOutput {
        switch recipe {
        case let .immediate(immediate):
            return executeImmediate(immediate, constrainedToWidth: maxWidth)
        case let .diagram(diagram):
            return makeTextOutput(
                attributedString: builder.buildStringSync(for: diagram, constrainedToWidth: maxWidth),
                node: diagram,
                constrainedToWidth: maxWidth,
                measurement: .standard
            )
        case let .attributed(node):
            return makeTextOutput(
                attributedString: builder.buildStringSync(for: node, constrainedToWidth: maxWidth),
                node: node,
                constrainedToWidth: maxWidth,
                measurement: .standard
            )
        }
    }

    private func executeImmediate(
        _ recipe: ImmediateLayoutRecipe,
        constrainedToWidth maxWidth: CGFloat
    ) -> ShallowLayoutOutput {
        switch recipe {
        #if canImport(UIKit) && !os(watchOS)
        case let .table(table):
            return makeTableCardOutput(table: table, constrainedToWidth: maxWidth)
        case .thematicBreak:
            return makeThematicBreakOutput(constrainedToWidth: maxWidth)
        #endif
        case let .codeBlock(codeBlock):
            return makeTextOutput(
                attributedString: builder.buildCodeBlockAttributedString(from: codeBlock),
                node: codeBlock,
                constrainedToWidth: maxWidth,
                measurement: .codeBlockInset
            )
        }
    }

    private func executeImmediateCancellable(
        _ recipe: ImmediateLayoutRecipe,
        constrainedToWidth maxWidth: CGFloat
    ) -> ShallowLayoutOutput? {
        guard !Task.isCancelled else { return nil }

        switch recipe {
        #if canImport(UIKit) && !os(watchOS)
        case let .table(table):
            let output = makeTableCardOutput(
                table: table,
                constrainedToWidth: maxWidth
            )
            guard !Task.isCancelled else { return nil }
            return output

        case .thematicBreak:
            let output = makeThematicBreakOutput(constrainedToWidth: maxWidth)
            guard !Task.isCancelled else { return nil }
            return output
        #endif

        case let .codeBlock(codeBlock):
            let attributedString = builder.buildCodeBlockAttributedString(from: codeBlock)
            guard !Task.isCancelled else { return nil }
            return makeTextOutputCancellable(
                attributedString: attributedString,
                node: codeBlock,
                constrainedToWidth: maxWidth,
                measurement: .codeBlockInset
            )
        }
    }

    private func makeTextOutput(
        attributedString: NSAttributedString,
        node: MarkdownNode,
        constrainedToWidth maxWidth: CGFloat,
        measurement: TextMeasurement
    ) -> ShallowLayoutOutput {
        let size: CGSize
        switch measurement {
        case .standard:
            if shouldUseArithmeticLayout(for: node, styledString: attributedString) {
                size = arithmeticCalculator.calculateSize(
                    for: attributedString,
                    constrainedToWidth: maxWidth
                )
            } else {
                size = textCalculator.calculateSize(
                    for: attributedString,
                    constrainedToWidth: maxWidth
                )
            }
        case .codeBlockInset:
            let totalInset = builder.theme.codeBlock.layoutTotalInset
            var measuredSize = textCalculator.calculateSize(
                for: attributedString,
                constrainedToWidth: max(0, maxWidth - totalInset)
            )
            measuredSize.width += totalInset
            measuredSize.height += totalInset
            size = measuredSize
        }

        return ShallowLayoutOutput(size: size, attributedString: attributedString)
    }

    private func makeTextOutputCancellable(
        attributedString: NSAttributedString,
        node: MarkdownNode,
        constrainedToWidth maxWidth: CGFloat,
        measurement: TextMeasurement
    ) -> ShallowLayoutOutput? {
        guard !Task.isCancelled else { return nil }
        let output = makeTextOutput(
            attributedString: attributedString,
            node: node,
            constrainedToWidth: maxWidth,
            measurement: measurement
        )
        guard !Task.isCancelled else { return nil }
        return output
    }

    private func makeLayoutResult(
        node: MarkdownNode,
        output: ShallowLayoutOutput,
        children: [LayoutResult],
        variantHash: Int
    ) -> LayoutResult {
        LayoutResult(
            node: node,
            size: output.size,
            attributedString: output.attributedString,
            children: children,
            customDraw: output.customDraw,
            appearance: appearance,
            renderFingerprint: makeRenderFingerprint(for: node, variantHash: variantHash)
        )
    }

    // MARK: - Thematic Break Layout (iOS only)

    #if canImport(UIKit) && !os(watchOS)
    private func makeThematicBreakOutput(
        constrainedToWidth maxWidth: CGFloat
    ) -> ShallowLayoutOutput {
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

        return ShallowLayoutOutput(
            size: totalSize,
            customDraw: customDraw
        )
    }
    #endif

    // MARK: - Table Card Layout (iOS only)

    #if canImport(UIKit) && !os(watchOS)
    /// Produces shallow table output using CGContext card rendering instead of TextKit.
    /// The closure captures pre-computed layout and resolved colors for thread safety.
    private func makeTableCardOutput(
        table: TableNode,
        constrainedToWidth maxWidth: CGFloat
    ) -> ShallowLayoutOutput {
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

        return ShallowLayoutOutput(
            size: layout.totalSize,
            customDraw: customDraw
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
