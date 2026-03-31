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
    
    public init(
        theme: Theme = .default,
        cache: LayoutCache = LayoutCache(),
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        mathAdapter: (any MathRenderingAdapter)? = nil
    ) {
        self.textCalculator = TextKitCalculator()
        self.arithmeticCalculator = ArithmeticTextCalculator()
        self.cache = cache
        let highlighter = SplashHighlighter(theme: theme)
        self.builder = AttributedStringBuilder(
            theme: theme,
            highlighter: highlighter,
            diagramRegistry: diagramRegistry,
            mathAdapter: mathAdapter ?? DefaultMathRenderingAdapter()
        )
    }
    
    private final class SendableBox<T>: @unchecked Sendable {
        var value: T?
        init(_ value: T? = nil) { self.value = value }
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
        if let cached = cache.getLayout(for: node, constrainedToWidth: maxWidth) {
            return cached
        }

        #if canImport(UIKit) && !os(watchOS)
        // Card-style table rendering on iOS: bypass TextKit, draw directly via CGContext
        if let table = node as? TableNode {
            let result = solveTableCard(table: table, constrainedToWidth: maxWidth)
            cache.setLayout(result, constrainedToWidth: maxWidth)
            return result
        }

        // Thematic break: draw a hairline matching legacy DividerAttachment
        if node is ThematicBreakNode {
            let result = solveThematicBreak(node: node, constrainedToWidth: maxWidth)
            cache.setLayout(result, constrainedToWidth: maxWidth)
            return result
        }
        #endif


        // 1. Convert AST to styled NSAttributedString based on Theme
        let styledString: NSAttributedString
        var size: CGSize

        // Special handling for nodes that have internal padding in their UI representation
        if let code = node as? CodeBlockNode {
            styledString = builder.buildCodeBlockAttributedString(from: code)

            // TextKit needs to know that we inset the container 8pts horizontally by the UI view
            // to accurately wrap the string if it's too long.
            let totalInset = builder.theme.codeBlock.layoutTotalInset
            let insets = CGSize(width: totalInset, height: totalInset)
            size = textCalculator.calculateSize(
                for: styledString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height

        } else if let diagram = node as? DiagramNode {
            styledString = await builder.buildDiagramAttributedString(from: diagram)

            let totalInset = builder.theme.codeBlock.layoutTotalInset
            let insets = CGSize(width: totalInset, height: totalInset)
            size = textCalculator.calculateSize(
                for: styledString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height

        } else {
            styledString = await builder.buildString(for: node, constrainedToWidth: maxWidth)
            
            if shouldUseArithmeticLayout(for: node, styledString: styledString) {
                size = arithmeticCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
            } else {
                size = textCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
            }
        }

        // 3. Recurse down children (if they represent separate visual block elements)
        // For basic implementation, we assume paragraphs/headers handle their own inline children.
        // But for Documents, we must layout all top-level blocks.
        var childLayouts: [LayoutResult] = []

        if let doc = node as? DocumentNode {
            for child in doc.children {
                childLayouts.append(await solve(node: child, constrainedToWidth: maxWidth))
            }
        }

        // strictly immutable frame container
        let result = LayoutResult(
            node: node,
            size: size,
            attributedString: styledString,
            children: childLayouts
        )

        // Memoize the result
        cache.setLayout(result, constrainedToWidth: maxWidth)

        return result
    }

    /// Synchronous variant of `solve` that avoids Swift concurrency entirely.
    /// Uses `buildStringSync` (cached math / fallback text, no async rendering).
    /// Safe to call from the main thread without RunLoop polling.
    public func solveSync(node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) -> LayoutResult {
        if let cached = cache.getLayout(for: node, constrainedToWidth: maxWidth) {
            return cached
        }

        #if canImport(UIKit) && !os(watchOS)
        if let table = node as? TableNode {
            let result = solveTableCard(table: table, constrainedToWidth: maxWidth)
            cache.setLayout(result, constrainedToWidth: maxWidth)
            return result
        }

        if node is ThematicBreakNode {
            let result = solveThematicBreak(node: node, constrainedToWidth: maxWidth)
            cache.setLayout(result, constrainedToWidth: maxWidth)
            return result
        }
        #endif

        let styledString: NSAttributedString
        var size: CGSize

        if let code = node as? CodeBlockNode {
            styledString = builder.buildCodeBlockAttributedString(from: code)
            let totalInset = builder.theme.codeBlock.layoutTotalInset
            let insets = CGSize(width: totalInset, height: totalInset)
            size = textCalculator.calculateSize(
                for: styledString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height
        } else {
            styledString = builder.buildStringSync(for: node, constrainedToWidth: maxWidth)
            
            if shouldUseArithmeticLayout(for: node, styledString: styledString) {
                size = arithmeticCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
            } else {
                size = textCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
            }
        }

        var childLayouts: [LayoutResult] = []
        if let doc = node as? DocumentNode {
            for child in doc.children {
                childLayouts.append(solveSync(node: child, constrainedToWidth: maxWidth))
            }
        }

        let result = LayoutResult(
            node: node,
            size: size,
            attributedString: styledString,
            children: childLayouts
        )
        cache.setLayout(result, constrainedToWidth: maxWidth)
        return result
    }

    // MARK: - Thematic Break Layout (iOS only)

    #if canImport(UIKit) && !os(watchOS)
    private func solveThematicBreak(node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) -> LayoutResult {
        let paddingTop = builder.theme.thematicBreak.paddingTop
        let paddingBottom = builder.theme.thematicBreak.paddingBottom
        let dividerHeight = builder.theme.thematicBreak.dividerHeight
        let totalHeight = paddingTop + dividerHeight + paddingBottom
        let totalSize = CGSize(width: maxWidth, height: totalHeight)

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
            customDraw: customDraw
        )
    }
    #endif

    // MARK: - Table Card Layout (iOS only)

    #if canImport(UIKit) && !os(watchOS)
    /// Produces a `LayoutResult` for a table node that uses CGContext card rendering
    /// instead of TextKit. The `customDraw` closure captures the pre-computed layout
    /// and resolved colors so that rasterization is fully thread-safe.
    private func solveTableCard(table: TableNode, constrainedToWidth maxWidth: CGFloat) -> LayoutResult {
        let layout = TableCardRenderer.computeLayout(
            from: table,
            theme: builder.theme,
            constrainedToWidth: maxWidth
        )

        // Resolve UIColor -> CGColor on the current thread (which has trait collection context).
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
