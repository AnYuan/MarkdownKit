import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class TableLayoutSharedTests: XCTestCase {

    func testGridRectangularizesRaggedRowsAndIgnoresEmptyContent() {
        let table = TableNode(
            range: nil,
            columnAlignments: [],
            children: [
                ParagraphNode(range: nil, children: [text("ignored section")]),
                TableHeadNode(range: nil, children: [
                    row(["H1", "H2"]),
                    TableRowNode(range: nil, children: []),
                    TableRowNode(range: nil, children: [
                        ParagraphNode(range: nil, children: [text("ignored row child")])
                    ])
                ]),
                TableBodyNode(range: nil, children: [
                    row(["A", "B", "C"]),
                    row(["D"])
                ])
            ]
        )

        let grid = TableLayoutShared.Grid(table: table)

        XCTAssertEqual(grid.columnCount, 3)
        XCTAssertEqual(grid.rows.count, 3)
        XCTAssertEqual(grid.rows.map { $0.cells.map(\.text) }, [
            ["H1", "H2", ""],
            ["A", "B", "C"],
            ["D", "", ""]
        ])
        XCTAssertTrue(grid.rows.allSatisfy { $0.cells.count == grid.columnCount })
        XCTAssertEqual(grid.rows[2].cells.map(\.column), [0, 1, 2])
    }

    func testDirectCellsFormOneCompatibilityRowAfterStructuredRows() {
        let table = TableNode(
            range: nil,
            columnAlignments: [],
            children: [
                TableHeadNode(range: nil, children: [
                    cell("Direct A"),
                    TableRowNode(range: nil, children: []),
                    row(["Structured"]),
                    ParagraphNode(range: nil, children: [text("ignored")]),
                    cell("Direct B")
                ]),
                TableBodyNode(range: nil, children: [
                    cell("Body A"),
                    cell("Body B")
                ])
            ]
        )

        let grid = TableLayoutShared.Grid(table: table)

        XCTAssertEqual(grid.columnCount, 2)
        XCTAssertEqual(grid.rows.map { $0.cells.map(\.text) }, [
            ["Structured", ""],
            ["Direct A", "Direct B"],
            ["Body A", "Body B"]
        ])
        XCTAssertEqual(grid.rows.map(\.role), [
            .header,
            .header,
            .body(index: 0)
        ])
    }

    func testRolesCarryBodyIndicesIndependentOfHeaderCount() {
        let table = TableNode(
            range: nil,
            columnAlignments: [],
            children: [
                TableBodyNode(range: nil, children: [row(["B0"])]),
                TableHeadNode(range: nil, children: [row(["H0"])]),
                TableBodyNode(range: nil, children: [cell("B1")]),
                TableHeadNode(range: nil, children: [cell("H1")]),
                TableBodyNode(range: nil, children: [row(["B2"])])
            ]
        )

        let rows = TableLayoutShared.Grid(table: table).rows

        XCTAssertEqual(rows.map(\.role), [
            .body(index: 0),
            .header,
            .body(index: 1),
            .header,
            .body(index: 2)
        ])
        XCTAssertEqual(rows.map(\.isHeader), [false, true, false, true, false])
    }

    func testAlignmentDefaultsAndColumnConsistency() {
        let table = TableNode(
            range: nil,
            columnAlignments: [nil, .center, .right],
            children: [
                TableHeadNode(range: nil, children: [row(["A", "B", "C", "D"])]),
                TableBodyNode(range: nil, children: [row(["1"])])
            ]
        )

        let grid = TableLayoutShared.Grid(table: table)
        let expected: [TableLayoutShared.Alignment] = [.left, .center, .right, .left]

        XCTAssertEqual(grid.columnCount, 4)
        XCTAssertEqual(grid.rows[0].cells.map(\.alignment), expected)
        XCTAssertEqual(grid.rows[1].cells.map(\.alignment), expected)
    }

    func testInlineFlatteningAndEmptyDisplayText() {
        let richCell = TableCellNode(range: nil, children: [
            text("  alpha\n"),
            EmphasisNode(range: nil, children: [
                InlineCodeNode(range: nil, code: "let x"),
                text("\n"),
                MathNode(range: nil, style: .inline, equation: "x+y")
            ]),
            text("  ")
        ])
        let emptyCell = TableCellNode(range: nil, children: [text("\n \n")])
        let table = TableNode(
            range: nil,
            columnAlignments: [],
            children: [
                TableBodyNode(range: nil, children: [
                    TableRowNode(range: nil, children: [richCell, emptyCell]),
                    row(["padding source"])
                ])
            ]
        )

        let grid = TableLayoutShared.Grid(table: table)

        XCTAssertEqual(grid.rows[0].cells[0].text, "alpha let x x+y")
        XCTAssertEqual(grid.rows[0].cells[0].displayText, "alpha let x x+y")
        XCTAssertEqual(grid.rows[0].cells[1].text, "")
        XCTAssertEqual(grid.rows[0].cells[1].displayText, " ")
        XCTAssertEqual(grid.rows[1].cells[1].text, "")
        XCTAssertEqual(grid.rows[1].cells[1].displayText, " ")
    }

    func testAppKitPolicyRepresentsCurrentFormula() {
        let policy = TableLayoutShared.UniformColumnPolicy.appKit(
            horizontalPadding: 16,
            borderAllowance: 2
        )

        let geometry = policy.geometry(columnCount: 3, constrainedToWidth: 400)
        XCTAssertEqual(geometry.availableWidth, 384)
        XCTAssertEqual(geometry.columnWidth, 128)
        XCTAssertEqual(geometry.contentWidth, 110)
        XCTAssertEqual(geometry.columnOrigins, [0, 128, 256])
        XCTAssertEqual(geometry.columnWidths, [128, 128, 128])
        XCTAssertEqual(geometry.totalWidth, 384)

        let narrow = policy.geometry(columnCount: 3, constrainedToWidth: 100)
        XCTAssertEqual(narrow.availableWidth, 160)
        XCTAssertEqual(narrow.columnWidth, 72)
        XCTAssertEqual(narrow.contentWidth, 54)
    }

    func testUIKitAttributedPolicyRepresentsCurrentFormula() {
        let policy = TableLayoutShared.UniformColumnPolicy.uiKitAttributed(horizontalInset: 8)
        let geometry = policy.geometry(columnCount: 3, constrainedToWidth: 400)

        XCTAssertEqual(geometry.availableWidth, 384)
        XCTAssertEqual(geometry.columnWidth, 128)
        XCTAssertEqual(geometry.contentWidth, 128)
        XCTAssertEqual(geometry.columnOrigins, [8, 136, 264])
        XCTAssertEqual(geometry.columnWidths, [128, 128, 128])
        XCTAssertEqual(geometry.totalWidth, 400)
    }

    func testUIKitCardPolicyRepresentsCurrentFormula() {
        let policy = TableLayoutShared.UniformColumnPolicy.uiKitCard(
            borderWidth: 1,
            cellPadding: 12
        )
        let geometry = policy.geometry(columnCount: 3, constrainedToWidth: 400)

        XCTAssertEqual(geometry.availableWidth, 398)
        XCTAssertEqual(geometry.columnWidth, 132)
        XCTAssertEqual(geometry.contentWidth, 108)
        XCTAssertEqual(geometry.columnOrigins, [1, 133, 265])
        XCTAssertEqual(geometry.columnWidths, [132, 132, 132])
        XCTAssertEqual(geometry.totalWidth, 398)
    }

    func testZeroColumnsReturnsZeroGeometryForEveryPolicy() {
        let policies: [TableLayoutShared.UniformColumnPolicy] = [
            .appKit(horizontalPadding: 16, borderAllowance: 2),
            .uiKitAttributed(horizontalInset: 8),
            .uiKitCard(borderWidth: 1, cellPadding: 12)
        ]

        for policy in policies {
            XCTAssertEqual(
                policy.geometry(columnCount: 0, constrainedToWidth: .infinity),
                .zero
            )
            XCTAssertEqual(
                policy.geometry(columnCount: -1, constrainedToWidth: .nan),
                .zero
            )
        }
    }

    func testInvalidWidthsAndManyColumnsProduceFiniteNonnegativeGeometry() {
        let invalidPolicy = TableLayoutShared.UniformColumnPolicy(
            minimumAvailableWidth: -.infinity,
            availableWidthDeduction: .nan,
            minimumColumnWidth: -1,
            contentWidthDeduction: .infinity,
            minimumContentWidth: -.infinity,
            leadingColumnOrigin: -5,
            totalWidthAddition: .nan,
            totalWidthLimit: .constrainedWidth
        )
        let widths: [CGFloat] = [0, -100, .infinity, -.infinity, .nan]

        for width in widths {
            assertFiniteNonnegative(
                invalidPolicy.geometry(columnCount: 10_000, constrainedToWidth: width),
                expectedColumnCount: 10_000
            )
        }

        let cardPolicy = TableLayoutShared.UniformColumnPolicy.uiKitCard(
            borderWidth: .infinity,
            cellPadding: -12
        )
        assertFiniteNonnegative(
            cardPolicy.geometry(columnCount: 1_000, constrainedToWidth: 320),
            expectedColumnCount: 1_000
        )
    }

    func testSharedValuesAreEquatableAndSendable() {
        let table = TableNode(
            range: nil,
            columnAlignments: [.left],
            children: [TableBodyNode(range: nil, children: [row(["A"])])]
        )
        let firstGrid = TableLayoutShared.Grid(table: table)
        let secondGrid = TableLayoutShared.Grid(table: table)
        let policy = TableLayoutShared.UniformColumnPolicy.uiKitAttributed(horizontalInset: 8)
        let geometry = policy.geometry(columnCount: 1, constrainedToWidth: 200)

        XCTAssertEqual(firstGrid, secondGrid)
        requireSendable(firstGrid)
        requireSendable(policy)
        requireSendable(geometry)
    }

    func testNeutralAlignmentUsesSinglePlatformConversion() {
        XCTAssertEqual(TableLayoutShared.Alignment.left.textAlignment, .left)
        XCTAssertEqual(TableLayoutShared.Alignment.center.textAlignment, .center)
        XCTAssertEqual(TableLayoutShared.Alignment.right.textAlignment, .right)
    }

    private func assertFiniteNonnegative(
        _ geometry: TableLayoutShared.UniformColumnGeometry,
        expectedColumnCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let scalars = [
            geometry.availableWidth,
            geometry.columnWidth,
            geometry.contentWidth,
            geometry.totalWidth
        ] + geometry.columnOrigins + geometry.columnWidths

        XCTAssertEqual(geometry.columnOrigins.count, expectedColumnCount, file: file, line: line)
        XCTAssertEqual(geometry.columnWidths.count, expectedColumnCount, file: file, line: line)
        XCTAssertTrue(scalars.allSatisfy(\.isFinite), file: file, line: line)
        XCTAssertTrue(scalars.allSatisfy { $0 >= 0 }, file: file, line: line)
    }

    private func row(_ texts: [String]) -> TableRowNode {
        TableRowNode(range: nil, children: texts.map(cell))
    }

    private func cell(_ value: String) -> TableCellNode {
        TableCellNode(range: nil, children: [text(value)])
    }

    private func text(_ value: String) -> TextNode {
        TextNode(range: nil, text: value)
    }

    private func requireSendable<T: Sendable>(_: T) {}
}
