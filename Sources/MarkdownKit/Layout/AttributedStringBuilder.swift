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
    private let appearance: MarkdownAppearance
    private let secondaryLabelColor: Color

    private typealias Attributes = [NSAttributedString.Key: Any]

    private enum ResourceLeaf {
        case image(ImageNode, baseAttributes: Attributes)
        case math(MathNode, contextFont: Font?)
        case diagram(DiagramNode)
    }

    private enum AsyncCancellationPolicy {
        case total
        case cooperative

        var shouldCancel: Bool {
            switch self {
            case .total:
                return false
            case .cooperative:
                return Task.isCancelled
            }
        }
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

    /// The LIFO stack advances one child at a time so cancellable planning has a
    /// bounded checkpoint. Helpers enqueue the continuation before current work.
    private enum PlanningWork {
        case block(MarkdownNode)
        case inline([MarkdownNode], index: Int, baseAttributes: Attributes)
        case detailsChildren([MarkdownNode], index: Int)
        case blockQuoteChildren([MarkdownNode], index: Int, style: NSParagraphStyle)
        case countListItems(ListNode, childIndex: Int, count: Int)
        case listChildren(
            ListNode,
            childIndex: Int,
            itemIndex: Int,
            itemCount: Int,
            font: Font
        )
        case listItemChildren(
            [MarkdownNode],
            index: Int,
            baseAttributes: Attributes,
            prefixWidth: CGFloat
        )
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
        imageLoadingPolicy: ImageLoadingPolicy = .default,
        appearance: MarkdownAppearance
    ) {
        self.theme = theme
        self.highlighter = highlighter
        self.diagramRegistry = diagramRegistry
        self.mathAdapter = mathAdapter
        self.imageLoadingPolicy = imageLoadingPolicy
        self.appearance = appearance
        self.secondaryLabelColor = AppearanceColorResolver.resolveColor(
            .platformSecondaryLabel,
            for: appearance
        )
    }

    func buildString(for node: MarkdownNode, constrainedToWidth maxWidth: CGFloat) async -> NSAttributedString {
        let operations = makeRenderOperations(for: node)
        return await materialize(operations, constrainedToWidth: maxWidth)
    }

    func buildStringCancellable(
        for node: MarkdownNode,
        constrainedToWidth maxWidth: CGFloat,
        cooperation: inout LayoutCooperationState
    ) async -> NSAttributedString? {
        guard let operations = await makeRenderOperationsCancellable(
            for: node,
            cooperation: &cooperation
        ) else {
            return nil
        }
        return await materializeCancellable(
            operations,
            constrainedToWidth: maxWidth,
            cooperation: &cooperation
        )
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
            processPlanningWork(current, work: &work, operations: &operations)
        }

        return operations
    }

    private func makeRenderOperationsCancellable(
        for node: MarkdownNode,
        cooperation: inout LayoutCooperationState
    ) async -> [RenderOperation]? {
        var operations: [RenderOperation] = []
        var work: [PlanningWork] = [.block(node)]

        while let current = work.popLast() {
            guard !Task.isCancelled else { return nil }
            if cooperation.shouldYield(after: .planning) {
                await Task<Never, Never>.yield()
                guard !Task.isCancelled else { return nil }
            }
            processPlanningWork(current, work: &work, operations: &operations)
        }

        guard !Task.isCancelled else { return nil }
        return operations
    }

    private func processPlanningWork(
        _ current: PlanningWork,
        work: inout [PlanningWork],
        operations: inout [RenderOperation]
    ) {
        switch current {
        case let .block(node):
            enqueueBlock(node, onto: &work)

        case let .inline(children, index, baseAttributes):
            enqueueInline(
                children,
                index: index,
                baseAttributes: baseAttributes,
                onto: &work
            )

        case let .detailsChildren(children, index):
            enqueueDetailsChild(children, index: index, onto: &work)

        case let .blockQuoteChildren(children, index, style):
            enqueueBlockQuoteChild(
                children,
                index: index,
                style: style,
                onto: &work
            )

        case let .countListItems(list, childIndex, count):
            enqueueListItemCount(
                list,
                childIndex: childIndex,
                count: count,
                onto: &work
            )

        case let .listChildren(list, childIndex, itemIndex, itemCount, font):
            enqueueListChild(
                list,
                childIndex: childIndex,
                itemIndex: itemIndex,
                itemCount: itemCount,
                font: font,
                onto: &work
            )

        case let .listItemChildren(children, index, baseAttributes, prefixWidth):
            enqueueListItemChild(
                children,
                index: index,
                baseAttributes: baseAttributes,
                prefixWidth: prefixWidth,
                onto: &work
            )

        case let .operation(operation):
            operations.append(operation)
        }
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
                    index: 0,
                    baseAttributes: summaryAttributes
                ))
            } else {
                detailsWork.append(.operation(.staticLeaf(.text(
                    "Details",
                    attributes: summaryAttributes
                ))))
            }

            if details.isOpen {
                if !details.children.isEmpty {
                    detailsWork.append(.detailsChildren(details.children, index: 0))
                }
            }
            orderedWork = detailsWork

        case let summary as SummaryNode:
            orderedWork = [
                .inline(
                    summary.children,
                    index: 0,
                    baseAttributes: detailsSummaryAttributes()
                )
            ]

        case let header as HeaderNode:
            let token = themeToken(forHeaderLevel: header.level)
            orderedWork = [
                .inline(
                    header.children,
                    index: 0,
                    baseAttributes: defaultAttributes(for: token)
                )
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
                    index: 0,
                    baseAttributes: defaultAttributes(for: theme.typography.paragraph)
                )
            ]

        case let code as CodeBlockNode:
            orderedWork = [
                .operation(.staticLeaf(.codeBlock(code)))
            ]

        case let list as ListNode:
            orderedWork = [
                .countListItems(list, childIndex: 0, count: 0)
            ]

        case is ListItemNode:
            orderedWork = []

        case let blockQuote as BlockQuoteNode:
            let quoteStyle = blockQuoteParagraphStyle()
            orderedWork = blockQuote.children.isEmpty
                ? []
                : [.blockQuoteChildren(blockQuote.children, index: 0, style: quoteStyle)]

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

    private func enqueueInline(
        _ children: [MarkdownNode],
        index: Int,
        baseAttributes: Attributes,
        onto work: inout [PlanningWork]
    ) {
        guard children.indices.contains(index) else { return }
        if children.indices.contains(index + 1) {
            work.append(.inline(
                children,
                index: index + 1,
                baseAttributes: baseAttributes
            ))
        }

        let child = children[index]
        switch child {
        case let text as TextNode:
            work.append(.operation(.staticLeaf(.text(
                text.text,
                attributes: baseAttributes
            ))))

        case let code as InlineCodeNode:
            work.append(.operation(.staticLeaf(.text(
                code.code,
                attributes: inlineCodeAttributes(base: baseAttributes)
            ))))

        case let link as LinkNode:
            work.append(.inline(
                link.children,
                index: 0,
                baseAttributes: linkAttributes(
                    base: baseAttributes,
                    destination: link.destination
                )
            ))

        case let image as ImageNode:
            work.append(.operation(.resource(.image(
                image,
                baseAttributes: baseAttributes
            ))))

        case let math as MathNode:
            work.append(.operation(.resource(.math(
                math,
                contextFont: baseAttributes[.font] as? Font
            ))))

        case is EmphasisNode:
            work.append(.inline(
                child.children,
                index: 0,
                baseAttributes: italicAttributes(base: baseAttributes)
            ))

        case is StrongNode:
            work.append(.inline(
                child.children,
                index: 0,
                baseAttributes: boldAttributes(base: baseAttributes)
            ))

        case is StrikethroughNode:
            work.append(.inline(
                child.children,
                index: 0,
                baseAttributes: strikethroughAttributes(base: baseAttributes)
            ))

        default:
            guard child is any InlineNode else { return }
            work.append(.inline(
                child.children,
                index: 0,
                baseAttributes: baseAttributes
            ))
        }
    }

    private func enqueueDetailsChild(
        _ children: [MarkdownNode],
        index: Int,
        onto work: inout [PlanningWork]
    ) {
        guard children.indices.contains(index) else { return }
        if children.indices.contains(index + 1) {
            work.append(.detailsChildren(children, index: index + 1))
        }
        work.append(.operation(.endCapture))
        work.append(.block(children[index]))
        work.append(.operation(.beginCapture(.appendIfNotEmpty(prefix: "\n"))))
    }

    private func enqueueBlockQuoteChild(
        _ children: [MarkdownNode],
        index: Int,
        style: NSParagraphStyle,
        onto work: inout [PlanningWork]
    ) {
        guard children.indices.contains(index) else { return }
        if children.indices.contains(index + 1) {
            work.append(.blockQuoteChildren(children, index: index + 1, style: style))
        }
        work.append(.operation(.appendNewlineIfOutputNotEmpty))

        let child = children[index]
        if let paragraph = child as? ParagraphNode {
            work.append(.inline(
                paragraph.children,
                index: 0,
                baseAttributes: blockQuoteContentAttributes(style: style)
            ))
            work.append(.operation(.staticLeaf(.blockQuoteBar(style))))
        } else {
            work.append(.operation(.endCapture))
            work.append(.block(child))
            work.append(.operation(.beginCapture(.append)))
        }
    }

    private func enqueueListItemCount(
        _ list: ListNode,
        childIndex: Int,
        count: Int,
        onto work: inout [PlanningWork]
    ) {
        guard list.children.indices.contains(childIndex) else {
            if count > 0 {
                work.append(.listChildren(
                    list,
                    childIndex: 0,
                    itemIndex: 0,
                    itemCount: count,
                    font: theme.typography.paragraph.font
                ))
            }
            return
        }

        let nextCount = count + (list.children[childIndex] is ListItemNode ? 1 : 0)
        work.append(.countListItems(
            list,
            childIndex: childIndex + 1,
            count: nextCount
        ))
    }

    private func enqueueListChild(
        _ list: ListNode,
        childIndex: Int,
        itemIndex: Int,
        itemCount: Int,
        font: Font,
        onto work: inout [PlanningWork]
    ) {
        guard list.children.indices.contains(childIndex) else { return }

        let item = list.children[childIndex] as? ListItemNode
        if list.children.indices.contains(childIndex + 1) {
            work.append(.listChildren(
                list,
                childIndex: childIndex + 1,
                itemIndex: itemIndex + (item == nil ? 0 : 1),
                itemCount: itemCount,
                font: font
            ))
        }

        guard let item else { return }
        let oneBasedIndex = itemIndex + 1
        let (prefix, isCheckbox) = listItemPrefix(
            for: list,
            item: item,
            oneBasedIndex: oneBasedIndex
        )
        let prefixWidth = listItemPrefixWidth(prefix, font: font)
        let itemStyle = listItemParagraphStyle(
            prefixWidth: prefixWidth,
            isLastItem: oneBasedIndex == itemCount
        )
        let listAttributes = listItemBaseAttributes(font: font, style: itemStyle)
        var prefixAttributes = listAttributes
        if isCheckbox, let range = item.range {
            prefixAttributes[.markdownCheckbox] = CheckboxInteractionData(
                isChecked: item.checkbox == .checked,
                range: range
            )
        }

        if !item.children.isEmpty {
            work.append(.listItemChildren(
                item.children,
                index: 0,
                baseAttributes: listAttributes,
                prefixWidth: prefixWidth
            ))
        }
        work.append(.operation(.staticLeaf(.text(
            prefix,
            attributes: prefixAttributes
        ))))
        work.append(.operation(.appendNewlineIfOutputNotEmpty))
    }

    private func enqueueListItemChild(
        _ children: [MarkdownNode],
        index: Int,
        baseAttributes: Attributes,
        prefixWidth: CGFloat,
        onto work: inout [PlanningWork]
    ) {
        guard children.indices.contains(index) else { return }
        if children.indices.contains(index + 1) {
            work.append(.listItemChildren(
                children,
                index: index + 1,
                baseAttributes: baseAttributes,
                prefixWidth: prefixWidth
            ))
        }

        let child = children[index]
        if let paragraph = child as? ParagraphNode {
            work.append(.inline(
                paragraph.children,
                index: 0,
                baseAttributes: baseAttributes
            ))
        } else if let nestedList = child as? ListNode {
            work.append(.operation(.endCapture))
            work.append(.block(nestedList))
            work.append(.operation(.beginCapture(
                .paragraphStyle(nestedListParagraphStyle(prefixWidth: prefixWidth))
            )))
            work.append(.operation(.staticLeaf(.text("\n", attributes: [:]))))
        } else {
            work.append(.operation(.endCapture))
            work.append(.block(child))
            work.append(.operation(.beginCapture(.append)))
        }
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
                guard let rendered = await materialize(
                    resource,
                    constrainedToWidth: maxWidth,
                    cancellationPolicy: .total
                ) else {
                    preconditionFailure("Total materialization unexpectedly canceled")
                }
                state.append(rendered)
            }
        }

        return state.finish()
    }

    private func materializeCancellable(
        _ operations: [RenderOperation],
        constrainedToWidth maxWidth: CGFloat,
        cooperation: inout LayoutCooperationState
    ) async -> NSAttributedString? {
        var state = MaterializationState()

        for operation in operations {
            guard !Task.isCancelled else { return nil }
            if cooperation.shouldYield(after: .materialization) {
                await Task<Never, Never>.yield()
                guard !Task.isCancelled else { return nil }
            }
            let action = state.apply(operation)

            switch action {
            case .handled:
                continue

            case let .staticLeaf(leaf):
                guard !Task.isCancelled else { return nil }
                let attributedString = makeAttributedString(
                    for: leaf,
                    constrainedToWidth: maxWidth
                )
                guard !Task.isCancelled else { return nil }
                state.append(attributedString)

            case let .resource(resource):
                guard !Task.isCancelled else { return nil }
                guard let rendered = await materialize(
                    resource,
                    constrainedToWidth: maxWidth,
                    cancellationPolicy: .cooperative
                ) else { return nil }
                guard !Task.isCancelled else { return nil }
                state.append(rendered)
            }
        }

        guard !Task.isCancelled else { return nil }
        return state.finish()
    }

    private func materialize(
        _ resource: ResourceLeaf,
        constrainedToWidth maxWidth: CGFloat,
        cancellationPolicy: AsyncCancellationPolicy
    ) async -> NSAttributedString? {
        guard !cancellationPolicy.shouldCancel else { return nil }

        switch resource {
        case let .image(image, baseAttributes):
            let attachment = await ImageAttachmentBuilder.build(
                from: image,
                constrainedToWidth: maxWidth,
                imageLoadingPolicy: imageLoadingPolicy
            )
            guard !cancellationPolicy.shouldCancel else { return nil }
            if let attachment {
                return attachment
            }
            let fallback = imageFallbackAttributedString(
                from: image,
                baseAttributes: baseAttributes
            )
            guard !cancellationPolicy.shouldCancel else { return nil }
            return fallback

        case let .math(math, contextFont):
            let rendered = await mathAdapter.render(
                from: math,
                theme: theme,
                contextFont: contextFont
            )
            guard !cancellationPolicy.shouldCancel else { return nil }
            let resolved = resolveAdapterColors(in: rendered)
            guard !cancellationPolicy.shouldCancel else { return nil }
            return resolved

        case let .diagram(diagram):
            return await buildDiagramAttributedString(
                from: diagram,
                cancellationPolicy: cancellationPolicy
            )
        }
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
                    let rendered = mathAdapter.renderSync(
                        from: math,
                        theme: theme,
                        contextFont: contextFont
                    )
                    state.append(resolveAdapterColors(in: rendered))

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
                .foregroundColor: secondaryLabelColor,
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
        guard let rendered = await buildDiagramAttributedString(
            from: diagram,
            cancellationPolicy: .total
        ) else {
            preconditionFailure("Total diagram materialization unexpectedly canceled")
        }
        return rendered
    }

    func buildDiagramAttributedStringCancellable(
        from diagram: DiagramNode
    ) async -> NSAttributedString? {
        await buildDiagramAttributedString(
            from: diagram,
            cancellationPolicy: .cooperative
        )
    }

    private func buildDiagramAttributedString(
        from diagram: DiagramNode,
        cancellationPolicy: AsyncCancellationPolicy
    ) async -> NSAttributedString? {
        guard !cancellationPolicy.shouldCancel else { return nil }

        if let adapter = diagramRegistry.adapter(for: diagram.language) {
            let rendered = await adapter.render(
                source: diagram.source,
                language: diagram.language
            )
            guard !cancellationPolicy.shouldCancel else { return nil }
            if let rendered {
                let resolved = resolveAdapterColors(in: rendered)
                guard !cancellationPolicy.shouldCancel else { return nil }
                return resolved
            }
        }

        guard !cancellationPolicy.shouldCancel else { return nil }
        let fallback = CodeBlockNode(
            range: diagram.range,
            language: diagram.language.rawValue,
            code: diagram.source
        )
        let rendered = buildCodeBlockAttributedString(from: fallback)
        guard !cancellationPolicy.shouldCancel else { return nil }
        return rendered
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
        attributes[.foregroundColor] = secondaryLabelColor
        let altText = image.altText ?? image.source ?? "image"
        return NSAttributedString(string: "[\(altText)]", attributes: attributes)
    }

    private func resolveAdapterColors(in attributedString: NSAttributedString) -> NSAttributedString {
        AppearanceColorResolver.resolveColors(in: attributedString, for: appearance)
    }
}
