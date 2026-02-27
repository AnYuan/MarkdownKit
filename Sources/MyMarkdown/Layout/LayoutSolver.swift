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
    private let cache: LayoutCache
    private let highlighter: SplashHighlighter
    
    public init(theme: Theme = .default, cache: LayoutCache = LayoutCache()) {
        self.theme = theme
        self.textCalculator = TextKitCalculator()
        self.cache = cache
        self.highlighter = SplashHighlighter(theme: theme)
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
        let styledString = await createAttributedString(for: node, constrainedToWidth: maxWidth)
        
        // 2. Measure exactly using the background TextKitCalculator
        let size = textCalculator.calculateSize(for: styledString, constrainedToWidth: maxWidth)
        
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
    
    // MARK: - Internal Styling
    
    private func createAttributedString(for node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) async -> NSAttributedString {
        let string = NSMutableAttributedString()
        
        switch node {
        case let table as TableNode:
            let colCount = max(1, table.columnAlignments.count)
            let colWidth = maxWidth / CGFloat(colCount)
            
            let paragraphStyle = NSMutableParagraphStyle()
            var tabs: [NSTextTab] = []
            for i in 1...colCount {
                let alignment: NSTextAlignment
                let align = i <= table.columnAlignments.count ? table.columnAlignments[i-1] : nil
                switch align {
                case .right: alignment = .right
                case .center: alignment = .center
                default: alignment = .left
                }
                let tab = NSTextTab(textAlignment: alignment, location: colWidth * CGFloat(i), options: [:])
                tabs.append(tab)
            }
            paragraphStyle.tabStops = tabs
            paragraphStyle.defaultTabInterval = colWidth
            
            let attributes: [NSAttributedString.Key: Any] = [
                .font: theme.paragraph.font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: theme.textColor.foreground,
                .backgroundColor: theme.tableColor.background
            ]
            
            let rawText = extractTableText(from: table)
            string.append(NSAttributedString(string: rawText, attributes: attributes))
            
        case let header as HeaderNode:
            let token = themeToken(forHeaderLevel: header.level)
            let attributes = defaultAttributes(for: token)
            let rawText = extractInlineText(from: header.children)
            string.append(NSAttributedString(string: rawText, attributes: attributes))
            
        case let text as TextNode:
            let attributes = defaultAttributes(for: theme.paragraph)
            string.append(NSAttributedString(string: text.text, attributes: attributes))
            
        case let math as MathNode:
            // Suspend the LayoutSolver Task while WebKit evaluates the JavaScript via MathJax
            if let image = await renderMath(latex: math.equation) {
                #if canImport(UIKit)
                let attachment = NSTextAttachment()
                attachment.image = image
                
                // For Inline Math, align with text baseline. For Block, span available width if needed.
                let offsetY: CGFloat = math.isInline ? -4.0 : 0.0
                attachment.bounds = CGRect(x: 0, y: offsetY, width: image.size.width, height: image.size.height)
                
                let attrString = NSAttributedString(attachment: attachment)
                string.append(attrString)
                #endif
            } else {
                // Fallback to raw text if WebKit JS execution fails 
                let attr = defaultAttributes(for: theme.codeBlock)
                string.append(NSAttributedString(string: math.equation, attributes: attr))
            }
            
        case let paragraph as ParagraphNode:
            let attributes = defaultAttributes(for: theme.paragraph)
            let rawText = extractInlineText(from: paragraph.children)
            string.append(NSAttributedString(string: rawText, attributes: attributes))
            
        case let code as CodeBlockNode:
            // Process the raw string through our Splash syntax highlighter
            let highlighted = highlighter.highlight(code.code, language: code.language)
            string.append(highlighted)
            
        case let list as ListNode:
            // Just stack list children with some indentation
            for child in list.children {
                let childAttr = await createAttributedString(for: child, constrainedToWidth: maxWidth)
                if string.length > 0 {
                    string.append(NSAttributedString(string: "\n"))
                }
                string.append(childAttr)
            }
            
        case let listItem as ListItemNode:
            let attributes = defaultAttributes(for: theme.paragraph)
            
            // Add Checkbox or Bullet
            var preText = "• "
            switch listItem.checkbox {
            case .checked: preText = "☑ "
            case .unchecked: preText = "☐ "
            case .none: break
            }
            
            string.append(NSAttributedString(string: preText, attributes: attributes))
            
            for child in listItem.children {
                let childAttr = await createAttributedString(for: child, constrainedToWidth: maxWidth)
                string.append(childAttr)
            }
            
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
    
    // MARK: - Async Math Helper
    private func renderMath(latex: String) async -> NativeImage? {
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                MathRenderer.shared.render(latex: latex) { image in
                    continuation.resume(returning: image)
                }
            }
        }
    }
    
    // MARK: - Inline Text Helper
    private func extractInlineText(from children: [MarkdownNode]) -> String {
        var result = ""
        for child in children {
            switch child {
            case let text as TextNode:
                result += text.text
            case let code as InlineCodeNode:
                result += code.code
            case let link as LinkNode:
                result += extractInlineText(from: link.children)
            case let image as ImageNode:
                result += image.altText ?? ""
            default:
                // Recursively extract from any other container nodes (e.g. emphasis, strong)
                result += extractInlineText(from: child.children)
            }
        }
        return result
    }

    // MARK: - Table Helper
    private func extractTableText(from table: TableNode) -> String {
        var rows: [String] = []
        for section in table.children {
            let sectionChildren = (section as? TableHeadNode)?.children ?? (section as? TableBodyNode)?.children ?? []
            for row in sectionChildren {
                let rowChildren = (row as? TableRowNode)?.children ?? []
                var cells: [String] = []
                for cell in rowChildren {
                    var cellText = ""
                    let cellChildren = (cell as? TableCellNode)?.children ?? []
                    for cellChild in cellChildren {
                        if let textNode = cellChild as? TextNode {
                            cellText += textNode.text
                        }
                    }
                    cells.append(cellText)
                }
                rows.append(cells.joined(separator: "\t"))
            }
        }
        return rows.joined(separator: "\n")
    }
}

