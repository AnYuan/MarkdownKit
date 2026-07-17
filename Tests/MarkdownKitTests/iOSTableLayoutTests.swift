import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

/// iOS-specific tests verifying the intentional `customDraw` table contract:
/// `LayoutSolver` routes `TableNode` to `TableCardRenderer` and draws the card
/// directly via `CGContext`, so `LayoutResult.attributedString` is nil on this
/// platform. These tests exercise `TableCardRenderer`'s computed layout model
/// (cell content, column alignment/widths, header/body fonts, row geometry)
/// and confirm the closure renders into a `CGContext`.
final class iOSTableLayoutTests: XCTestCase {

    // MARK: - LayoutResult Contract

    func testUIKitTableRoutesToCustomDrawWithNilAttributedString() async throws {
        let markdown = """
        | Name | Score |
        |------|-------|
        | Alice | 95   |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 400)
        let tableLayout = layout.children[0]

        XCTAssertTrue(tableLayout.node is TableNode, "Expected the first child to be a TableNode")
        XCTAssertNil(tableLayout.attributedString,
                     "UIKit table layout should not produce an attributed string — it is drawn via customDraw")
        XCTAssertNotNil(tableLayout.customDraw,
                        "UIKit table layout should provide a customDraw closure")
    }

    func testUIKitSyncTableRetainsCustomDrawContractAndExactGeometry() throws {
        let document = TestHelper.parse("""
        | A | B |
        |---|---|
        | 1 | 2 |
        """)
        let table = try XCTUnwrap(document.children.first as? TableNode)
        let width: CGFloat = 400

        let result = LayoutSolver().solveSync(node: table, constrainedToWidth: width)
        let expected = TableCardRenderer.computeLayout(
            from: table,
            theme: .default,
            constrainedToWidth: width
        )

        XCTAssertEqual(result.size, expected.totalSize)
        XCTAssertNil(result.attributedString)
        XCTAssertNotNil(result.customDraw)
    }

    func testUIKitThematicBreakCustomDrawContractMatchesInBothEnvelopes() async throws {
        let thematicBreak = try XCTUnwrap(
            TestHelper.parse("---").children.first as? ThematicBreakNode
        )
        let width: CGFloat = 375
        let solver = LayoutSolver(cache: LayoutCache())

        let async = await solver.solve(node: thematicBreak, constrainedToWidth: width)
        let sync = solver.solveSync(node: thematicBreak, constrainedToWidth: width)
        let style = Theme.default.thematicBreak
        let expectedSize = CGSize(
            width: width,
            height: style.paddingTop + style.dividerHeight + style.paddingBottom
        )

        for result in [async, sync] {
            XCTAssertEqual(result.size, expectedSize)
            XCTAssertNil(result.attributedString)
            XCTAssertNotNil(result.customDraw)
        }
        XCTAssertNotEqual(async.renderFingerprint, sync.renderFingerprint)
    }

    func testUIKitTableLayoutSizeMatchesTableCardRendererComputedLayout() async throws {
        let markdown = """
        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
        """
        let width: CGFloat = 600
        let layout = await TestHelper.solveLayout(markdown, width: width)
        let tableLayout = layout.children[0]

        let document = TestHelper.parse(markdown)
        let table = try XCTUnwrap(document.children.first as? TableNode)
        let computed = TableCardRenderer.computeLayout(from: table, theme: .default, constrainedToWidth: width)

        XCTAssertEqual(tableLayout.size, computed.totalSize,
                       "LayoutSolver's reported size should match TableCardRenderer's computed total size")
    }

    // MARK: - TableCardRenderer Cell Content

    func testTableCardRendererCellContentMatchesSourceMarkdown() throws {
        let markdown = """
        | Platform | Status |
        |----------|--------|
        | macOS    | Done   |
        | iOS      | WIP    |
        """
        let document = TestHelper.parse(markdown)
        let table = try XCTUnwrap(document.children.first as? TableNode)
        let layout = TableCardRenderer.computeLayout(from: table, theme: .default, constrainedToWidth: 500)

        XCTAssertEqual(layout.rows.count, 3, "Expected 1 header row + 2 body rows")

        let headerTexts = layout.rows[0].cells.map(\.text.string)
        XCTAssertEqual(headerTexts, ["Platform", "Status"])

        let firstBodyTexts = layout.rows[1].cells.map(\.text.string)
        XCTAssertEqual(firstBodyTexts, ["macOS", "Done"])

        let secondBodyTexts = layout.rows[2].cells.map(\.text.string)
        XCTAssertEqual(secondBodyTexts, ["iOS", "WIP"])

        XCTAssertTrue(layout.rows[0].isHeader, "First row should be flagged as the header")
        XCTAssertFalse(layout.rows[1].isHeader, "Body rows should not be flagged as the header")
        XCTAssertFalse(layout.rows[2].isHeader, "Body rows should not be flagged as the header")
    }

    func testTableCardRendererDoesNotExposeRawMarkdownSyntax() throws {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let document = TestHelper.parse(markdown)
        let table = try XCTUnwrap(document.children.first as? TableNode)
        let layout = TableCardRenderer.computeLayout(from: table, theme: .default, constrainedToWidth: 400)

        for row in layout.rows {
            for cell in row.cells {
                XCTAssertFalse(cell.text.string.contains("|"), "Cell text should not contain raw markdown pipes")
                XCTAssertFalse(cell.text.string.contains("-"), "Cell text should not contain separator dashes")
            }
        }
    }

    // MARK: - Column Alignment

    func testTableCardRendererColumnAlignmentMatchesMarkdownSpec() throws {
        let markdown = """
        | Left | Center | Right |
        |:-----|:------:|------:|
        | a    | b      | c     |
        """
        let document = TestHelper.parse(markdown)
        let table = try XCTUnwrap(document.children.first as? TableNode)
        let layout = TableCardRenderer.computeLayout(from: table, theme: .default, constrainedToWidth: 600)

        let headerRow = layout.rows[0]
        XCTAssertEqual(headerRow.cells[0].alignment, .left, "Column 0 should be left-aligned")
        XCTAssertEqual(headerRow.cells[1].alignment, .center, "Column 1 should be center-aligned")
        XCTAssertEqual(headerRow.cells[2].alignment, .right, "Column 2 should be right-aligned")

        // Alignment should be consistent across every row, not just the header.
        let bodyRow = layout.rows[1]
        XCTAssertEqual(bodyRow.cells[0].alignment, .left)
        XCTAssertEqual(bodyRow.cells[1].alignment, .center)
        XCTAssertEqual(bodyRow.cells[2].alignment, .right)
    }

    // MARK: - Column Widths

    func testTableCardRendererColumnWidthsAreEvenlySplitAndPositive() throws {
        let markdown = """
        | A | B | C | D |
        |---|---|---|---|
        | 1 | 2 | 3 | 4 |
        """
        let document = TestHelper.parse(markdown)
        let table = try XCTUnwrap(document.children.first as? TableNode)
        let width: CGFloat = 400
        let layout = TableCardRenderer.computeLayout(from: table, theme: .default, constrainedToWidth: width)

        XCTAssertEqual(layout.columnWidths.count, 4, "Expected one width per column")
        for columnWidth in layout.columnWidths {
            XCTAssertGreaterThan(columnWidth, 0, "Every column should have positive width")
        }

        let firstWidth = layout.columnWidths[0]
        for columnWidth in layout.columnWidths {
            XCTAssertEqual(columnWidth, firstWidth, accuracy: 0.5,
                           "Columns should be evenly split when cell content is similar in size")
        }
    }

    // MARK: - Header / Body Fonts

    func testTableCardRendererHeaderUsesSemiboldBodyUsesRegularFont() throws {
        let markdown = """
        | Header |
        |--------|
        | Body   |
        """
        let document = TestHelper.parse(markdown)
        let table = try XCTUnwrap(document.children.first as? TableNode)
        let layout = TableCardRenderer.computeLayout(from: table, theme: .default, constrainedToWidth: 400)

        let headerFont = try XCTUnwrap(
            layout.rows[0].cells[0].text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        )
        let bodyFont = try XCTUnwrap(
            layout.rows[1].cells[0].text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
        )

        // `.semibold` doesn't necessarily flip the `.traitBold` symbolic bit, so
        // compare the descriptor's numeric weight trait instead — this is the
        // same signal `UIFont.systemFont(ofSize:weight:)` encodes.
        let headerWeight = weightTrait(of: headerFont)
        let bodyWeight = weightTrait(of: bodyFont)

        XCTAssertEqual(headerWeight, UIFont.Weight.semibold.rawValue, accuracy: 0.01,
                       "Header row should use the semibold system font weight")
        XCTAssertEqual(bodyWeight, UIFont.Weight.regular.rawValue, accuracy: 0.01,
                       "Body row should use the regular system font weight")
        XCTAssertGreaterThan(headerWeight, bodyWeight, "Header font should be heavier than the body font")
        XCTAssertEqual(headerFont.pointSize, Theme.default.table.fontSize, accuracy: 0.01)
        XCTAssertEqual(bodyFont.pointSize, Theme.default.table.fontSize, accuracy: 0.01)
    }

    private func weightTrait(of font: UIFont) -> CGFloat {
        let traits = font.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        return traits?[.weight] as? CGFloat ?? 0
    }

    // MARK: - Row Geometry

    func testTableCardRendererRowGeometryIsMonotonicAndNonOverlapping() throws {
        let markdown = """
        | Name  | Score |
        |-------|-------|
        | Alice | 95    |
        | Bob   | 87    |
        """
        let document = TestHelper.parse(markdown)
        let table = try XCTUnwrap(document.children.first as? TableNode)
        let layout = TableCardRenderer.computeLayout(from: table, theme: .default, constrainedToWidth: 420)

        XCTAssertEqual(layout.rows.count, 3)

        var previousRowEnd: CGFloat = 0
        for (index, row) in layout.rows.enumerated() {
            XCTAssertGreaterThan(row.height, 0, "Row \(index) should have positive height")
            XCTAssertGreaterThanOrEqual(row.yOffset, previousRowEnd,
                                        "Row \(index) should start at or after the previous row's end")
            previousRowEnd = row.yOffset + row.height
        }

        XCTAssertLessThanOrEqual(previousRowEnd, layout.totalSize.height,
                                 "Rows should fit within the total computed card height")
    }

    // MARK: - Constrained Size

    func testTableCardRendererConstrainedWidthProducesFiniteNonNegativeSize() throws {
        let markdown = """
        | Feature | Status | Priority | Owner |
        |---------|--------|----------|-------|
        | Parsing | Done   | High     | Core  |
        """
        let document = TestHelper.parse(markdown)
        let table = try XCTUnwrap(document.children.first as? TableNode)
        let width: CGFloat = 100 // Very narrow width — should not crash or produce invalid geometry.
        let layout = TableCardRenderer.computeLayout(from: table, theme: .default, constrainedToWidth: width)

        XCTAssertTrue(layout.totalSize.width.isFinite)
        XCTAssertTrue(layout.totalSize.height.isFinite)
        XCTAssertGreaterThanOrEqual(layout.totalSize.width, 0)
        XCTAssertGreaterThan(layout.totalSize.height, 0)
        XCTAssertLessThanOrEqual(layout.totalSize.width, width,
                                 "Table card width should not exceed the constrained width")

        for columnWidth in layout.columnWidths {
            XCTAssertGreaterThanOrEqual(columnWidth, 0, "Column widths should never be negative")
        }
    }

    func testUIKitTableContentFitsWithinConstrainedWidth() async throws {
        let markdown = """
        | Feature | Status | Priority |
        |:--------|:------:|--------:|
        | Parsing | Done   | High    |
        | Layout  | WIP    | Medium  |
        """
        let width: CGFloat = 375 // iPhone SE width
        let layout = await TestHelper.solveLayout(markdown, width: width)
        let tableLayout = layout.children[0]

        XCTAssertLessThanOrEqual(tableLayout.size.width, width,
                                 "Table layout width should not exceed the constrained width")
        XCTAssertGreaterThan(tableLayout.size.height, 0,
                             "Table should have positive height")
        XCTAssertNil(tableLayout.attributedString)
        XCTAssertNotNil(tableLayout.customDraw)
    }

    // MARK: - CGContext Rendering

    func testTableCardRendererDrawsIntoCGContextWithoutCrashing() throws {
        let markdown = """
        | Name  | Score |
        |-------|-------|
        | Alice | 95    |
        | Bob   | 87    |
        """
        let document = TestHelper.parse(markdown)
        let table = try XCTUnwrap(document.children.first as? TableNode)
        let theme = Theme.default
        let layout = TableCardRenderer.computeLayout(from: table, theme: theme, constrainedToWidth: 420)
        let resolvedColors = TableCardRenderer.ResolvedColors.resolve(from: theme)

        let renderer = UIGraphicsImageRenderer(size: layout.totalSize)
        let image = renderer.image { rendererContext in
            TableCardRenderer.draw(
                layout: layout,
                resolvedColors: resolvedColors,
                in: rendererContext.cgContext,
                size: layout.totalSize
            )
        }

        XCTAssertTrue(TestHelper.imageContainsVisibleNonWhitePixel(image.cgImage),
                      "Drawing the table card should paint visible content into the context")
    }

    func testUIKitTableCustomDrawRendersThroughLayoutSolverPipeline() async throws {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 400)
        let tableLayout = layout.children[0]
        let customDraw = try XCTUnwrap(tableLayout.customDraw)

        let renderer = UIGraphicsImageRenderer(size: tableLayout.size)
        let image = renderer.image { rendererContext in
            customDraw(rendererContext.cgContext, tableLayout.size)
        }

        XCTAssertTrue(TestHelper.imageContainsVisibleNonWhitePixel(image.cgImage),
                      "The LayoutSolver-provided customDraw closure should paint visible content")
    }
}
#endif
