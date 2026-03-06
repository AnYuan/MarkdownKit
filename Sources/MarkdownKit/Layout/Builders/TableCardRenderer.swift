//
//  TableCardRenderer.swift
//  MarkdownKit
//

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// A CGContext-based renderer that draws Markdown tables as rounded-corner cards,
/// matching the legacy OneCopilotMobile iOS table visual spec pixel-perfectly.
///
/// Visual spec:
/// - 8pt corner radius card with 1pt border (separator color)
/// - Header row: secondarySystemGroupedBackground, 13pt semibold
/// - Body rows: clear background, 13pt regular
/// - Cell padding: 12pt horizontal, 8pt vertical
/// - 0.5pt divider lines between rows
/// - No alternating row colors
struct TableCardRenderer {

    // MARK: - Layout Models

    // Note: These structs use @unchecked Sendable because NSAttributedString is not
    // formally Sendable, but our instances are immutable and never mutated after creation,
    // making them safe to send across isolation boundaries.

    struct TableLayout: @unchecked Sendable {
        let rows: [RowLayout]
        let columnWidths: [CGFloat]
        let totalSize: CGSize
        let cornerRadius: CGFloat
        let borderWidth: CGFloat
        let cellPaddingH: CGFloat
        let cellPaddingV: CGFloat
        let dividerHeight: CGFloat
    }

    struct RowLayout: @unchecked Sendable {
        let cells: [CellLayout]
        let isHeader: Bool
        let yOffset: CGFloat
        let height: CGFloat
    }

    struct CellLayout: @unchecked Sendable {
        let text: NSAttributedString
        let xOffset: CGFloat
        let width: CGFloat
        let alignment: NSTextAlignment
    }

    // MARK: - Layout Constants

    private static let cornerRadius: CGFloat = 8
    private static let borderWidth: CGFloat = 1
    private static let cellPaddingH: CGFloat = 12
    private static let cellPaddingV: CGFloat = 8
    private static let dividerHeight: CGFloat = 0.5
    private static let tableFontSize: CGFloat = 13

    // MARK: - Compute Layout

    /// Computes the full table layout from a `TableNode`, measuring every cell's text
    /// to determine column widths and row heights.
    static func computeLayout(
        from table: TableNode,
        theme: Theme,
        constrainedToWidth maxWidth: CGFloat
    ) -> TableLayout {
        let allRows = normalizedTableRows(from: table)
        let columnCount = allRows.map(\.cells.count).max() ?? 0
        guard columnCount > 0 else {
            return TableLayout(
                rows: [], columnWidths: [], totalSize: .zero,
                cornerRadius: cornerRadius, borderWidth: borderWidth,
                cellPaddingH: cellPaddingH, cellPaddingV: cellPaddingV,
                dividerHeight: dividerHeight
            )
        }

        let headerFont = UIFont.systemFont(ofSize: tableFontSize, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: tableFontSize, weight: .regular)
        let textColor = theme.colors.textColor.foreground

        // Available width for content after border on both sides
        let availableWidth = max(0, maxWidth - borderWidth * 2)
        let columnWidth = floor(availableWidth / CGFloat(columnCount))

        // Content width inside a cell (after horizontal padding)
        let contentWidth = max(0, columnWidth - cellPaddingH * 2)

        // First pass: build cells, measure heights
        var rowLayouts: [RowLayout] = []
        var yOffset: CGFloat = borderWidth // start after top border

        for (rowIndex, row) in allRows.enumerated() {
            let cells = normalizedCells(for: row.cells, columnCount: columnCount)
            let font = row.isHead ? headerFont : bodyFont

            var cellLayouts: [CellLayout] = []
            var maxCellHeight: CGFloat = 0

            for col in 0..<columnCount {
                let alignment = tableTextAlignment(for: table, column: col)
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.alignment = alignment
                paragraphStyle.lineBreakMode = .byWordWrapping

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]

                let cellText = cells[col].isEmpty ? " " : cells[col]
                let attrString = NSAttributedString(string: cellText, attributes: attrs)

                // Measure text height
                let boundingRect = attrString.boundingRect(
                    with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
                let cellHeight = ceil(boundingRect.height)
                maxCellHeight = max(maxCellHeight, cellHeight)

                let xOffset = borderWidth + columnWidth * CGFloat(col)
                cellLayouts.append(CellLayout(
                    text: attrString,
                    xOffset: xOffset,
                    width: columnWidth,
                    alignment: alignment
                ))
            }

            let rowHeight = maxCellHeight + cellPaddingV * 2

            // Add divider space before this row (except first row)
            if rowIndex > 0 {
                yOffset += dividerHeight
            }

            rowLayouts.append(RowLayout(
                cells: cellLayouts,
                isHeader: row.isHead,
                yOffset: yOffset,
                height: rowHeight
            ))

            yOffset += rowHeight
        }

        yOffset += borderWidth // bottom border

        let totalWidth = columnWidth * CGFloat(columnCount) + borderWidth * 2
        let totalSize = CGSize(
            width: min(totalWidth, maxWidth),
            height: yOffset
        )

        let columnWidths = Array(repeating: columnWidth, count: columnCount)

        return TableLayout(
            rows: rowLayouts,
            columnWidths: columnWidths,
            totalSize: totalSize,
            cornerRadius: cornerRadius,
            borderWidth: borderWidth,
            cellPaddingH: cellPaddingH,
            cellPaddingV: cellPaddingV,
            dividerHeight: dividerHeight
        )
    }

    // MARK: - Draw

    /// Draws the table card into a `CGContext`. Thread-safe — uses only resolved `CGColor` values.
    ///
    /// All UIColor-to-CGColor resolution happens at layout time (in `computeLayout`), and the
    /// resolved colors are passed in via the `ResolvedColors` struct. This ensures no UIKit
    /// trait-collection access occurs during background rasterization.
    static func draw(
        layout: TableLayout,
        resolvedColors: ResolvedColors,
        in context: CGContext,
        size: CGSize
    ) {
        guard !layout.rows.isEmpty else { return }

        let cardRect = CGRect(origin: .zero, size: size)
        let borderInset = layout.borderWidth / 2
        let borderRect = cardRect.insetBy(dx: borderInset, dy: borderInset)
        let clipPath = UIBezierPath(roundedRect: cardRect, cornerRadius: layout.cornerRadius)

        // Clip to rounded rect for the entire card
        context.saveGState()
        context.addPath(clipPath.cgPath)
        context.clip()

        // Fill entire card with body background (clear/white)
        context.setFillColor(resolvedColors.bodyBackground)
        context.fill(cardRect)

        // Draw header row background
        for row in layout.rows where row.isHeader {
            let headerRect = CGRect(
                x: 0,
                y: row.yOffset,
                width: size.width,
                height: row.height
            )
            context.setFillColor(resolvedColors.headerBackground)
            context.fill(headerRect)
        }

        // Draw cell text
        for row in layout.rows {
            for cell in row.cells {
                let textOrigin = CGPoint(
                    x: cell.xOffset + layout.cellPaddingH,
                    y: row.yOffset + layout.cellPaddingV
                )
                let textWidth = cell.width - layout.cellPaddingH * 2
                let textRect = CGRect(
                    x: textOrigin.x,
                    y: textOrigin.y,
                    width: textWidth,
                    height: row.height - layout.cellPaddingV * 2
                )
                cell.text.draw(with: textRect, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            }
        }

        // Draw row dividers (0.5pt lines between rows)
        context.setStrokeColor(resolvedColors.divider)
        context.setLineWidth(layout.dividerHeight)

        for i in 1..<layout.rows.count {
            let y = layout.rows[i].yOffset - layout.dividerHeight / 2
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: size.width, y: y))
            context.strokePath()
        }

        // Draw column dividers (0.5pt vertical lines between columns)
        if layout.columnWidths.count > 1 {
            var xAccum: CGFloat = layout.borderWidth
            for colIndex in 0..<(layout.columnWidths.count - 1) {
                xAccum += layout.columnWidths[colIndex]
                context.move(to: CGPoint(x: xAccum, y: 0))
                context.addLine(to: CGPoint(x: xAccum, y: size.height))
                context.strokePath()
            }
        }

        context.restoreGState()

        // Draw outer border stroke (on top of everything, clipped to rounded rect)
        context.setStrokeColor(resolvedColors.border)
        context.setLineWidth(layout.borderWidth)
        context.addPath(UIBezierPath(roundedRect: borderRect, cornerRadius: layout.cornerRadius).cgPath)
        context.strokePath()
    }

    // MARK: - Resolved Colors

    /// Pre-resolved CGColor values for thread-safe drawing.
    /// All UIColor -> CGColor conversion must happen on the main thread or a thread
    /// with the correct trait collection before passing to `draw()`.
    struct ResolvedColors: Sendable {
        let headerBackground: CGColor
        let bodyBackground: CGColor
        let border: CGColor
        let divider: CGColor

        static func resolve(from theme: Theme) -> ResolvedColors {
            ResolvedColors(
                headerBackground: theme.colors.tableColor.background.cgColor,
                bodyBackground: UIColor.clear.cgColor,
                border: theme.colors.tableColor.foreground.cgColor,
                divider: theme.colors.tableColor.foreground.cgColor
            )
        }
    }

    // MARK: - Table Parsing Helpers (shared with TableAttributedStringBuilder)

    private static func normalizedTableRows(from table: TableNode) -> [(cells: [String], isHead: Bool)] {
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

    private static func normalizedCells(for cells: [String], columnCount: Int) -> [String] {
        if cells.count >= columnCount {
            return Array(cells.prefix(columnCount))
        }
        return cells + Array(repeating: "", count: columnCount - cells.count)
    }

    private static func tableCellText(from cell: TableCellNode) -> String {
        flattenInlineText(from: cell)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func flattenInlineText(from node: MarkdownNode) -> String {
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

    private static func tableTextAlignment(for table: TableNode, column: Int) -> NSTextAlignment {
        guard column < table.columnAlignments.count else { return .left }
        switch table.columnAlignments[column] {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .none: return .left
        }
    }
}
#endif
