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
        let columnOrigins: [CGFloat]
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
        let contentWidth: CGFloat
        let alignment: NSTextAlignment
    }

    // MARK: - Compute Layout

    /// Computes the full table layout from a `TableNode`, measuring every cell's text
    /// to determine column widths and row heights.
    static func computeLayout(
        from table: TableNode,
        theme: Theme,
        constrainedToWidth maxWidth: CGFloat
    ) -> TableLayout {
        let tableStyle = theme.table
        let cornerRadius = TableLayoutShared.finiteNonnegative(tableStyle.cornerRadius)
        let borderWidth = TableLayoutShared.finiteNonnegative(tableStyle.borderWidth)
        let cellPaddingH = TableLayoutShared.finiteNonnegative(tableStyle.cellPaddingH)
        let cellPaddingV = TableLayoutShared.finiteNonnegative(tableStyle.cellPaddingV)
        let dividerHeight = TableLayoutShared.finiteNonnegative(tableStyle.dividerHeight)
        let fontSize = TableLayoutShared.finiteNonnegative(tableStyle.fontSize)

        let grid = TableLayoutShared.Grid(table: table)
        guard grid.columnCount > 0 else {
            return TableLayout(
                rows: [], columnOrigins: [], columnWidths: [], totalSize: .zero,
                cornerRadius: cornerRadius, borderWidth: borderWidth,
                cellPaddingH: cellPaddingH, cellPaddingV: cellPaddingV,
                dividerHeight: dividerHeight
            )
        }

        let headerFont = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let bodyFont = UIFont.systemFont(ofSize: fontSize, weight: .regular)
        let textColor = theme.colors.textColor.foreground
        let paragraphStyles = (
            left: wrappingParagraphStyle(alignment: .left),
            center: wrappingParagraphStyle(alignment: .center),
            right: wrappingParagraphStyle(alignment: .right)
        )

        let geometry = TableLayoutShared.UniformColumnPolicy.uiKitCard(
            borderWidth: borderWidth,
            cellPadding: cellPaddingH
        ).geometry(
            columnCount: grid.columnCount,
            constrainedToWidth: maxWidth
        )

        // First pass: build cells, measure heights
        var rowLayouts: [RowLayout] = []
        var yOffset: CGFloat = borderWidth // start after top border

        for (rowIndex, row) in grid.rows.enumerated() {
            let font = row.isHeader ? headerFont : bodyFont

            var cellLayouts: [CellLayout] = []
            var maxCellHeight: CGFloat = 0

            for cell in row.cells {
                let alignment = cell.alignment.textAlignment
                let paragraphStyle = switch cell.alignment {
                case .left:
                    paragraphStyles.left
                case .center:
                    paragraphStyles.center
                case .right:
                    paragraphStyles.right
                }

                let attrs: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: textColor,
                    .paragraphStyle: paragraphStyle
                ]

                let attrString = NSAttributedString(string: cell.displayText, attributes: attrs)

                // Measure text height
                let cellHeight: CGFloat
                if geometry.contentWidth > 0 {
                    let boundingRect = attrString.boundingRect(
                        with: CGSize(width: geometry.contentWidth, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil
                    )
                    cellHeight = TableLayoutShared.finiteNonnegative(ceil(boundingRect.height))
                } else {
                    cellHeight = 0
                }
                maxCellHeight = max(maxCellHeight, cellHeight)

                cellLayouts.append(CellLayout(
                    text: attrString,
                    xOffset: geometry.columnOrigin(at: cell.column),
                    width: geometry.columnWidth,
                    contentWidth: geometry.contentWidth,
                    alignment: alignment
                ))
            }

            let rowHeight = TableLayoutShared.saturatingSum(
                maxCellHeight,
                TableLayoutShared.saturatingProduct(cellPaddingV, 2)
            )

            // Add divider space before this row (except first row)
            if rowIndex > 0 {
                yOffset = TableLayoutShared.saturatingSum(yOffset, dividerHeight)
            }

            rowLayouts.append(RowLayout(
                cells: cellLayouts,
                isHeader: row.isHeader,
                yOffset: yOffset,
                height: rowHeight
            ))

            yOffset = TableLayoutShared.saturatingSum(yOffset, rowHeight)
        }

        yOffset = TableLayoutShared.saturatingSum(yOffset, borderWidth) // bottom border
        let columnOrigins = geometry.columnOrigins
        let columnWidths = geometry.columnWidths
        let totalSize = CGSize(
            width: geometry.totalWidth,
            height: yOffset
        )

        return TableLayout(
            rows: rowLayouts,
            columnOrigins: columnOrigins,
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
        guard !layout.rows.isEmpty,
              size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return
        }

        let cardRect = CGRect(origin: .zero, size: size)
        let borderInset = min(
            TableLayoutShared.finiteNonnegative(layout.borderWidth / 2),
            min(size.width, size.height) / 2
        )
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
                y: TableLayoutShared.finiteNonnegative(row.yOffset),
                width: size.width,
                height: TableLayoutShared.finiteNonnegative(row.height)
            )
            context.setFillColor(resolvedColors.headerBackground)
            context.fill(headerRect)
        }

        // Draw cell text
        for row in layout.rows {
            for cell in row.cells {
                let textRect = CGRect(
                    x: TableLayoutShared.saturatingSum(cell.xOffset, layout.cellPaddingH),
                    y: TableLayoutShared.saturatingSum(row.yOffset, layout.cellPaddingV),
                    width: cell.contentWidth,
                    height: TableLayoutShared.finiteNonnegative(
                        row.height - layout.cellPaddingV * 2
                    )
                )
                guard textRect.width > 0, textRect.height > 0 else { continue }
                cell.text.draw(
                    with: textRect,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    context: nil
                )
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
        if layout.columnOrigins.count > 1 {
            for xOrigin in layout.columnOrigins.dropFirst() {
                context.move(to: CGPoint(x: xOrigin, y: 0))
                context.addLine(to: CGPoint(x: xOrigin, y: size.height))
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

    private static func wrappingParagraphStyle(
        alignment: NSTextAlignment
    ) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        return style.copy() as! NSParagraphStyle
    }
}
#endif
