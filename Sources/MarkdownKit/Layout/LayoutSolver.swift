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
    private let cache: LayoutCache
    private let builder: AttributedStringBuilder
    
    public init(
        theme: Theme = .default,
        cache: LayoutCache = LayoutCache(),
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        mathAdapter: (any MathRenderingAdapter)? = nil
    ) {
        self.textCalculator = TextKitCalculator()
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
        
        // 1. Convert AST to styled NSAttributedString based on Theme
        let styledString: NSAttributedString
        var size: CGSize
        
        // Special handling for nodes that have internal padding in their UI representation
        if let code = node as? CodeBlockNode {
            styledString = builder.buildCodeBlockAttributedString(from: code)
            
            // TextKit needs to know that we inset the container 8pts horizontally by the UI view
            // to accurately wrap the string if it's too long.
            let insets = CGSize(width: 16, height: 16) // 8 left + 8 right, 8 top + 8 bottom
            size = textCalculator.calculateSize(
                for: styledString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height
            
        } else if let diagram = node as? DiagramNode {
            styledString = await builder.buildDiagramAttributedString(from: diagram)
            
            let insets = CGSize(width: 16, height: 16)
            size = textCalculator.calculateSize(
                for: styledString,
                constrainedToWidth: max(0, maxWidth - insets.width)
            )
            size.width += insets.width
            size.height += insets.height
            
        } else {
            styledString = await builder.buildString(for: node, constrainedToWidth: maxWidth)
            size = textCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
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
    

}
