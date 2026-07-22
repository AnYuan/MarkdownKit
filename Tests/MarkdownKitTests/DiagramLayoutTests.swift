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

    func testWarmDiagramCacheHitAvoidsRepeatedAdapterWork() async throws {
        let diagram = try XCTUnwrap(
            TestHelper.parse(
                "```mermaid\ngraph TD\nA-->B\n```",
                plugins: [DiagramExtractionPlugin()]
            ).children.first as? DiagramNode
        )
        let cache = LayoutCache()
        let adapter = RecordingDiagramAdapter(output: "rendered")
        var registry = DiagramAdapterRegistry()
        registry.register(adapter, for: .mermaid)
        let solver = LayoutSolver(cache: cache, diagramRegistry: registry)

        let first = await solver.solve(node: diagram, constrainedToWidth: 320)
        cache.resetStatsForTesting()
        let second = await solver.solve(node: diagram, constrainedToWidth: 320)
        let renderCount = await adapter.renderCount()

        XCTAssertEqual(renderCount, 1)
        TestHelper.assertDebugCounter(cache.hitCountForTesting, equals: 1)
        XCTAssertEqual(cache.missCountForTesting, 0)
        XCTAssertEqual(second.renderFingerprint, first.renderFingerprint)
    }

    func testCancelledDiagramLayoutIsNotPublishedAndRetryRendersAgain() async throws {
        let diagram = try XCTUnwrap(
            TestHelper.parse(
                "```mermaid\ngraph TD\nA-->B\n```",
                plugins: [DiagramExtractionPlugin()]
            ).children.first as? DiagramNode
        )
        let cache = LayoutCache()
        let adapter = TestHelper.BlockingDiagramAdapter(output: "rendered")
        var registry = DiagramAdapterRegistry()
        registry.register(adapter, for: .mermaid)
        let solver = LayoutSolver(cache: cache, diagramRegistry: registry)

        let task = Task {
            await solver.solve(
                node: diagram,
                constrainedToWidth: 320
            ).attributedString?.string
        }
        guard await adapter.waitUntilFirstRenderStarts() else {
            await adapter.releaseFirstRender()
            task.cancel()
            _ = await task.value
            XCTFail("Diagram adapter did not start within the timeout")
            return
        }
        task.cancel()
        await adapter.releaseFirstRender()
        let canceledResult = await task.value

        cache.resetStatsForTesting()
        let retry = await solver.solve(node: diagram, constrainedToWidth: 320)
        let renderCount = await adapter.renderCount()

        XCTAssertEqual(renderCount, 2)
        XCTAssertEqual(cache.hitCountForTesting, 0)
        TestHelper.assertDebugCounter(cache.missCountForTesting, equals: 1)
        XCTAssertEqual(canceledResult, "rendered")
        XCTAssertEqual(retry.attributedString?.string, "rendered")
    }

    func testCancelledPublicSolveStillCompletesAllResourcesWithoutPublishingCache() async {
        let sources = (0..<5).map { "public-total-\($0)" }
        let document = DocumentNode(
            range: nil,
            children: sources.map {
                DiagramNode(range: nil, language: .mermaid, source: $0)
            }
        )
        let cache = LayoutCache()
        let adapter = TestHelper.BlockingDiagramAdapter(output: "rendered")
        var registry = DiagramAdapterRegistry()
        registry.register(adapter, for: .mermaid)
        let solver = LayoutSolver(cache: cache, diagramRegistry: registry)

        let task = Task {
            await solver.solve(
                node: document,
                constrainedToWidth: 320
            ).children.compactMap { $0.attributedString?.string }
        }
        guard await adapter.waitUntilFirstRenderStarts() else {
            task.cancel()
            await adapter.releaseFirstRender()
            _ = await task.value
            XCTFail("First public diagram did not start within the timeout")
            return
        }

        task.cancel()
        await adapter.releaseFirstRender()
        let canceledOutput = await task.value
        let canceledSources = await adapter.renderedSources()

        XCTAssertEqual(canceledOutput, Array(repeating: "rendered", count: 5))
        XCTAssertEqual(canceledSources, sources)

        cache.resetStatsForTesting()
        let retry = await solver.solve(node: document, constrainedToWidth: 320)
        let totalRenderCount = await adapter.renderCount()

        XCTAssertEqual(retry.children.count, 5)
        XCTAssertEqual(cache.hitCountForTesting, 0)
        TestHelper.assertDebugCounter(cache.missCountForTesting, equals: 6)
        XCTAssertEqual(totalRenderCount, 10)
    }

    func testCancellableBuilderStopsBeforeLaterMathResources() async {
        let equations = (0..<5).map { "builder-resource-\($0)" }
        let paragraph = ParagraphNode(
            range: nil,
            children: equations.map {
                MathNode(range: nil, style: .inline, equation: $0)
            }
        )
        let adapter = TestHelper.BlockingMathAdapter(output: "rendered")
        let solver = LayoutSolver(cache: LayoutCache(), mathAdapter: adapter)

        let task = Task {
            await solver.solveCancellable(
                node: paragraph,
                constrainedToWidth: 320
            ) == nil
        }
        guard await adapter.waitUntilFirstRenderStarts() else {
            task.cancel()
            await adapter.releaseFirstRender()
            _ = await task.value
            XCTFail("First paragraph diagram did not start within the timeout")
            return
        }

        task.cancel()
        await adapter.releaseFirstRender()
        let resultWasNil = await task.value
        let renderedEquations = await adapter.renderedEquations()

        XCTAssertTrue(resultWasNil)
        XCTAssertEqual(renderedEquations, [equations[0]])
    }

    func testCancellableDocumentDiscardsStagedLayoutsAfterCancellation() async {
        let sources = (0..<5).map { "transactional-cache-\($0)" }
        let document = DocumentNode(
            range: nil,
            children: sources.map {
                DiagramNode(range: nil, language: .mermaid, source: $0)
            }
        )
        let cache = LayoutCache()
        let adapter = TestHelper.BlockingDiagramAdapter(output: "rendered", blockOnRender: 4)
        var registry = DiagramAdapterRegistry()
        registry.register(adapter, for: .mermaid)
        let solver = LayoutSolver(cache: cache, diagramRegistry: registry)

        let task = Task {
            await solver.solveCancellable(
                node: document,
                constrainedToWidth: 320
            ) == nil
        }
        guard await adapter.waitUntilBlockedRenderStarts() else {
            task.cancel()
            await adapter.releaseBlockedRender()
            _ = await task.value
            XCTFail("Fourth document diagram did not start within the timeout")
            return
        }

        task.cancel()
        await adapter.releaseBlockedRender()
        let resultWasNil = await task.value
        XCTAssertTrue(resultWasNil)

        cache.resetStatsForTesting()
        let retry = await solver.solve(node: document, constrainedToWidth: 320)
        let renderedSources = await adapter.renderedSources()

        XCTAssertEqual(cache.hitCountForTesting, 0)
        TestHelper.assertDebugCounter(cache.missCountForTesting, equals: 6)
        XCTAssertEqual(retry.children.count, 5)
        XCTAssertEqual(Array(renderedSources.suffix(5)), sources)
        XCTAssertEqual(renderedSources.count, 9)
    }

    func testSuccessfulCancellableSolveUsesStagedOverlayAndPublishesTransaction() async throws {
        let firstDiagram = DiagramNode(
            range: nil,
            language: .mermaid,
            source: "shared-staged-overlay"
        )
        let secondDiagram = DiagramNode(
            range: nil,
            language: .mermaid,
            source: "shared-staged-overlay"
        )
        let document = DocumentNode(
            range: nil,
            children: [firstDiagram, secondDiagram]
        )
        let cache = LayoutCache()
        let adapter = RecordingDiagramAdapter(output: "rendered")
        var registry = DiagramAdapterRegistry()
        registry.register(adapter, for: .mermaid)
        let solver = LayoutSolver(cache: cache, diagramRegistry: registry)

        let cancellableResult: LayoutResult? = await solver.solveCancellable(
            node: document,
            constrainedToWidth: 320
        )
        let first = try XCTUnwrap(cancellableResult)
        let firstRenderCount = await adapter.renderCount()
        XCTAssertEqual(first.children.count, 2)
        XCTAssertEqual(firstRenderCount, 1)
        XCTAssertEqual(
            first.children[0].renderFingerprint,
            first.children[1].renderFingerprint
        )
        XCTAssertNotEqual(
            first.children[0].stableIdentity,
            first.children[1].stableIdentity
        )

        cache.resetStatsForTesting()
        let childRetry = await solver.solve(node: firstDiagram, constrainedToWidth: 320)
        XCTAssertEqual(childRetry.attributedString?.string, "rendered")
        TestHelper.assertDebugCounter(cache.hitCountForTesting, equals: 1)
        XCTAssertEqual(cache.missCountForTesting, 0)

        cache.resetStatsForTesting()
        let retry = await solver.solve(node: document, constrainedToWidth: 320)
        let retryRenderCount = await adapter.renderCount()

        XCTAssertEqual(retry.children.count, 2)
        TestHelper.assertDebugCounter(cache.hitCountForTesting, equals: 1)
        XCTAssertEqual(cache.missCountForTesting, 0)
        XCTAssertEqual(retryRenderCount, 1)
    }

    func testSyncDiagramSkipsAdapterAndAsyncDiagramUsesCodeBlockInset() async throws {
        let diagram = try XCTUnwrap(
            TestHelper.parse(
                "```mermaid\ngraph TD\nA-->B\n```",
                plugins: [DiagramExtractionPlugin()]
            ).children.first as? DiagramNode
        )
        let rawOutput = NSAttributedString(string: "rendered")
        let adapter = RecordingDiagramAdapter(output: rawOutput.string)
        var registry = DiagramAdapterRegistry()
        registry.register(adapter, for: .mermaid)
        let solver = LayoutSolver(cache: LayoutCache(), diagramRegistry: registry)
        let width: CGFloat = 320

        let sync = solver.solveSync(node: diagram, constrainedToWidth: width)
        let syncExpected = TextKitCalculator().calculateSize(
            for: NSAttributedString(),
            constrainedToWidth: width
        )
        let syncRenderCount = await adapter.renderCount()

        XCTAssertEqual(syncRenderCount, 0)
        XCTAssertEqual(sync.attributedString?.string, "")
        XCTAssertEqual(sync.size, syncExpected)

        let async = await solver.solve(node: diagram, constrainedToWidth: width)
        let totalInset = Theme.default.codeBlock.layoutTotalInset
        var asyncExpected = TextKitCalculator().calculateSize(
            for: rawOutput,
            constrainedToWidth: max(0, width - totalInset)
        )
        asyncExpected.width += totalInset
        asyncExpected.height += totalInset
        let asyncRenderCount = await adapter.renderCount()

        XCTAssertEqual(asyncRenderCount, 1)
        XCTAssertEqual(async.size, asyncExpected)
        XCTAssertNotEqual(async.renderFingerprint, sync.renderFingerprint)
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

private struct RecordingDiagramAdapter: DiagramRenderingAdapter {
    private let output: String
    private let state = DiagramAdapterState()

    init(output: String) {
        self.output = output
    }

    func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        await state.recordRender()
        return NSAttributedString(string: output)
    }

    func renderCount() async -> Int {
        await state.renderCount
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine("RecordingDiagramAdapter")
        hasher.combine(output)
    }
}

private actor DiagramAdapterState {
    private(set) var renderCount = 0

    func recordRender() {
        renderCount += 1
    }
}
