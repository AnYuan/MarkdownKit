import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Tests verifying cross-platform iOS/macOS layout behavior.
final class CrossPlatformLayoutTests: XCTestCase {

    // MARK: - Color.platformSecondaryLabel

    func testPlatformSecondaryLabelIsNotClear() {
        let color = Color.platformSecondaryLabel
        // The secondary label color should be an actual visible color, not .clear
        XCTAssertNotEqual(color, .clear)
    }

    func testPlatformSecondaryLabelMatchesNativeColor() {
        #if canImport(UIKit)
        XCTAssertEqual(Color.platformSecondaryLabel, UIColor.secondaryLabel)
        #elseif canImport(AppKit)
        XCTAssertEqual(Color.platformSecondaryLabel, NSColor.secondaryLabelColor)
        #endif
    }

    // MARK: - Table layout (cross-platform)
    //
    // AppKit renders tables as an `NSAttributedString` (NSTextTableBlock-based).
    // UIKit renders tables as a card drawn directly via `CGContext`, so
    // `LayoutResult.attributedString` is intentionally nil there; content is
    // instead verified through `TableCardRenderer`'s computed cell model, and
    // "rendered output" is the presence of a `customDraw` closure.

    func testTableLayoutProducesRenderedOutput() async throws {
        let markdown = """
        | Name | Score |
        |------|-------|
        | Alice | 95   |
        | Bob   | 87   |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 500)
        XCTAssertEqual(layout.children.count, 1)

        let tableLayout = layout.children[0]
        XCTAssertGreaterThan(tableLayout.size.height, 0)
        XCTAssertGreaterThan(tableLayout.size.width, 0)

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        XCTAssertNotNil(tableLayout.attributedString)
        #else
        XCTAssertNil(tableLayout.attributedString,
                     "UIKit tables are drawn via customDraw, not an attributed string")
        XCTAssertNotNil(tableLayout.customDraw, "UIKit tables should provide a customDraw closure")
        #endif
    }

    func testTableLayoutContainsAllCellContent() async throws {
        let markdown = """
        | Platform | Status |
        |----------|--------|
        | macOS    | Done   |
        | iOS      | Done   |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 500)
        let text = renderedTableText(from: layout.children[0], width: 500)

        XCTAssertTrue(text.contains("Platform"), "Missing header cell 'Platform'")
        XCTAssertTrue(text.contains("Status"), "Missing header cell 'Status'")
        XCTAssertTrue(text.contains("macOS"), "Missing body cell 'macOS'")
        XCTAssertTrue(text.contains("iOS"), "Missing body cell 'iOS'")
        XCTAssertTrue(text.contains("Done"), "Missing body cell 'Done'")
    }

    func testTableLayoutDoesNotExposeRawMarkdown() async throws {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 400)
        let text = renderedTableText(from: layout.children[0], width: 400)

        XCTAssertFalse(text.contains("|---"), "Should not expose markdown separator syntax")
    }

    func testTableLayoutHeaderUsesEmphasizedFontWeight() async throws {
        let markdown = """
        | Header |
        |--------|
        | Body   |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 400)
        let tableLayout = layout.children[0]

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        guard let attrStr = tableLayout.attributedString else {
            XCTFail("Table layout missing attributed string")
            return
        }

        // Check the first character's font (should be from the header row)
        guard attrStr.length > 0 else {
            XCTFail("Empty attributed string")
            return
        }

        let firstCharAttrs = attrStr.attributes(at: 0, effectiveRange: nil)
        guard let font = firstCharAttrs[.font] as? Font else {
            XCTFail("No font attribute on first character")
            return
        }

        let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
        XCTAssertTrue(isBold, "Header row should use bold font")
        #else
        // UIKit tables draw via `TableCardRenderer`, whose header row uses a
        // semibold system font (not necessarily flipping the `.traitBold` bit),
        // so compare the descriptor's numeric weight trait instead.
        let document = TestHelper.parse(markdown)
        guard let table = document.children.first as? TableNode else {
            XCTFail("Expected a TableNode")
            return
        }
        let cardLayout = TableCardRenderer.computeLayout(from: table, theme: .default, constrainedToWidth: 400)
        guard let headerFont = cardLayout.rows.first?.cells.first?.text.attribute(.font, at: 0, effectiveRange: nil) as? UIFont else {
            XCTFail("No font attribute on header cell")
            return
        }
        let traits = headerFont.fontDescriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        let weight = traits?[.weight] as? CGFloat ?? 0
        XCTAssertEqual(weight, UIFont.Weight.semibold.rawValue, accuracy: 0.01,
                       "Header row should use the semibold system font weight")
        #endif
    }

    func testTableLayoutSingleColumnTable() async throws {
        let markdown = """
        | Only |
        |------|
        | Cell |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 400)
        let text = renderedTableText(from: layout.children[0], width: 400)

        XCTAssertTrue(text.contains("Only"))
        XCTAssertTrue(text.contains("Cell"))
    }

    func testTableLayoutManyColumns() async throws {
        let markdown = """
        | A | B | C | D | E |
        |---|---|---|---|---|
        | 1 | 2 | 3 | 4 | 5 |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 800)
        let text = renderedTableText(from: layout.children[0], width: 800)

        for char in ["A", "B", "C", "D", "E", "1", "2", "3", "4", "5"] {
            XCTAssertTrue(text.contains(char), "Missing cell '\(char)' in table output")
        }
    }

    func testTableLayoutHandlesLongCellContent() async throws {
        let markdown = """
        | Name | Description |
        |------|-------------|
        | Alice | This is a very long description that should be handled gracefully on all platforms |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 250)
        let tableLayout = layout.children[0]
        let text = renderedTableText(from: tableLayout, width: 250)

        // On all platforms, the table should render without crash and contain content
        XCTAssertGreaterThan(text.count, 0)
        XCTAssertTrue(text.contains("Name"), "Header content should be present")
        XCTAssertTrue(text.contains("Alice"), "Body cell content should be present")
        XCTAssertTrue(tableLayout.size.width.isFinite && tableLayout.size.height.isFinite,
                     "Table geometry should remain finite for long cell content")
    }

    func testCanonicalTableGridFeedsPlatformAdapterContract() throws {
        let table = TableNode(
            range: nil,
            columnAlignments: [.left, .center, .right],
            children: [
                ParagraphNode(range: nil, children: [TextNode(range: nil, text: "ignored")]),
                TableHeadNode(range: nil, children: [
                    tableRow(["Name", "Status"])
                ]),
                TableBodyNode(range: nil, children: [
                    tableRow(["Alice"]),
                    ParagraphNode(range: nil, children: [TextNode(range: nil, text: "ignored")]),
                    tableRow(["Bob", "", "Done"])
                ])
            ]
        )
        let grid = TableLayoutShared.Grid(table: table)
        let expectedDisplayText = [
            ["Name", "Status", " "],
            ["Alice", " ", " "],
            ["Bob", " ", "Done"]
        ]

        XCTAssertEqual(grid.columnCount, 3)
        XCTAssertTrue(grid.rows.allSatisfy { $0.cells.count == grid.columnCount })
        XCTAssertEqual(grid.rows.map { $0.cells.map(\.displayText) }, expectedDisplayText)
        XCTAssertEqual(
            grid.rows.map { $0.cells.map(\.alignment) },
            Array(repeating: [.left, .center, .right], count: 3)
        )

        let layout = LayoutSolver().solveSync(node: table, constrainedToWidth: 400)

        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        let attributedString = try XCTUnwrap(layout.attributedString)
        XCTAssertNil(layout.customDraw)

        var nativeCells = Array(repeating: "", count: grid.rows.count * grid.columnCount)
        attributedString.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: attributedString.length)
        ) { value, range, _ in
            guard
                let style = value as? NSParagraphStyle,
                let block = style.textBlocks.first as? NSTextTableBlock
            else {
                return
            }

            XCTAssertEqual(block.table.numberOfColumns, grid.columnCount)
            let index = block.startingRow * grid.columnCount + block.startingColumn
            nativeCells[index] = attributedString.attributedSubstring(from: range).string
                .trimmingCharacters(in: .newlines)
        }
        XCTAssertEqual(nativeCells, expectedDisplayText.flatMap { $0 })
        #elseif canImport(UIKit) && !os(watchOS)
        XCTAssertNil(layout.attributedString)
        XCTAssertNotNil(layout.customDraw)

        let cardLayout = TableCardRenderer.computeLayout(
            from: table,
            theme: .default,
            constrainedToWidth: 400
        )
        XCTAssertEqual(cardLayout.columnWidths.count, grid.columnCount)
        XCTAssertEqual(
            cardLayout.rows.map { $0.cells.map(\.text.string) },
            expectedDisplayText
        )

        let nestedFallback = TableAttributedStringBuilder.build(
            from: table,
            theme: .default,
            constrainedToWidth: 400
        )
        XCTAssertGreaterThan(nestedFallback.length, 0)
        for text in ["Name", "Status", "Alice", "Bob", "Done"] {
            XCTAssertTrue(nestedFallback.string.contains(text))
        }
        #endif
    }

    // MARK: - Code block language label uses platformSecondaryLabel

    func testCodeBlockLanguageLabelColor() async throws {
        let markdown = """
        ```swift
        let x = 1
        ```
        """
        let layout = await TestHelper.solveLayout(markdown, width: 400)
        guard let attrStr = layout.children[0].attributedString else {
            XCTFail("Code layout missing attributed string")
            return
        }

        // The first run is the language label "SWIFT\n" which should use platformSecondaryLabel
        guard attrStr.length > 0 else { return }
        let attrs = attrStr.attributes(at: 0, effectiveRange: nil)
        guard let color = attrs[.foregroundColor] as? Color else {
            XCTFail("No foreground color on language label")
            return
        }
        XCTAssertEqual(
            color,
            AppearanceColorResolver.resolveColor(.platformSecondaryLabel, for: .light),
                       "Language label should use platformSecondaryLabel color")
    }

    // MARK: - Helpers

    /// Returns the rendered textual content of a table layout, using the
    /// attributed string on AppKit and the `TableCardRenderer`-computed cell
    /// text on UIKit (where `attributedString` is intentionally nil).
    private func renderedTableText(from tableLayout: LayoutResult, width: CGFloat) -> String {
        #if canImport(AppKit) && !targetEnvironment(macCatalyst)
        return tableLayout.attributedString?.string ?? ""
        #else
        guard let table = tableLayout.node as? TableNode else { return "" }
        let cardLayout = TableCardRenderer.computeLayout(from: table, theme: .default, constrainedToWidth: width)
        return cardLayout.rows
            .flatMap { $0.cells.map(\.text.string) }
            .joined(separator: "\n")
        #endif
    }

    private func tableRow(_ values: [String]) -> TableRowNode {
        TableRowNode(
            range: nil,
            children: values.map {
                TableCellNode(
                    range: nil,
                    children: [TextNode(range: nil, text: $0)]
                )
            }
        )
    }
}
