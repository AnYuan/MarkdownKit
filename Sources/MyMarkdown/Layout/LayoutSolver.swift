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

            string.append(buildTableAttributedString(from: table, paragraphStyle: paragraphStyle))
            
        case let header as HeaderNode:
            let token = themeToken(forHeaderLevel: header.level)
            let baseAttrs = defaultAttributes(for: token)
            string.append(buildInlineAttributedString(from: header.children, baseAttributes: baseAttrs))
            
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
            let baseAttrs = defaultAttributes(for: theme.paragraph)
            string.append(buildInlineAttributedString(from: paragraph.children, baseAttributes: baseAttrs))
            
        case let code as CodeBlockNode:
            // Process the raw string through our Splash syntax highlighter
            let highlighted = highlighter.highlight(code.code, language: code.language)
            string.append(highlighted)
            
        case let list as ListNode:
            for child in list.children {
                let childAttr = await createAttributedString(for: child, constrainedToWidth: maxWidth)
                if string.length > 0 {
                    string.append(NSAttributedString(string: "\n"))
                }
                string.append(childAttr)
            }

        case let listItem as ListItemNode:
            let baseAttrs = defaultAttributes(for: theme.paragraph)

            var preText = "• "
            switch listItem.checkbox {
            case .checked: preText = "☑ "
            case .unchecked: preText = "☐ "
            case .none: break
            }

            string.append(NSAttributedString(string: preText, attributes: baseAttrs))

            for child in listItem.children {
                if let para = child as? ParagraphNode {
                    string.append(buildInlineAttributedString(from: para.children, baseAttributes: baseAttrs))
                } else if let nestedList = child as? ListNode {
                    let nestedAttr = await createAttributedString(for: nestedList, constrainedToWidth: maxWidth)
                    string.append(NSAttributedString(string: "\n"))
                    // Indent nested list items
                    let indented = NSMutableAttributedString(attributedString: nestedAttr)
                    let indentStyle = NSMutableParagraphStyle()
                    indentStyle.headIndent = 20
                    indentStyle.firstLineHeadIndent = 20
                    indentStyle.lineHeightMultiple = theme.paragraph.lineHeightMultiple
                    indented.addAttribute(.paragraphStyle, value: indentStyle, range: NSRange(location: 0, length: indented.length))
                    string.append(indented)
                } else {
                    let childAttr = await createAttributedString(for: child, constrainedToWidth: maxWidth)
                    string.append(childAttr)
                }
            }

        case let blockQuote as BlockQuoteNode:
            let quoteStyle = NSMutableParagraphStyle()
            quoteStyle.headIndent = 16
            quoteStyle.firstLineHeadIndent = 16
            quoteStyle.lineHeightMultiple = theme.paragraph.lineHeightMultiple
            quoteStyle.paragraphSpacing = theme.paragraph.paragraphSpacing

            for child in blockQuote.children {
                if let para = child as? ParagraphNode {
                    var quoteAttrs = defaultAttributes(for: theme.paragraph)
                    quoteAttrs[.paragraphStyle] = quoteStyle
                    quoteAttrs[.foregroundColor] = Color.gray
                    let inlineStr = buildInlineAttributedString(from: para.children, baseAttributes: quoteAttrs)

                    // Prepend quote bar
                    let bar = NSAttributedString(string: "┃ ", attributes: [
                        .foregroundColor: Color.systemBlue,
                        .font: theme.paragraph.font,
                        .paragraphStyle: quoteStyle
                    ])
                    string.append(bar)
                    string.append(inlineStr)
                } else {
                    let childAttr = await createAttributedString(for: child, constrainedToWidth: maxWidth)
                    string.append(childAttr)
                }
                if string.length > 0 {
                    string.append(NSAttributedString(string: "\n"))
                }
            }

        case is ThematicBreakNode:
            let hrAttrs: [NSAttributedString.Key: Any] = [
                .font: theme.paragraph.font,
                .foregroundColor: Color.gray
            ]
            let line = String(repeating: "─", count: 40)
            string.append(NSAttributedString(string: line, attributes: hrAttrs))

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
    
    // MARK: - Font Trait Helper

    private func fontWithTrait(_ font: Font, trait: FontTrait) -> Font {
        #if canImport(UIKit)
        let descriptor = font.fontDescriptor
        var traits = descriptor.symbolicTraits
        switch trait {
        case .bold: traits.insert(.traitBold)
        case .italic: traits.insert(.traitItalic)
        }
        if let newDescriptor = descriptor.withSymbolicTraits(traits) {
            return Font(descriptor: newDescriptor, size: 0)
        }
        return font
        #elseif canImport(AppKit)
        let manager = NSFontManager.shared
        switch trait {
        case .bold: return manager.convert(font, toHaveTrait: .boldFontMask)
        case .italic: return manager.convert(font, toHaveTrait: .italicFontMask)
        }
        #endif
    }

    private enum FontTrait {
        case bold, italic
    }

    // MARK: - Inline Attributed String Builder

    /// Builds a rich NSAttributedString from inline children, preserving styles
    /// for bold, italic, inline code, links, and images.
    private func buildInlineAttributedString(
        from children: [MarkdownNode],
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in children {
            switch child {
            case let text as TextNode:
                result.append(NSAttributedString(string: text.text, attributes: baseAttributes))

            case let code as InlineCodeNode:
                var codeAttrs = baseAttributes
                codeAttrs[.font] = theme.codeBlock.font
                codeAttrs[.backgroundColor] = theme.codeColor.background
                result.append(NSAttributedString(string: code.code, attributes: codeAttrs))

            case let link as LinkNode:
                var linkAttrs = baseAttributes
                linkAttrs[.foregroundColor] = Color.systemBlue
                linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if let dest = link.destination, let url = URL(string: dest) {
                    linkAttrs[.link] = url
                }
                let linkText = buildInlineAttributedString(from: link.children, baseAttributes: linkAttrs)
                result.append(linkText)

            case let image as ImageNode:
                var imgAttrs = baseAttributes
                imgAttrs[.foregroundColor] = Color.secondaryLabelColor
                let altText = image.altText ?? image.source ?? "image"
                result.append(NSAttributedString(string: "[\(altText)]", attributes: imgAttrs))

            case let math as MathNode:
                var mathAttrs = baseAttributes
                mathAttrs[.font] = theme.codeBlock.font
                mathAttrs[.foregroundColor] = Color.systemPurple
                let prefix = math.isInline ? "" : "\n"
                let suffix = math.isInline ? "" : "\n"
                result.append(NSAttributedString(string: "\(prefix)\(math.equation)\(suffix)", attributes: mathAttrs))

            case is EmphasisNode:
                var italicAttrs = baseAttributes
                if let font = baseAttributes[.font] as? Font {
                    italicAttrs[.font] = fontWithTrait(font, trait: .italic)
                }
                result.append(buildInlineAttributedString(from: child.children, baseAttributes: italicAttrs))

            case is StrongNode:
                var boldAttrs = baseAttributes
                if let font = baseAttributes[.font] as? Font {
                    boldAttrs[.font] = fontWithTrait(font, trait: .bold)
                }
                result.append(buildInlineAttributedString(from: child.children, baseAttributes: boldAttrs))

            case is StrikethroughNode:
                var strikeAttrs = baseAttributes
                strikeAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(buildInlineAttributedString(from: child.children, baseAttributes: strikeAttrs))

            default:
                let childResult = buildInlineAttributedString(from: child.children, baseAttributes: baseAttributes)
                if childResult.length > 0 {
                    result.append(childResult)
                }
            }
        }
        return result
    }

    // MARK: - Table Helper
    private func buildTableAttributedString(from table: TableNode, paragraphStyle: NSParagraphStyle) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let boldFont = fontWithTrait(theme.paragraph.font, trait: .bold)

        let headAttrs: [NSAttributedString.Key: Any] = [
            .font: boldFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: theme.textColor.foreground,
            .backgroundColor: theme.tableColor.background
        ]
        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.paragraph.font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: theme.textColor.foreground,
            .backgroundColor: theme.tableColor.background
        ]
        let separatorAttrs: [NSAttributedString.Key: Any] = [
            .font: theme.paragraph.font,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: Color.gray
        ]

        for section in table.children {
            let isHead = section is TableHeadNode
            let sectionChildren = (section as? TableHeadNode)?.children ?? (section as? TableBodyNode)?.children ?? []
            for row in sectionChildren {
                let rowChildren = (row as? TableRowNode)?.children ?? []
                var cells: [String] = []
                for cell in rowChildren {
                    let cellChildren = (cell as? TableCellNode)?.children ?? []
                    var cellText = ""
                    for cellChild in cellChildren {
                        if let textNode = cellChild as? TextNode {
                            cellText += textNode.text
                        }
                    }
                    cells.append(cellText)
                }
                let rowText = cells.joined(separator: "\t")
                result.append(NSAttributedString(string: rowText + "\n", attributes: isHead ? headAttrs : bodyAttrs))
            }
            if isHead {
                let separator = String(repeating: "─", count: 30)
                result.append(NSAttributedString(string: separator + "\n", attributes: separatorAttrs))
            }
        }
        return result
    }
}

