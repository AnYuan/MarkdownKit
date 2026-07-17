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
    let theme: Theme
    private let highlighter: SplashHighlighter
    private let diagramRegistry: DiagramAdapterRegistry
    private let mathAdapter: any MathRenderingAdapter
    private let imageLoadingPolicy: ImageLoadingPolicy

    init(
        theme: Theme,
        highlighter: SplashHighlighter,
        diagramRegistry: DiagramAdapterRegistry,
        mathAdapter: any MathRenderingAdapter = DefaultMathRenderingAdapter(),
        imageLoadingPolicy: ImageLoadingPolicy = .default
    ) {
        self.theme = theme
        self.highlighter = highlighter
        self.diagramRegistry = diagramRegistry
        self.mathAdapter = mathAdapter
        self.imageLoadingPolicy = imageLoadingPolicy
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
            string.append(await mathAdapter.render(from: math, theme: theme, contextFont: nil))

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
            let font = theme.typography.paragraph.font
            let listItemCount = list.children.filter { $0 is ListItemNode }.count
            var currentListItemIndex = 0

            for child in list.children {
                guard let item = child as? ListItemNode else { continue }
                currentListItemIndex += 1
                let isLastItem = currentListItemIndex == listItemCount

                if string.length > 0 {
                    string.append(NSAttributedString(string: "\n"))
                }

                let (prefix, isCheckbox) = listItemPrefix(for: list, item: item, oneBasedIndex: currentListItemIndex)
                let prefixWidth = listItemPrefixWidth(prefix, font: font)
                let itemStyle = listItemParagraphStyle(prefixWidth: prefixWidth, isLastItem: isLastItem)
                let listAttrs = listItemBaseAttributes(font: font, style: itemStyle)

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
                        let indentStyle = nestedListParagraphStyle(prefixWidth: prefixWidth)
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
            let quoteStyle = blockQuoteParagraphStyle()

            for child in blockQuote.children {
                if let para = child as? ParagraphNode {
                    let quoteAttrs = blockQuoteContentAttributes(style: quoteStyle)
                    let inlineStr = await buildInlineAttributedString(
                        from: para.children,
                        baseAttributes: quoteAttrs,
                        constrainedToWidth: maxWidth
                    )
                    string.append(blockQuoteBarAttributedString(style: quoteStyle))
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
            #if canImport(UIKit) && !os(watchOS)
            break // Handled by LayoutSolver via customDraw on iOS
            #else
            string.append(buildThematicBreakAttributedString())
            #endif

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
            string.append(mathAdapter.renderSync(from: math, theme: theme, contextFont: nil))

        case let paragraph as ParagraphNode:
            let baseAttrs = defaultAttributes(for: theme.typography.paragraph)
            string.append(buildInlineAttributedStringSync(from: paragraph.children, baseAttributes: baseAttrs))

        case let code as CodeBlockNode:
            string.append(buildCodeBlockAttributedString(from: code))

        case let list as ListNode:
            let font = theme.typography.paragraph.font
            let listItemCount = list.children.filter { $0 is ListItemNode }.count
            var currentListItemIndex = 0
            for child in list.children {
                guard let item = child as? ListItemNode else { continue }
                currentListItemIndex += 1
                let isLastItem = currentListItemIndex == listItemCount
                if string.length > 0 { string.append(NSAttributedString(string: "\n")) }

                let (prefix, _) = listItemPrefix(for: list, item: item, oneBasedIndex: currentListItemIndex)
                let prefixWidth = listItemPrefixWidth(prefix, font: font)
                let itemStyle = listItemParagraphStyle(prefixWidth: prefixWidth, isLastItem: isLastItem)
                let listAttrs = listItemBaseAttributes(font: font, style: itemStyle)

                string.append(NSAttributedString(string: prefix, attributes: listAttrs))
                for itemChild in item.children {
                    if let para = itemChild as? ParagraphNode {
                        string.append(buildInlineAttributedStringSync(from: para.children, baseAttributes: listAttrs))
                    } else if let nestedList = itemChild as? ListNode {
                        string.append(NSAttributedString(string: "\n"))
                        let nestedAttr = NSMutableAttributedString(attributedString: buildStringSync(for: nestedList, constrainedToWidth: maxWidth))
                        let indentStyle = nestedListParagraphStyle(prefixWidth: prefixWidth)
                        nestedAttr.addAttribute(.paragraphStyle, value: indentStyle, range: NSRange(location: 0, length: nestedAttr.length))
                        string.append(nestedAttr)
                    } else {
                        string.append(buildStringSync(for: itemChild, constrainedToWidth: maxWidth))
                    }
                }
            }

        case let blockQuote as BlockQuoteNode:
            let quoteStyle = blockQuoteParagraphStyle()
            for child in blockQuote.children {
                if let para = child as? ParagraphNode {
                    let quoteAttrs = blockQuoteContentAttributes(style: quoteStyle)
                    string.append(blockQuoteBarAttributedString(style: quoteStyle))
                    string.append(buildInlineAttributedStringSync(from: para.children, baseAttributes: quoteAttrs))
                } else {
                    string.append(buildStringSync(for: child, constrainedToWidth: maxWidth))
                }
                if string.length > 0 { string.append(NSAttributedString(string: "\n")) }
            }

        case is ThematicBreakNode:
            #if canImport(UIKit) && !os(watchOS)
            break // Handled by LayoutSolver via customDraw on iOS
            #else
            string.append(buildThematicBreakAttributedString())
            #endif

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
                result.append(NSAttributedString(string: code.code, attributes: inlineCodeAttributes(base: baseAttributes)))
            case let link as LinkNode:
                let linkAttrs = linkAttributes(base: baseAttributes, destination: link.destination)
                result.append(buildInlineAttributedStringSync(from: link.children, baseAttributes: linkAttrs))
            case let emphasis as EmphasisNode:
                result.append(buildInlineAttributedStringSync(from: emphasis.children, baseAttributes: italicAttributes(base: baseAttributes)))
            case let strong as StrongNode:
                result.append(buildInlineAttributedStringSync(from: strong.children, baseAttributes: boldAttributes(base: baseAttributes)))
            case let strikethrough as StrikethroughNode:
                result.append(buildInlineAttributedStringSync(from: strikethrough.children, baseAttributes: strikethroughAttributes(base: baseAttributes)))
            case let image as ImageNode:
                result.append(imageFallbackAttributedString(from: image, baseAttributes: baseAttributes))
            case let math as MathNode:
                let contextFont = baseAttributes[.font] as? Font
                result.append(mathAdapter.renderSync(from: math, theme: theme, contextFont: contextFont))
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
        paragraphStyle.lineBreakMode = .byWordWrapping

        let safeFont = token.font
        return [
            .font: safeFont,
            .paragraphStyle: paragraphStyle,
            .foregroundColor: theme.colors.textColor.foreground
        ]
    }

    // MARK: - Shared attribute helpers (consumed by both async / sync paths)
    //
    // These pure helpers were previously inlined twice — once in
    // `buildString` (async) and once in `buildStringSync` — and kept drifting
    // out of sync between the two paths. Extracting them gives the equivalence
    // tests in `AttributedStringBuilderEquivalenceTests` a single source of
    // truth to guard.

    /// `(prefix, isCheckbox)` for a list item under the current list. The
    /// prefix's measured width feeds `listItemParagraphStyle.headIndent`.
    func listItemPrefix(for list: ListNode, item: ListItemNode, oneBasedIndex: Int) -> (prefix: String, isCheckbox: Bool) {
        switch item.checkbox {
        case .checked:   return (theme.list.checkedCharacter, true)
        case .unchecked: return (theme.list.uncheckedCharacter, true)
        case .none:
            let bullet = list.isOrdered ? "\(oneBasedIndex). " : theme.list.bulletCharacter
            return (bullet, false)
        }
    }

    func listItemPrefixWidth(_ prefix: String, font: Font) -> CGFloat {
        (prefix as NSString).size(withAttributes: [.font: font]).width
    }

    /// Paragraph style for list-item body lines (continuation lines align under
    /// the first character of content, not the bullet). `isLastItem` flips the
    /// trailing paragraph spacing back to the theme's block default so the gap
    /// after the last item matches the surrounding flow.
    func listItemParagraphStyle(prefixWidth: CGFloat, isLastItem: Bool) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
        style.paragraphSpacing = isLastItem ? theme.typography.paragraph.paragraphSpacing : 2
        style.lineBreakMode = .byWordWrapping
        style.headIndent = prefixWidth
        style.firstLineHeadIndent = 0
        return style
    }

    func listItemBaseAttributes(font: Font, style: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .paragraphStyle: style,
            .foregroundColor: theme.colors.textColor.foreground
        ]
    }

    /// Paragraph style applied to a nested list so its bullets align to the
    /// outer item's indent + nested delta.
    func nestedListParagraphStyle(prefixWidth: CGFloat) -> NSMutableParagraphStyle {
        let nestedIndent = prefixWidth + theme.list.nestedIndentDelta
        let style = NSMutableParagraphStyle()
        style.headIndent = nestedIndent
        style.firstLineHeadIndent = nestedIndent - prefixWidth
        style.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
        style.paragraphSpacing = theme.typography.paragraph.paragraphSpacing
        style.lineBreakMode = .byWordWrapping
        return style
    }

    func blockQuoteParagraphStyle() -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = theme.blockQuote.indent
        style.firstLineHeadIndent = theme.blockQuote.indent
        style.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
        style.paragraphSpacing = theme.typography.paragraph.paragraphSpacing
        return style
    }

    /// The leading "┃ " bar that prefixes each block-quote line.
    func blockQuoteBarAttributedString(style: NSParagraphStyle) -> NSAttributedString {
        NSAttributedString(string: theme.blockQuote.barCharacter, attributes: [
            .foregroundColor: theme.colors.blockQuoteColor.foreground,
            .font: theme.typography.paragraph.font,
            .paragraphStyle: style
        ])
    }

    func blockQuoteContentAttributes(style: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        var attrs = defaultAttributes(for: theme.typography.paragraph)
        attrs[.paragraphStyle] = style
        attrs[.foregroundColor] = theme.colors.blockQuoteColor.background
        return attrs
    }

    func inlineCodeAttributes(base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attrs = base
        let baseFont = (base[.font] as? Font) ?? theme.typography.paragraph.font
        attrs[.font] = Font.monospacedSystemFont(
            ofSize: max(theme.codeBlock.inlineCodeMinFontSize, baseFont.pointSize * theme.codeBlock.inlineCodeFontSizeRatio),
            weight: .regular
        )
        attrs[.foregroundColor] = theme.colors.inlineCodeColor.foreground
        attrs[.backgroundColor] = theme.colors.inlineCodeColor.background
        return attrs
    }

    func linkAttributes(base: [NSAttributedString.Key: Any], destination: String?) -> [NSAttributedString.Key: Any] {
        var attrs = base
        attrs[.foregroundColor] = theme.colors.linkColor.foreground
        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        if let dest = destination, let url = URL(string: dest) {
            attrs[.link] = url
        }
        return attrs
    }

    func italicAttributes(base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attrs = base
        if let font = base[.font] as? Font {
            attrs[.font] = FontTraitResolver.adding(.italic, to: font)
        }
        return attrs
    }

    func boldAttributes(base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attrs = base
        if let font = base[.font] as? Font {
            attrs[.font] = FontTraitResolver.adding(.bold, to: font)
        }
        return attrs
    }

    func strikethroughAttributes(base: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var attrs = base
        attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        return attrs
    }
    
    // MARK: - Code Block Helper

    func buildCodeBlockAttributedString(from code: CodeBlockNode) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if let label = normalizedCodeLanguageLabel(from: code.language) {
            let labelStyle = NSMutableParagraphStyle()
            labelStyle.paragraphSpacing = theme.codeBlock.labelParagraphSpacing
            labelStyle.lineHeightMultiple = 1.0

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: theme.codeBlock.labelFont,
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

    // MARK: - Thematic Break Helper (macOS text fallback)

    private func buildThematicBreakAttributedString() -> NSAttributedString {
        let rule = String(repeating: "─", count: 40)
        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = theme.typography.paragraph.paragraphSpacing
        style.lineBreakMode = .byClipping
        let attrs: [NSAttributedString.Key: Any] = [
            .font: theme.typography.paragraph.font,
            .foregroundColor: theme.colors.thematicBreakColor.foreground,
            .paragraphStyle: style
        ]
        return NSAttributedString(string: rule, attributes: attrs)
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

        let disclosure = details.isOpen ? theme.details.openDisclosure : theme.details.closedDisclosure
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
            attrs[.font] = FontTraitResolver.adding(.bold, to: font)
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
                result.append(NSAttributedString(string: code.code, attributes: inlineCodeAttributes(base: baseAttributes)))

            case let link as LinkNode:
                let linkAttrs = linkAttributes(base: baseAttributes, destination: link.destination)
                let linkText = await buildInlineAttributedString(
                    from: link.children,
                    baseAttributes: linkAttrs,
                    constrainedToWidth: maxWidth
                )
                result.append(linkText)

            case let image as ImageNode:
                if let attachment = await ImageAttachmentBuilder.build(
                    from: image,
                    constrainedToWidth: maxWidth,
                    imageLoadingPolicy: imageLoadingPolicy
                ) {
                    result.append(attachment)
                } else {
                    result.append(imageFallbackAttributedString(
                        from: image,
                        baseAttributes: baseAttributes
                    ))
                }

            case let math as MathNode:
                let contextFont = baseAttributes[.font] as? Font
                result.append(await mathAdapter.render(from: math, theme: theme, contextFont: contextFont))

            case is EmphasisNode:
                result.append(await buildInlineAttributedString(
                    from: child.children,
                    baseAttributes: italicAttributes(base: baseAttributes),
                    constrainedToWidth: maxWidth
                ))

            case is StrongNode:
                result.append(await buildInlineAttributedString(
                    from: child.children,
                    baseAttributes: boldAttributes(base: baseAttributes),
                    constrainedToWidth: maxWidth
                ))

            case is StrikethroughNode:
                result.append(await buildInlineAttributedString(
                    from: child.children,
                    baseAttributes: strikethroughAttributes(base: baseAttributes),
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

    private func imageFallbackAttributedString(
        from image: ImageNode,
        baseAttributes: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        var attributes = baseAttributes
        attributes[.foregroundColor] = Color.platformSecondaryLabel
        let altText = image.altText ?? image.source ?? "image"
        return NSAttributedString(string: "[\(altText)]", attributes: attributes)
    }
}
