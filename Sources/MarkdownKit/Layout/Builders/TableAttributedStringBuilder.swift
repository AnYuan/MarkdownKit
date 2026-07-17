//
//  TableAttributedStringBuilder.swift
//  MarkdownKit
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct TableAttributedStringBuilder {

    static func build(
        from table: TableNode,
        theme: Theme,
        constrainedToWidth maxWidth: CGFloat
    ) -> NSAttributedString {
        let grid = TableLayoutShared.Grid(table: table)
        guard grid.columnCount > 0 else { return NSAttributedString() }

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        return buildTableAttributedString_AppKit(
            grid: grid,
            theme: theme,
            constrainedToWidth: maxWidth
        )
        #else
        return buildTableAttributedString_UIKit(
            grid: grid,
            theme: theme,
            constrainedToWidth: maxWidth
        )
        #endif
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    private static func buildTableAttributedString_AppKit(
        grid: TableLayoutShared.Grid,
        theme: Theme,
        constrainedToWidth maxWidth: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let cellFont = theme.typography.paragraph.font
        let headerFont = FontTraitResolver.adding(.bold, to: cellFont)

        let textTable = NSTextTable()
        textTable.numberOfColumns = grid.columnCount
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false

        let tableStyle = theme.table
        let geometry = TableLayoutShared.UniformColumnPolicy.appKit(
            horizontalPadding: tableStyle.appKitHorizontalPadding,
            borderAllowance: tableStyle.appKitBorderAllowance
        ).geometry(
            columnCount: grid.columnCount,
            constrainedToWidth: maxWidth
        )

        for (rowIndex, row) in grid.rows.enumerated() {
            let rowBackground = tableRowBackgroundColor(
                role: row.role,
                theme: theme
            )

            for cell in row.cells {
                let block = configuredTableBlock(
                    table: textTable,
                    row: rowIndex,
                    column: cell.column,
                    backgroundColor: rowBackground,
                    contentWidth: geometry.contentWidth,
                    theme: theme
                )

                let paragraphStyleMut = NSMutableParagraphStyle()
                paragraphStyleMut.textBlocks = [block]
                paragraphStyleMut.paragraphSpacing = 0
                paragraphStyleMut.paragraphSpacingBefore = 0
                paragraphStyleMut.alignment = cell.alignment.textAlignment
                let paragraphStyle = paragraphStyleMut.copy() as! NSParagraphStyle

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: row.isHeader ? headerFont : cellFont,
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: theme.colors.textColor.foreground
                ]

                result.append(NSAttributedString(string: cell.displayText, attributes: attrs))
                result.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }

        return result
    }

    private static func configuredTableBlock(
        table: NSTextTable,
        row: Int,
        column: Int,
        backgroundColor: Color,
        contentWidth: CGFloat,
        theme: Theme
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
        block.setContentWidth(contentWidth, type: .absoluteValueType)
        block.setBorderColor(theme.colors.tableColor.foreground)
        block.backgroundColor = backgroundColor

        return block
    }

    private static func tableRowBackgroundColor(
        role: TableLayoutShared.RowRole,
        theme: Theme
    ) -> Color {
        switch role {
        case .header:
            return theme.colors.tableColor.background
        case let .body(index) where index.isMultiple(of: 2):
            return .clear
        case .body:
            let bg = theme.colors.tableColor.background
            var alpha: CGFloat = 1.0
            bg.usingColorSpace(.deviceRGB)?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            return bg.withAlphaComponent(alpha * theme.table.alternatingRowAlpha)
        }
    }
    #endif

    #if canImport(UIKit)
    private static let maximumGeneratedCharactersPerCell = 4_096

    private static func buildTableAttributedString_UIKit(
        grid: TableLayoutShared.Grid,
        theme: Theme,
        constrainedToWidth maxWidth: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let cellFont = theme.typography.paragraph.font
        let headerFont = FontTraitResolver.adding(.bold, to: cellFont)

        let tableStyle = theme.table
        let geometry = TableLayoutShared.UniformColumnPolicy.uiKitAttributed(
            horizontalInset: tableStyle.uiKitHorizontalInset
        ).geometry(
            columnCount: grid.columnCount,
            constrainedToWidth: maxWidth
        )
        let rawColumnWidth = geometry.columnWidth
        let leadingColumnOrigin = geometry.columnOrigin(at: 0)

        if rawColumnWidth < tableStyle.minimumReadableColumnWidth {
            return buildTableAttributedString_UIKitNarrowFallback(
                grid: grid,
                horizontalInset: leadingColumnOrigin,
                headerFont: headerFont,
                cellFont: cellFont,
                theme: theme
            )
        }

        let columnWidth = rawColumnWidth

        for (rowIndex, row) in grid.rows.enumerated() {
            let isLastRow = rowIndex == grid.rows.count - 1
            let rowBackground = tableRowBackgroundColorUIKit(
                role: row.role,
                theme: theme
            )

            let tabStops = row.cells.map { cell in
                NSTextTab(
                    textAlignment: cell.alignment.textAlignment,
                    location: geometry.columnOrigin(at: cell.column)
                )
            }

            let paragraphStyleMut = NSMutableParagraphStyle()
            paragraphStyleMut.tabStops = tabStops
            paragraphStyleMut.firstLineHeadIndent = leadingColumnOrigin
            paragraphStyleMut.headIndent = leadingColumnOrigin
            paragraphStyleMut.alignment = row.cells[0].alignment.textAlignment
            paragraphStyleMut.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
            paragraphStyleMut.paragraphSpacing = tableStyle.cellParagraphSpacing
            let paragraphStyle = paragraphStyleMut.copy() as! NSParagraphStyle

            let font = row.isHeader ? headerFont : cellFont
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: theme.colors.textColor.foreground,
                .backgroundColor: rowBackground
            ]

            let maxCharsPerCell = boundedCharacterCount(
                for: columnWidth,
                divisor: 8,
                minimum: 4
            )
            let rowText = row.cells.map { cell -> String in
                let text = cell.displayText
                if text.count > maxCharsPerCell {
                    return String(text.prefix(maxCharsPerCell - 1)) + "\u{2026}"
                }
                return text
            }.joined(separator: "\t")
            result.append(NSAttributedString(string: rowText, attributes: attrs))

            if row.isHeader {
                let separatorStyleMut = NSMutableParagraphStyle()
                separatorStyleMut.tabStops = tabStops
                separatorStyleMut.firstLineHeadIndent = leadingColumnOrigin
                separatorStyleMut.headIndent = leadingColumnOrigin
                separatorStyleMut.paragraphSpacing = tableStyle.cellParagraphSpacing
                let separatorStyle = separatorStyleMut.copy() as! NSParagraphStyle

                let sepAttrs: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .paragraphStyle: separatorStyle,
                    .foregroundColor: theme.colors.tableColor.foreground
                ]

                let dashes = Array(
                    repeating: String(
                        repeating: "─",
                        count: boundedCharacterCount(
                            for: columnWidth,
                            divisor: 8,
                            minimum: 3
                        )
                    ),
                    count: grid.columnCount
                )
                result.append(NSAttributedString(string: "\n" + dashes.joined(separator: "\t"), attributes: sepAttrs))
            } else if !isLastRow {
                let separatorStyleMut = NSMutableParagraphStyle()
                separatorStyleMut.tabStops = tabStops
                separatorStyleMut.firstLineHeadIndent = leadingColumnOrigin
                separatorStyleMut.headIndent = leadingColumnOrigin
                separatorStyleMut.paragraphSpacing = tableStyle.cellParagraphSpacing
                let separatorStyle = separatorStyleMut.copy() as! NSParagraphStyle

                let sepAttrs: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .paragraphStyle: separatorStyle,
                    .foregroundColor: theme.colors.tableColor.foreground.withAlphaComponent(tableStyle.separatorAlpha)
                ]

                let dashes = Array(
                    repeating: String(
                        repeating: "─",
                        count: boundedCharacterCount(
                            for: columnWidth,
                            divisor: 10,
                            minimum: 3
                        )
                    ),
                    count: grid.columnCount
                )
                result.append(NSAttributedString(string: "\n" + dashes.joined(separator: "\t"), attributes: sepAttrs))
            }

            if rowIndex < grid.rows.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }

        return result
    }

    private static func tableRowBackgroundColorUIKit(
        role: TableLayoutShared.RowRole,
        theme: Theme
    ) -> Color {
        switch role {
        case .header:
            return theme.colors.tableColor.background
        case let .body(index) where index.isMultiple(of: 2):
            return .clear
        case .body:
            return theme.colors.tableColor.background.withAlphaComponent(
                theme.table.alternatingRowAlpha
            )
        }
    }

    private static func buildTableAttributedString_UIKitNarrowFallback(
        grid: TableLayoutShared.Grid,
        horizontalInset: CGFloat,
        headerFont: Font,
        cellFont: Font,
        theme: Theme
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()

        let paragraphStyleMut = NSMutableParagraphStyle()
        paragraphStyleMut.firstLineHeadIndent = horizontalInset
        paragraphStyleMut.headIndent = horizontalInset
        paragraphStyleMut.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
        paragraphStyleMut.paragraphSpacing = 3
        paragraphStyleMut.lineBreakMode = .byWordWrapping
        let paragraphStyle = paragraphStyleMut.copy() as! NSParagraphStyle
        let maxCharsNarrow = max(1, theme.table.narrowFallbackMaxChars)

        for (rowIndex, row) in grid.rows.enumerated() {
            let rowText = row.cells.map { cell -> String in
                let text = cell.displayText
                if text.count > maxCharsNarrow {
                    return String(text.prefix(maxCharsNarrow - 1)) + "\u{2026}"
                }
                return text
            }.joined(separator: "  |  ")

            let attrs: [NSAttributedString.Key: Any] = [
                .font: row.isHeader ? headerFont : cellFont,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: theme.colors.textColor.foreground
            ]

            result.append(NSAttributedString(string: rowText, attributes: attrs))

            if row.isHeader {
                let separator = Array(
                    repeating: String(repeating: "─", count: 5),
                    count: grid.columnCount
                ).joined(separator: "  |  ")
                let separatorAttrs: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: theme.colors.tableColor.foreground
                ]
                result.append(NSAttributedString(string: "\n" + separator, attributes: separatorAttrs))
            }

            if rowIndex < grid.rows.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }

        return result
    }

    private static func boundedCharacterCount(
        for columnWidth: CGFloat,
        divisor: CGFloat,
        minimum: Int
    ) -> Int {
        let scaled = floor(columnWidth / divisor)
        let bounded = min(
            max(scaled, CGFloat(minimum)),
            CGFloat(maximumGeneratedCharactersPerCell)
        )
        return Int(bounded)
    }
    #endif

}
