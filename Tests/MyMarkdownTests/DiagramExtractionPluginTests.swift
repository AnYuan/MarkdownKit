import XCTest
@testable import MyMarkdown

final class DiagramExtractionPluginTests: XCTestCase {

    func testMermaidFenceConvertsToDiagramNode() throws {
        let markdown = """
        ```mermaid
        graph TD
        A-->B
        ```
        """

        let doc = TestHelper.parse(markdown, plugins: [DiagramExtractionPlugin()])
        guard let diagram = doc.children.first as? DiagramNode else {
            XCTFail("Expected diagram fence to convert to DiagramNode")
            return
        }

        XCTAssertEqual(diagram.language, .mermaid)
        XCTAssertTrue(diagram.source.contains("graph TD"))
    }

    func testUnsupportedFenceLanguageRemainsCodeBlock() throws {
        let markdown = """
        ```swift
        print("Hello")
        ```
        """

        let doc = TestHelper.parse(markdown, plugins: [DiagramExtractionPlugin()])
        XCTAssertTrue(doc.children.first is CodeBlockNode)
    }

    func testDiagramFenceInsideDetailsBodyConvertsWhenPluginsChained() throws {
        let markdown = """
        <details open>
        <summary>Diagram</summary>

        ```mermaid
        graph TD
        A-->B
        ```
        </details>
        """

        let doc = TestHelper.parse(
            markdown,
            plugins: [DetailsExtractionPlugin(), DiagramExtractionPlugin()]
        )

        guard let details = doc.children.first as? DetailsNode else {
            XCTFail("Expected DetailsNode")
            return
        }

        let diagrams = details.children.compactMap { $0 as? DiagramNode }
        XCTAssertEqual(diagrams.count, 1)
        XCTAssertEqual(diagrams.first?.language, .mermaid)
    }
}
