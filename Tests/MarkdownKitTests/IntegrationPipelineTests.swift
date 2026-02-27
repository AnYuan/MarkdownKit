import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

final class IntegrationPipelineTests: XCTestCase {

    // MARK: - Complex Document End-to-End

    func testComplexDocumentEndToEndLayout() async throws {
        let markdown = """
        # Title

        A paragraph with **bold** and *italic* text.

        - Item 1
        - Item 2
        - Item 3

        ```swift
        let x = 42
        ```

        | Col A | Col B |
        |-------|-------|
        | 1     | 2     |

        ---
        """

        let layout = await TestHelper.solveLayout(markdown, width: 600)
        XCTAssertGreaterThanOrEqual(layout.children.count, 5,
            "Complex document should produce at least 5 top-level layout children")

        for (index, child) in layout.children.enumerated() {
            XCTAssertGreaterThan(child.size.height, 0,
                "Child[\(index)] (\(type(of: child.node))) should have non-zero height")
            XCTAssertNotNil(child.attributedString,
                "Child[\(index)] (\(type(of: child.node))) should have attributed string")
        }
    }

    func testDocumentWithAllInlineFormattingTypes() async throws {
        let markdown = "**bold** *italic* ~~struck~~ `code` [link](https://example.com) ![img](url)"
        let layout = await TestHelper.solveLayout(markdown)
        let paraLayout = layout.children[0]

        guard let attrStr = paraLayout.attributedString else {
            XCTFail("Expected attributed string for paragraph with all inline types")
            return
        }

        let text = attrStr.string
        XCTAssertTrue(text.contains("bold"), "Should contain bold text")
        XCTAssertTrue(text.contains("italic"), "Should contain italic text")
        XCTAssertTrue(text.contains("struck"), "Should contain strikethrough text")
        XCTAssertTrue(text.contains("code"), "Should contain inline code text")
        XCTAssertTrue(text.contains("link"), "Should contain link text")
        XCTAssertTrue(text.contains("[img]"), "Should contain image alt text in brackets")
    }

    func testMultiPluginDocumentIntegration() async throws {
        let markdown = """
        # Title

        Inline math: $x^2$

        ```mermaid
        graph TD
        A-->B
        ```

        <details>
        <summary>Expand</summary>

        Hidden content.
        </details>
        """

        let plugins: [ASTPlugin] = [
            MathExtractionPlugin(),
            DiagramExtractionPlugin(),
            DetailsExtractionPlugin()
        ]

        let doc = TestHelper.parse(markdown, plugins: plugins)

        // Verify all plugin-specific node types are present
        func findNodeType<T: MarkdownNode>(_ type: T.Type, in node: MarkdownNode) -> Bool {
            if node is T { return true }
            return node.children.contains { findNodeType(type, in: $0) }
        }

        XCTAssertTrue(findNodeType(MathNode.self, in: doc),
            "Document should contain MathNode after MathExtractionPlugin")
        XCTAssertTrue(findNodeType(DiagramNode.self, in: doc),
            "Document should contain DiagramNode after DiagramExtractionPlugin")
        XCTAssertTrue(findNodeType(DetailsNode.self, in: doc),
            "Document should contain DetailsNode after DetailsExtractionPlugin")

        // Verify layout works end-to-end
        let solver = LayoutSolver()
        let layout = await solver.solve(node: doc, constrainedToWidth: 600)
        XCTAssertGreaterThanOrEqual(layout.children.count, 3,
            "Multi-plugin document should produce multiple layout children")
    }

    // MARK: - Layout Constraints

    func testLayoutWidthConstraintRespected() async throws {
        let markdown = """
        # Wide Header

        A paragraph with enough text to potentially exceed narrow width constraints if wrapping is broken.

        - List item one
        - List item two
        """

        let constraintWidth: CGFloat = 300
        let layout = await TestHelper.solveLayout(markdown, width: constraintWidth)

        for (index, child) in layout.children.enumerated() {
            XCTAssertLessThanOrEqual(child.size.width, constraintWidth + 1,
                "Child[\(index)] width (\(child.size.width)) should not exceed constraint (\(constraintWidth))")
        }
    }

    func testLayoutWithCustomThemeProducesCorrectFonts() async throws {
        #if canImport(UIKit)
        let textC = ColorToken(foreground: .label)
        let codeC = ColorToken(foreground: .label, background: .secondarySystemBackground)
        let tableC = ColorToken(foreground: .separator, background: .secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        let textC = ColorToken(foreground: .labelColor)
        let codeC = ColorToken(foreground: .labelColor, background: .windowBackgroundColor)
        let tableC = ColorToken(foreground: .gridColor, background: .controlBackgroundColor)
        #endif

        let customTheme = Theme(
            header1: TypographyToken(font: Font.systemFont(ofSize: 36)),
            header2: TypographyToken(font: Font.systemFont(ofSize: 28)),
            header3: TypographyToken(font: Font.systemFont(ofSize: 22)),
            paragraph: TypographyToken(font: Font.systemFont(ofSize: 18)),
            codeBlock: TypographyToken(font: Font.monospacedSystemFont(ofSize: 15, weight: .regular)),
            textColor: textC,
            codeColor: codeC,
            tableColor: tableC
        )

        let layout = await TestHelper.solveLayout("# Header", theme: customTheme)
        let headerLayout = layout.children[0]

        guard let attrStr = headerLayout.attributedString else {
            XCTFail("Expected attributed string for header")
            return
        }

        var foundFont = false
        attrStr.enumerateAttribute(NSAttributedString.Key.font, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            if let font = value as? Font {
                // Custom theme uses size 36 for H1
                XCTAssertEqual(font.pointSize, 36, accuracy: 0.1,
                    "Header should use custom theme font size 36")
                foundFont = true
            }
        }
        XCTAssertTrue(foundFont, "Should find font attribute in header layout")
    }

    // MARK: - List Layout Details

    func testNestedListLayoutProducesIndentation() async throws {
        let markdown = """
        - A
          - B
            - C
        """
        let layout = await TestHelper.solveLayout(markdown)
        let listLayout = layout.children[0]

        guard let attrStr = listLayout.attributedString else {
            XCTFail("Expected attributed string for nested list")
            return
        }

        // Verify indentation exists via paragraph style
        var foundIndent = false
        attrStr.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: attrStr.length)) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            if style.headIndent > 0 || style.firstLineHeadIndent > 0 {
                foundIndent = true
            }
        }
        XCTAssertTrue(foundIndent, "Nested list should have indented paragraph styles")
    }

    func testOrderedListLayoutProducesNumberedPrefixes() async throws {
        let markdown = """
        1. First
        2. Second
        3. Third
        """
        let layout = await TestHelper.solveLayout(markdown)
        let listLayout = layout.children[0]

        guard let text = listLayout.attributedString?.string else {
            XCTFail("Expected attributed string for ordered list")
            return
        }

        XCTAssertTrue(text.contains("1. ") || text.contains("1."), "Should contain numbered prefix '1.'")
        XCTAssertTrue(text.contains("2. ") || text.contains("2."), "Should contain numbered prefix '2.'")
        XCTAssertTrue(text.contains("3. ") || text.contains("3."), "Should contain numbered prefix '3.'")
    }

    // MARK: - Plugin + Layout Integration

    func testBlockQuoteInsideDetailsLayoutIntegration() async throws {
        let markdown = """
        <details open>
        <summary>Info</summary>

        > This is a blockquote inside details.
        </details>
        """

        let layout = await TestHelper.solveLayout(
            markdown,
            width: 700,
            plugins: [DetailsExtractionPlugin()]
        )
        let detailsLayout = layout.children[0]

        guard let text = detailsLayout.attributedString?.string else {
            XCTFail("Expected attributed string for details with blockquote")
            return
        }

        XCTAssertTrue(text.contains("▼"), "Open details should show ▼ disclosure")
        XCTAssertTrue(text.contains("Info"), "Should show summary text")
        XCTAssertTrue(text.contains("┃") || text.contains("blockquote"),
            "Should show blockquote content (bar or text)")
    }

    // MARK: - Performance & Edge Cases

    func testLargeDocumentLayoutPerformance() async throws {
        var lines: [String] = ["# Large Document"]
        for i in 1...50 {
            lines.append("\nParagraph \(i) with some content that needs measuring.")
        }
        let markdown = lines.joined(separator: "\n")

        let layout = await TestHelper.solveLayout(markdown, width: 600)
        XCTAssertGreaterThan(layout.children.count, 40,
            "Large document should produce many layout children")
    }

    func testEmptyAndWhitespaceDocumentLayout() async throws {
        let emptyLayout = await TestHelper.solveLayout("")
        XCTAssertEqual(emptyLayout.children.count, 0)

        let whitespaceLayout = await TestHelper.solveLayout("   \n  \n   ")
        XCTAssertEqual(whitespaceLayout.children.count, 0)
    }
}
