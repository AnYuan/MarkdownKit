import XCTest
@testable import MyMarkdown

final class DiagramLayoutTests: XCTestCase {

    func testDiagramLayoutFallsBackToCodeBlockWhenNoAdapterRegistered() async throws {
        let markdown = """
        ```mermaid
        graph TD
        A-->B
        ```
        """

        let doc = TestHelper.parse(markdown, plugins: [DiagramExtractionPlugin()])
        let solver = LayoutSolver()
        let layout = await solver.solve(node: doc, constrainedToWidth: 700)

        guard let text = layout.children.first?.attributedString?.string else {
            XCTFail("Expected attributed string for diagram fallback")
            return
        }

        XCTAssertTrue(text.hasPrefix("MERMAID\n"))
        XCTAssertTrue(text.contains("graph TD"))
    }

    func testDiagramLayoutUsesRegisteredAdapterOutput() async throws {
        let markdown = """
        ```mermaid
        graph TD
        A-->B
        ```
        """

        let doc = TestHelper.parse(markdown, plugins: [DiagramExtractionPlugin()])
        var registry = DiagramAdapterRegistry()
        registry.register(MockDiagramAdapter(output: "[Rendered Mermaid Diagram]"), for: .mermaid)

        let solver = LayoutSolver(diagramRegistry: registry)
        let layout = await solver.solve(node: doc, constrainedToWidth: 700)

        guard let text = layout.children.first?.attributedString?.string else {
            XCTFail("Expected attributed string for adapter output")
            return
        }

        XCTAssertEqual(text, "[Rendered Mermaid Diagram]")
    }
}

private struct MockDiagramAdapter: DiagramRenderingAdapter {
    let output: String

    func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        NSAttributedString(string: output)
    }
}
