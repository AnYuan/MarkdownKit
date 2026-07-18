import XCTest
@testable import MarkdownKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

#if canImport(WebKit)
final class MermaidDiagramAdapterTests: XCTestCase {

    func testBundledScriptExists() {
        XCTAssertNotNil(
            MermaidResourceLocator.bundledScriptURL(),
            "Bundled mermaid.min.js resource should exist"
        )
    }

    func testBundledBootstrapAndScriptAreCoLocatedAndLinked() throws {
        let scriptURL = try XCTUnwrap(MermaidResourceLocator.bundledScriptURL())
        let bootstrapURL = try XCTUnwrap(MermaidResourceLocator.bundledBootstrapURL())
        let html = try String(contentsOf: bootstrapURL, encoding: .utf8)

        XCTAssertEqual(
            scriptURL.deletingLastPathComponent().standardizedFileURL,
            bootstrapURL.deletingLastPathComponent().standardizedFileURL
        )
        XCTAssertTrue(html.contains("<!DOCTYPE html>"))
        XCTAssertTrue(html.contains(#"<div id="mermaid-root"></div>"#))
        XCTAssertTrue(html.contains(#"<script src="mermaid.min.js"></script>"#))
    }

    @MainActor
    func testSnapshotCacheHasExplicitBounds() async throws {
        try await resetSnapshotter()

        let statistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()

        XCTAssertEqual(statistics.cacheCountLimit, 64)
        XCTAssertEqual(statistics.cacheTotalCostLimit, 64 * 1024 * 1024)
    }

    @MainActor
    func testSameSourceUsesCachedImageWithFreshAttachment() async throws {
        try await resetSnapshotter()
        let adapter = MermaidDiagramAdapter()
        let source = """
        graph TD;
            A-->B;
        """

        let first = try await renderedAttachment(from: adapter, source: source)
        let second = try await renderedAttachment(from: adapter, source: source)
        let statistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()

        XCTAssertFalse(first.attachment === second.attachment)
        XCTAssertEqual(first.image.size, second.image.size)
        XCTAssertGreaterThan(first.image.size.width, 0)
        XCTAssertGreaterThan(first.image.size.height, 0)
        XCTAssertEqual(statistics.actualWebViewRenderStartCount, 1)
        XCTAssertEqual(statistics.cacheHitCount, 1)
    }

    @MainActor
    func testDifferentSourcesDoNotCollideInCache() async throws {
        try await resetSnapshotter()
        let adapter = MermaidDiagramAdapter()
        let firstSource = """
        graph TD;
            A-->B;
        """
        let secondSource = """
        graph LR;
            X-->Y;
        """

        let first = try await renderedAttachment(from: adapter, source: firstSource)
        let second = try await renderedAttachment(from: adapter, source: secondSource)
        let firstAgain = try await renderedAttachment(from: adapter, source: firstSource)
        let statistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()

        XCTAssertGreaterThan(second.image.size.width, 0)
        XCTAssertEqual(first.image.size, firstAgain.image.size)
        XCTAssertEqual(statistics.actualWebViewRenderStartCount, 2)
        XCTAssertEqual(statistics.cacheHitCount, 1)
    }

    @MainActor
    func testFailedRenderIsNotCachedAndRetryStartsAgain() async throws {
        try await resetSnapshotter()
        let adapter = MermaidDiagramAdapter()
        let source = "graph TD;\nA-->B;"

        MermaidDiagramAdapter.failNextJavaScriptEvaluationForTesting()
        let first = await adapter.render(source: source, language: .mermaid)
        let second = await adapter.render(source: source, language: .mermaid)
        let statistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()

        XCTAssertNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(statistics.actualWebViewRenderStartCount, 2)
        XCTAssertEqual(statistics.cacheHitCount, 0)
    }

    @MainActor
    func testQueuedCancellationResumesNilWithoutStartingQueuedRender() async throws {
        try await resetSnapshotter()
        let adapter = MermaidDiagramAdapter()
        try await prepareReadySnapshotter(using: adapter)
        let activeSource = """
        graph TD;
            A-->B;
        """
        let queuedSource = """
        graph TD;
            C-->D;
        """

        MermaidDiagramAdapter.pauseNextRenderForTesting()
        let activeTask = Task {
            await adapter.render(source: activeSource, language: .mermaid) != nil
        }
        try await waitUntil("paused Mermaid request to become active") {
            MermaidDiagramAdapter.snapshotterStatisticsForTesting().isRendering
        }

        let queuedTask = Task {
            await adapter.render(source: queuedSource, language: .mermaid) == nil
        }
        try await waitUntil("second Mermaid request to enter the queue") {
            MermaidDiagramAdapter.snapshotterStatisticsForTesting().queuedRequestCount == 1
        }

        queuedTask.cancel()
        let queuedWasNil = await queuedTask.value
        let whilePaused = MermaidDiagramAdapter.snapshotterStatisticsForTesting()

        XCTAssertTrue(queuedWasNil)
        XCTAssertEqual(whilePaused.actualWebViewRenderStartCount, 0)
        XCTAssertEqual(whilePaused.queuedRequestCount, 0)

        MermaidDiagramAdapter.resumePausedRenderForTesting()
        let activeRendered = await activeTask.value
        XCTAssertTrue(activeRendered)
        try await waitUntilSnapshotterIsIdle()

        let finalStatistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()
        XCTAssertEqual(finalStatistics.actualWebViewRenderStartCount, 1)
    }

    @MainActor
    func testTimedOutRenderAndInitializationFailureRecoverBeforeRetry() async throws {
        try await resetSnapshotter()
        let adapter = MermaidDiagramAdapter()
        let source = "graph TD;\nA-->B;"

        try await prepareReadySnapshotter(using: adapter)
        MermaidDiagramAdapter.pauseNextRenderForTesting()
        let timedOutTask = Task {
            await adapter.render(source: source, language: .mermaid) == nil
        }
        try await waitUntil("paused Mermaid render to become active before timeout") {
            let statistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()
            return statistics.actualWebViewRenderStartCount == 0 && statistics.isRendering
        }

        MermaidDiagramAdapter.timeOutActiveRenderForTesting()
        let timedOutWasNil = await timedOutTask.value
        XCTAssertTrue(timedOutWasNil)

        MermaidDiagramAdapter.invalidateSnapshotterReadinessForTesting()
        let retry = try await renderedAttachment(from: adapter, source: source)
        let statistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()

        XCTAssertGreaterThan(retry.image.size.width, 0)
        XCTAssertEqual(statistics.actualWebViewRenderStartCount, 1)
        XCTAssertEqual(statistics.cacheHitCount, 0)
    }

    @MainActor
    func testActiveCancellationResumesNilAndDoesNotCacheResult() async throws {
        try await resetSnapshotter()
        let adapter = MermaidDiagramAdapter()
        try await prepareReadySnapshotter(using: adapter)
        let source = """
        graph TD;
            A-->B;
        """

        MermaidDiagramAdapter.pauseNextRenderForTesting()
        let cancelledTask = Task {
            await adapter.render(source: source, language: .mermaid) == nil
        }
        try await waitUntil("paused Mermaid request to become active") {
            let statistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()
            return statistics.actualWebViewRenderStartCount == 0 && statistics.isRendering
        }

        cancelledTask.cancel()
        let cancelledWasNil = await cancelledTask.value
        XCTAssertTrue(cancelledWasNil)

        let whileCancelled = MermaidDiagramAdapter.snapshotterStatisticsForTesting()
        XCTAssertTrue(whileCancelled.isRendering)
        MermaidDiagramAdapter.resumePausedRenderForTesting()
        try await waitUntilSnapshotterIsIdle()

        let retryTask = Task {
            await adapter.render(source: source, language: .mermaid) != nil
        }
        let retryRendered = await retryTask.value
        let statistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()

        XCTAssertTrue(retryRendered)
        XCTAssertEqual(statistics.actualWebViewRenderStartCount, 1)
        XCTAssertEqual(statistics.cacheHitCount, 0)
    }

    @MainActor
    func testCachedHitQueuedBehindActiveMissDoesNotOvertake() async throws {
        try await resetSnapshotter()
        let adapter = MermaidDiagramAdapter()
        let cachedSource = """
        graph TD;
            Warm-->Cache;
        """
        let missSource = """
        graph TD;
            Older-->Miss;
        """

        _ = try await renderedAttachment(from: adapter, source: cachedSource)

        MermaidDiagramAdapter.pauseNextRenderForTesting()
        let missTask = Task {
            await adapter.render(source: missSource, language: .mermaid) != nil
        }
        try await waitUntil("paused cache miss to become active") {
            MermaidDiagramAdapter.snapshotterStatisticsForTesting().isRendering
        }

        let cachedTask = Task {
            await adapter.render(source: cachedSource, language: .mermaid) != nil
        }
        try await waitUntil("cached request to queue behind the active miss") {
            MermaidDiagramAdapter.snapshotterStatisticsForTesting().queuedRequestCount == 1
        }

        let whilePaused = MermaidDiagramAdapter.snapshotterStatisticsForTesting()
        XCTAssertEqual(whilePaused.cacheHitCount, 0)
        XCTAssertEqual(whilePaused.queuedRequestCount, 1)
        XCTAssertTrue(whilePaused.isRendering)

        MermaidDiagramAdapter.resumePausedRenderForTesting()
        let missRendered = await missTask.value
        let cachedRendered = await cachedTask.value
        XCTAssertTrue(missRendered)
        XCTAssertTrue(cachedRendered)

        let finalStatistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()
        XCTAssertEqual(finalStatistics.actualWebViewRenderStartCount, 2)
        XCTAssertEqual(finalStatistics.cacheHitCount, 1)
    }

    @MainActor
    private func prepareReadySnapshotter(using adapter: MermaidDiagramAdapter) async throws {
        _ = try await renderedAttachment(
            from: adapter,
            source: "graph TD;\nWarm-->Up;"
        )
        try await resetSnapshotter()
    }

    @MainActor
    private func resetSnapshotter() async throws {
        try await waitUntilSnapshotterIsIdle()
        MermaidDiagramAdapter.resetSnapshotterForTesting()
    }

    @MainActor
    private func waitUntilSnapshotterIsIdle() async throws {
        try await waitUntil("Mermaid snapshotter to become idle") {
            let statistics = MermaidDiagramAdapter.snapshotterStatisticsForTesting()
            return !statistics.isRendering && statistics.queuedRequestCount == 0
        }
    }

    @MainActor
    private func waitUntil(
        _ description: String,
        condition: @MainActor () -> Bool
    ) async throws {
        for _ in 0..<600 {
            if condition() {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for \(description)")
        throw WaitError.timedOut
    }

    @MainActor
    private func renderedAttachment(
        from adapter: MermaidDiagramAdapter,
        source: String
    ) async throws -> RenderedAttachment {
        let maybeAttributedString = await adapter.render(source: source, language: .mermaid)
        let attributedString = try XCTUnwrap(
            maybeAttributedString,
            "Expected Mermaid render to produce an attachment"
        )
        let attachment = try XCTUnwrap(
            attributedString.attribute(.attachment, at: 0, effectiveRange: nil) as? NSTextAttachment
        )
        let image = try XCTUnwrap(attachment.image)
        return RenderedAttachment(attachment: attachment, image: image)
    }

    private struct RenderedAttachment {
        let attachment: NSTextAttachment
        let image: NativeImage
    }

    private enum WaitError: Error {
        case timedOut
    }
}
#endif
