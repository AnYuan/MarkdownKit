#if canImport(SwiftUI)
import XCTest
@testable import MarkdownKit

@available(iOS 14.0, macOS 11.0, *)
@MainActor
final class MarkdownRenderCoordinatorBenchmarkTests: XCTestCase {
    private static let width: CGFloat = 720
    private static let plugins: [ASTPlugin] = [DiagramExtractionPlugin()]
    private static let theme = Theme.default

    private struct Scenario {
        let engine: MarkdownEngine
        let adapter: TestHelper.BlockingDiagramAdapter
        let registry: DiagramAdapterRegistry
    }

    private enum SetupError: Error {
        case firstDiagramDidNotStart
    }

    func testRapidUpdateLatestSettledLatency() async throws {
        let harness = BenchmarkHarness()
        var finalScenario: Scenario?
        let result = try await harness.measureMainActorAsync(
            label: "latest-settled",
            fixture: "large-3-updates",
            setup: {
                let scenario = try await Self.makeBlockedScenario()
                finalScenario = scenario
                return scenario
            },
            operation: Self.runNewerUpdates
        )

        BenchmarkReportFormatter.printSections([
            (title: "Coordinator Streaming", results: [result])
        ])

        let scenario = try XCTUnwrap(finalScenario)
        let finalText = TestHelper.flattenedLayoutText(from: scenario.engine.layouts)
        let renderedSources = await scenario.adapter.renderedSources()
        let expectedSources = [
            Self.diagramSource(marker: "FIRST"),
            Self.diagramSource(marker: "LATEST")
        ]
        XCTAssertTrue(finalText.contains("VERSION_MARKER_LATEST"))
        XCTAssertFalse(finalText.contains("VERSION_MARKER_FIRST"))
        XCTAssertFalse(finalText.contains("VERSION_MARKER_MIDDLE"))
        XCTAssertEqual(
            renderedSources.map(Self.normalizedDiagramSource),
            expectedSources.map(Self.normalizedDiagramSource)
        )
    }

    private static func makeBlockedScenario() async throws -> Scenario {
        let engine = MarkdownEngine()
        let adapter = TestHelper.BlockingDiagramAdapter(output: "[Rendered streaming diagram]")
        var registry = DiagramAdapterRegistry()
        registry.register(adapter, for: .mermaid)
        let scenario = Scenario(engine: engine, adapter: adapter, registry: registry)

        engine.updateEffectiveContentWidth(
            Self.width,
            markdown: Self.firstDocument,
            plugins: Self.plugins,
            theme: Self.theme,
            diagramRegistry: registry,
            imageLoadingPolicy: .default,
            resourceLimits: .default,
            appearance: .light
        )

        guard await adapter.waitUntilFirstRenderStarts() else {
            await adapter.releaseFirstRender()
            await engine.waitUntilSettled()
            XCTFail("First stale coordinator layout did not reach the blocking diagram adapter within the timeout")
            throw SetupError.firstDiagramDidNotStart
        }

        return scenario
    }

    private static func runNewerUpdates(_ scenario: Scenario) async {
        renderImmediately(Self.middleDocument, in: scenario)
        renderImmediately(Self.latestDocument, in: scenario)
        await scenario.adapter.releaseFirstRender()
        await scenario.engine.waitUntilSettled()
    }

    private static func renderImmediately(_ markdown: String, in scenario: Scenario) {
        scenario.engine.renderForCurrentPlatform(
            markdown: markdown,
            plugins: Self.plugins,
            theme: Self.theme,
            fallbackWidth: Self.width,
            diagramRegistry: scenario.registry,
            imageLoadingPolicy: .default,
            resourceLimits: .default,
            appearance: .light
        )
    }

    private static let firstDocument = document(marker: "FIRST", appendedSections: 0)
    private static let middleDocument = document(marker: "MIDDLE", appendedSections: 1)
    private static let latestDocument = document(marker: "LATEST", appendedSections: 2)

    private static func document(marker: String, appendedSections: Int) -> String {
        let additions = (0..<appendedSections).map { index in
            let section = index + 1
            return """
            ## Streaming addition \(section)

            This appended section models a growing editor document with realistic paragraph, list, and inline `code` content.

            - Incremental item \(section).1
            - Incremental item \(section).2
            """
        }.joined(separator: "\n\n")

        return """
        # Coordinator streaming update

        VERSION_MARKER_\(marker)

        ```mermaid
        \(diagramSource(marker: marker))
        ```

        \(BenchmarkFixtures.large)

        \(additions)
        """
    }

    private static func diagramSource(marker: String) -> String {
        """
        graph TD
        Source_\(marker)-->Parser_\(marker)
        Parser_\(marker)-->Layout_\(marker)
        """
    }

    private static func normalizedDiagramSource(_ source: String) -> String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
