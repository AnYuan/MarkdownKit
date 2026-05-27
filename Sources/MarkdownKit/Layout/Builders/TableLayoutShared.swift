//
//  TableLayoutShared.swift
//  MarkdownKit
//
//  Internal helpers shared between `TableAttributedStringBuilder` (AppKit
//  `NSTextTable` path + iOS tab-stop fallback) and `TableCardRenderer` (iOS
//  CGContext card draw). Both consumers normalize the `TableNode`'s nested
//  head/body/row/cell structure into a flat `(cells: [String], isHead: Bool)`
//  matrix and resolve per-column text alignment the same way.
//

import Foundation

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum TableLayoutShared {

    /// Walks a `TableNode`'s head / body / row / cell children and produces a
    /// flat row list. Each row carries its raw cell strings (with inline
    /// formatting already flattened) and an `isHead` flag.
    static func normalizedTableRows(from table: TableNode) -> [(cells: [String], isHead: Bool)] {
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

    /// Pads or truncates a row to exactly `columnCount` cells.
    static func normalizedCells(for cells: [String], columnCount: Int) -> [String] {
        if cells.count >= columnCount {
            return Array(cells.prefix(columnCount))
        }
        return cells + Array(repeating: "", count: columnCount - cells.count)
    }

    static func tableCellText(from cell: TableCellNode) -> String {
        flattenInlineText(from: cell)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Concatenates the visible text inside an inline subtree. Used to derive
    /// plain-text cell content from rich-AST cells.
    static func flattenInlineText(from node: MarkdownNode) -> String {
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

    static func tableTextAlignment(for table: TableNode, column: Int) -> NSTextAlignment {
        guard column < table.columnAlignments.count else { return .left }
        switch table.columnAlignments[column] {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .none: return .left
        }
    }
}
