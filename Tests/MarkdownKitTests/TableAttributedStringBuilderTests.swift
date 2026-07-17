import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class TableAttributedStringBuilderTests: XCTestCase {

    func testEmptyCanonicalTableReturnsEmptyAttributedOutput() {
        let table = TableNode(
            range: nil,
            columnAlignments: [],
            children: [
                TableHeadNode(
                    range: nil,
                    children: [TableRowNode(range: nil, children: [])]
                )
            ]
        )

        let output = TableAttributedStringBuilder.build(
            from: table,
            theme: testTheme(),
            constrainedToWidth: 400
        )

        XCTAssertEqual(output.length, 0)
        XCTAssertEqual(output.string, "")
    }

    #if canImport(AppKit) && !targetEnvironment(macCatalyst)
    func testAppKitNativeTableUsesSharedGeometryAndCanonicalCells() throws {
        let table = makeTable(
            alignments: [.left, .center, .right],
            header: ["H1", "H2", "H3"],
            body: [
                ["B1", "", "B3"],
                ["C1", "C2", "C3"]
            ]
        )
        let theme = testTheme()
        let output = TableAttributedStringBuilder.build(
            from: table,
            theme: theme,
            constrainedToWidth: 400
        )

        XCTAssertEqual(output.string, "H1\nH2\nH3\nB1\n \nB3\nC1\nC2\nC3\n")
        XCTAssertEqual(output.string.filter { $0 == "\n" }.count, 9)
        XCTAssertTrue(output.string.hasSuffix("\n"))

        let cells = nativeCells(in: output)
        XCTAssertEqual(cells.count, 9)
        let first = try XCTUnwrap(cells[Coordinate(row: 0, column: 0)])
        XCTAssertEqual(first.block.table.numberOfColumns, 3)
        XCTAssertEqual(first.block.table.layoutAlgorithm, .automaticLayoutAlgorithm)
        XCTAssertTrue(first.block.table.collapsesBorders)
        XCTAssertFalse(first.block.table.hidesEmptyCells)
        XCTAssertEqual(first.block.contentWidth, 110)
        XCTAssertEqual(first.block.contentWidthValueType, .absoluteValueType)

        for row in 0..<3 {
            for column in 0..<3 {
                let cell = try XCTUnwrap(cells[Coordinate(row: row, column: column)])
                XCTAssertEqual(cell.block.startingRow, row)
                XCTAssertEqual(cell.block.startingColumn, column)
                XCTAssertEqual(cell.block.rowSpan, 1)
                XCTAssertEqual(cell.block.columnSpan, 1)
                XCTAssertEqual(cell.style.paragraphSpacing, 0)
                XCTAssertEqual(cell.style.paragraphSpacingBefore, 0)
                XCTAssertEqual(cell.block.contentWidth, 110)

                for edge: NSRectEdge in [.minX, .maxX, .minY, .maxY] {
                    XCTAssertEqual(cell.block.width(for: .border, edge: edge), 1)
                    XCTAssertEqual(cell.block.width(for: .padding, edge: edge), 8)
                    XCTAssertEqual(cell.block.width(for: .margin, edge: edge), 0)
                    XCTAssertEqual(
                        cell.block.widthValueType(for: .border, edge: edge),
                        .absoluteValueType
                    )
                    XCTAssertEqual(
                        cell.block.widthValueType(for: .padding, edge: edge),
                        .absoluteValueType
                    )
                    XCTAssertEqual(
                        cell.block.widthValueType(for: .margin, edge: edge),
                        .absoluteValueType
                    )
                    assertColor(
                        cell.block.borderColor(for: edge),
                        equals: theme.colors.tableColor.foreground
                    )
                }
            }
        }

        XCTAssertEqual(cells[Coordinate(row: 0, column: 0)]?.style.alignment, .left)
        XCTAssertEqual(cells[Coordinate(row: 0, column: 1)]?.style.alignment, .center)
        XCTAssertEqual(cells[Coordinate(row: 0, column: 2)]?.style.alignment, .right)

        let narrow = TableAttributedStringBuilder.build(
            from: table,
            theme: theme,
            constrainedToWidth: 100
        )
        let narrowFirst = try XCTUnwrap(
            nativeCells(in: narrow)[Coordinate(row: 0, column: 0)]
        )
        XCTAssertEqual(narrowFirst.block.contentWidth, 54)
    }

    func testAppKitNativeTablePreservesFontsForegroundAndRoleBackgrounds() throws {
        let table = makeTable(
            alignments: [.left],
            header: ["Header"],
            body: [["Body 0"], ["Body 1"]]
        )
        let theme = testTheme()
        let output = TableAttributedStringBuilder.build(
            from: table,
            theme: theme,
            constrainedToWidth: 400
        )
        let cells = nativeCells(in: output)
        let header = try XCTUnwrap(cells[Coordinate(row: 0, column: 0)])
        let firstBody = try XCTUnwrap(cells[Coordinate(row: 1, column: 0)])
        let secondBody = try XCTUnwrap(cells[Coordinate(row: 2, column: 0)])

        XCTAssertTrue(
            NSFontManager.shared.traits(of: header.font).contains(.boldFontMask)
        )
        XCTAssertEqual(firstBody.font, theme.typography.paragraph.font)
        XCTAssertEqual(secondBody.font, theme.typography.paragraph.font)
        assertColor(header.foreground, equals: theme.colors.textColor.foreground)
        assertColor(firstBody.foreground, equals: theme.colors.textColor.foreground)

        assertColor(
            header.block.backgroundColor,
            equals: theme.colors.tableColor.background
        )
        XCTAssertEqual(
            try XCTUnwrap(colorComponents(firstBody.block.backgroundColor)).alpha,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(colorComponents(secondBody.block.backgroundColor)).alpha,
            0.8 * theme.table.alternatingRowAlpha,
            accuracy: 0.001
        )
    }

    private struct Coordinate: Hashable {
        let row: Int
        let column: Int
    }

    private struct NativeCell {
        let block: NSTextTableBlock
        let style: NSParagraphStyle
        let font: NSFont
        let foreground: NSColor
    }

    private func nativeCells(in attributedString: NSAttributedString) -> [Coordinate: NativeCell] {
        var cells: [Coordinate: NativeCell] = [:]
        attributedString.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, range, _ in
            guard
                let style = value as? NSParagraphStyle,
                let block = style.textBlocks.first as? NSTextTableBlock,
                let font = attributedString.attribute(
                    .font,
                    at: range.location,
                    effectiveRange: nil
                ) as? NSFont,
                let foreground = attributedString.attribute(
                    .foregroundColor,
                    at: range.location,
                    effectiveRange: nil
                ) as? NSColor
            else {
                return
            }

            cells[Coordinate(row: block.startingRow, column: block.startingColumn)] = NativeCell(
                block: block,
                style: style,
                font: font,
                foreground: foreground
            )
        }
        return cells
    }
    #endif

    #if canImport(UIKit)
    func testUIKitNormalPathUsesSharedTabGeometryAndPreservesRowStyling() throws {
        let table = makeTable(
            alignments: [.left, .center, .right],
            header: ["12345678901234567", "Center", "Right"],
            body: [
                ["Body A", "", "Body C"],
                ["Second A", "Second B", "Second C"]
            ]
        )
        let theme = testTheme()
        let output = TableAttributedStringBuilder.build(
            from: table,
            theme: theme,
            constrainedToWidth: 400
        )
        let headerSeparator = Array(
            repeating: String(repeating: "─", count: 16),
            count: 3
        ).joined(separator: "\t")
        let bodySeparator = Array(
            repeating: String(repeating: "─", count: 12),
            count: 3
        ).joined(separator: "\t")

        XCTAssertEqual(
            output.string,
            """
            123456789012345…\tCenter\tRight
            \(headerSeparator)
            Body A\t \tBody C
            \(bodySeparator)
            Second A\tSecond B\tSecond C
            """
        )

        let headerStyle = try paragraphStyle(in: output, containing: "123456789012345…")
        XCTAssertEqual(headerStyle.tabStops.count, 3)
        XCTAssertEqual(headerStyle.tabStops.map(\.location), [8, 136, 264])
        XCTAssertEqual(headerStyle.tabStops.map(\.alignment), [.left, .center, .right])
        XCTAssertEqual(headerStyle.firstLineHeadIndent, 8)
        XCTAssertEqual(headerStyle.headIndent, 8)
        XCTAssertEqual(headerStyle.alignment, .left)
        XCTAssertEqual(
            headerStyle.lineHeightMultiple,
            theme.typography.paragraph.lineHeightMultiple
        )
        XCTAssertEqual(headerStyle.paragraphSpacing, theme.table.cellParagraphSpacing)

        let headerRange = (output.string as NSString).range(of: "123456789012345…")
        let firstBodyRange = (output.string as NSString).range(of: "Body A")
        let secondBodyRange = (output.string as NSString).range(of: "Second A")
        let headerFont = try XCTUnwrap(
            output.attribute(.font, at: headerRange.location, effectiveRange: nil) as? UIFont
        )
        let firstBodyFont = try XCTUnwrap(
            output.attribute(.font, at: firstBodyRange.location, effectiveRange: nil) as? UIFont
        )
        XCTAssertTrue(headerFont.fontDescriptor.symbolicTraits.contains(.traitBold))
        XCTAssertEqual(firstBodyFont, theme.typography.paragraph.font)

        assertColor(
            output.attribute(
                .backgroundColor,
                at: headerRange.location,
                effectiveRange: nil
            ) as? UIColor,
            equals: theme.colors.tableColor.background
        )
        XCTAssertEqual(
            try XCTUnwrap(colorComponents(
                output.attribute(
                    .backgroundColor,
                    at: firstBodyRange.location,
                    effectiveRange: nil
                ) as? UIColor
            )).alpha,
            0,
            accuracy: 0.001
        )
        XCTAssertEqual(
            try XCTUnwrap(colorComponents(
                output.attribute(
                    .backgroundColor,
                    at: secondBodyRange.location,
                    effectiveRange: nil
                ) as? UIColor
            )).alpha,
            theme.table.alternatingRowAlpha,
            accuracy: 0.001
        )

        let bodySeparatorRange = (output.string as NSString).range(of: bodySeparator)
        XCTAssertEqual(
            try XCTUnwrap(colorComponents(
                output.attribute(
                    .foregroundColor,
                    at: bodySeparatorRange.location,
                    effectiveRange: nil
                ) as? UIColor
            )).alpha,
            theme.table.separatorAlpha,
            accuracy: 0.001
        )
    }

    func testUIKitNarrowFallbackPreservesPipesTruncationAndFiniteAttributes() throws {
        let table = makeTable(
            alignments: [.left, .center, .right, .left, .right],
            header: ["abcdefghijklmnop", "B", "C", "D", "E"],
            body: [["123456789012345", "", "three", "four", "five"]]
        )
        let theme = testTheme()
        let output = TableAttributedStringBuilder.build(
            from: table,
            theme: theme,
            constrainedToWidth: 100
        )
        let separator = Array(
            repeating: String(repeating: "─", count: 5),
            count: 5
        ).joined(separator: "  |  ")

        XCTAssertEqual(
            output.string,
            """
            abcdefghijk…  |  B  |  C  |  D  |  E
            \(separator)
            12345678901…  |     |  three  |  four  |  five
            """
        )
        XCTAssertFalse(output.string.contains("\t"))

        let headerStyle = try paragraphStyle(in: output, containing: "abcdefghijk…")
        XCTAssertEqual(headerStyle.firstLineHeadIndent, 8)
        XCTAssertEqual(headerStyle.headIndent, 8)
        XCTAssertEqual(
            headerStyle.lineHeightMultiple,
            theme.typography.paragraph.lineHeightMultiple
        )
        XCTAssertEqual(headerStyle.paragraphSpacing, 3)
        XCTAssertEqual(headerStyle.lineBreakMode, .byWordWrapping)

        let invalidWidthOutput = TableAttributedStringBuilder.build(
            from: table,
            theme: theme,
            constrainedToWidth: .nan
        )
        XCTAssertTrue(invalidWidthOutput.string.contains("  |  "))
        invalidWidthOutput.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: invalidWidthOutput.length)
        ) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            XCTAssertTrue(style.firstLineHeadIndent.isFinite)
            XCTAssertTrue(style.headIndent.isFinite)
            XCTAssertTrue(style.lineHeightMultiple.isFinite)
            XCTAssertTrue(style.paragraphSpacing.isFinite)
            XCTAssertTrue(style.tabStops.allSatisfy { $0.location.isFinite })
        }
    }

    func testUIKitNormalPathBoundsGeneratedContentForExtremeFiniteWidth() {
        let table = makeTable(
            alignments: [.left],
            header: [String(repeating: "x", count: 5_000)],
            body: [["Body"]]
        )
        let output = TableAttributedStringBuilder.build(
            from: table,
            theme: testTheme(),
            constrainedToWidth: .greatestFiniteMagnitude
        )

        XCTAssertTrue(output.string.contains("\u{2026}"))
        XCTAssertLessThan(output.length, 9_000)
    }

    func testUIKitNarrowFallbackClampsNegativeCharacterLimit() {
        let table = makeTable(
            alignments: [.left],
            header: ["Header"],
            body: [["Body"]]
        )
        let theme = testTheme(
            tableStyle: Theme.TableStyle(
                minimumReadableColumnWidth: .greatestFiniteMagnitude,
                narrowFallbackMaxChars: .min
            )
        )
        let output = TableAttributedStringBuilder.build(
            from: table,
            theme: theme,
            constrainedToWidth: 100
        )

        XCTAssertEqual(output.string, "\u{2026}\n─────\n\u{2026}")
    }

    private func paragraphStyle(
        in attributedString: NSAttributedString,
        containing text: String
    ) throws -> NSParagraphStyle {
        let range = (attributedString.string as NSString).range(of: text)
        XCTAssertNotEqual(range.location, NSNotFound)
        return try XCTUnwrap(
            attributedString.attribute(
                .paragraphStyle,
                at: range.location,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
    }
    #endif

    private func makeTable(
        alignments: [TableAlignment?],
        header: [String]?,
        body: [[String]]
    ) -> TableNode {
        var sections: [MarkdownNode] = []
        if let header {
            sections.append(
                TableHeadNode(range: nil, children: [row(header)])
            )
        }
        if !body.isEmpty {
            sections.append(
                TableBodyNode(range: nil, children: body.map(row))
            )
        }
        return TableNode(
            range: nil,
            columnAlignments: alignments,
            children: sections
        )
    }

    private func row(_ values: [String]) -> TableRowNode {
        TableRowNode(range: nil, children: values.map(cell))
    }

    private func cell(_ value: String) -> TableCellNode {
        TableCellNode(
            range: nil,
            children: [TextNode(range: nil, text: value)]
        )
    }

    private func testTheme(
        tableStyle: Theme.TableStyle = Theme.TableStyle()
    ) -> Theme {
        let base = Theme.default
        return Theme(
            typography: base.typography,
            colors: Theme.Colors(
                textColor: ColorToken(
                    foreground: Color(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
                ),
                codeColor: base.colors.codeColor,
                inlineCodeColor: base.colors.inlineCodeColor,
                tableColor: ColorToken(
                    foreground: Color(red: 0.4, green: 0.5, blue: 0.6, alpha: 0.7),
                    background: Color(red: 0.7, green: 0.3, blue: 0.2, alpha: 0.8)
                ),
                linkColor: base.colors.linkColor,
                blockQuoteColor: base.colors.blockQuoteColor,
                thematicBreakColor: base.colors.thematicBreakColor
            ),
            table: tableStyle
        )
    }

    private struct ColorComponents {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat
        let alpha: CGFloat
    }

    private func colorComponents(_ color: Color?) -> ColorComponents? {
        guard let color else { return nil }
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0

        #if canImport(UIKit)
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return nil
        }
        #elseif canImport(AppKit)
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return nil
        }
        rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #endif

        return ColorComponents(red: red, green: green, blue: blue, alpha: alpha)
    }

    private func assertColor(
        _ actual: Color?,
        equals expected: Color,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard
            let actual = colorComponents(actual),
            let expected = colorComponents(expected)
        else {
            XCTFail("Expected colors convertible to RGB", file: file, line: line)
            return
        }

        XCTAssertEqual(actual.red, expected.red, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.green, expected.green, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.blue, expected.blue, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.alpha, expected.alpha, accuracy: 0.001, file: file, line: line)
    }
}
