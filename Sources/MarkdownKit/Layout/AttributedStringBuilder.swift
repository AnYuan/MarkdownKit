//
//  AttributedStringBuilder.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A builder dedicated solely to converting the AST into an NSAttributedString.
struct AttributedStringBuilder {
    private let theme: Theme
    private let highlighter: SplashHighlighter
    private let diagramRegistry: DiagramAdapterRegistry
    private let mathAdapter: any MathRenderingAdapter

    init(theme: Theme, highlighter: SplashHighlighter, diagramRegistry: DiagramAdapterRegistry, mathAdapter: any MathRenderingAdapter = DefaultMathRenderingAdapter()) {
        self.theme = theme
        self.highlighter = highlighter
        self.diagramRegistry = diagramRegistry
        self.mathAdapter = mathAdapter
    }
    func buildString(for node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) async -> NSAttributedString {
        let string = NSMutableAttributedString()
        
        switch node {
        case let table as TableNode:
            string.append(TableAttributedStringBuilder.build(from: table, theme: theme, constrainedToWidth: maxWidth))

        case let diagram as DiagramNode:
            // This case is now handled in solve() for size calculation, but we still need to build the string here
            string.append(await buildDiagramAttributedString(from: diagram))

        case let details as DetailsNode:
            string.append(await buildDetailsAttributedString(from: details, constrainedToWidth: maxWidth))

        case let summary as SummaryNode:
            let baseAttrs = detailsSummaryAttributes()
            string.append(await buildInlineAttributedString(
                from: summary.children,
                baseAttributes: baseAttrs,
                constrainedToWidth: maxWidth
            ))
            
        case let header as HeaderNode:
            let token = themeToken(forHeaderLevel: header.level)
            let baseAttrs = defaultAttributes(for: token)
            string.append(await buildInlineAttributedString(
                from: header.children,
                baseAttributes: baseAttrs,
                constrainedToWidth: maxWidth
            ))
            
        case let text as TextNode:
            let attributes = defaultAttributes(for: theme.typography.paragraph)
            string.append(NSAttributedString(string: text.text, attributes: attributes))
            
        case let math as MathNode:
            string.append(await mathAdapter.render(from: math, theme: theme))

        case let paragraph as ParagraphNode:
            let baseAttrs = defaultAttributes(for: theme.typography.paragraph)
            string.append(await buildInlineAttributedString(
                from: paragraph.children,
                baseAttributes: baseAttrs,
                constrainedToWidth: maxWidth
            ))
            
        case let code as CodeBlockNode:
            string.append(buildCodeBlockAttributedString(from: code))
            
        case let list as ListNode:
            let compactStyle = NSMutableParagraphStyle()
            compactStyle.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
            compactStyle.paragraphSpacing = 4

            let listAttrs: [NSAttributedString.Key: Any] = [
                .font: theme.typography.paragraph.font,
                .paragraphStyle: compactStyle,
                .foregroundColor: theme.colors.textColor.foreground
            ]

            for (itemIndex, child) in list.children.enumerated() {
                guard let item = child as? ListItemNode else { continue }

                if string.length > 0 {
                    string.append(NSAttributedString(string: "\n"))
                }

                // Determine prefix: checkbox > ordered number > bullet
                var prefix: String
                var isCheckbox = false
                switch item.checkbox {
                case .checked: 
                    prefix = "☑ "
                    isCheckbox = true
                case .unchecked: 
                    prefix = "☐ "
                    isCheckbox = true
                case .none:
                    prefix = list.isOrdered ? "\(itemIndex + 1). " : "• "
                }
                
                var itemPrefixAttrs = listAttrs
                if isCheckbox, let range = item.range {
                    let interactionState = CheckboxInteractionData(isChecked: item.checkbox == .checked, range: range)
                    itemPrefixAttrs[.markdownCheckbox] = interactionState
                }
                
                string.append(NSAttributedString(string: prefix, attributes: itemPrefixAttrs))

                // Render item content
                for itemChild in item.children {
                    if let para = itemChild as? ParagraphNode {
                        string.append(await buildInlineAttributedString(
                            from: para.children,
                            baseAttributes: listAttrs,
                            constrainedToWidth: maxWidth
                        ))
                    } else if let nestedList = itemChild as? ListNode {
                        let nestedAttr = await buildString(for: nestedList, constrainedToWidth: maxWidth)
                        string.append(NSAttributedString(string: "\n"))
                        let indented = NSMutableAttributedString(attributedString: nestedAttr)
                        let indentStyle = NSMutableParagraphStyle()
                        indentStyle.headIndent = 20
                        indentStyle.firstLineHeadIndent = 20
                        indentStyle.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
                        indentStyle.paragraphSpacing = 4
                        indented.addAttribute(.paragraphStyle, value: indentStyle, range: NSRange(location: 0, length: indented.length))
                        string.append(indented)
                    } else {
                        let childAttr = await buildString(for: itemChild, constrainedToWidth: maxWidth)
                        string.append(childAttr)
                    }
                }
            }

        case is ListItemNode:
            // ListItems are handled inside ListNode above; this case handles orphans
            break

        case let blockQuote as BlockQuoteNode:
            let quoteStyle = NSMutableParagraphStyle()
            quoteStyle.headIndent = 16
            quoteStyle.firstLineHeadIndent = 16
            quoteStyle.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
            quoteStyle.paragraphSpacing = theme.typography.paragraph.paragraphSpacing

            for child in blockQuote.children {
                if let para = child as? ParagraphNode {
                    var quoteAttrs = defaultAttributes(for: theme.typography.paragraph)
                    quoteAttrs[.paragraphStyle] = quoteStyle
                    quoteAttrs[.foregroundColor] = theme.colors.blockQuoteColor.background
                    let inlineStr = await buildInlineAttributedString(
                        from: para.children,
                        baseAttributes: quoteAttrs,
                        constrainedToWidth: maxWidth
                    )

                    // Prepend quote bar
                    let bar = NSAttributedString(string: "┃ ", attributes: [
                        .foregroundColor: theme.colors.blockQuoteColor.foreground,
                        .font: theme.typography.paragraph.font,
                        .paragraphStyle: quoteStyle
                    ])
                    string.append(bar)
                    string.append(inlineStr)
                } else {
                    let childAttr = await buildString(for: child, constrainedToWidth: maxWidth)
                    string.append(childAttr)
                }
                if string.length > 0 {
                    string.append(NSAttributedString(string: "\n"))
                }
            }

        case is ThematicBreakNode:
            let hrAttrs: [NSAttributedString.Key: Any] = [
                .font: theme.typography.paragraph.font,
                .foregroundColor: theme.colors.thematicBreakColor.foreground
            ]
            let line = String(repeating: "─", count: 40)
            string.append(NSAttributedString(string: line, attributes: hrAttrs))

        default:
            break
        }

        return string
    }

    // MARK: - Synchronous Build (no Swift concurrency)

    /// Builds an attributed string synchronously, without any async calls.
    /// Math nodes render as fallback text, images render as alt text, diagrams are skipped.
    func buildStringSync(for node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) -> NSAttributedString {
        let string = NSMutableAttributedString()

        switch node {
        case let table as TableNode:
            string.append(TableAttributedStringBuilder.build(from: table, theme: theme, constrainedToWidth: maxWidth))

        case let header as HeaderNode:
            let token = themeToken(forHeaderLevel: header.level)
            let baseAttrs = defaultAttributes(for: token)
            string.append(buildInlineAttributedStringSync(from: header.children, baseAttributes: baseAttrs))

        case let text as TextNode:
            let attributes = defaultAttributes(for: theme.typography.paragraph)
            string.append(NSAttributedString(string: text.text, attributes: attributes))

        case let math as MathNode:
            string.append(mathAdapter.renderSync(from: math, theme: theme))

        case let paragraph as ParagraphNode:
            let baseAttrs = defaultAttributes(for: theme.typography.paragraph)
            string.append(buildInlineAttributedStringSync(from: paragraph.children, baseAttributes: baseAttrs))

        case let code as CodeBlockNode:
            string.append(buildCodeBlockAttributedString(from: code))

        case let list as ListNode:
            let compactStyle = NSMutableParagraphStyle()
            compactStyle.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
            compactStyle.paragraphSpacing = 4
            let listAttrs: [NSAttributedString.Key: Any] = [
                .font: theme.typography.paragraph.font,
                .paragraphStyle: compactStyle,
                .foregroundColor: theme.colors.textColor.foreground
            ]
            for (itemIndex, child) in list.children.enumerated() {
                guard let item = child as? ListItemNode else { continue }
                if string.length > 0 { string.append(NSAttributedString(string: "\n")) }
                var prefix: String
                switch item.checkbox {
                case .checked: prefix = "☑ "
                case .unchecked: prefix = "☐ "
                case .none: prefix = list.isOrdered ? "\(itemIndex + 1). " : "• "
                }
                string.append(NSAttributedString(string: prefix, attributes: listAttrs))
                for itemChild in item.children {
                    if let para = itemChild as? ParagraphNode {
                        string.append(buildInlineAttributedStringSync(from: para.children, baseAttributes: listAttrs))
                    } else if let nestedList = itemChild as? ListNode {
                        string.append(NSAttributedString(string: "\n"))
                        let nestedAttr = NSMutableAttributedString(attributedString: buildStringSync(for: nestedList, constrainedToWidth: maxWidth))
                        let indentStyle = NSMutableParagraphStyle()
                        indentStyle.headIndent = 20
                        indentStyle.firstLineHeadIndent = 20
                        indentStyle.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
                        indentStyle.paragraphSpacing = 4
                        nestedAttr.addAttribute(.paragraphStyle, value: indentStyle, range: NSRange(location: 0, length: nestedAttr.length))
                        string.append(nestedAttr)
                    } else {
                        string.append(buildStringSync(for: itemChild, constrainedToWidth: maxWidth))
                    }
                }
            }

        case let blockQuote as BlockQuoteNode:
            let quoteStyle = NSMutableParagraphStyle()
            quoteStyle.headIndent = 16
            quoteStyle.firstLineHeadIndent = 16
            quoteStyle.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
            quoteStyle.paragraphSpacing = theme.typography.paragraph.paragraphSpacing
            for child in blockQuote.children {
                if let para = child as? ParagraphNode {
                    var quoteAttrs = defaultAttributes(for: theme.typography.paragraph)
                    quoteAttrs[.paragraphStyle] = quoteStyle
                    quoteAttrs[.foregroundColor] = theme.colors.blockQuoteColor.background
                    let bar = NSAttributedString(string: "┃ ", attributes: [
                        .foregroundColor: theme.colors.blockQuoteColor.foreground,
                        .font: theme.typography.paragraph.font,
                        .paragraphStyle: quoteStyle
                    ])
                    string.append(bar)
                    string.append(buildInlineAttributedStringSync(from: para.children, baseAttributes: quoteAttrs))
                } else {
                    string.append(buildStringSync(for: child, constrainedToWidth: maxWidth))
                }
                if string.length > 0 { string.append(NSAttributedString(string: "\n")) }
            }

        case is ThematicBreakNode:
            let hrAttrs: [NSAttributedString.Key: Any] = [
                .font: theme.typography.paragraph.font,
                .foregroundColor: theme.colors.thematicBreakColor.foreground
            ]
            string.append(NSAttributedString(string: String(repeating: "─", count: 40), attributes: hrAttrs))

        default:
            break
        }

        return string
    }

    /// Synchronous inline string builder — no async calls.
    private func buildInlineAttributedStringSync(
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
                let baseFont = (baseAttributes[.font] as? Font) ?? theme.typography.paragraph.font
                codeAttrs[.font] = Font.monospacedSystemFont(ofSize: max(11, baseFont.pointSize * 0.92), weight: .regular)
                codeAttrs[.foregroundColor] = theme.colors.inlineCodeColor.foreground
                codeAttrs[.backgroundColor] = theme.colors.inlineCodeColor.background
                result.append(NSAttributedString(string: code.code, attributes: codeAttrs))
            case let link as LinkNode:
                var linkAttrs = baseAttributes
                linkAttrs[.foregroundColor] = theme.colors.linkColor.foreground
                linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if let dest = link.destination, let url = URL(string: dest) {
                    linkAttrs[.link] = url
                }
                result.append(buildInlineAttributedStringSync(from: link.children, baseAttributes: linkAttrs))
            case let emphasis as EmphasisNode:
                var emAttrs = baseAttributes
                if let font = emAttrs[.font] as? Font {
                    emAttrs[.font] = fontWithTrait(font, trait: .italic)
                }
                result.append(buildInlineAttributedStringSync(from: emphasis.children, baseAttributes: emAttrs))
            case let strong as StrongNode:
                var strongAttrs = baseAttributes
                if let font = strongAttrs[.font] as? Font {
                    strongAttrs[.font] = fontWithTrait(font, trait: .bold)
                }
                result.append(buildInlineAttributedStringSync(from: strong.children, baseAttributes: strongAttrs))
            case let strikethrough as StrikethroughNode:
                var stAttrs = baseAttributes
                stAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(buildInlineAttributedStringSync(from: strikethrough.children, baseAttributes: stAttrs))
            case let math as MathNode:
                result.append(mathAdapter.renderSync(from: math, theme: theme))
            default:
                break
            }
        }
        return result
    }

    private func themeToken(forHeaderLevel level: Int) -> TypographyToken {
        switch level {
        case 1: return theme.typography.header1
        case 2: return theme.typography.header2
        default: return theme.typography.header3
        }
    }
    
    private func defaultAttributes(for token: TypographyToken) -> [NSAttributedString.Key: Any] {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = token.lineHeightMultiple
        paragraphStyle.paragraphSpacing = token.paragraphSpacing
        
        let safeFont = token.font
        return [
            .font: safeFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: theme.colors.textColor.foreground
        ]
    }
    
    // MARK: - Async Math Helper

    
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
        var symbolicTraits = font.fontDescriptor.symbolicTraits
        switch trait {
        case .bold:
            symbolicTraits.insert(.bold)
        case .italic:
            symbolicTraits.insert(.italic)
        }
        
        let descriptor = font.fontDescriptor.withSymbolicTraits(symbolicTraits)
        return Font(descriptor: descriptor, size: font.pointSize) ?? font
        #endif
    }

    private enum FontTrait {
        case bold, italic
    }

    // MARK: - Code Block Helper
    
    // Extracted from the dynamic hot path to prevent CoreText cache contention under 8x concurrency scaling.
    private static nonisolated(unsafe) let rawLabelFont = Font.monospacedSystemFont(ofSize: 11, weight: .semibold)

    func buildCodeBlockAttributedString(from code: CodeBlockNode) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if let label = normalizedCodeLanguageLabel(from: code.language) {
            let labelStyle = NSMutableParagraphStyle()
            labelStyle.paragraphSpacing = 6
            labelStyle.lineHeightMultiple = 1.0

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.rawLabelFont,
                .foregroundColor: Color.platformSecondaryLabel,
                .paragraphStyle: labelStyle
            ]
            result.append(NSAttributedString(string: label + "\n", attributes: labelAttrs))
        }

        // Process the raw string through our Splash syntax highlighter.
        let highlighted = highlighter.highlight(code.code, language: code.language)
        result.append(highlighted)
        return result
    }

    private func normalizedCodeLanguageLabel(from language: String?) -> String? {
        guard let language else { return nil }
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed.uppercased()
    }

    // MARK: - Diagram Helper

    func buildDiagramAttributedString(from diagram: DiagramNode) async -> NSAttributedString {
        if let adapter = diagramRegistry.adapter(for: diagram.language),
           let rendered = await adapter.render(source: diagram.source, language: diagram.language) {
            return rendered
        }

        let fallback = CodeBlockNode(
            range: diagram.range,
            language: diagram.language.rawValue,
            code: diagram.source
        )
        return buildCodeBlockAttributedString(from: fallback)
    }

    // MARK: - Details Helper

    private func buildDetailsAttributedString(
        from details: DetailsNode,
        constrainedToWidth maxWidth: CGFloat
    ) async -> NSAttributedString {
        let result = NSMutableAttributedString()
        let summaryAttrs = detailsSummaryAttributes()

        let disclosure = details.isOpen ? "▼ " : "▶ "
        result.append(NSAttributedString(string: disclosure, attributes: summaryAttrs))

        if let summary = details.summary, !summary.children.isEmpty {
            let summaryText = await buildInlineAttributedString(
                from: summary.children,
                baseAttributes: summaryAttrs,
                constrainedToWidth: maxWidth
            )
            result.append(summaryText)
        } else {
            result.append(NSAttributedString(string: "Details", attributes: summaryAttrs))
        }

        guard details.isOpen else {
            return result
        }

        var didAppendBody = false
        for child in details.children {
            let childAttr = await buildString(for: child, constrainedToWidth: maxWidth)
            guard childAttr.length > 0 else { continue }

            if !didAppendBody {
                result.append(NSAttributedString(string: "\n"))
                didAppendBody = true
            } else {
                result.append(NSAttributedString(string: "\n"))
            }
            result.append(childAttr)
        }

        return result
    }

    private func detailsSummaryAttributes() -> [NSAttributedString.Key: Any] {
        var attrs = defaultAttributes(for: theme.typography.paragraph)
        if let font = attrs[.font] as? Font {
            attrs[.font] = fontWithTrait(font, trait: .bold)
        }
        return attrs
    }

    // MARK: - Inline Attributed String Builder

    /// Builds a rich NSAttributedString from inline children, preserving styles
    /// for bold, italic, inline code, links, and images.
    private func buildInlineAttributedString(
        from children: [MarkdownNode],
        baseAttributes: [NSAttributedString.Key: Any],
        constrainedToWidth maxWidth: CGFloat
    ) async -> NSAttributedString {
        let result = NSMutableAttributedString()
        for child in children {
            switch child {
            case let text as TextNode:
                result.append(NSAttributedString(string: text.text, attributes: baseAttributes))

            case let code as InlineCodeNode:
                var codeAttrs = baseAttributes
                let baseFont = (baseAttributes[.font] as? Font) ?? theme.typography.paragraph.font
                codeAttrs[.font] = Font.monospacedSystemFont(
                    ofSize: max(11, baseFont.pointSize * 0.92),
                    weight: .regular
                )
                codeAttrs[.foregroundColor] = theme.colors.inlineCodeColor.foreground
                codeAttrs[.backgroundColor] = theme.colors.inlineCodeColor.background
                result.append(NSAttributedString(string: code.code, attributes: codeAttrs))

            case let link as LinkNode:
                var linkAttrs = baseAttributes
                linkAttrs[.foregroundColor] = theme.colors.linkColor.foreground
                linkAttrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                if let dest = link.destination, let url = URL(string: dest) {
                    linkAttrs[.link] = url
                }
                let linkText = await buildInlineAttributedString(
                    from: link.children,
                    baseAttributes: linkAttrs,
                    constrainedToWidth: maxWidth
                )
                result.append(linkText)

            case let image as ImageNode:
                if let attachment = await ImageAttachmentBuilder.build(from: image, constrainedToWidth: maxWidth) {
                    result.append(attachment)
                } else {
                    var imgAttrs = baseAttributes
                    imgAttrs[.foregroundColor] = Color.platformSecondaryLabel
                    let altText = image.altText ?? image.source ?? "image"
                    result.append(NSAttributedString(string: "[\(altText)]", attributes: imgAttrs))
                }

            case let math as MathNode:
                result.append(await mathAdapter.render(from: math, theme: theme))

            case is EmphasisNode:
                var italicAttrs = baseAttributes
                if let font = baseAttributes[.font] as? Font {
                    italicAttrs[.font] = fontWithTrait(font, trait: .italic)
                }
                result.append(await buildInlineAttributedString(
                    from: child.children,
                    baseAttributes: italicAttrs,
                    constrainedToWidth: maxWidth
                ))

            case is StrongNode:
                var boldAttrs = baseAttributes
                if let font = baseAttributes[.font] as? Font {
                    boldAttrs[.font] = fontWithTrait(font, trait: .bold)
                }
                result.append(await buildInlineAttributedString(
                    from: child.children,
                    baseAttributes: boldAttrs,
                    constrainedToWidth: maxWidth
                ))

            case is StrikethroughNode:
                var strikeAttrs = baseAttributes
                strikeAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(await buildInlineAttributedString(
                    from: child.children,
                    baseAttributes: strikeAttrs,
                    constrainedToWidth: maxWidth
                ))

            default:
                let childResult = await buildInlineAttributedString(
                    from: child.children,
                    baseAttributes: baseAttributes,
                    constrainedToWidth: maxWidth
                )
                if childResult.length > 0 {
                    result.append(childResult)
                }
            }
        }
        return result
    }






}
