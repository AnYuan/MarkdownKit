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
        let allRows = normalizedTableRows(from: table)
        let columnCount = allRows.map(\.cells.count).max() ?? 0
        guard columnCount > 0 else { return NSAttributedString() }

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        return buildTableAttributedString_AppKit(
            allRows: allRows,
            columnCount: columnCount,
            table: table,
            theme: theme,
            constrainedToWidth: maxWidth
        )
        #else
        return buildTableAttributedString_UIKit(
            allRows: allRows,
            columnCount: columnCount,
            table: table,
            theme: theme,
            constrainedToWidth: maxWidth
        )
        #endif
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    private static func buildTableAttributedString_AppKit(
        allRows: [(cells: [String], isHead: Bool)],
        columnCount: Int,
        table: TableNode,
        theme: Theme,
        constrainedToWidth maxWidth: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let cellFont = theme.typography.paragraph.font
        let headerFont = FontTraitResolver.adding(.bold, to: cellFont)

        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.layoutAlgorithm = .automaticLayoutAlgorithm
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false

        let tableStyle = theme.table
        let availableTableWidth = max(160, maxWidth - tableStyle.appKitHorizontalPadding)
        let perColumnWidth = max(72, floor(availableTableWidth / CGFloat(columnCount)))
        let horizontalPadding = tableStyle.appKitHorizontalPadding
        let borderAllowance = tableStyle.appKitBorderAllowance
        let contentWidth = max(48, perColumnWidth - horizontalPadding - borderAllowance)

        var bodyRowIndex = 0
        for (rowIndex, row) in allRows.enumerated() {
            let rowBackground = tableRowBackgroundColor(
                isHeader: row.isHead,
                bodyRowIndex: bodyRowIndex,
                theme: theme
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
                    backgroundColor: rowBackground,
                    contentWidth: contentWidth,
                    theme: theme
                )

                let paragraphStyleMut = NSMutableParagraphStyle()
                paragraphStyleMut.textBlocks = [block]
                paragraphStyleMut.paragraphSpacing = 0
                paragraphStyleMut.paragraphSpacingBefore = 0
                paragraphStyleMut.alignment = tableTextAlignment(for: table, column: columnIndex)
                let paragraphStyle = paragraphStyleMut.copy() as! NSParagraphStyle

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: row.isHead ? headerFont : cellFont,
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: theme.colors.textColor.foreground
                ]

                let cellText = cells[columnIndex].isEmpty ? " " : cells[columnIndex]
                result.append(NSAttributedString(string: cellText, attributes: attrs))
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

    private static func tableRowBackgroundColor(isHeader: Bool, bodyRowIndex: Int, theme: Theme) -> Color {
        if isHeader {
            return theme.colors.tableColor.background
        }

        if bodyRowIndex.isMultiple(of: 2) {
            return .clear
        }

        let bg = theme.colors.tableColor.background
        var alpha: CGFloat = 1.0
        bg.usingColorSpace(.deviceRGB)?.getRed(nil, green: nil, blue: nil, alpha: &alpha)
        return bg.withAlphaComponent(alpha * theme.table.alternatingRowAlpha)
    }
    #endif

    #if canImport(UIKit)
    private static func buildTableAttributedString_UIKit(
        allRows: [(cells: [String], isHead: Bool)],
        columnCount: Int,
        table: TableNode,
        theme: Theme,
        constrainedToWidth maxWidth: CGFloat
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let cellFont = theme.typography.paragraph.font
        let headerFont = FontTraitResolver.adding(.bold, to: cellFont)

        let tableStyle = theme.table
        let horizontalInset = tableStyle.uiKitHorizontalInset
        let availableWidth = max(160, maxWidth - horizontalInset * 2)
        let rawColumnWidth = floor(availableWidth / CGFloat(columnCount))

        if rawColumnWidth < tableStyle.minimumReadableColumnWidth {
            return buildTableAttributedString_UIKitNarrowFallback(
                allRows: allRows,
                columnCount: columnCount,
                horizontalInset: horizontalInset,
                headerFont: headerFont,
                cellFont: cellFont,
                theme: theme
            )
        }

        let columnWidth = rawColumnWidth
        var bodyRowIndex = 0

        for (rowIndex, row) in allRows.enumerated() {
            let cells = normalizedCells(for: row.cells, columnCount: columnCount)
            let isLastRow = rowIndex == allRows.count - 1
            let rowBackground = tableRowBackgroundColorUIKit(
                isHeader: row.isHead,
                bodyRowIndex: bodyRowIndex,
                theme: theme
            )
            if !row.isHead {
                bodyRowIndex += 1
            }

            var tabStops: [NSTextTab] = []
            for col in 0..<columnCount {
                let alignment = tableTextAlignment(for: table, column: col)
                tabStops.append(NSTextTab(textAlignment: alignment, location: horizontalInset + columnWidth * CGFloat(col)))
            }

            let paragraphStyleMut = NSMutableParagraphStyle()
            paragraphStyleMut.tabStops = tabStops
            paragraphStyleMut.firstLineHeadIndent = horizontalInset
            paragraphStyleMut.headIndent = horizontalInset
            paragraphStyleMut.alignment = tableTextAlignment(for: table, column: 0)
            paragraphStyleMut.lineHeightMultiple = theme.typography.paragraph.lineHeightMultiple
            paragraphStyleMut.paragraphSpacing = tableStyle.cellParagraphSpacing
            let paragraphStyle = paragraphStyleMut.copy() as! NSParagraphStyle

            let font = row.isHead ? headerFont : cellFont
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: theme.colors.textColor.foreground,
                .backgroundColor: rowBackground
            ]

            let maxCharsPerCell = max(4, Int(columnWidth / 8))
            let rowText = cells.map { cell -> String in
                let text = cell.isEmpty ? " " : cell
                if text.count > maxCharsPerCell {
                    return String(text.prefix(maxCharsPerCell - 1)) + "\u{2026}"
                }
                return text
            }.joined(separator: "\t")
            result.append(NSAttributedString(string: rowText, attributes: attrs))

            if row.isHead {
                let separatorStyleMut = NSMutableParagraphStyle()
                separatorStyleMut.tabStops = tabStops
                separatorStyleMut.firstLineHeadIndent = horizontalInset
                separatorStyleMut.headIndent = horizontalInset
                separatorStyleMut.paragraphSpacing = tableStyle.cellParagraphSpacing
                let separatorStyle = separatorStyleMut.copy() as! NSParagraphStyle

                let sepAttrs: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .paragraphStyle: separatorStyle,
                    .foregroundColor: theme.colors.tableColor.foreground
                ]

                let dashes = Array(
                    repeating: String(repeating: "─", count: max(3, Int(columnWidth / 8))),
                    count: columnCount
                )
                result.append(NSAttributedString(string: "\n" + dashes.joined(separator: "\t"), attributes: sepAttrs))
            } else if !isLastRow {
                let separatorStyleMut = NSMutableParagraphStyle()
                separatorStyleMut.tabStops = tabStops
                separatorStyleMut.firstLineHeadIndent = horizontalInset
                separatorStyleMut.headIndent = horizontalInset
                separatorStyleMut.paragraphSpacing = tableStyle.cellParagraphSpacing
                let separatorStyle = separatorStyleMut.copy() as! NSParagraphStyle

                let sepAttrs: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .paragraphStyle: separatorStyle,
                    .foregroundColor: theme.colors.tableColor.foreground.withAlphaComponent(tableStyle.separatorAlpha)
                ]

                let dashes = Array(
                    repeating: String(repeating: "─", count: max(3, Int(columnWidth / 10))),
                    count: columnCount
                )
                result.append(NSAttributedString(string: "\n" + dashes.joined(separator: "\t"), attributes: sepAttrs))
            }

            if rowIndex < allRows.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }

        return result
    }

    private static func tableRowBackgroundColorUIKit(isHeader: Bool, bodyRowIndex: Int, theme: Theme) -> Color {
        if isHeader {
            return theme.colors.tableColor.background
        }
        if bodyRowIndex.isMultiple(of: 2) {
            return .clear
        }
        return theme.colors.tableColor.background.withAlphaComponent(theme.table.alternatingRowAlpha)
    }

    private static func buildTableAttributedString_UIKitNarrowFallback(
        allRows: [(cells: [String], isHead: Bool)],
        columnCount: Int,
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

        let maxCharsNarrow = theme.table.narrowFallbackMaxChars

        for (rowIndex, row) in allRows.enumerated() {
            let cells = normalizedCells(for: row.cells, columnCount: columnCount)
            let rowText = cells.map { cell -> String in
                let text = cell.isEmpty ? " " : cell
                if text.count > maxCharsNarrow {
                    return String(text.prefix(maxCharsNarrow - 1)) + "\u{2026}"
                }
                return text
            }.joined(separator: "  |  ")

            let attrs: [NSAttributedString.Key: Any] = [
                .font: row.isHead ? headerFont : cellFont,
                .paragraphStyle: paragraphStyle,
                .foregroundColor: theme.colors.textColor.foreground
            ]

            result.append(NSAttributedString(string: rowText, attributes: attrs))

            if row.isHead {
                let separator = Array(
                    repeating: String(repeating: "─", count: 5),
                    count: columnCount
                ).joined(separator: "  |  ")
                let separatorAttrs: [NSAttributedString.Key: Any] = [
                    .font: cellFont,
                    .paragraphStyle: paragraphStyle,
                    .foregroundColor: theme.colors.tableColor.foreground
                ]
                result.append(NSAttributedString(string: "\n" + separator, attributes: separatorAttrs))
            }

            if rowIndex < allRows.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: attrs))
            }
        }

        return result
    }
    #endif

    // Table-parsing helpers (normalizedTableRows / normalizedCells /
    // tableCellText / flattenInlineText / tableTextAlignment) live in
    // `TableLayoutShared` so `TableCardRenderer` can share them. Call those
    // through the `TableLayoutShared` enum below.

    private static func normalizedTableRows(from table: TableNode) -> [(cells: [String], isHead: Bool)] {
        TableLayoutShared.normalizedTableRows(from: table)
    }

    private static func normalizedCells(for cells: [String], columnCount: Int) -> [String] {
        TableLayoutShared.normalizedCells(for: cells, columnCount: columnCount)
    }

    private static func tableTextAlignment(for table: TableNode, column: Int) -> NSTextAlignment {
        TableLayoutShared.tableTextAlignment(for: table, column: column)
    }

}
