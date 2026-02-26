//
//  LayoutSolver.swift
//  MyMarkdown
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
public final class LayoutSolver {
    
    private let theme: Theme
    private let textCalculator: TextKitCalculator
    
    public init(theme: Theme = .default) {
        self.theme = theme
        self.textCalculator = TextKitCalculator()
    }
    
    /// Recursively calculates the layout for a node and all its children.
    ///
    /// - Parameters:
    ///   - node: The root AST node.
    ///   - maxWidth: The maximum layout boundaries (e.g. view width).
    /// - Returns: A fully calculated `LayoutResult` tree holding sizes and attributed strings.
    public func solve(node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) -> LayoutResult {
        
        // 1. Convert AST to styled NSAttributedString based on Theme
        let styledString = createAttributedString(for: node)
        
        // 2. Measure exactly using the background TextKitCalculator
        let size = textCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
        
        // 3. Recurse down children (if they represent separate visual block elements)
        // For basic implementation, we assume paragraphs/headers handle their own inline children.
        // But for Documents, we must layout all top-level blocks.
        var childLayouts: [LayoutResult] = []
        
        if let doc = node as? DocumentNode {
            for child in doc.children {
                childLayouts.append(solve(node: child, constrainedToWidth: maxWidth))
            }
        }
        
        // Return strictly immutable frame container
        return LayoutResult(
            node: node,
            size: size,
            attributedString: styledString,
            children: childLayouts
        )
    }
    
    // MARK: - Internal Styling
    
    private func createAttributedString(for node: MarkdownNode) -> NSAttributedString {
        let string = NSMutableAttributedString()
        
        switch node {
        case let header as HeaderNode:
            let token = themeToken(forHeaderLevel: header.level)
            let attributes = defaultAttributes(for: token)
            // Just extracting raw text for the prototype solver
            if let textNode = header.children.first as? TextNode {
                string.append(NSAttributedString(string: textNode.text, attributes: attributes))
            }
            
        case let paragraph as ParagraphNode:
            let attributes = defaultAttributes(for: theme.paragraph)
            if let textNode = paragraph.children.first as? TextNode {
                string.append(NSAttributedString(string: textNode.text, attributes: attributes))
            }
            
        case let code as CodeBlockNode:
            let attributes = defaultAttributes(for: theme.codeBlock)
            string.append(NSAttributedString(string: code.code, attributes: attributes))
            
        default:
            break
        }
        
        return string
    }
    
    private func themeToken(forHeaderLevel level: Int) -> TypographyToken {
        switch level {
        case 1: return theme.header1
        case 2: return theme.header2
        default: return theme.header3
        }
    }
    
    private func defaultAttributes(for token: TypographyToken) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = token.lineHeightMultiple
        paragraphStyle.paragraphSpacing = token.paragraphSpacing
        
        return [
            .font: token.font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: theme.textColor.foreground
        ]
    }
}
