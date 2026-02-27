import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class LayoutSolverExtendedTests: XCTestCase {

    func testListLayoutProducesNonZeroSize() async throws {
        let markdown = """
        - First item
        - Second item
        - Third item
        """
        let layout = await TestHelper.solveLayout(markdown)
        XCTAssertEqual(layout.children.count, 1)

        let listLayout = layout.children[0]
        XCTAssertGreaterThan(listLayout.size.height, 0)
        XCTAssertGreaterThan(listLayout.size.width, 0)
        XCTAssertNotNil(listLayout.attributedString)
    }

    func testCheckboxListLayoutIncludesSymbols() async throws {
        let markdown = """
        - [x] Done
        - [ ] Todo
        """
        let layout = await TestHelper.solveLayout(markdown)
        let listLayout = layout.children[0]

        guard let attrStr = listLayout.attributedString else {
            XCTFail("List layout missing attributed string")
            return
        }

        let text = attrStr.string
        // The LayoutSolver prepends checkbox symbols: ☑ for checked, ☐ for unchecked
        XCTAssertTrue(text.contains("\u{2611}") || text.contains("☑"),
                       "Expected checked checkbox symbol in: \(text)")
        XCTAssertTrue(text.contains("\u{2610}") || text.contains("☐"),
                       "Expected unchecked checkbox symbol in: \(text)")
    }

    func testTableLayoutProducesAttributedString() async throws {
        let markdown = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let layout = await TestHelper.solveLayout(markdown)
        XCTAssertEqual(layout.children.count, 1)

        let tableLayout = layout.children[0]
        XCTAssertNotNil(tableLayout.attributedString)
        XCTAssertGreaterThan(tableLayout.size.height, 0)

        // Verify the table produced some text content
        let text = tableLayout.attributedString?.string ?? ""
        XCTAssertGreaterThan(text.count, 0, "Table text should not be empty")
    }

    func testTableLayoutRetainsHeaderContent() async throws {
        let markdown = """
        | Feature | Status | Priority |
        |:--------|:------:|--------:|
        | Parsing | Done | High |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 700)
        let tableLayout = layout.children[0]

        guard let text = tableLayout.attributedString?.string else {
            XCTFail("Table layout missing attributed string")
            return
        }

        XCTAssertTrue(text.contains("Feature"))
        XCTAssertTrue(text.contains("Status"))
        XCTAssertTrue(text.contains("Priority"))
        XCTAssertFalse(text.contains("|---"), "Rendered table should not expose raw markdown separator syntax")
    }

    func testTableLayoutUsesNativeTextTableBlocks() async throws {
        let markdown = """
        | Left | Center | Right |
        |:-----|:------:|------:|
        | x    | y      | z     |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 600)
        let tableLayout = layout.children[0]

        guard let attrStr = tableLayout.attributedString else {
            XCTFail("Table layout missing attributed string")
            return
        }

        let text = attrStr.string
        XCTAssertFalse(text.contains("|"), "Rendered table should not rely on text pipes")

        var tableBlocks: [NSTextTableBlock] = []
        var foundCenterAlignedCell = false

        attrStr.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: attrStr.length)
        ) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            for block in style.textBlocks {
                if let tableBlock = block as? NSTextTableBlock {
                    tableBlocks.append(tableBlock)
                    if style.alignment == .center {
                        foundCenterAlignedCell = true
                    }
                }
            }
        }

        XCTAssertFalse(tableBlocks.isEmpty, "Expected table rendering to use NSTextTableBlock")
        XCTAssertEqual(tableBlocks.first?.table.numberOfColumns, 3)
        XCTAssertTrue(foundCenterAlignedCell, "Expected center alignment to be propagated to paragraph style")
    }

    func testTableLayoutRespectsPerColumnAlignment() async throws {
        let markdown = """
        | Feature | Status | Priority |
        |:--------|:------:|--------:|
        | Parsing | Done   | High    |
        | Math    | WIP    | Medium  |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 700)
        let tableLayout = layout.children[0]

        guard let attrStr = tableLayout.attributedString else {
            XCTFail("Table layout missing attributed string")
            return
        }

        var sawLeftColumn = false
        var sawCenterColumn = false
        var sawRightColumn = false

        attrStr.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: attrStr.length)
        ) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            for block in style.textBlocks {
                guard let tableBlock = block as? NSTextTableBlock else { continue }
                switch tableBlock.startingColumn {
                case 0:
                    sawLeftColumn = true
                    XCTAssertEqual(style.alignment, .left)
                case 1:
                    sawCenterColumn = true
                    XCTAssertEqual(style.alignment, .center)
                case 2:
                    sawRightColumn = true
                    XCTAssertEqual(style.alignment, .right)
                default:
                    break
                }
            }
        }

        XCTAssertTrue(sawLeftColumn, "Expected left-aligned first column")
        XCTAssertTrue(sawCenterColumn, "Expected centered second column")
        XCTAssertTrue(sawRightColumn, "Expected right-aligned third column")
    }

    func testTableLayoutAppliesHeaderAndAlternatingRowBackgrounds() async throws {
        let markdown = """
        | Col A | Col B |
        |:------|------:|
        | r1a   | r1b   |
        | r2a   | r2b   |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 600)
        let tableLayout = layout.children[0]

        guard let attrStr = tableLayout.attributedString else {
            XCTFail("Table layout missing attributed string")
            return
        }

        var headerHasBackground = false
        var firstBodyHasBackground = false
        var secondBodyHasBackground = false

        attrStr.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: attrStr.length)
        ) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            for block in style.textBlocks {
                guard let tableBlock = block as? NSTextTableBlock else { continue }
                let hasBackground = alpha(of: tableBlock.backgroundColor) > 0.01
                switch tableBlock.startingRow {
                case 0: headerHasBackground = headerHasBackground || hasBackground
                case 1: firstBodyHasBackground = firstBodyHasBackground || hasBackground
                case 2: secondBodyHasBackground = secondBodyHasBackground || hasBackground
                default: break
                }
            }
        }

        XCTAssertTrue(headerHasBackground, "Header row should have a background fill")
        XCTAssertFalse(firstBodyHasBackground, "First body row should remain unshaded")
        XCTAssertTrue(secondBodyHasBackground, "Second body row should use zebra striping")
    }

    func testClosedDetailsLayoutShowsOnlySummaryRow() async throws {
        let markdown = """
        <details>
        <summary>Build status</summary>

        Hidden body.
        </details>
        """

        let layout = await TestHelper.solveLayout(
            markdown,
            width: 700,
            plugins: [DetailsExtractionPlugin()]
        )
        let detailsLayout = layout.children[0]

        guard let text = detailsLayout.attributedString?.string else {
            XCTFail("Details layout missing attributed string")
            return
        }

        XCTAssertTrue(text.contains("▶ Build status"))
        XCTAssertFalse(text.contains("Hidden body."))
    }

    func testOpenDetailsLayoutShowsSummaryAndBody() async throws {
        let markdown = """
        <details open>
        <summary>Build status</summary>

        Visible body.
        </details>
        """

        let layout = await TestHelper.solveLayout(
            markdown,
            width: 700,
            plugins: [DetailsExtractionPlugin()]
        )
        let detailsLayout = layout.children[0]

        guard let text = detailsLayout.attributedString?.string else {
            XCTFail("Details layout missing attributed string")
            return
        }

        XCTAssertTrue(text.contains("▼ Build status"))
        XCTAssertTrue(text.contains("Visible body."))
    }

    func testHeaderLevelsUseCorrectThemeTokens() async throws {
        for level in 1...3 {
            let markdown = String(repeating: "#", count: level) + " Header"
            let layout = await TestHelper.solveLayout(markdown)
            let headerLayout = layout.children[0]

            XCTAssertNotNil(headerLayout.attributedString,
                           "Header level \(level) should have attributed string")
            XCTAssertGreaterThan(headerLayout.size.height, 0,
                                "Header level \(level) should have non-zero height")
        }
    }

    func testCodeBlockLayoutUsesSplashHighlighter() async throws {
        let markdown = """
        ```python
        x = 42
        print(x)
        ```
        """
        let layout = await TestHelper.solveLayout(markdown)
        let codeLayout = layout.children[0]

        XCTAssertNotNil(codeLayout.attributedString)
        XCTAssertGreaterThan(codeLayout.size.height, 0)

        var attrCount = 0
        codeLayout.attributedString?.enumerateAttributes(
            in: NSRange(location: 0, length: codeLayout.attributedString!.length)
        ) { _, _, _ in
            attrCount += 1
        }
        XCTAssertGreaterThan(attrCount, 0)
    }

    func testCodeBlockLayoutPrependsLanguageLabelWhenPresent() async throws {
        let markdown = """
        ```swift
        let x = 1
        ```
        """
        let layout = await TestHelper.solveLayout(markdown)
        let codeLayout = layout.children[0]

        guard let text = codeLayout.attributedString?.string else {
            XCTFail("Code layout missing attributed string")
            return
        }

        XCTAssertTrue(text.hasPrefix("SWIFT\n"), "Expected uppercase language label prefix in code block")
    }

    func testCodeBlockLayoutOmitsLanguageLabelWhenMissing() async throws {
        let markdown = """
        ```
        plain text
        ```
        """
        let layout = await TestHelper.solveLayout(markdown)
        let codeLayout = layout.children[0]

        guard let text = codeLayout.attributedString?.string else {
            XCTFail("Code layout missing attributed string")
            return
        }

        XCTAssertFalse(text.hasPrefix("SWIFT\n"))
        XCTAssertTrue(text.contains("plain text"))
    }

    func testEmptyDocumentLayoutProducesZeroChildren() async throws {
        let layout = await TestHelper.solveLayout("")
        XCTAssertEqual(layout.children.count, 0)
    }
}

private func alpha(of color: Color?) -> CGFloat {
    #if canImport(UIKit)
    return color?.cgColor.alpha ?? 0
    #elseif canImport(AppKit)
    return color?.alphaComponent ?? 0
    #endif
}
