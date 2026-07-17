//
//  TableLayoutShared.swift
//  MarkdownKit
//
//  Canonical table content and uniform column geometry shared by the native,
//  attributed-string, and card table adapters.
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum TableLayoutShared {

    enum Alignment: Sendable, Equatable {
        case left
        case center
        case right

        var textAlignment: NSTextAlignment {
            switch self {
            case .left:
                return .left
            case .center:
                return .center
            case .right:
                return .right
            }
        }
    }

    enum RowRole: Sendable, Equatable {
        case header
        case body(index: Int)

        var isHeader: Bool {
            self == .header
        }
    }

    struct Cell: Sendable, Equatable {
        let text: String
        let column: Int
        let alignment: Alignment

        var displayText: String {
            text.isEmpty ? " " : text
        }
    }

    struct Row: Sendable, Equatable {
        let cells: [Cell]
        let role: RowRole

        var isHeader: Bool {
            role.isHeader
        }
    }

    struct Grid: Sendable, Equatable {
        let rows: [Row]
        let columnCount: Int

        init(table: TableNode) {
            let sourceRows = TableLayoutShared.sourceRows(from: table)
            let columnCount = sourceRows.reduce(0) { maximum, row in
                max(maximum, row.texts.count)
            }
            let alignments = (0..<columnCount).map {
                TableLayoutShared.alignment(for: table, column: $0)
            }

            var bodyRowIndex = 0
            self.rows = sourceRows.map { sourceRow in
                let role: RowRole
                if sourceRow.isHeader {
                    role = .header
                } else {
                    role = .body(index: bodyRowIndex)
                    bodyRowIndex += 1
                }

                let texts = TableLayoutShared.rectangularized(
                    sourceRow.texts,
                    columnCount: columnCount
                )
                let cells = texts.enumerated().map { column, text in
                    Cell(
                        text: text,
                        column: column,
                        alignment: alignments[column]
                    )
                }
                return Row(cells: cells, role: role)
            }
            self.columnCount = columnCount
        }
    }

    struct UniformColumnPolicy: Sendable, Equatable {
        enum TotalWidthLimit: Sendable, Equatable {
            case none
            case constrainedWidth
        }

        let minimumAvailableWidth: CGFloat
        let availableWidthDeduction: CGFloat
        let minimumColumnWidth: CGFloat
        let contentWidthDeduction: CGFloat
        let minimumContentWidth: CGFloat
        let leadingColumnOrigin: CGFloat
        let totalWidthAddition: CGFloat
        let totalWidthLimit: TotalWidthLimit

        init(
            minimumAvailableWidth: CGFloat = 0,
            availableWidthDeduction: CGFloat = 0,
            minimumColumnWidth: CGFloat = 0,
            contentWidthDeduction: CGFloat = 0,
            minimumContentWidth: CGFloat = 0,
            leadingColumnOrigin: CGFloat = 0,
            totalWidthAddition: CGFloat = 0,
            totalWidthLimit: TotalWidthLimit = .none
        ) {
            self.minimumAvailableWidth = TableLayoutShared.finiteNonnegative(minimumAvailableWidth)
            self.availableWidthDeduction = TableLayoutShared.finiteNonnegative(availableWidthDeduction)
            self.minimumColumnWidth = TableLayoutShared.finiteNonnegative(minimumColumnWidth)
            self.contentWidthDeduction = TableLayoutShared.finiteNonnegative(contentWidthDeduction)
            self.minimumContentWidth = TableLayoutShared.finiteNonnegative(minimumContentWidth)
            self.leadingColumnOrigin = TableLayoutShared.finiteNonnegative(leadingColumnOrigin)
            self.totalWidthAddition = TableLayoutShared.finiteNonnegative(totalWidthAddition)
            self.totalWidthLimit = totalWidthLimit
        }

        static func appKit(
            horizontalPadding: CGFloat,
            borderAllowance: CGFloat
        ) -> Self {
            let horizontalPadding = TableLayoutShared.finiteNonnegative(horizontalPadding)
            let borderAllowance = TableLayoutShared.finiteNonnegative(borderAllowance)
            return Self(
                minimumAvailableWidth: 160,
                availableWidthDeduction: horizontalPadding,
                minimumColumnWidth: 72,
                contentWidthDeduction: TableLayoutShared.saturatingSum(
                    horizontalPadding,
                    borderAllowance
                ),
                minimumContentWidth: 48
            )
        }

        static func uiKitAttributed(horizontalInset: CGFloat) -> Self {
            let horizontalInset = TableLayoutShared.finiteNonnegative(horizontalInset)
            let doubleInset = TableLayoutShared.saturatingProduct(horizontalInset, 2)
            return Self(
                minimumAvailableWidth: 160,
                availableWidthDeduction: doubleInset,
                leadingColumnOrigin: horizontalInset,
                totalWidthAddition: doubleInset
            )
        }

        static func uiKitCard(
            borderWidth: CGFloat,
            cellPadding: CGFloat
        ) -> Self {
            let borderWidth = TableLayoutShared.finiteNonnegative(borderWidth)
            let doubleBorder = TableLayoutShared.saturatingProduct(borderWidth, 2)
            let doublePadding = TableLayoutShared.saturatingProduct(
                TableLayoutShared.finiteNonnegative(cellPadding),
                2
            )
            return Self(
                availableWidthDeduction: doubleBorder,
                contentWidthDeduction: doublePadding,
                leadingColumnOrigin: borderWidth,
                totalWidthAddition: doubleBorder,
                totalWidthLimit: .constrainedWidth
            )
        }

        func geometry(
            columnCount: Int,
            constrainedToWidth maximumWidth: CGFloat
        ) -> UniformColumnGeometry {
            let columnCount = max(0, columnCount)
            guard columnCount > 0 else { return .zero }

            let maximumWidth = TableLayoutShared.finiteNonnegative(maximumWidth)
            let widthAfterDeduction = max(0, maximumWidth - availableWidthDeduction)
            let availableWidth = max(minimumAvailableWidth, widthAfterDeduction)
            let dividedWidth = floor(availableWidth / CGFloat(columnCount))
            let columnWidth = max(
                minimumColumnWidth,
                TableLayoutShared.finiteNonnegative(dividedWidth)
            )
            let contentWidth = max(
                minimumContentWidth,
                max(0, columnWidth - contentWidthDeduction)
            )

            let rawTotalWidth = TableLayoutShared.saturatingSum(
                TableLayoutShared.saturatingProduct(columnWidth, CGFloat(columnCount)),
                totalWidthAddition
            )
            let totalWidth = switch totalWidthLimit {
            case .none:
                rawTotalWidth
            case .constrainedWidth:
                min(rawTotalWidth, maximumWidth)
            }

            return UniformColumnGeometry(
                columnCount: columnCount,
                availableWidth: availableWidth,
                columnWidth: columnWidth,
                contentWidth: contentWidth,
                leadingColumnOrigin: leadingColumnOrigin,
                totalWidth: totalWidth
            )
        }
    }

    struct UniformColumnGeometry: Sendable, Equatable {
        let columnCount: Int
        let availableWidth: CGFloat
        let columnWidth: CGFloat
        let contentWidth: CGFloat
        let leadingColumnOrigin: CGFloat
        let totalWidth: CGFloat

        var columnOrigins: [CGFloat] {
            (0..<columnCount).map(columnOrigin(at:))
        }

        var columnWidths: [CGFloat] {
            Array(repeating: columnWidth, count: columnCount)
        }

        func columnOrigin(at column: Int) -> CGFloat {
            precondition(column >= 0 && column < columnCount)
            return TableLayoutShared.saturatingSum(
                leadingColumnOrigin,
                TableLayoutShared.saturatingProduct(columnWidth, CGFloat(column))
            )
        }

        static let zero = Self(
            columnCount: 0,
            availableWidth: 0,
            columnWidth: 0,
            contentWidth: 0,
            leadingColumnOrigin: 0,
            totalWidth: 0
        )
    }

    static func finiteNonnegative(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(0, value) : 0
    }

    static func saturatingSum(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let result = lhs + rhs
        return result.isFinite ? max(0, result) : .greatestFiniteMagnitude
    }

    static func saturatingProduct(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        let result = lhs * rhs
        return result.isFinite ? max(0, result) : .greatestFiniteMagnitude
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

    private struct SourceRow {
        let texts: [String]
        let isHeader: Bool
    }

    private static func sourceRows(from table: TableNode) -> [SourceRow] {
        var rows: [SourceRow] = []

        for section in table.children {
            let isHeader = section is TableHeadNode
            let sectionChildren = (section as? TableHeadNode)?.children
                ?? (section as? TableBodyNode)?.children
                ?? []

            var directCells: [TableCellNode] = []
            for child in sectionChildren {
                if let row = child as? TableRowNode {
                    let texts = row.children
                        .compactMap { $0 as? TableCellNode }
                        .map { tableCellText(from: $0) }
                    if !texts.isEmpty {
                        rows.append(SourceRow(texts: texts, isHeader: isHeader))
                    }
                } else if let cell = child as? TableCellNode {
                    directCells.append(cell)
                }
            }

            if !directCells.isEmpty {
                rows.append(SourceRow(
                    texts: directCells.map { tableCellText(from: $0) },
                    isHeader: isHeader
                ))
            }
        }

        return rows
    }

    private static func rectangularized(_ cells: [String], columnCount: Int) -> [String] {
        let columnCount = max(0, columnCount)
        if cells.count >= columnCount {
            return Array(cells.prefix(columnCount))
        }
        return cells + Array(repeating: "", count: columnCount - cells.count)
    }

    private static func alignment(for table: TableNode, column: Int) -> Alignment {
        guard column >= 0, column < table.columnAlignments.count else { return .left }
        switch table.columnAlignments[column] {
        case .some(.left), .none:
            return .left
        case .some(.center):
            return .center
        case .some(.right):
            return .right
        }
    }
}
