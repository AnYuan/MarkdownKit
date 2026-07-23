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
    private let preparedCache: PreparedContentCache

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

    private struct InitializationComponents {
        let cacheVariantHash: Int
        let syncCacheVariantHash: Int
        let builder: AttributedStringBuilder
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
        self.preparedCache = PreparedContentCache()
        let components = Self.makeInitializationComponents(
            theme: theme,
            diagramRegistry: diagramRegistry,
            mathAdapter: mathAdapter,
            imageLoadingPolicy: imageLoadingPolicy,
            appearance: appearance
        )
        self.cacheVariantHash = components.cacheVariantHash
        self.syncCacheVariantHash = components.syncCacheVariantHash
        self.builder = components.builder
    }

    init(
        theme: Theme = .default,
        cache: LayoutCache = LayoutCache(),
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        mathAdapter: (any MathRenderingAdapter)? = nil,
        imageLoadingPolicy: ImageLoadingPolicy = .default,
        appearance: MarkdownAppearance = .light,
        preparedCache: PreparedContentCache
    ) {
        self.textCalculator = TextKitCalculator()
        self.arithmeticCalculator = ArithmeticTextCalculator()
        self.cache = cache
        self.appearance = appearance
        self.preparedCache = preparedCache
        let components = Self.makeInitializationComponents(
            theme: theme,
            diagramRegistry: diagramRegistry,
            mathAdapter: mathAdapter,
            imageLoadingPolicy: imageLoadingPolicy,
            appearance: appearance
        )
        self.cacheVariantHash = components.cacheVariantHash
        self.syncCacheVariantHash = components.syncCacheVariantHash
        self.builder = components.builder
    }

    private static func makeInitializationComponents(
        theme: Theme,
        diagramRegistry: DiagramAdapterRegistry,
        mathAdapter: (any MathRenderingAdapter)?,
        imageLoadingPolicy: ImageLoadingPolicy,
        appearance: MarkdownAppearance
    ) -> InitializationComponents {
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
        var syncHasher = Hasher()
        syncHasher.combine(cacheVariantHash)
        syncHasher.combine("synchronous-layout")
        let highlighter = SplashHighlighter(theme: resolvedTheme)
        return InitializationComponents(
            cacheVariantHash: cacheVariantHash,
            syncCacheVariantHash: syncHasher.finalize(),
            builder: AttributedStringBuilder(
                theme: resolvedTheme,
                highlighter: highlighter,
                diagramRegistry: diagramRegistry,
                mathAdapter: resolvedMathAdapter,
                imageLoadingPolicy: imageLoadingPolicy,
                appearance: appearance
            )
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

    // MARK: - PreparedContentCache helpers

    /// Returns true for node types whose attributed output is width-independent enough
    /// to be a prepared-cache candidate root. Does NOT scan descendants.
    private func isOrdinaryEligibleRoot(_ node: MarkdownNode) -> Bool {
        return node is ParagraphNode || node is HeaderNode || node is TextNode ||
               node is ListNode || node is BlockQuoteNode ||
               node is DetailsNode || node is SummaryNode
    }

    private struct PreparedNodeClassification {
        let isCacheEligible: Bool
        let supportsArithmeticLayout: Bool
    }

    private func appendPreparedClassificationChildren(
        of node: MarkdownNode,
        to work: inout [MarkdownNode]
    ) {
        if let summary = (node as? DetailsNode)?.summary {
            work.append(summary)
        }
        work.append(contentsOf: node.children)
    }

    /// Classifies a prepared-cache miss. Resource-bearing subtrees remain
    /// uncached, while code/details descendants only disable arithmetic routing
    /// because their attributed output is still width-free.
    private func classifyPreparedNode(
        _ node: MarkdownNode,
        structuralArithmeticSupport: Bool? = nil
    ) -> PreparedNodeClassification {
        var supportsArithmeticLayout = structuralArithmeticSupport
            ?? Self.supportsArithmeticLayoutStructure(node)
        var work: [MarkdownNode] = []
        appendPreparedClassificationChildren(of: node, to: &work)

        while let current = work.popLast() {
            if current is TableNode ||
                current is ImageNode ||
                current is MathNode ||
                current is DiagramNode {
                return PreparedNodeClassification(
                    isCacheEligible: false,
                    supportsArithmeticLayout: false
                )
            }
            if current is CodeBlockNode ||
                current is DetailsNode ||
                current is ThematicBreakNode {
                supportsArithmeticLayout = false
            }
            if supportsArithmeticLayout,
               !Self.isModeledArithmeticDescendant(current) {
                supportsArithmeticLayout = false
            }
            appendPreparedClassificationChildren(of: current, to: &work)
        }

        return PreparedNodeClassification(
            isCacheEligible: true,
            supportsArithmeticLayout: supportsArithmeticLayout
        )
    }

    /// Builds a frozen `PreparedContentCache.Payload` for an ordinary eligible node.
    /// Selects `.arithmetic` only when `isPureTextBlock` and the profile agree.
    private func makePreparedPayload(
        attributedString: NSAttributedString,
        supportsArithmeticLayout: Bool
    ) -> PreparedContentCache.Payload {
        if supportsArithmeticLayout {
            let profile = arithmeticCalculator.profile(for: attributedString)
            if profile.supportsArithmeticLayout {
                let prepared = arithmeticCalculator.prepare(attributedString: attributedString)
                return PreparedContentCache.Payload(
                    attributedString: attributedString,
                    measurementPlan: .arithmetic(prepared)
                )
            }
        }
        return PreparedContentCache.Payload(attributedString: attributedString, measurementPlan: .textKit)
    }

    /// Shared code-block inset sizing. One source of truth for both cached and uncached paths.
    private func codeBlockInsetSize(
        for attributedString: NSAttributedString,
        constrainedToWidth maxWidth: CGFloat
    ) -> CGSize {
        let totalInset = builder.theme.codeBlock.layoutTotalInset
        var size = textCalculator.calculateSize(
            for: attributedString,
            constrainedToWidth: max(0, maxWidth - totalInset)
        )
        size.width += totalInset
        size.height += totalInset
        return size
    }

    /// Resolves a width-independent arithmetic plan at one concrete width. A
    /// wrapped line whose visible glyphs all came from fallback fonts is routed
    /// through TextKit because AppKit's line-box metrics for that shape depend on
    /// process-global fallback state.
    private func sizeFromArithmeticPlan(
        _ prepared: ArithmeticTextCalculator.PreparedText,
        attributedString: NSAttributedString,
        constrainedToWidth maxWidth: CGFloat
    ) -> CGSize {
        let outcome = arithmeticCalculator.layoutOutcome(
            prepared: prepared,
            constrainedToWidth: maxWidth,
            stopWhenTextKitFallbackIsRequired: true
        )
        precondition(!outcome.wasCancelled)
        if outcome.requiresTextKitFallback {
            return textCalculator.calculateSize(
                for: attributedString,
                constrainedToWidth: maxWidth
            )
        }
        return outcome.size
    }

    /// Cancellable counterpart used only by the coordinator path. Ordinary
    /// async and synchronous solves remain total even when their enclosing Task
    /// is cancelled; only `solveCancellable` may abandon partial geometry.
    private func sizeFromArithmeticPlanCancellable(
        _ prepared: ArithmeticTextCalculator.PreparedText,
        attributedString: NSAttributedString,
        constrainedToWidth maxWidth: CGFloat
    ) -> CGSize? {
        let outcome = arithmeticCalculator.layoutOutcome(
            prepared: prepared,
            constrainedToWidth: maxWidth,
            stopWhenTextKitFallbackIsRequired: true,
            shouldCancel: { Task<Never, Never>.isCancelled }
        )
        guard !outcome.wasCancelled, !Task.isCancelled else { return nil }
        if outcome.requiresTextKitFallback {
            let size = textCalculator.calculateSize(
                for: attributedString,
                constrainedToWidth: maxWidth
            )
            guard !Task.isCancelled else { return nil }
            return size
        }
        return outcome.size
    }

    /// Computes the size from a cached payload without re-running the builder,
    /// profile, or ArithmeticTextCalculator.prepare.
    private func sizeFromPreparedPayload(
        _ payload: PreparedContentCache.Payload,
        constrainedToWidth maxWidth: CGFloat
    ) -> CGSize {
        switch payload.measurementPlan {
        case .arithmetic(let prepared):
            return sizeFromArithmeticPlan(
                prepared,
                attributedString: payload.attributedString,
                constrainedToWidth: maxWidth
            )
        case .textKit:
            return textCalculator.calculateSize(for: payload.attributedString, constrainedToWidth: maxWidth)
        case .codeBlockInset:
            return codeBlockInsetSize(for: payload.attributedString, constrainedToWidth: maxWidth)
        }
    }

    /// Returns a `ShallowLayoutOutput` sized from a prepared payload, reusing its
    /// frozen attributed string. Skips all builder and measurement-plan work.
    private func outputFromPreparedPayload(
        _ payload: PreparedContentCache.Payload,
        constrainedToWidth maxWidth: CGFloat
    ) -> ShallowLayoutOutput {
        ShallowLayoutOutput(
            size: sizeFromPreparedPayload(payload, constrainedToWidth: maxWidth),
            attributedString: payload.attributedString
        )
    }

    private func outputFromPreparedPayloadCancellable(
        _ payload: PreparedContentCache.Payload,
        constrainedToWidth maxWidth: CGFloat
    ) -> ShallowLayoutOutput? {
        guard !Task.isCancelled else { return nil }
        let size: CGSize
        switch payload.measurementPlan {
        case .arithmetic(let prepared):
            guard let arithmeticSize = sizeFromArithmeticPlanCancellable(
                prepared,
                attributedString: payload.attributedString,
                constrainedToWidth: maxWidth
            ) else {
                return nil
            }
            size = arithmeticSize
        case .textKit:
            size = textCalculator.calculateSize(
                for: payload.attributedString,
                constrainedToWidth: maxWidth
            )
        case .codeBlockInset:
            size = codeBlockInsetSize(
                for: payload.attributedString,
                constrainedToWidth: maxWidth
            )
        }
        guard !Task.isCancelled else { return nil }
        return ShallowLayoutOutput(
            size: size,
            attributedString: payload.attributedString
        )
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
        var preparedBatch = preparedCache.makeWriteBatch()

        guard let result = await solveCancellable(
            node: node,
            constrainedToWidth: maxWidth,
            cooperation: &cooperation,
            writeBatch: &writeBatch,
            preparedBatch: &preparedBatch
        ) else {
            return nil
        }

        guard !Task.isCancelled else { return nil }
        writeBatch.commit()
        preparedBatch.commit()
        return result
    }

    private func solveCancellable(
        node: MarkdownNode,
        constrainedToWidth maxWidth: CGFloat,
        cooperation: inout LayoutCooperationState,
        writeBatch: inout LayoutCache.WriteBatch,
        preparedBatch: inout PreparedContentCache.WriteBatch
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
            cooperation: &cooperation,
            preparedBatch: &preparedBatch
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
                    writeBatch: &writeBatch,
                    preparedBatch: &preparedBatch
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
            if case let .codeBlock(codeBlock) = immediate {
                let key = PreparedContentCache.Key(node: codeBlock, variantHash: cacheVariantHash)
                if let hit = preparedCache.get(key) {
                    return outputFromPreparedPayload(hit, constrainedToWidth: maxWidth)
                }
                let attrStr = builder.buildCodeBlockAttributedString(from: codeBlock)
                let payload = PreparedContentCache.Payload(
                    attributedString: attrStr, measurementPlan: .codeBlockInset
                )
                if !Task.isCancelled { preparedCache.set(payload, for: key) }
                return outputFromPreparedPayload(payload, constrainedToWidth: maxWidth)
            }
            return executeImmediate(immediate, constrainedToWidth: maxWidth)

        case let .diagram(diagram):
            return makeTextOutput(
                attributedString: await builder.buildDiagramAttributedString(from: diagram),
                node: diagram,
                constrainedToWidth: maxWidth,
                measurement: .codeBlockInset
            )

        case let .attributed(node):
            let isEligible = isOrdinaryEligibleRoot(node)
            let prepKey = isEligible ? PreparedContentCache.Key(node: node, variantHash: cacheVariantHash) : nil
            if let prepKey, let hit = preparedCache.get(prepKey) {
                return outputFromPreparedPayload(hit, constrainedToWidth: maxWidth)
            }
            let attrStr = await builder.buildString(for: node, constrainedToWidth: maxWidth)
            if let prepKey {
                let classification = classifyPreparedNode(node)
                if classification.isCacheEligible {
                    let payload = makePreparedPayload(
                        attributedString: attrStr,
                        supportsArithmeticLayout: classification.supportsArithmeticLayout
                    )
                    if !Task.isCancelled { preparedCache.set(payload, for: prepKey) }
                    return outputFromPreparedPayload(payload, constrainedToWidth: maxWidth)
                }
            }
            return makeTextOutput(attributedString: attrStr, node: node, constrainedToWidth: maxWidth, measurement: .standard)
        }
    }

    private func executeCancellable(
        _ recipe: ShallowLayoutRecipe,
        constrainedToWidth maxWidth: CGFloat,
        cooperation: inout LayoutCooperationState,
        preparedBatch: inout PreparedContentCache.WriteBatch
    ) async -> ShallowLayoutOutput? {
        guard !Task.isCancelled else { return nil }

        switch recipe {
        case let .immediate(immediate):
            return executeImmediateCancellable(
                immediate,
                constrainedToWidth: maxWidth,
                preparedBatch: &preparedBatch
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
            let isEligible = isOrdinaryEligibleRoot(node)
            let prepKey = isEligible ? PreparedContentCache.Key(node: node, variantHash: cacheVariantHash) : nil
            if let prepKey, let hit = preparedBatch.get(prepKey) {
                return outputFromPreparedPayloadCancellable(
                    hit,
                    constrainedToWidth: maxWidth
                )
            }
            guard let attrStr = await builder.buildStringCancellable(
                for: node,
                constrainedToWidth: maxWidth,
                cooperation: &cooperation
            ) else {
                return nil
            }
            guard !Task.isCancelled else { return nil }
            if let prepKey {
                let classification = classifyPreparedNode(node)
                if classification.isCacheEligible {
                    let payload = makePreparedPayload(
                        attributedString: attrStr,
                        supportsArithmeticLayout: classification.supportsArithmeticLayout
                    )
                    guard let output = outputFromPreparedPayloadCancellable(
                        payload,
                        constrainedToWidth: maxWidth
                    ) else {
                        return nil
                    }
                    preparedBatch.stage(payload, for: prepKey)
                    return output
                }
            }
            return makeTextOutputCancellable(
                attributedString: attrStr,
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
            if case let .codeBlock(codeBlock) = immediate {
                let key = PreparedContentCache.Key(node: codeBlock, variantHash: syncCacheVariantHash)
                if let hit = preparedCache.get(key) {
                    return outputFromPreparedPayload(hit, constrainedToWidth: maxWidth)
                }
                let attrStr = builder.buildCodeBlockAttributedString(from: codeBlock)
                let payload = PreparedContentCache.Payload(
                    attributedString: attrStr, measurementPlan: .codeBlockInset
                )
                preparedCache.set(payload, for: key)
                return outputFromPreparedPayload(payload, constrainedToWidth: maxWidth)
            }
            return executeImmediate(immediate, constrainedToWidth: maxWidth)

        case let .diagram(diagram):
            return makeTextOutput(
                attributedString: builder.buildStringSync(for: diagram, constrainedToWidth: maxWidth),
                node: diagram,
                constrainedToWidth: maxWidth,
                measurement: .standard
            )

        case let .attributed(node):
            let isEligible = isOrdinaryEligibleRoot(node)
            let prepKey = isEligible ? PreparedContentCache.Key(node: node, variantHash: syncCacheVariantHash) : nil
            if let prepKey, let hit = preparedCache.get(prepKey) {
                return outputFromPreparedPayload(hit, constrainedToWidth: maxWidth)
            }
            let attrStr = builder.buildStringSync(for: node, constrainedToWidth: maxWidth)
            if let prepKey {
                let classification = classifyPreparedNode(node)
                if classification.isCacheEligible {
                    let payload = makePreparedPayload(
                        attributedString: attrStr,
                        supportsArithmeticLayout: classification.supportsArithmeticLayout
                    )
                    preparedCache.set(payload, for: prepKey)
                    return outputFromPreparedPayload(payload, constrainedToWidth: maxWidth)
                }
            }
            return makeTextOutput(attributedString: attrStr, node: node, constrainedToWidth: maxWidth, measurement: .standard)
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
        constrainedToWidth maxWidth: CGFloat,
        preparedBatch: inout PreparedContentCache.WriteBatch
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
            let key = PreparedContentCache.Key(node: codeBlock, variantHash: cacheVariantHash)
            if let hit = preparedBatch.get(key) {
                return outputFromPreparedPayloadCancellable(
                    hit,
                    constrainedToWidth: maxWidth
                )
            }
            let attrStr = builder.buildCodeBlockAttributedString(from: codeBlock)
            guard !Task.isCancelled else { return nil }
            let payload = PreparedContentCache.Payload(
                attributedString: attrStr, measurementPlan: .codeBlockInset
            )
            guard let output = outputFromPreparedPayloadCancellable(
                payload,
                constrainedToWidth: maxWidth
            ) else {
                return nil
            }
            preparedBatch.stage(payload, for: key)
            return output
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
                let prepared = arithmeticCalculator.prepare(
                    attributedString: attributedString
                )
                size = sizeFromArithmeticPlan(
                    prepared,
                    attributedString: attributedString,
                    constrainedToWidth: maxWidth
                )
            } else {
                size = textCalculator.calculateSize(
                    for: attributedString,
                    constrainedToWidth: maxWidth
                )
            }
        case .codeBlockInset:
            size = codeBlockInsetSize(for: attributedString, constrainedToWidth: maxWidth)
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
        let size: CGSize
        switch measurement {
        case .standard:
            if shouldUseArithmeticLayout(for: node, styledString: attributedString) {
                let prepared = arithmeticCalculator.prepare(
                    attributedString: attributedString
                )
                guard !Task.isCancelled,
                      let arithmeticSize = sizeFromArithmeticPlanCancellable(
                        prepared,
                        attributedString: attributedString,
                        constrainedToWidth: maxWidth
                      ) else {
                    return nil
                }
                size = arithmeticSize
            } else {
                size = textCalculator.calculateSize(
                    for: attributedString,
                    constrainedToWidth: maxWidth
                )
            }
        case .codeBlockInset:
            size = codeBlockInsetSize(
                for: attributedString,
                constrainedToWidth: maxWidth
            )
        }
        guard !Task.isCancelled else { return nil }
        return ShallowLayoutOutput(size: size, attributedString: attributedString)
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
        guard Self.supportsArithmeticLayoutStructure(node) else { return false }
        return classifyPreparedNode(
            node,
            structuralArithmeticSupport: true
        ).supportsArithmeticLayout
    }

    /// Width-independent builder shapes whose paragraph/list semantics are
    /// modeled by `ArithmeticTextCalculator`. This predicate is shared by the
    /// prepared-cache and uncached routing paths; malformed or newly introduced
    /// container shapes fail closed to TextKit.
    static func supportsArithmeticLayoutStructure(_ node: MarkdownNode) -> Bool {
        if node is ParagraphNode || node is HeaderNode {
            return true
        }

        if let quote = node as? BlockQuoteNode {
            return !quote.children.isEmpty
                && quote.children.allSatisfy { $0 is ParagraphNode }
        }

        guard let rootList = node as? ListNode else { return false }
        var pendingLists = [rootList]

        while let list = pendingLists.popLast() {
            guard !list.children.isEmpty else { return false }

            for child in list.children {
                guard let item = child as? ListItemNode,
                      item.children.count == 1 || item.children.count == 2,
                      item.children[0] is ParagraphNode else {
                    return false
                }

                if item.children.count == 2 {
                    guard let nestedList = item.children[1] as? ListNode else {
                        return false
                    }
                    pendingLists.append(nestedList)
                }
            }
        }

        return true
    }

    /// Exact node vocabulary whose builder output is represented by the
    /// arithmetic text model. Public/custom and newly introduced node types
    /// fail closed until their attributed output has explicit oracle coverage.
    private static func isModeledArithmeticDescendant(_ node: MarkdownNode) -> Bool {
        node is ParagraphNode
            || node is HeaderNode
            || node is ListNode
            || node is ListItemNode
            || node is BlockQuoteNode
            || node is TextNode
            || node is EmphasisNode
            || node is StrongNode
            || node is StrikethroughNode
            || node is InlineCodeNode
            || node is LinkNode
    }
}
