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
    private let diagramRegistry: DiagramAdapterRegistry
    
    public init(
        theme: Theme = .default,
        cache: LayoutCache = LayoutCache(),
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry()
    ) {
        self.theme = theme
        self.textCalculator = TextKitCalculator()
        self.cache = cache
        self.highlighter = SplashHighlighter(theme: theme)
        self.diagramRegistry = diagramRegistry
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
            string.append(buildTableAttributedString(from: table))

        case let diagram as DiagramNode:
            string.append(await buildDiagramAttributedString(from: diagram))

        case let details as DetailsNode:
            string.append(await buildDetailsAttributedString(from: details, constrainedToWidth: maxWidth))

        case let summary as SummaryNode:
            let baseAttrs = detailsSummaryAttributes()
            string.append(await buildInlineAttributedString(from: summary.children, baseAttributes: baseAttrs))
            
        case let header as HeaderNode:
            let token = themeToken(forHeaderLevel: header.level)
            let baseAttrs = defaultAttributes(for: token)
            string.append(await buildInlineAttributedString(from: header.children, baseAttributes: baseAttrs))
            
        case let text as TextNode:
            let attributes = defaultAttributes(for: theme.paragraph)
            string.append(NSAttributedString(string: text.text, attributes: attributes))
            
        case let math as MathNode:
            // Suspend while MathJaxSwift converts TeX to SVG and the renderer rasterizes attachment image
            if let image = await renderMath(latex: math.equation, display: !math.isInline) {
                let attachment = NSTextAttachment()
                #if canImport(UIKit)
                attachment.image = image
                #elseif canImport(AppKit)
                attachment.image = image
                #endif

                // Align inline math vertically with surrounding text metrics.
                attachment.bounds = attachmentBounds(
                    for: image.size,
                    isInline: math.isInline,
                    font: theme.paragraph.font
                )

                let attrString = NSAttributedString(attachment: attachment)
                string.append(attrString)
            } else {
                // Fallback to raw text if conversion/rasterization fails.
                let attr = defaultAttributes(for: theme.codeBlock)
                string.append(NSAttributedString(string: math.equation, attributes: attr))
            }
            
        case let paragraph as ParagraphNode:
            let baseAttrs = defaultAttributes(for: theme.paragraph)
            string.append(await buildInlineAttributedString(from: paragraph.children, baseAttributes: baseAttrs))
            
        case let code as CodeBlockNode:
            string.append(buildCodeBlockAttributedString(from: code))
            
        case let list as ListNode:
            let compactStyle = NSMutableParagraphStyle()
            compactStyle.lineHeightMultiple = theme.paragraph.lineHeightMultiple
            compactStyle.paragraphSpacing = 4

            let listAttrs: [NSAttributedString.Key: Any] = [
                .font: theme.paragraph.font,
                .paragraphStyle: compactStyle,
                .foregroundColor: theme.textColor.foreground
            ]

            for (itemIndex, child) in list.children.enumerated() {
                guard let item = child as? ListItemNode else { continue }

                if string.length > 0 {
                    string.append(NSAttributedString(string: "\n"))
                }

                // Determine prefix: checkbox > ordered number > bullet
                var prefix: String
                switch item.checkbox {
                case .checked: prefix = "☑ "
                case .unchecked: prefix = "☐ "
                case .none:
                    prefix = list.isOrdered ? "\(itemIndex + 1). " : "• "
                }
                string.append(NSAttributedString(string: prefix, attributes: listAttrs))

                // Render item content
                for itemChild in item.children {
                    if let para = itemChild as? ParagraphNode {
                        string.append(await buildInlineAttributedString(from: para.children, baseAttributes: listAttrs))
                    } else if let nestedList = itemChild as? ListNode {
                        let nestedAttr = await createAttributedString(for: nestedList, constrainedToWidth: maxWidth)
                        string.append(NSAttributedString(string: "\n"))
                        let indented = NSMutableAttributedString(attributedString: nestedAttr)
                        let indentStyle = NSMutableParagraphStyle()
                        indentStyle.headIndent = 20
                        indentStyle.firstLineHeadIndent = 20
                        indentStyle.lineHeightMultiple = theme.paragraph.lineHeightMultiple
                        indentStyle.paragraphSpacing = 4
                        indented.addAttribute(.paragraphStyle, value: indentStyle, range: NSRange(location: 0, length: indented.length))
                        string.append(indented)
                    } else {
                        let childAttr = await createAttributedString(for: itemChild, constrainedToWidth: maxWidth)
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
            quoteStyle.lineHeightMultiple = theme.paragraph.lineHeightMultiple
            quoteStyle.paragraphSpacing = theme.paragraph.paragraphSpacing

            for child in blockQuote.children {
                if let para = child as? ParagraphNode {
                    var quoteAttrs = defaultAttributes(for: theme.paragraph)
                    quoteAttrs[.paragraphStyle] = quoteStyle
                    quoteAttrs[.foregroundColor] = Color.gray
                    let inlineStr = await buildInlineAttributedString(from: para.children, baseAttributes: quoteAttrs)

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
    private func renderMath(latex: String, display: Bool) async -> NativeImage? {
        return await withCheckedContinuation { continuation in
            Task { @MainActor in
                MathRenderer.shared.render(latex: latex, display: display) { image in
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

    // MARK: - Code Block Helper

    private func buildCodeBlockAttributedString(from code: CodeBlockNode) -> NSAttributedString {
        let result = NSMutableAttributedString()

        if let label = normalizedCodeLanguageLabel(from: code.language) {
            let labelStyle = NSMutableParagraphStyle()
            labelStyle.paragraphSpacing = 6
            labelStyle.lineHeightMultiple = 1.0

            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: Font.monospacedSystemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: Color.secondaryLabelColor,
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

    private func buildDiagramAttributedString(from diagram: DiagramNode) async -> NSAttributedString {
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
                baseAttributes: summaryAttrs
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
            let childAttr = await createAttributedString(for: child, constrainedToWidth: maxWidth)
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
        var attrs = defaultAttributes(for: theme.paragraph)
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
        baseAttributes: [NSAttributedString.Key: Any]
    ) async -> NSAttributedString {
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
                let linkText = await buildInlineAttributedString(from: link.children, baseAttributes: linkAttrs)
                result.append(linkText)

            case let image as ImageNode:
                var imgAttrs = baseAttributes
                imgAttrs[.foregroundColor] = Color.secondaryLabelColor
                let altText = image.altText ?? image.source ?? "image"
                result.append(NSAttributedString(string: "[\(altText)]", attributes: imgAttrs))

            case let math as MathNode:
                if let image = await renderMath(latex: math.equation, display: !math.isInline) {
                    let attachment = NSTextAttachment()
                    #if canImport(UIKit)
                    attachment.image = image
                    #elseif canImport(AppKit)
                    attachment.image = image
                    #endif

                    let baseFont = (baseAttributes[.font] as? Font) ?? theme.paragraph.font
                    attachment.bounds = attachmentBounds(
                        for: image.size,
                        isInline: math.isInline,
                        font: baseFont
                    )
                    result.append(NSAttributedString(attachment: attachment))
                } else {
                    var mathAttrs = baseAttributes
                    mathAttrs[.font] = theme.codeBlock.font
                    mathAttrs[.foregroundColor] = Color.systemPurple
                    let prefix = math.isInline ? "" : "\n"
                    let suffix = math.isInline ? "" : "\n"
                    result.append(NSAttributedString(string: "\(prefix)\(math.equation)\(suffix)", attributes: mathAttrs))
                }

            case is EmphasisNode:
                var italicAttrs = baseAttributes
                if let font = baseAttributes[.font] as? Font {
                    italicAttrs[.font] = fontWithTrait(font, trait: .italic)
                }
                result.append(await buildInlineAttributedString(from: child.children, baseAttributes: italicAttrs))

            case is StrongNode:
                var boldAttrs = baseAttributes
                if let font = baseAttributes[.font] as? Font {
                    boldAttrs[.font] = fontWithTrait(font, trait: .bold)
                }
                result.append(await buildInlineAttributedString(from: child.children, baseAttributes: boldAttrs))

            case is StrikethroughNode:
                var strikeAttrs = baseAttributes
                strikeAttrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                result.append(await buildInlineAttributedString(from: child.children, baseAttributes: strikeAttrs))

            default:
                let childResult = await buildInlineAttributedString(from: child.children, baseAttributes: baseAttributes)
                if childResult.length > 0 {
                    result.append(childResult)
                }
            }
        }
        return result
    }

    private func attachmentBounds(for imageSize: CGSize, isInline: Bool, font: Font) -> CGRect {
        guard isInline else {
            return CGRect(origin: .zero, size: imageSize)
        }

        // Center the attachment against the font's typographic midline.
        let textMidline = (font.ascender + font.descender) / 2.0
        let imageMidline = imageSize.height / 2.0
        let offsetY = textMidline - imageMidline

        return CGRect(x: 0, y: offsetY, width: imageSize.width, height: imageSize.height)
    }

    // MARK: - Table Helper
    private func buildTableAttributedString(from table: TableNode) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let allRows = normalizedTableRows(from: table)
        let columnCount = allRows.map(\.cells.count).max() ?? 0
        guard columnCount > 0 else { return result }

        let cellFont = theme.paragraph.font
        let headerFont = fontWithTrait(theme.paragraph.font, trait: .bold)

        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false

        var bodyRowIndex = 0
        for (rowIndex, row) in allRows.enumerated() {
            let rowBackground = tableRowBackgroundColor(
                isHeader: row.isHead,
                bodyRowIndex: bodyRowIndex
            )
            if !row.isHead {
                bodyRowIndex += 1
            }

            let cells = normalizedCells(for: row.cells, columnCount: columnCount)
            for columnIndex in 0..<columnCount {
                let block = configuredTableBlock(
                    table: textTable,
                    row: rowIndex,
                    column: columnIndex,
                    backgroundColor: rowBackground
                )

                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.textBlocks = [block]
                paragraphStyle.paragraphSpacing = 0
                paragraphStyle.paragraphSpacingBefore = 0
                paragraphStyle.alignment = textAlignment(
                    for: table.columnAlignments[safe: columnIndex] ?? nil
                )

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: row.isHead ? headerFont : cellFont,
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: theme.textColor.foreground
                ]

                let cellText = cells[columnIndex].isEmpty ? " " : cells[columnIndex]
                result.append(NSAttributedString(string: cellText, attributes: attrs))
                result.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }

        return result
    }

    private func configuredTableBlock(
        table: NSTextTable,
        row: Int,
        column: Int,
        backgroundColor: Color
    ) -> NSTextTableBlock {
        let block = NSTextTableBlock(
            table: table,
            startingRow: row,
            rowSpan: 1,
            startingColumn: column,
            columnSpan: 1
        )

        block.setWidth(1.0, type: .absoluteValueType, for: .border)
        block.setWidth(8.0, type: .absoluteValueType, for: .padding)
        block.setWidth(0.0, type: .absoluteValueType, for: .margin)
        block.setBorderColor(theme.tableColor.foreground)
        block.backgroundColor = backgroundColor

        return block
    }

    private func tableRowBackgroundColor(isHeader: Bool, bodyRowIndex: Int) -> Color {
        if isHeader {
            return theme.tableColor.background
        }

        // GitHub-like zebra striping: apply subtle shading to every other body row.
        if bodyRowIndex.isMultiple(of: 2) {
            return .clear
        }
        return theme.tableColor.background.withAlphaComponent(0.45)
    }

    private func textAlignment(for alignment: TableAlignment?) -> NSTextAlignment {
        switch alignment {
        case .right:
            return .right
        case .center:
            return .center
        case .left, .none:
            return .left
        }
    }

    private func normalizedTableRows(from table: TableNode) -> [(cells: [String], isHead: Bool)] {
        var rows: [(cells: [String], isHead: Bool)] = []

        for section in table.children {
            let isHead = section is TableHeadNode
            let sectionChildren = (section as? TableHeadNode)?.children
                ?? (section as? TableBodyNode)?.children
                ?? []

            var directCells: [TableCellNode] = []
            for child in sectionChildren {
                if let row = child as? TableRowNode {
                    let rowCells = row.children.compactMap { $0 as? TableCellNode }
                    let texts = rowCells.map { tableCellText(from: $0) }
                    if !texts.isEmpty {
                        rows.append((cells: texts, isHead: isHead))
                    }
                } else if let cell = child as? TableCellNode {
                    directCells.append(cell)
                }
            }

            if !directCells.isEmpty {
                let texts = directCells.map { tableCellText(from: $0) }
                rows.append((cells: texts, isHead: isHead))
            }
        }

        return rows
    }

    private func normalizedCells(for cells: [String], columnCount: Int) -> [String] {
        if cells.count >= columnCount {
            return Array(cells.prefix(columnCount))
        }
        return cells + Array(repeating: "", count: columnCount - cells.count)
    }

    private func tableCellText(from cell: TableCellNode) -> String {
        flattenInlineText(from: cell)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func flattenInlineText(from node: MarkdownNode) -> String {
        switch node {
        case let text as TextNode:
            return text.text
        case let inlineCode as InlineCodeNode:
            return inlineCode.code
        case let math as MathNode:
            return math.equation
        default:
            return node.children.map { flattenInlineText(from: $0) }.joined()
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
