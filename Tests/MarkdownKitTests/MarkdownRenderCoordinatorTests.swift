import XCTest
@testable import MarkdownKit

#if canImport(SwiftUI)
private final class ParseVisitCounter {
    private let lock = NSLock()
    private var visitCount = 0

    func increment() {
        lock.lock()
        visitCount += 1
        lock.unlock()
    }

    func value() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return visitCount
    }
}

private struct FingerprintedCountingPlugin: ASTPlugin {
    let counter: ParseVisitCounter
    let fingerprintValue: Int

    func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        counter.increment()
        return nodes
    }

    func cacheFingerprint(into hasher: inout Hasher) {
        hasher.combine(String(reflecting: type(of: self)))
        hasher.combine(fingerprintValue)
    }
}

private final class BlockingVisitPlugin: ASTPlugin {
    struct Snapshot {
        let totalVisits: Int
        let activeVisits: Int
        let maxActiveVisits: Int
    }

    private let firstVisitEntered: XCTestExpectation
    private let gate = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var didBlockFirstVisit = false
    private var didReleaseFirstVisit = false
    private var totalVisits = 0
    private var activeVisits = 0
    private var maxActiveVisits = 0

    init(firstVisitEntered: XCTestExpectation) {
        self.firstVisitEntered = firstVisitEntered
    }

    func visit(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        var shouldBlock = false

        lock.lock()
        totalVisits += 1
        activeVisits += 1
        maxActiveVisits = max(maxActiveVisits, activeVisits)
        if !didBlockFirstVisit {
            didBlockFirstVisit = true
            shouldBlock = true
        }
        lock.unlock()

        if shouldBlock {
            firstVisitEntered.fulfill()
            gate.wait()
        }

        lock.lock()
        activeVisits -= 1
        lock.unlock()
        return nodes
    }

    func releaseFirstVisit() {
        lock.lock()
        let shouldSignal = !didReleaseFirstVisit
        didReleaseFirstVisit = true
        lock.unlock()

        if shouldSignal {
            gate.signal()
        }
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            totalVisits: totalVisits,
            activeVisits: activeVisits,
            maxActiveVisits: maxActiveVisits
        )
    }
}

@available(iOS 14.0, macOS 11.0, *)
@MainActor
final class MarkdownRenderCoordinatorTests: XCTestCase {
    private let initialWidth: CGFloat = 360
    private let limits = MarkdownParser.ResourceLimits.default

    func testSingleFlightKeepsOnlyLatestPendingRender() async {
        let engine = MarkdownEngine()
        let firstVisitEntered = expectation(description: "first plugin visit entered")
        let plugin = BlockingVisitPlugin(firstVisitEntered: firstVisitEntered)
        defer { plugin.releaseFirstVisit() }

        let firstText = "FIRST_RENDER_TOKEN"
        let middleText = "MIDDLE_RENDER_TOKEN"
        let latestText = "LATEST_RENDER_TOKEN"

        submitInitialRender(
            engine,
            markdown: firstText,
            plugins: [plugin],
            appearance: .light
        )
        await fulfillment(of: [firstVisitEntered], timeout: 2)

        renderImmediately(
            engine,
            markdown: middleText,
            plugins: [plugin],
            appearance: .light
        )
        renderImmediately(
            engine,
            markdown: latestText,
            plugins: [plugin],
            appearance: .light
        )

        let beforeRelease = plugin.snapshot()
        XCTAssertEqual(beforeRelease.totalVisits, 1)
        XCTAssertEqual(beforeRelease.activeVisits, 1)
        XCTAssertEqual(beforeRelease.maxActiveVisits, 1)

        plugin.releaseFirstVisit()
        await engine.waitUntilSettled()

        let afterRelease = plugin.snapshot()
        XCTAssertEqual(afterRelease.maxActiveVisits, 1)
        XCTAssertEqual(afterRelease.totalVisits, 2)

        let finalText = TestHelper.flattenedLayoutText(from: engine.layouts)
        XCTAssertTrue(finalText.contains(latestText))
        XCTAssertFalse(finalText.contains(firstText))
        XCTAssertFalse(finalText.contains(middleText))
    }

    func testCanceledParseSeedsSameKeyReuse() async {
        let engine = MarkdownEngine()
        let firstVisitEntered = expectation(description: "first parse reached plugin visit")
        let plugin = BlockingVisitPlugin(firstVisitEntered: firstVisitEntered)
        defer { plugin.releaseFirstVisit() }

        let markdown = "SAME_PARSE_KEY_MARKDOWN"

        submitInitialRender(
            engine,
            markdown: markdown,
            plugins: [plugin],
            appearance: .light
        )
        await fulfillment(of: [firstVisitEntered], timeout: 2)

        renderImmediately(
            engine,
            markdown: markdown,
            plugins: [plugin],
            theme: themed(textColor: .systemRed),
            appearance: .dark
        )

        let beforeRelease = plugin.snapshot()
        XCTAssertEqual(beforeRelease.totalVisits, 1)
        XCTAssertEqual(beforeRelease.activeVisits, 1)

        plugin.releaseFirstVisit()
        await engine.waitUntilSettled()

        let afterRelease = plugin.snapshot()
        XCTAssertEqual(afterRelease.totalVisits, 1)
        XCTAssertEqual(afterRelease.maxActiveVisits, 1)

        XCTAssertFalse(engine.layouts.isEmpty)
        XCTAssertTrue(engine.layouts.allSatisfy { $0.appearance == .dark })
        XCTAssertTrue(TestHelper.flattenedLayoutText(from: engine.layouts).contains(markdown))
    }

    func testParseKeyReuseAndInvalidationBoundaries() async {
        let engine = MarkdownEngine()
        let counter = ParseVisitCounter()
        let pluginV1 = FingerprintedCountingPlugin(counter: counter, fingerprintValue: 1)

        let text = "PARSE_KEY_BASE_TEXT"
        submitInitialRender(
            engine,
            markdown: text,
            plugins: [pluginV1],
            appearance: .light
        )
        await engine.waitUntilSettled()
        XCTAssertEqual(counter.value(), 1)

        updateEffectiveWidth(
            engine,
            width: 410,
            markdown: text,
            plugins: [pluginV1],
            theme: .default,
            appearance: .light
        )
        updateEffectiveWidth(
            engine,
            width: 520,
            markdown: text,
            plugins: [pluginV1],
            theme: .default,
            appearance: .light
        )
        await engine.waitUntilSettled()

        XCTAssertEqual(counter.value(), 1)
        XCTAssertEqual(engine.preferredWidth(fallback: 1), 520, accuracy: 0.01)

        renderImmediately(
            engine,
            markdown: text,
            plugins: [pluginV1],
            theme: themed(textColor: .systemBlue),
            appearance: .light
        )
        await engine.waitUntilSettled()
        XCTAssertEqual(counter.value(), 1)

        renderImmediately(
            engine,
            markdown: text,
            plugins: [pluginV1],
            theme: themed(textColor: .systemBlue),
            appearance: .dark
        )
        await engine.waitUntilSettled()
        XCTAssertEqual(counter.value(), 1)

        let updatedText = "PARSE_KEY_UPDATED_TEXT"
        renderImmediately(
            engine,
            markdown: updatedText,
            plugins: [pluginV1],
            theme: themed(textColor: .systemBlue),
            appearance: .dark
        )
        await engine.waitUntilSettled()
        XCTAssertEqual(counter.value(), 2)

        let tighterLimits = MarkdownParser.ResourceLimits(
            maximumInputBytes: limits.maximumInputBytes - 1,
            maximumNestingDepth: limits.maximumNestingDepth
        )
        renderImmediately(
            engine,
            markdown: updatedText,
            plugins: [pluginV1],
            theme: themed(textColor: .systemBlue),
            resourceLimits: tighterLimits,
            appearance: .dark
        )
        await engine.waitUntilSettled()
        XCTAssertEqual(counter.value(), 3)

        let pluginV2 = FingerprintedCountingPlugin(counter: counter, fingerprintValue: 2)
        renderImmediately(
            engine,
            markdown: updatedText,
            plugins: [pluginV2],
            theme: themed(textColor: .systemBlue),
            resourceLimits: tighterLimits,
            appearance: .dark
        )
        await engine.waitUntilSettled()
        XCTAssertEqual(counter.value(), 4)
    }

    func testDebouncedDarkToggleUsesLatestConfigurationWithoutReparse() async throws {
        let engine = MarkdownEngine()
        let counter = ParseVisitCounter()
        let countingPlugin = FingerprintedCountingPlugin(counter: counter, fingerprintValue: 9)
        let plugins: [ASTPlugin] = [DetailsExtractionPlugin(), countingPlugin]

        let markdown = """
        <details>
        <summary>Coordinator summary</summary>

        DETAILS_BODY_TOKEN
        </details>
        """

        submitInitialRender(
            engine,
            markdown: markdown,
            plugins: plugins,
            appearance: .light
        )
        await engine.waitUntilSettled()
        XCTAssertEqual(counter.value(), 1)

        let displayedDetails = try XCTUnwrap(firstTopLevelDetails(in: engine.layouts))
        XCTAssertFalse(displayedDetails.node.isOpen)
        XCTAssertEqual(displayedDetails.layout.appearance, .light)

        scheduleDebouncedRender(
            engine,
            markdown: markdown,
            plugins: plugins,
            appearance: .dark
        )
        engine.toggleDetails(at: displayedDetails.index, details: displayedDetails.node)
        await engine.waitUntilSettled()

        XCTAssertEqual(counter.value(), 1)

        let finalDetails = try XCTUnwrap(firstTopLevelDetails(in: engine.layouts))
        XCTAssertTrue(finalDetails.node.isOpen)
        XCTAssertEqual(finalDetails.layout.appearance, .dark)

        let finalText = TestHelper.flattenedLayoutText(from: engine.layouts)
        XCTAssertTrue(finalText.contains("DETAILS_BODY_TOKEN"))
    }

    func testLatestConfigurationCancelsStaleDiagramResourcesAndReusesParsedAST() async {
        let engine = MarkdownEngine()
        let counter = ParseVisitCounter()
        let countingPlugin = FingerprintedCountingPlugin(counter: counter, fingerprintValue: 10)
        let plugins: [ASTPlugin] = [DiagramExtractionPlugin(), countingPlugin]
        let sources = (0..<1_000).map { "graph TD\nA\($0)-->B\($0)" }
        let markdown = sources.map { source in
            """
            ```mermaid
            \(source)
            ```
            """
        }.joined(separator: "\n\n")
        let staleAdapter = TestHelper.BlockingDiagramAdapter(output: "STALE_RENDERED_ADAPTER_TEXT")
        var staleRegistry = DiagramAdapterRegistry()
        staleRegistry.register(staleAdapter, for: .mermaid)

        submitInitialRender(
            engine,
            markdown: markdown,
            plugins: plugins,
            diagramRegistry: staleRegistry,
            appearance: .light
        )
        guard await staleAdapter.waitUntilFirstRenderStarts() else {
            await staleAdapter.releaseFirstRender()
            await engine.waitUntilSettled()
            XCTFail("First stale diagram did not start within the timeout")
            return
        }

        renderImmediately(
            engine,
            markdown: markdown,
            plugins: plugins,
            theme: themed(textColor: .systemGreen),
            diagramRegistry: DiagramAdapterRegistry(),
            appearance: .dark
        )
        await staleAdapter.releaseFirstRender()
        await engine.waitUntilSettled()

        let staleSources = await staleAdapter.renderedSources()
        let finalDiagrams = engine.layouts.compactMap { layout -> (LayoutResult, DiagramNode)? in
            guard let diagram = layout.node as? DiagramNode else { return nil }
            return (layout, diagram)
        }
        let finalSources = finalDiagrams.map {
            $0.1.source.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        XCTAssertEqual(staleSources.count, 1)
        XCTAssertEqual(
            staleSources.first?.trimmingCharacters(in: .whitespacesAndNewlines),
            sources.first
        )
        XCTAssertEqual(counter.value(), 1)
        XCTAssertEqual(engine.layouts.count, 1_000)
        XCTAssertEqual(finalDiagrams.count, 1_000)
        XCTAssertEqual(finalSources, sources)
        XCTAssertTrue(finalDiagrams.allSatisfy { $0.0.appearance == .dark })
        XCTAssertTrue(finalDiagrams.allSatisfy {
            $0.0.attributedString?.string.hasPrefix("MERMAID\n") == true
        })
        XCTAssertFalse(
            TestHelper.flattenedLayoutText(from: engine.layouts)
                .contains("STALE_RENDERED_ADAPTER_TEXT")
        )
    }

    private func submitInitialRender(
        _ engine: MarkdownEngine,
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme = .default,
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        resourceLimits: MarkdownParser.ResourceLimits = .default,
        appearance: MarkdownAppearance
    ) {
        engine.updateEffectiveContentWidth(
            initialWidth,
            markdown: markdown,
            plugins: plugins,
            theme: theme,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: .default,
            resourceLimits: resourceLimits,
            appearance: appearance
        )
    }

    private func renderImmediately(
        _ engine: MarkdownEngine,
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme = .default,
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        resourceLimits: MarkdownParser.ResourceLimits = .default,
        appearance: MarkdownAppearance
    ) {
        engine.renderForCurrentPlatform(
            markdown: markdown,
            plugins: plugins,
            theme: theme,
            fallbackWidth: initialWidth,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: .default,
            resourceLimits: resourceLimits,
            appearance: appearance
        )
    }

    private func scheduleDebouncedRender(
        _ engine: MarkdownEngine,
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme = .default,
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        resourceLimits: MarkdownParser.ResourceLimits = .default,
        appearance: MarkdownAppearance
    ) {
        engine.scheduleDebouncedRender(
            markdown: markdown,
            plugins: plugins,
            theme: theme,
            fallbackWidth: initialWidth,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: .default,
            resourceLimits: resourceLimits,
            appearance: appearance
        )
    }

    private func updateEffectiveWidth(
        _ engine: MarkdownEngine,
        width: CGFloat,
        markdown: String,
        plugins: [ASTPlugin],
        theme: Theme = .default,
        diagramRegistry: DiagramAdapterRegistry = DiagramAdapterRegistry(),
        resourceLimits: MarkdownParser.ResourceLimits = .default,
        appearance: MarkdownAppearance
    ) {
        engine.updateEffectiveContentWidth(
            width,
            markdown: markdown,
            plugins: plugins,
            theme: theme,
            diagramRegistry: diagramRegistry,
            imageLoadingPolicy: .default,
            resourceLimits: resourceLimits,
            appearance: appearance
        )
    }

    private func firstTopLevelDetails(in layouts: [LayoutResult]) -> (index: Int, layout: LayoutResult, node: DetailsNode)? {
        guard let index = layouts.firstIndex(where: { $0.node is DetailsNode }),
              let node = layouts[index].node as? DetailsNode else {
            return nil
        }
        return (index, layouts[index], node)
    }

    private func themed(textColor: Color) -> Theme {
        let base = Theme.default
        return Theme(
            typography: base.typography,
            colors: Theme.Colors(
                textColor: ColorToken(foreground: textColor),
                codeColor: base.colors.codeColor,
                inlineCodeColor: base.colors.inlineCodeColor,
                tableColor: base.colors.tableColor,
                linkColor: base.colors.linkColor,
                blockQuoteColor: base.colors.blockQuoteColor,
                thematicBreakColor: base.colors.thematicBreakColor
            ),
            codeBlock: base.codeBlock,
            blockQuote: base.blockQuote,
            list: base.list,
            details: base.details,
            table: base.table,
            syntaxColors: base.syntaxColors,
            highlight: base.highlight,
            thematicBreak: base.thematicBreak
        )
    }
}
#endif
