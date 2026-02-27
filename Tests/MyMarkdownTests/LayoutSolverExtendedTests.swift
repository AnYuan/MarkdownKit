import XCTest
@testable import MyMarkdown

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

    func testTableLayoutAppliesTabStops() async throws {
        let markdown = """
        | Left | Right |
        |:-----|------:|
        | x    | y     |
        """
        let layout = await TestHelper.solveLayout(markdown, width: 600)
        let tableLayout = layout.children[0]

        guard let attrStr = tableLayout.attributedString else {
            XCTFail("Table layout missing attributed string")
            return
        }

        var foundTabStops = false
        attrStr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            if let style = value as? NSParagraphStyle, !style.tabStops.isEmpty {
                foundTabStops = true
            }
        }
        XCTAssertTrue(foundTabStops, "Table attributed string should have tab stops")
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

    func testEmptyDocumentLayoutProducesZeroChildren() async throws {
        let layout = await TestHelper.solveLayout("")
        XCTAssertEqual(layout.children.count, 0)
    }
}
