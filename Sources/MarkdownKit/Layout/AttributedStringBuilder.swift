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

    private typealias Attributes = [NSAttributedString.Key: Any]

    private enum ResourceLeaf {
        case image(ImageNode, baseAttributes: Attributes)
        case math(MathNode, contextFont: Font?)
        case diagram(DiagramNode)
    }

    private enum StaticLeaf {
        case text(String, attributes: Attributes)
        case table(TableNode)
        case codeBlock(CodeBlockNode)
        case blockQuoteBar(NSParagraphStyle)
        case thematicBreak
    }

    private enum CaptureDisposition {
        case append
        case appendIfNotEmpty(prefix: String)
        case paragraphStyle(NSParagraphStyle)
    }

    private enum RenderOperation {
        case staticLeaf(StaticLeaf)
        case resource(ResourceLeaf)
        case beginCapture(CaptureDisposition)
        case endCapture
        case appendNewlineIfOutputNotEmpty
    }

    private enum MaterializationAction {
        case handled
        case staticLeaf(StaticLeaf)
        case resource(ResourceLeaf)
    }

    private enum PlanningWork {
        case block(MarkdownNode)
        case inline([MarkdownNode], baseAttributes: Attributes)
        case operation(RenderOperation)
    }

    private struct CaptureFrame {
        let string = NSMutableAttributedString()
        let disposition: CaptureDisposition
    }

    private struct MaterializationState {
        private let output = NSMutableAttributedString()
        private var captures: [CaptureFrame] = []

        func finish() -> NSAttributedString {
            precondition(captures.isEmpty, "Render program ended with unclosed captures")
            return output
        }

        mutating func apply(_ operation: RenderOperation) -> MaterializationAction {
            switch operation {
            case let .staticLeaf(leaf):
                return .staticLeaf(leaf)

            case let .resource(resource):
                return .resource(resource)

            case let .beginCapture(disposition):
                captures.append(CaptureFrame(disposition: disposition))

            case .endCapture:
                precondition(
                    !captures.isEmpty,
                    "Render program ended a capture without a matching begin"
                )
                let capture = captures.removeLast()
                switch capture.disposition {
                case .append:
                    append(capture.string)

                case let .appendIfNotEmpty(prefix):
                    if capture.string.length > 0 {
                        append(NSAttributedString(string: prefix))
                        append(capture.string)
                    }

                case let .paragraphStyle(style):
                    let transformed = NSMutableAttributedString(attributedString: capture.string)
                    if transformed.length > 0 {
                        transformed.addAttribute(
                            .paragraphStyle,
                            value: style,
                            range: NSRange(location: 0, length: transformed.length)
                        )
                    }
                    append(transformed)
                }

            case .appendNewlineIfOutputNotEmpty:
                if currentLength > 0 {
                    append(NSAttributedString(string: "\n"))
                }
            }
            return .handled
        }

        mutating func append(_ string: NSAttributedString) {
            if let capture = captures.last {
                capture.string.append(string)
            } else {
                output.append(string)
            }
        }

        private var currentLength: Int {
            captures.last?.string.length ?? output.length
        }
    }

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
        let operations = makeRenderOperations(for: node)
        return await materialize(operations, constrainedToWidth: maxWidth)
    }

    // MARK: - Synchronous Build (no Swift concurrency)

    /// Builds an attributed string synchronously, without any async calls.
    /// Math nodes render as fallback text, images render as alt text, diagrams are skipped.
    func buildStringSync(for node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) -> NSAttributedString {
        let operations = makeRenderOperations(for: node)
        return materializeSync(operations, constrainedToWidth: maxWidth)
    }

    private func makeRenderOperations(for node: MarkdownNode) -> [RenderOperation] {
        var operations: [RenderOperation] = []
        var work: [PlanningWork] = [.block(node)]

        while let current = work.popLast() {
            switch current {
            case let .block(node):
                enqueueBlock(node, onto: &work)

            case let .inline(children, baseAttributes):
                enqueueInline(children, baseAttributes: baseAttributes, onto: &work)

            case let .operation(operation):
                operations.append(operation)
            }
        }

        return operations
    }

    private func enqueueBlock(
        _ node: MarkdownNode,
        onto work: inout [PlanningWork]
    ) {
        let orderedWork: [PlanningWork]

        switch node {
        case let table as TableNode:
            orderedWork = [
                .operation(.staticLeaf(.table(table)))
            ]

        case let diagram as DiagramNode:
            orderedWork = [.operation(.resource(.diagram(diagram)))]

        case let details as DetailsNode:
            var detailsWork: [PlanningWork] = []
            let summaryAttributes = detailsSummaryAttributes()
            let disclosure = details.isOpen
                ? theme.details.openDisclosure
                : theme.details.closedDisclosure
            detailsWork.append(.operation(.staticLeaf(.text(
                disclosure,
                attributes: summaryAttributes
            ))))

            if let summary = details.summary, !summary.children.isEmpty {
                detailsWork.append(.inline(
                    summary.children,
                    baseAttributes: summaryAttributes
                ))
            } else {
                detailsWork.append(.operation(.staticLeaf(.text(
                    "Details",
                    attributes: summaryAttributes
                ))))
            }

            if details.isOpen {
                for child in details.children {
                    detailsWork.append(.operation(.beginCapture(
                        .appendIfNotEmpty(prefix: "\n")
                    )))
                    detailsWork.append(.block(child))
                    detailsWork.append(.operation(.endCapture))
                }
            }
            orderedWork = detailsWork

        case let summary as SummaryNode:
            orderedWork = [
                .inline(summary.children, baseAttributes: detailsSummaryAttributes())
            ]

        case let header as HeaderNode:
            let token = themeToken(forHeaderLevel: header.level)
            orderedWork = [
                .inline(header.children, baseAttributes: defaultAttributes(for: token))
            ]

        case let text as TextNode:
            orderedWork = [
                .operation(.staticLeaf(.text(
                    text.text,
                    attributes: defaultAttributes(for: theme.typography.paragraph)
                )))
            ]

        case let math as MathNode:
            orderedWork = [.operation(.resource(.math(math, contextFont: nil)))]

        case let paragraph as ParagraphNode:
            orderedWork = [
                .inline(
                    paragraph.children,
                    baseAttributes: defaultAttributes(for: theme.typography.paragraph)
                )
            ]

        case let code as CodeBlockNode:
            orderedWork = [
                .operation(.staticLeaf(.codeBlock(code)))
            ]

        case let list as ListNode:
            orderedWork = planningWork(for: list)

        case is ListItemNode:
            orderedWork = []

        case let blockQuote as BlockQuoteNode:
            let quoteStyle = blockQuoteParagraphStyle()
            var quoteWork: [PlanningWork] = []
            for child in blockQuote.children {
                if let paragraph = child as? ParagraphNode {
                    quoteWork.append(.operation(.staticLeaf(.blockQuoteBar(quoteStyle))))
                    quoteWork.append(.inline(
                        paragraph.children,
                        baseAttributes: blockQuoteContentAttributes(style: quoteStyle)
                    ))
                } else {
                    quoteWork.append(.operation(.beginCapture(.append)))
                    quoteWork.append(.block(child))
                    quoteWork.append(.operation(.endCapture))
                }
                quoteWork.append(.operation(.appendNewlineIfOutputNotEmpty))
            }
            orderedWork = quoteWork

        case is ThematicBreakNode:
            #if canImport(UIKit) && !os(watchOS)
            orderedWork = []
            #else
            orderedWork = [
                .operation(.staticLeaf(.thematicBreak))
            ]
            #endif

        default:
            orderedWork = []
        }

        work.append(contentsOf: orderedWork.reversed())
    }

    private func planningWork(for list: ListNode) -> [PlanningWork] {
        let font = theme.typography.paragraph.font
        let items = list.children.compactMap { $0 as? ListItemNode }
        var orderedWork: [PlanningWork] = []

        for (offset, item) in items.enumerated() {
            let oneBasedIndex = offset + 1
            let isLastItem = oneBasedIndex == items.count
            let (prefix, isCheckbox) = listItemPrefix(
                for: list,
                item: item,
                oneBasedIndex: oneBasedIndex
            )
            let prefixWidth = listItemPrefixWidth(prefix, font: font)
            let itemStyle = listItemParagraphStyle(
                prefixWidth: prefixWidth,
                isLastItem: isLastItem
            )
            let listAttributes = listItemBaseAttributes(font: font, style: itemStyle)
            var prefixAttributes = listAttributes
            if isCheckbox, let range = item.range {
                prefixAttributes[.markdownCheckbox] = CheckboxInteractionData(
                    isChecked: item.checkbox == .checked,
                    range: range
                )
            }

            orderedWork.append(.operation(.appendNewlineIfOutputNotEmpty))
            orderedWork.append(.operation(.staticLeaf(.text(
                prefix,
                attributes: prefixAttributes
            ))))

            for child in item.children {
                if let paragraph = child as? ParagraphNode {
                    orderedWork.append(.inline(
                        paragraph.children,
                        baseAttributes: listAttributes
                    ))
                } else if let nestedList = child as? ListNode {
                    orderedWork.append(.operation(.staticLeaf(.text("\n", attributes: [:]))))
                    orderedWork.append(.operation(.beginCapture(
                        .paragraphStyle(nestedListParagraphStyle(prefixWidth: prefixWidth))
                    )))
                    orderedWork.append(.block(nestedList))
                    orderedWork.append(.operation(.endCapture))
                } else {
                    orderedWork.append(.operation(.beginCapture(.append)))
                    orderedWork.append(.block(child))
                    orderedWork.append(.operation(.endCapture))
                }
            }
        }

        return orderedWork
    }

    private func enqueueInline(
        _ children: [MarkdownNode],
        baseAttributes: Attributes,
        onto work: inout [PlanningWork]
    ) {
        var orderedWork: [PlanningWork] = []

        for child in children {
            switch child {
            case let text as TextNode:
                orderedWork.append(.operation(.staticLeaf(.text(
                    text.text,
                    attributes: baseAttributes
                ))))

            case let code as InlineCodeNode:
                orderedWork.append(.operation(.staticLeaf(.text(
                    code.code,
                    attributes: inlineCodeAttributes(base: baseAttributes)
                ))))

            case let link as LinkNode:
                orderedWork.append(.inline(
                    link.children,
                    baseAttributes: linkAttributes(
                        base: baseAttributes,
                        destination: link.destination
                    )
                ))

            case let image as ImageNode:
                orderedWork.append(.operation(.resource(.image(
                    image,
                    baseAttributes: baseAttributes
                ))))

            case let math as MathNode:
                orderedWork.append(.operation(.resource(.math(
                    math,
                    contextFont: baseAttributes[.font] as? Font
                ))))

            case is EmphasisNode:
                orderedWork.append(.inline(
                    child.children,
                    baseAttributes: italicAttributes(base: baseAttributes)
                ))

            case is StrongNode:
                orderedWork.append(.inline(
                    child.children,
                    baseAttributes: boldAttributes(base: baseAttributes)
                ))

            case is StrikethroughNode:
                orderedWork.append(.inline(
                    child.children,
                    baseAttributes: strikethroughAttributes(base: baseAttributes)
                ))

            default:
                guard child is any InlineNode else { continue }
                orderedWork.append(.inline(
                    child.children,
                    baseAttributes: baseAttributes
                ))
            }
        }

        work.append(contentsOf: orderedWork.reversed())
    }

    private func materialize(
        _ operations: [RenderOperation],
        constrainedToWidth maxWidth: CGFloat
    ) async -> NSAttributedString {
        var state = MaterializationState()

        for operation in operations {
            switch state.apply(operation) {
            case .handled:
                continue

            case let .staticLeaf(leaf):
                state.append(makeAttributedString(
                    for: leaf,
                    constrainedToWidth: maxWidth
                ))

            case let .resource(resource):
                switch resource {
                case let .image(image, baseAttributes):
                    if let attachment = await ImageAttachmentBuilder.build(
                        from: image,
                        constrainedToWidth: maxWidth,
                        imageLoadingPolicy: imageLoadingPolicy
                    ) {
                        state.append(attachment)
                    } else {
                        state.append(imageFallbackAttributedString(
                            from: image,
                            baseAttributes: baseAttributes
                        ))
                    }

                case let .math(math, contextFont):
                    state.append(await mathAdapter.render(
                        from: math,
                        theme: theme,
                        contextFont: contextFont
                    ))

                case let .diagram(diagram):
                    state.append(await buildDiagramAttributedString(from: diagram))
                }
            }
        }

        return state.finish()
    }

    private func materializeSync(
        _ operations: [RenderOperation],
        constrainedToWidth maxWidth: CGFloat
    ) -> NSAttributedString {
        var state = MaterializationState()

        for operation in operations {
            switch state.apply(operation) {
            case .handled:
                continue

            case let .staticLeaf(leaf):
                state.append(makeAttributedString(
                    for: leaf,
                    constrainedToWidth: maxWidth
                ))

            case let .resource(resource):
                switch resource {
                case let .image(image, baseAttributes):
                    state.append(imageFallbackAttributedString(
                        from: image,
                        baseAttributes: baseAttributes
                    ))

                case let .math(math, contextFont):
                    state.append(mathAdapter.renderSync(
                        from: math,
                        theme: theme,
                        contextFont: contextFont
                    ))

                case .diagram:
                    continue
                }
            }
        }

        return state.finish()
    }

    private func makeAttributedString(
        for leaf: StaticLeaf,
        constrainedToWidth maxWidth: CGFloat
    ) -> NSAttributedString {
        switch leaf {
        case let .text(text, attributes):
            NSAttributedString(string: text, attributes: attributes)
        case let .table(table):
            TableAttributedStringBuilder.build(
                from: table,
                theme: theme,
                constrainedToWidth: maxWidth
            )
        case let .codeBlock(codeBlock):
            buildCodeBlockAttributedString(from: codeBlock)
        case let .blockQuoteBar(style):
            blockQuoteBarAttributedString(style: style)
        case .thematicBreak:
            buildThematicBreakAttributedString()
        }
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

    private func detailsSummaryAttributes() -> [NSAttributedString.Key: Any] {
        var attrs = defaultAttributes(for: theme.typography.paragraph)
        if let font = attrs[.font] as? Font {
            attrs[.font] = FontTraitResolver.adding(.bold, to: font)
        }
        return attrs
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
