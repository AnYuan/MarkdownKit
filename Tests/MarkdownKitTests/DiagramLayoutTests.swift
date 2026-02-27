import XCTest
@testable import MarkdownKit

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
    // MARK: - DiagramAdapterRegistry Tests

    func testRegistryAdapterReturnsNilForUnregisteredLanguage() {
        let registry = DiagramAdapterRegistry()
        XCTAssertNil(registry.adapter(for: .mermaid),
            "Empty registry should return nil for any language")
    }

    func testRegistryRegisterAndRetrieve() async {
        var registry = DiagramAdapterRegistry()
        registry.register(MockDiagramAdapter(output: "test"), for: .mermaid)

        let adapter = registry.adapter(for: .mermaid)
        XCTAssertNotNil(adapter, "Should retrieve registered adapter")

        let result = await adapter?.render(source: "graph TD", language: .mermaid)
        XCTAssertEqual(result?.string, "test")
    }

    func testRegistryOverwriteExistingAdapter() async {
        var registry = DiagramAdapterRegistry()
        registry.register(MockDiagramAdapter(output: "A"), for: .mermaid)
        registry.register(MockDiagramAdapter(output: "B"), for: .mermaid)

        let result = await registry.adapter(for: .mermaid)?.render(source: "", language: .mermaid)
        XCTAssertEqual(result?.string, "B", "Later registration should overwrite earlier one")
    }

    func testRegistryMultipleLanguages() {
        var registry = DiagramAdapterRegistry()
        registry.register(MockDiagramAdapter(output: "Mermaid"), for: .mermaid)
        registry.register(MockDiagramAdapter(output: "GeoJSON"), for: .geojson)

        XCTAssertNotNil(registry.adapter(for: .mermaid))
        XCTAssertNotNil(registry.adapter(for: .geojson))
        XCTAssertNil(registry.adapter(for: .topojson), "Unregistered language should return nil")
    }

    func testRegistryInitWithAdapters() async {
        let registry = DiagramAdapterRegistry(adapters: [
            .stl: MockDiagramAdapter(output: "STL Render")
        ])

        let result = await registry.adapter(for: .stl)?.render(source: "", language: .stl)
        XCTAssertEqual(result?.string, "STL Render")
    }

    func testDiagramLanguageAllCases() {
        let allCases = DiagramLanguage.allCases
        XCTAssertEqual(allCases.count, 4, "DiagramLanguage should have exactly 4 cases")
        XCTAssertTrue(allCases.contains(.mermaid))
        XCTAssertTrue(allCases.contains(.geojson))
        XCTAssertTrue(allCases.contains(.topojson))
        XCTAssertTrue(allCases.contains(.stl))
    }
}

private struct MockDiagramAdapter: DiagramRenderingAdapter {
    let output: String

    func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        NSAttributedString(string: output)
    }
}
