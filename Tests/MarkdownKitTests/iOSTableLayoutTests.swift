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

    func testTableCardRendererUsesCanonicalDisplayTextForRaggedAndEmptyCells() {
        let table = TableNode(
            range: nil,
            columnAlignments: [.left, .center, .right],
            children: [
                TableHeadNode(range: nil, children: [
                    TableRowNode(range: nil, children: [cell("H1"), cell("")])
                ]),
                TableBodyNode(range: nil, children: [
                    row(["A"]),
                    row(["B", "C", "D"])
                ])
            ]
        )

        let layout = TableCardRenderer.computeLayout(
            from: table,
            theme: .default,
            constrainedToWidth: 400
        )

        XCTAssertEqual(layout.rows.map { $0.cells.map(\.text.string) }, [
            ["H1", " ", " "],
            ["A", " ", " "],
            ["B", "C", "D"]
        ])
        XCTAssertTrue(layout.rows.allSatisfy { $0.cells.count == 3 })
        for row in layout.rows {
            XCTAssertEqual(row.cells.map(\.xOffset), layout.columnOrigins)
            XCTAssertEqual(row.cells.map(\.width), layout.columnWidths)
            XCTAssertTrue(row.cells.allSatisfy { $0.contentWidth == 108 })
        }
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

    func testTableCardRendererUsesExactDefaultSharedCardGeometry() throws {
        let table = try parsedTable(from: """
        | A | B | C |
        |---|---|---|
        | 1 | 2 | 3 |
        """)

        let layout = TableCardRenderer.computeLayout(
            from: table,
            theme: .default,
            constrainedToWidth: 400
        )

        XCTAssertEqual(layout.columnWidths, [132, 132, 132])
        XCTAssertEqual(layout.columnOrigins, [1, 133, 265])
        XCTAssertEqual(layout.totalSize.width, 398)
        for row in layout.rows {
            XCTAssertEqual(row.cells.map(\.xOffset), [1, 133, 265])
            XCTAssertEqual(row.cells.map(\.width), [132, 132, 132])
            XCTAssertEqual(row.cells.map(\.contentWidth), [108, 108, 108])
        }
    }

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

    func testTableCardRendererNarrowInvalidAndManyColumnGeometryStaysSafe() {
        let values = (0..<128).map { "C\($0)" }
        let table = makeTable(alignments: [], header: values, body: [values])
        let widths: [CGFloat] = [
            0, 1, 24, 100, 375, 400,
            -100, .nan, .infinity, -.infinity
        ]

        for width in widths {
            let layout = TableCardRenderer.computeLayout(
                from: table,
                theme: .default,
                constrainedToWidth: width
            )
            let geometryValues = layout.columnOrigins
                + layout.columnWidths
                + layout.rows.flatMap { row in
                    [row.yOffset, row.height, row.height - layout.cellPaddingV * 2]
                        + row.cells.flatMap {
                            [$0.xOffset, $0.width, $0.contentWidth]
                        }
                }
                + [layout.totalSize.width, layout.totalSize.height]

            XCTAssertEqual(layout.columnOrigins.count, values.count)
            XCTAssertEqual(layout.columnWidths.count, values.count)
            XCTAssertTrue(
                geometryValues.allSatisfy { $0.isFinite && $0 >= 0 },
                "Expected finite nonnegative geometry for width \(width)"
            )

            for (origin, nextOrigin) in zip(
                layout.columnOrigins,
                layout.columnOrigins.dropFirst()
            ) {
                XCTAssertLessThanOrEqual(
                    origin,
                    nextOrigin,
                    "Column origins must be monotonic for width \(width)"
                )
            }

            var previousRowEnd: CGFloat = 0
            for row in layout.rows {
                XCTAssertGreaterThanOrEqual(row.yOffset, previousRowEnd)
                previousRowEnd = row.yOffset + row.height
                XCTAssertEqual(row.cells.map(\.xOffset), layout.columnOrigins)
                XCTAssertEqual(row.cells.map(\.width), layout.columnWidths)
            }
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

    func testTableCardRendererHonorsConfiguredFontSizeWithoutChangingWeights() throws {
        let configuredSize: CGFloat = 17
        let theme = makeTheme(tableStyle: Theme.TableStyle(fontSize: configuredSize))
        let table = makeTable(alignments: [.left], header: ["Header"], body: [["Body"]])
        let layout = TableCardRenderer.computeLayout(
            from: table,
            theme: theme,
            constrainedToWidth: 400
        )

        let headerFont = try XCTUnwrap(
            layout.rows[0].cells[0].text.attribute(
                .font,
                at: 0,
                effectiveRange: nil
            ) as? UIFont
        )
        let bodyFont = try XCTUnwrap(
            layout.rows[1].cells[0].text.attribute(
                .font,
                at: 0,
                effectiveRange: nil
            ) as? UIFont
        )

        XCTAssertEqual(headerFont.pointSize, configuredSize, accuracy: 0.01)
        XCTAssertEqual(bodyFont.pointSize, configuredSize, accuracy: 0.01)
        XCTAssertEqual(weightTrait(of: headerFont),
                       UIFont.Weight.semibold.rawValue,
                       accuracy: 0.01)
        XCTAssertEqual(weightTrait(of: bodyFont),
                       UIFont.Weight.regular.rawValue,
                       accuracy: 0.01)
    }

    func testTableCardRendererSanitizesInvalidThemeMetrics() throws {
        let theme = makeTheme(
            tableStyle: Theme.TableStyle(
                cornerRadius: .nan,
                borderWidth: -1,
                cellPaddingH: .infinity,
                cellPaddingV: -8,
                dividerHeight: .nan,
                fontSize: -.infinity
            )
        )
        let table = makeTable(
            alignments: [.left, .right],
            header: ["Header", "Value"],
            body: [["Body", "1"]]
        )
        let layout = TableCardRenderer.computeLayout(
            from: table,
            theme: theme,
            constrainedToWidth: 200
        )
        let scalarGeometry = [
            layout.cornerRadius,
            layout.borderWidth,
            layout.cellPaddingH,
            layout.cellPaddingV,
            layout.dividerHeight,
            layout.totalSize.width,
            layout.totalSize.height
        ] + layout.columnOrigins + layout.columnWidths
            + layout.rows.flatMap { row in
                [row.yOffset, row.height] + row.cells.flatMap {
                    [$0.xOffset, $0.width, $0.contentWidth]
                }
            }

        XCTAssertTrue(scalarGeometry.allSatisfy { $0.isFinite && $0 >= 0 })
        for row in layout.rows {
            for cell in row.cells {
                let font = try XCTUnwrap(
                    cell.text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
                )
                XCTAssertTrue(font.pointSize.isFinite)
                XCTAssertGreaterThanOrEqual(font.pointSize, 0)
            }
        }
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

    func testLongUnbrokenAndNormalizedMultilineCellsHaveFiniteWrappedHeights() {
        let longText = String(repeating: "unbroken", count: 80)
        let table = TableNode(
            range: nil,
            columnAlignments: [.left, .left],
            children: [
                TableHeadNode(range: nil, children: [row(["A", "B"])]),
                TableBodyNode(range: nil, children: [
                    TableRowNode(range: nil, children: [
                        cell(longText),
                        TableCellNode(
                            range: nil,
                            children: [TextNode(range: nil, text: "alpha\nbeta\ngamma")]
                        )
                    ])
                ])
            ]
        )

        let layout = TableCardRenderer.computeLayout(
            from: table,
            theme: .default,
            constrainedToWidth: 100
        )
        let bodyRow = layout.rows[1]

        XCTAssertEqual(bodyRow.cells[0].text.string, longText)
        XCTAssertEqual(bodyRow.cells[1].text.string, "alpha beta gamma")
        XCTAssertGreaterThan(bodyRow.height, layout.rows[0].height)
        XCTAssertTrue(layout.rows.allSatisfy { $0.height.isFinite && $0.height >= 0 })
        XCTAssertTrue(layout.totalSize.height.isFinite)
        for cell in bodyRow.cells {
            let paragraphStyle = cell.text.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) as? NSParagraphStyle
            XCTAssertEqual(paragraphStyle?.lineBreakMode, .byWordWrapping)
        }
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

    func testTableCardRendererDrawSafelyNoOpsForInvalidTargetSizesAndPaintsNormally() {
        let table = makeTable(alignments: [.left], header: ["Header"], body: [["Body"]])
        let theme = Theme.default
        let layout = TableCardRenderer.computeLayout(
            from: table,
            theme: theme,
            constrainedToWidth: 200
        )
        let resolvedColors = TableCardRenderer.ResolvedColors.resolve(from: theme)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: layout.totalSize, format: format)
        let referenceImage = renderer.image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: layout.totalSize))
        }
        let referencePixels = pixelData(from: referenceImage)
        let invalidSizes: [CGSize] = [
            .zero,
            CGSize(width: 0, height: layout.totalSize.height),
            CGSize(width: layout.totalSize.width, height: 0),
            CGSize(width: -1, height: layout.totalSize.height),
            CGSize(width: layout.totalSize.width, height: -1),
            CGSize(width: .nan, height: layout.totalSize.height),
            CGSize(width: layout.totalSize.width, height: .infinity),
            CGSize(width: -.infinity, height: layout.totalSize.height)
        ]

        for invalidSize in invalidSizes {
            let image = renderer.image { rendererContext in
                UIColor.white.setFill()
                rendererContext.fill(CGRect(origin: .zero, size: layout.totalSize))
                TableCardRenderer.draw(
                    layout: layout,
                    resolvedColors: resolvedColors,
                    in: rendererContext.cgContext,
                    size: invalidSize
                )
            }
            XCTAssertEqual(
                pixelData(from: image),
                referencePixels,
                "Invalid target size \(invalidSize) should leave the context unchanged"
            )
        }

        let normalImage = renderer.image { rendererContext in
            UIColor.white.setFill()
            rendererContext.fill(CGRect(origin: .zero, size: layout.totalSize))
            TableCardRenderer.draw(
                layout: layout,
                resolvedColors: resolvedColors,
                in: rendererContext.cgContext,
                size: layout.totalSize
            )
        }
        XCTAssertNotEqual(pixelData(from: normalImage), referencePixels)
    }

    func testUIKitTableCustomDrawKeepsHeaderFillAndNoBodyZebraStriping() throws {
        let table = makeTable(alignments: [.left], header: [""], body: [[""], [""]])
        let theme = makeTheme(
            tableForeground: .black,
            tableBackground: .red
        )
        let result = LayoutSolver(theme: theme).solveSync(
            node: table,
            constrainedToWidth: 200
        )
        let customDraw = try XCTUnwrap(result.customDraw)
        let computed = TableCardRenderer.computeLayout(
            from: table,
            theme: theme,
            constrainedToWidth: 200
        )

        XCTAssertNil(result.attributedString)
        XCTAssertEqual(result.size, computed.totalSize)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: result.size, format: format).image {
            UIColor.white.setFill()
            $0.fill(CGRect(origin: .zero, size: result.size))
            customDraw($0.cgContext, result.size)
        }
        let rowSamples = try computed.rows.map { row -> CGImage in
            let point = CGPoint(
                x: result.size.width / 2,
                y: row.yOffset + row.height / 2
            )
            return try XCTUnwrap(croppedPixel(from: image, at: point))
        }

        XCTAssertTrue(
            TestHelper.imageContainsVisibleNonWhitePixel(rowSamples[0]),
            "The header row should retain its configured background fill"
        )
        XCTAssertFalse(
            TestHelper.imageContainsVisibleNonWhitePixel(rowSamples[1]),
            "The first body row should remain clear over the white canvas"
        )
        XCTAssertFalse(
            TestHelper.imageContainsVisibleNonWhitePixel(rowSamples[2]),
            "The second body row should not receive zebra striping"
        )
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

    private func parsedTable(from markdown: String) throws -> TableNode {
        let document = TestHelper.parse(markdown)
        return try XCTUnwrap(document.children.first as? TableNode)
    }

    private func makeTable(
        alignments: [TableAlignment?],
        header: [String]?,
        body: [[String]]
    ) -> TableNode {
        var sections: [MarkdownNode] = []
        if let header {
            sections.append(TableHeadNode(range: nil, children: [row(header)]))
        }
        if !body.isEmpty {
            sections.append(TableBodyNode(range: nil, children: body.map(row)))
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

    private func makeTheme(
        tableStyle: Theme.TableStyle = Theme.TableStyle(),
        tableForeground: UIColor? = nil,
        tableBackground: UIColor? = nil
    ) -> Theme {
        let base = Theme.default
        let colors = Theme.Colors(
            textColor: base.colors.textColor,
            codeColor: base.colors.codeColor,
            inlineCodeColor: base.colors.inlineCodeColor,
            tableColor: ColorToken(
                foreground: tableForeground ?? base.colors.tableColor.foreground,
                background: tableBackground ?? base.colors.tableColor.background
            ),
            linkColor: base.colors.linkColor,
            blockQuoteColor: base.colors.blockQuoteColor,
            thematicBreakColor: base.colors.thematicBreakColor
        )
        return Theme(
            typography: base.typography,
            colors: colors,
            table: tableStyle
        )
    }

    private func croppedPixel(from image: UIImage, at point: CGPoint) -> CGImage? {
        guard let cgImage = image.cgImage else { return nil }
        let x = min(max(Int(floor(point.x)), 0), cgImage.width - 1)
        let y = min(max(Int(floor(point.y)), 0), cgImage.height - 1)
        return cgImage.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))
    }

    private func pixelData(from image: UIImage) -> Data? {
        guard let data = image.cgImage?.dataProvider?.data else { return nil }
        return data as Data
    }
}
#endif
