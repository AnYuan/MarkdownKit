import XCTest
@testable import MarkdownKit

#if canImport(UIKit) && !os(watchOS)
import UIKit

@MainActor
final class iOSRasterPrefetchContractTests: XCTestCase {

    func testRasterRenderKeyPreservesExactVariantIdentity() {
        let base = RasterRenderKey(
            renderFingerprint: 41,
            appearance: .light,
            contentKind: .attributedText,
            logicalSize: CGSize(width: 320.125, height: 47.375),
            displayScale: 2.5
        )

        XCTAssertNotEqual(
            base,
            RasterRenderKey(
                renderFingerprint: 41,
                appearance: .dark,
                contentKind: .attributedText,
                logicalSize: base.logicalSize,
                displayScale: base.displayScale
            )
        )
        XCTAssertNotEqual(
            base,
            RasterRenderKey(
                renderFingerprint: 41,
                appearance: .light,
                contentKind: .customDraw,
                logicalSize: base.logicalSize,
                displayScale: base.displayScale
            )
        )
        XCTAssertNotEqual(
            base,
            RasterRenderKey(
                renderFingerprint: 41,
                appearance: .light,
                contentKind: .attributedText,
                logicalSize: CGSize(width: 320.375, height: 47.375),
                displayScale: base.displayScale
            )
        )
        XCTAssertNotEqual(
            base,
            RasterRenderKey(
                renderFingerprint: 41,
                appearance: .light,
                contentKind: .attributedText,
                logicalSize: base.logicalSize,
                displayScale: 3
            )
        )
        XCTAssertEqual(base.logicalSize, CGSize(width: 320.125, height: 47.375))
    }

    func testPreheatAndVisibleAcquisitionShareOnePublishableProducer() async throws {
        let renderer = ControlledRasterRenderer()
        let pipeline = makePipeline(renderer: renderer)
        let key = makeKey(101)
        let materializationCounter = RasterProducerMaterializationCounter()

        let preheatLease = try requirePending(
            pipeline.acquire(
                makeLazyRequest(
                    key,
                    priority: .utility,
                    counter: materializationCounter
                )
            )
        )
        let visibleLease = try requirePending(
            pipeline.acquire(
                makeLazyRequest(
                    key,
                    priority: .userInitiated,
                    counter: materializationCounter
                )
            )
        )
        let start = await renderer.nextStart()

        XCTAssertEqual(start.key, key)
        XCTAssertEqual(materializationCounter.count, 1)
        XCTAssertEqual(pipeline.statistics.producerStarts, 1)
        XCTAssertEqual(pipeline.statistics.producerJoins, 1)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 1)

        let renderedImage = makeImage(pixelWidth: 3, pixelHeight: 2, color: .red)
        renderer.complete(start, with: renderedImage)

        let preheatedImage = await preheatLease.value()
        let visibleImage = await visibleLease.value()
        preheatLease.release()
        visibleLease.release()
        await pipeline.drainForTesting()

        assertIdentical(preheatedImage, renderedImage)
        assertIdentical(visibleImage, renderedImage)
        assertIdentical(
            try requireCacheHit(
                pipeline.acquire(
                    makeLazyRequest(
                        key,
                        priority: .userInitiated,
                        counter: materializationCounter
                    )
                )
            ),
            renderedImage
        )
        XCTAssertEqual(materializationCounter.count, 1)
        XCTAssertEqual(pipeline.statistics.cacheHits, 1)
        XCTAssertEqual(pipeline.statistics.cacheInsertions, 1)
        XCTAssertEqual(pipeline.statistics.cacheEntryCount, 1)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 0)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(renderer.completionPriority(for: start)).rawValue,
            TaskPriority.userInitiated.rawValue
        )

        let productionImage = makeImage(pixelWidth: 2, pixelHeight: 2, color: .brown)
        let productionProducer = BlockingRasterProducer(image: productionImage)
        let productionPipeline = RasterImagePipeline()
        let productionKey = makeKey(102)
        let productionPreheatLease = try requirePending(
            productionPipeline.acquire(
                RasterRenderRequest(
                    key: productionKey,
                    priority: .utility,
                    produce: { productionProducer.produce() }
                )
            )
        )
        await productionProducer.waitUntilStarted()
        defer { productionProducer.resume() }

        let productionVisibleLease = try requirePending(
            productionPipeline.acquire(
                RasterRenderRequest(
                    key: productionKey,
                    priority: .userInitiated,
                    produce: { productionProducer.produce() }
                )
            )
        )
        productionProducer.resume()

        assertIdentical(await productionPreheatLease.value(), productionImage)
        assertIdentical(await productionVisibleLease.value(), productionImage)
        productionPreheatLease.release()
        productionVisibleLease.release()
        await productionPipeline.drainForTesting()
        XCTAssertFalse(productionProducer.ranOnMainThread)
        XCTAssertGreaterThanOrEqual(
            try XCTUnwrap(productionProducer.completionPriority).rawValue,
            TaskPriority.userInitiated.rawValue
        )
    }

    func testFinalConsumerCancellationStartsFreshGenerationAndRejectsLatePublication() async throws {
        let renderer = ControlledRasterRenderer()
        let pipeline = makePipeline(renderer: renderer)
        let key = makeKey(202)

        let abandonedLease = try requirePending(pipeline.acquire(makeRequest(key)))
        let generationA = await renderer.nextStart()
        abandonedLease.release()

        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 0)

        let replacementLease = try requirePending(pipeline.acquire(makeRequest(key)))
        let generationB = await renderer.nextStart()
        XCTAssertNotEqual(generationA.id, generationB.id)
        XCTAssertEqual(pipeline.statistics.producerStarts, 2)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 1)

        let imageA = makeImage(pixelWidth: 2, pixelHeight: 2, color: .red)
        let imageB = makeImage(pixelWidth: 2, pixelHeight: 2, color: .blue)
        renderer.complete(generationB, with: imageB)
        let replacementImage = await replacementLease.value()
        replacementLease.release()
        renderer.complete(generationA, with: imageA)
        await pipeline.drainForTesting()

        assertIdentical(replacementImage, imageB)
        assertIdentical(pipeline.cachedImageForTesting(for: key), imageB)
        XCTAssertEqual(pipeline.statistics.cacheInsertions, 1)
        XCTAssertEqual(pipeline.statistics.cacheEntryCount, 1)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 0)
    }

    func testRasterCacheEnforcesEntryAndByteCostLRUBounds() async throws {
        let imageA = makeImage(pixelWidth: 2, pixelHeight: 2, color: .red)
        let imageB = makeImage(pixelWidth: 2, pixelHeight: 2, color: .green)
        let imageC = makeImage(pixelWidth: 2, pixelHeight: 2, color: .blue)
        let smallImageCost = imageA.bytesPerRow * imageA.height

        let countRenderer = ControlledRasterRenderer()
        let countPipeline = makePipeline(
            renderer: countRenderer,
            entryLimit: 2,
            byteCostLimit: smallImageCost * 10
        )
        let countA = makeKey(301)
        let countB = makeKey(302)
        let countC = makeKey(303)

        try await render(countA, as: imageA, through: countPipeline, renderer: countRenderer)
        try await render(countB, as: imageB, through: countPipeline, renderer: countRenderer)
        assertIdentical(try requireCacheHit(countPipeline.acquire(makeRequest(countA))), imageA)
        try await render(countC, as: imageC, through: countPipeline, renderer: countRenderer)

        assertIdentical(countPipeline.cachedImageForTesting(for: countA), imageA)
        XCTAssertNil(countPipeline.cachedImageForTesting(for: countB))
        assertIdentical(countPipeline.cachedImageForTesting(for: countC), imageC)
        XCTAssertEqual(countPipeline.statistics.cacheEntryCount, 2)
        XCTAssertLessThanOrEqual(
            countPipeline.statistics.cacheEntryCount,
            countPipeline.statistics.cacheEntryLimit
        )
        XCTAssertLessThanOrEqual(
            countPipeline.statistics.cachedByteCost,
            countPipeline.statistics.cacheByteCostLimit
        )

        let costRenderer = ControlledRasterRenderer()
        let costPipeline = makePipeline(
            renderer: costRenderer,
            entryLimit: 10,
            byteCostLimit: smallImageCost * 2
        )
        let costA = makeKey(401)
        let costB = makeKey(402)
        let costC = makeKey(403)
        let oversizedKey = makeKey(404)

        try await render(costA, as: imageA, through: costPipeline, renderer: costRenderer)
        try await render(costB, as: imageB, through: costPipeline, renderer: costRenderer)
        _ = try requireCacheHit(costPipeline.acquire(makeRequest(costA)))
        try await render(costC, as: imageC, through: costPipeline, renderer: costRenderer)

        assertIdentical(costPipeline.cachedImageForTesting(for: costA), imageA)
        XCTAssertNil(costPipeline.cachedImageForTesting(for: costB))
        assertIdentical(costPipeline.cachedImageForTesting(for: costC), imageC)
        XCTAssertLessThanOrEqual(
            costPipeline.statistics.cachedByteCost,
            costPipeline.statistics.cacheByteCostLimit
        )

        let inFlightKey = makeKey(405)
        let inFlightLease = try requirePending(
            costPipeline.acquire(makeRequest(inFlightKey))
        )
        let inFlightStart = await costRenderer.nextStart()
        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
        XCTAssertEqual(costPipeline.statistics.cacheEntryCount, 0)
        XCTAssertEqual(costPipeline.statistics.cachedByteCost, 0)
        costRenderer.complete(inFlightStart, with: imageA)
        let inFlightImage = await inFlightLease.value()
        inFlightLease.release()
        await costPipeline.drainForTesting()
        assertIdentical(inFlightImage, imageA)
        XCTAssertNil(costPipeline.cachedImageForTesting(for: inFlightKey))

        let oversizedImage = makeImage(pixelWidth: 4, pixelHeight: 4, color: .purple)
        let returnedOversizedImage = try await render(
            oversizedKey,
            as: oversizedImage,
            through: costPipeline,
            renderer: costRenderer
        )

        assertIdentical(returnedOversizedImage, oversizedImage)
        XCTAssertNil(costPipeline.cachedImageForTesting(for: oversizedKey))
        XCTAssertLessThanOrEqual(
            costPipeline.statistics.cachedByteCost,
            costPipeline.statistics.cacheByteCostLimit
        )
    }

    func testCodeContentLayoutAndCollectionVisibleRasterKeysUseResolvedPaddingAndScale() async throws {
        let renderer = ControlledRasterRenderer()
        let pipeline = makePipeline(renderer: renderer)
        let padding: CGFloat = 23.25
        let scale: CGFloat = 2.75
        let theme = makeTheme(codePadding: padding)
        let codeLayout = makeCodeLayout(
            "let answer = 42",
            size: CGSize(width: 311.5, height: 101.25),
            appearance: .dark,
            renderFingerprint: 501
        )
        let diagramLayout = makeDiagramLayout(
            "graph TD; A-->B;",
            size: codeLayout.size,
            appearance: .dark,
            renderFingerprint: 502
        )

        for layout in [codeLayout, diagramLayout] {
            let contentLayout = AsyncCodeView.contentLayout(for: layout, theme: theme)
            XCTAssertEqual(
                contentLayout.size,
                CGSize(
                    width: layout.size.width - (padding * 2),
                    height: layout.size.height - (padding * 2)
                )
            )
            XCTAssertEqual(contentLayout.renderFingerprint, layout.renderFingerprint)
            XCTAssertEqual(contentLayout.appearance, layout.appearance)
        }

        let expectedContentLayout = AsyncCodeView.contentLayout(for: codeLayout, theme: theme)
        let expectedKey = try XCTUnwrap(
            AsyncTextView.rasterKey(for: expectedContentLayout, displayScale: scale)
        )
        let collection = makeCollectionView(pipeline: pipeline, displayScale: scale)
        collection.theme = theme
        await applyLayouts([codeLayout], to: collection)
        let platformCollectionView = try collectionView(in: collection)
        let indexPath = IndexPath(item: 0, section: 0)

        collection.collectionView(platformCollectionView, prefetchItemsAt: [indexPath])
        let prefetchStart = await renderer.nextStart()
        let prefetchRecord = try XCTUnwrap(
            collection.rasterPrefetchRecordsForTesting[indexPath]
        )
        let renderedImage = makeImage(pixelWidth: 2, pixelHeight: 2, color: .orange)

        renderer.complete(prefetchStart, with: renderedImage)
        await pipeline.drainForTesting()
        await collection.drainRasterPrefetchCompletionsForTesting()

        let cell = MarkdownCollectionViewCell(frame: CGRect(origin: .zero, size: codeLayout.size))
        cell.theme = theme
        cell.rasterPipelineForTesting = pipeline
        cell.displayScaleOverrideForTesting = scale
        cell.configure(with: codeLayout)
        let codeView = try XCTUnwrap(cell.contentView.subviews.first as? AsyncCodeView)
        let innerTextView = try XCTUnwrap(codeView.subviews.compactMap { $0 as? AsyncTextView }.first)

        XCTAssertEqual(prefetchStart.key, expectedKey)
        XCTAssertEqual(prefetchRecord.key, expectedKey)
        XCTAssertEqual(innerTextView.currentRasterKeyForTesting, expectedKey)
        XCTAssertEqual(pipeline.statistics.producerStarts, 1)
        XCTAssertEqual(pipeline.statistics.producerJoins, 0)
        XCTAssertEqual(pipeline.statistics.cacheHits, 1)
        assertIdentical((innerTextView.layer.contents as! CGImage), renderedImage)

        cell.configure(with: codeLayout)
        XCTAssertEqual(pipeline.statistics.producerStarts, 1)
        XCTAssertEqual(pipeline.statistics.cacheHits, 1)

        let updatedScale: CGFloat = 3.125
        cell.displayScaleOverrideForTesting = updatedScale
        let updatedScaleStart = await renderer.nextStart()
        XCTAssertEqual(updatedScaleStart.key.logicalSize, expectedKey.logicalSize)
        XCTAssertEqual(updatedScaleStart.key.displayScale, updatedScale)
        XCTAssertEqual(innerTextView.currentRasterKeyForTesting, updatedScaleStart.key)

        let updatedScaleImage = makeImage(
            pixelWidth: 3,
            pixelHeight: 3,
            color: .magenta
        )
        renderer.complete(updatedScaleStart, with: updatedScaleImage)
        await pipeline.drainForTesting()
        await innerTextView.drainRasterMountForTesting()
        assertIdentical((innerTextView.layer.contents as! CGImage), updatedScaleImage)
        XCTAssertEqual(pipeline.statistics.producerStarts, 2)
        cell.prepareForReuse()
    }

    func testCollectionPrefetchCompletionUsesInjectedScaleAndSelectableModeBypassesRasterization() async throws {
        let scale: CGFloat = 3.25
        let renderer = ControlledRasterRenderer()
        let pipeline = makePipeline(renderer: renderer)
        let collection = makeCollectionView(pipeline: pipeline, displayScale: scale)
        let layout = makeTextLayout("prefetch", renderFingerprint: 601)
        await applyLayouts([layout], to: collection)
        let platformCollectionView = try collectionView(in: collection)
        let indexPath = IndexPath(item: 0, section: 0)

        collection.collectionView(platformCollectionView, prefetchItemsAt: [indexPath])
        let start = await renderer.nextStart()
        XCTAssertEqual(start.key.displayScale, scale)
        XCTAssertEqual(collection.rasterPrefetchRecordsForTesting.count, 1)

        let renderedImage = makeImage(pixelWidth: 2, pixelHeight: 2, color: .cyan)
        renderer.complete(start, with: renderedImage)
        await pipeline.drainForTesting()
        await collection.drainRasterPrefetchCompletionsForTesting()

        XCTAssertTrue(collection.rasterPrefetchRecordsForTesting.isEmpty)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 0)

        let visibleCell = MarkdownCollectionViewCell(
            frame: CGRect(origin: .zero, size: layout.size)
        )
        visibleCell.rasterPipelineForTesting = pipeline
        visibleCell.displayScaleOverrideForTesting = scale
        visibleCell.configure(with: layout)
        let visibleTextView = try XCTUnwrap(
            visibleCell.contentView.subviews.first as? AsyncTextView
        )
        assertIdentical((visibleTextView.layer.contents as! CGImage), renderedImage)
        XCTAssertEqual(pipeline.statistics.producerStarts, 1)
        XCTAssertEqual(pipeline.statistics.cacheHits, 1)
        visibleCell.prepareForReuse()

        let selectableRenderer = ControlledRasterRenderer()
        let selectablePipeline = makePipeline(renderer: selectableRenderer)
        let selectableCollection = makeCollectionView(
            pipeline: selectablePipeline,
            displayScale: scale
        )
        selectableCollection.textInteractionMode = .selectableNative
        await applyLayouts([makeTextLayout("selectable", renderFingerprint: 602)], to: selectableCollection)
        let selectablePlatformView = try collectionView(in: selectableCollection)

        selectableCollection.collectionView(
            selectablePlatformView,
            prefetchItemsAt: [indexPath]
        )

        XCTAssertTrue(selectableCollection.rasterPrefetchRecordsForTesting.isEmpty)
        XCTAssertEqual(selectableRenderer.startCount, 0)
        XCTAssertEqual(selectablePipeline.statistics.producerStarts, 0)
        XCTAssertEqual(selectablePipeline.statistics.activePublishableGenerations, 0)
    }

    func testCollectionReplacementCancelsOnlyStalePrefetchGeneration() async throws {
        let renderer = ControlledRasterRenderer()
        let pipeline = makePipeline(renderer: renderer)
        let collection = makeCollectionView(pipeline: pipeline, displayScale: 2.5)
        let indexPath = IndexPath(item: 0, section: 0)
        let layoutA = makeTextLayout("occupant A", renderFingerprint: 701)
        let layoutB = makeTextLayout("occupant B", renderFingerprint: 702)
        let platformCollectionView = try collectionView(in: collection)

        await applyLayouts([layoutA], to: collection)
        collection.collectionView(platformCollectionView, prefetchItemsAt: [indexPath])
        let startA = await renderer.nextStart()
        let recordA = try XCTUnwrap(collection.rasterPrefetchRecordsForTesting[indexPath])
        XCTAssertEqual(recordA.key, startA.key)

        await applyLayouts([layoutB], to: collection)
        XCTAssertTrue(collection.rasterPrefetchRecordsForTesting.isEmpty)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 0)

        collection.collectionView(platformCollectionView, prefetchItemsAt: [indexPath])
        let startB = await renderer.nextStart()
        let recordB = try XCTUnwrap(collection.rasterPrefetchRecordsForTesting[indexPath])

        XCTAssertNotEqual(recordA.stableIdentity, recordB.stableIdentity)
        XCTAssertNotEqual(recordA.key, recordB.key)
        XCTAssertNotEqual(recordA.token, recordB.token)
        XCTAssertNotEqual(recordA.leaseGeneration, recordB.leaseGeneration)
        XCTAssertEqual(recordB.key, startB.key)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 1)

        let imageA = makeImage(pixelWidth: 2, pixelHeight: 2, color: .red)
        let imageB = makeImage(pixelWidth: 2, pixelHeight: 2, color: .blue)
        renderer.complete(startB, with: imageB)
        await collection.drainRasterPrefetchCompletionsForTesting()
        renderer.complete(startA, with: imageA)
        await pipeline.drainForTesting()

        XCTAssertTrue(collection.rasterPrefetchRecordsForTesting.isEmpty)
        XCTAssertNil(pipeline.cachedImageForTesting(for: recordA.key))
        assertIdentical(pipeline.cachedImageForTesting(for: recordB.key), imageB)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 0)

        let layoutC = makeTextLayout("occupant C", renderFingerprint: 703)
        await applyLayouts([layoutC], to: collection)
        collection.collectionView(platformCollectionView, prefetchItemsAt: [indexPath])
        let startC = await renderer.nextStart()
        let recordC = try XCTUnwrap(collection.rasterPrefetchRecordsForTesting[indexPath])
        collection.collectionView(
            platformCollectionView,
            cancelPrefetchingForItemsAt: [indexPath]
        )

        XCTAssertTrue(collection.rasterPrefetchRecordsForTesting.isEmpty)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 0)
        renderer.complete(
            startC,
            with: makeImage(pixelWidth: 2, pixelHeight: 2, color: .green)
        )
        await pipeline.drainForTesting()
        XCTAssertNil(pipeline.cachedImageForTesting(for: recordC.key))
    }

    func testCellHostedViewReplacementReleasesVisibleRasterLeasesAndRejectsLateMounts() async throws {
        let renderer = ControlledRasterRenderer()
        let pipeline = makePipeline(renderer: renderer)
        let scale: CGFloat = 2.25
        let cell = MarkdownCollectionViewCell(frame: CGRect(x: 0, y: 0, width: 320, height: 120))
        cell.rasterPipelineForTesting = pipeline
        cell.displayScaleOverrideForTesting = scale

        let textLayout = makeTextLayout("old text", renderFingerprint: 801)
        cell.configure(with: textLayout)
        let textStart = await renderer.nextStart()
        XCTAssertTrue(cell.contentView.subviews.first is AsyncTextView)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 1)
        cell.configure(with: textLayout)
        XCTAssertEqual(pipeline.statistics.producerStarts, 1)
        XCTAssertEqual(pipeline.statistics.producerJoins, 0)

        let codeLayout = makeCodeLayout(
            "let replacement = true",
            size: CGSize(width: 320, height: 120),
            appearance: .light,
            renderFingerprint: 802
        )
        cell.configure(with: codeLayout)
        let codeStart = await renderer.nextStart()
        let codeView = try XCTUnwrap(cell.contentView.subviews.first as? AsyncCodeView)
        let codeTextView = try XCTUnwrap(codeView.subviews.compactMap { $0 as? AsyncTextView }.first)

        XCTAssertEqual(codeTextView.currentRasterKeyForTesting, codeStart.key)
        XCTAssertEqual(
            pipeline.statistics.activePublishableGenerations,
            1,
            "Replacing the old AsyncTextView must release its visible lease before starting code rendering"
        )

        renderer.complete(
            textStart,
            with: makeImage(pixelWidth: 2, pixelHeight: 2, color: .red)
        )

        cell.textInteractionMode = .selectableNative
        cell.configure(with: makeTextLayout("native replacement", renderFingerprint: 803))
        let selectableView = try XCTUnwrap(cell.contentView.subviews.first as? SelectableTextView)

        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 0)
        renderer.complete(
            codeStart,
            with: makeImage(pixelWidth: 2, pixelHeight: 2, color: .blue)
        )
        await pipeline.drainForTesting()

        XCTAssertIdentical(cell.contentView.subviews.first, selectableView)
        XCTAssertNil(selectableView.layer.contents)
        XCTAssertEqual(pipeline.statistics.cacheEntryCount, 0)
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 0)

        cell.textInteractionMode = .asyncReadOnly
        let offscreenLayout = makeTextLayout("offscreen", renderFingerprint: 804)
        cell.configure(with: offscreenLayout)
        let offscreenStart = await renderer.nextStart()
        cell.didMoveToSuperview()
        XCTAssertEqual(pipeline.statistics.activePublishableGenerations, 0)

        renderer.complete(
            offscreenStart,
            with: makeImage(pixelWidth: 2, pixelHeight: 2, color: .yellow)
        )
        await pipeline.drainForTesting()
        XCTAssertNil(pipeline.cachedImageForTesting(for: offscreenStart.key))
    }

    private func makePipeline(
        renderer: ControlledRasterRenderer,
        entryLimit: Int = 128,
        byteCostLimit: Int = 64 * 1_024 * 1_024
    ) -> RasterImagePipeline {
        RasterImagePipeline(
            entryLimit: entryLimit,
            byteCostLimit: byteCostLimit,
            renderer: { request in
                await renderer.render(request)
            }
        )
    }

    private func makeKey(
        _ fingerprint: Int,
        contentKind: RasterContentKind = .attributedText,
        size: CGSize = CGSize(width: 240.125, height: 48.375),
        scale: CGFloat = 2
    ) -> RasterRenderKey {
        RasterRenderKey(
            renderFingerprint: fingerprint,
            appearance: .light,
            contentKind: contentKind,
            logicalSize: size,
            displayScale: scale
        )
    }

    private func makeRequest(
        _ key: RasterRenderKey,
        priority: TaskPriority = .utility
    ) -> RasterRenderRequest {
        RasterRenderRequest(key: key, priority: priority, produce: { nil })
    }

    private func makeLazyRequest(
        _ key: RasterRenderKey,
        priority: TaskPriority,
        counter: RasterProducerMaterializationCounter
    ) -> RasterRenderRequest {
        RasterRenderRequest(
            key: key,
            priority: priority,
            makeProducer: {
                counter.count += 1
                return { nil }
            }
        )
    }

    private func requirePending(
        _ acquisition: RasterImageAcquisition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> RasterImageLease {
        guard case let .pending(lease) = acquisition else {
            XCTFail("Expected a pending raster lease", file: file, line: line)
            throw ContractTestError.unexpectedAcquisition
        }
        return lease
    }

    private func requireCacheHit(
        _ acquisition: RasterImageAcquisition,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> CGImage {
        guard case let .cacheHit(image) = acquisition else {
            XCTFail("Expected a synchronous raster cache hit", file: file, line: line)
            throw ContractTestError.unexpectedAcquisition
        }
        return image
    }

    @discardableResult
    private func render(
        _ key: RasterRenderKey,
        as image: CGImage,
        through pipeline: RasterImagePipeline,
        renderer: ControlledRasterRenderer
    ) async throws -> CGImage {
        let lease = try requirePending(pipeline.acquire(makeRequest(key)))
        let start = await renderer.nextStart()
        XCTAssertEqual(start.key, key)
        renderer.complete(start, with: image)
        let leaseImage = await lease.value()
        let result = try XCTUnwrap(leaseImage)
        lease.release()
        await pipeline.drainForTesting()
        return result
    }

    private func assertIdentical(
        _ actual: CGImage?,
        _ expected: CGImage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected a raster image", file: file, line: line)
            return
        }
        XCTAssertTrue(actual === expected, file: file, line: line)
    }

    private func makeImage(
        pixelWidth: Int,
        pixelHeight: Int,
        color: UIColor
    ) -> CGImage {
        let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(color.cgColor)
        context.fill(
            CGRect(
                x: 0,
                y: 0,
                width: CGFloat(pixelWidth),
                height: CGFloat(pixelHeight)
            )
        )
        return context.makeImage()!
    }

    private func makeTheme(codePadding: CGFloat) -> Theme {
        let base = Theme.default
        return Theme(
            typography: base.typography,
            colors: base.colors,
            codeBlock: Theme.CodeBlockStyle(viewPadding: codePadding),
            blockQuote: base.blockQuote,
            list: base.list,
            details: base.details,
            table: base.table,
            syntaxColors: base.syntaxColors,
            highlight: base.highlight,
            thematicBreak: base.thematicBreak
        )
    }

    private func makeTextLayout(
        _ text: String,
        renderFingerprint: Int
    ) -> LayoutResult {
        LayoutResult(
            node: ParagraphNode(
                range: nil,
                children: [TextNode(range: nil, text: text)]
            ),
            size: CGSize(width: 320, height: 48),
            attributedString: NSAttributedString(string: text),
            appearance: .light,
            renderFingerprint: renderFingerprint
        )
    }

    private func makeCodeLayout(
        _ code: String,
        size: CGSize,
        appearance: MarkdownAppearance,
        renderFingerprint: Int
    ) -> LayoutResult {
        LayoutResult(
            node: CodeBlockNode(range: nil, language: "swift", code: code),
            size: size,
            attributedString: NSAttributedString(string: code),
            appearance: appearance,
            renderFingerprint: renderFingerprint
        )
    }

    private func makeDiagramLayout(
        _ source: String,
        size: CGSize,
        appearance: MarkdownAppearance,
        renderFingerprint: Int
    ) -> LayoutResult {
        LayoutResult(
            node: DiagramNode(range: nil, language: .mermaid, source: source),
            size: size,
            attributedString: NSAttributedString(string: source),
            appearance: appearance,
            renderFingerprint: renderFingerprint
        )
    }

    private func makeCollectionView(
        pipeline: RasterImagePipeline,
        displayScale: CGFloat
    ) -> MarkdownCollectionView {
        let view = MarkdownCollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 480)
        )
        view.rasterPipelineForTesting = pipeline
        view.displayScaleOverrideForTesting = displayScale
        return view
    }

    private func collectionView(
        in view: MarkdownCollectionView
    ) throws -> UICollectionView {
        try XCTUnwrap(view.subviews.compactMap { $0 as? UICollectionView }.first)
    }

    private func applyLayouts(
        _ layouts: [LayoutResult],
        to view: MarkdownCollectionView
    ) async {
        let applied = expectation(description: "Diffable layout snapshot applied")
        view.onLayoutSnapshotApplicationCompletionForTesting = {
            applied.fulfill()
        }
        view.layouts = layouts
        await fulfillment(of: [applied], timeout: 2)
        view.onLayoutSnapshotApplicationCompletionForTesting = nil
    }
}

@MainActor
private final class ControlledRasterRenderer {
    struct Start: Equatable {
        let id: Int
        let key: RasterRenderKey
    }

    private var nextID = 0
    private var queuedStarts: [Start] = []
    private var startWaiters: [CheckedContinuation<Start, Never>] = []
    private var renderWaiters: [Int: CheckedContinuation<CGImage?, Never>] = [:]
    private var completionPriorities: [Int: TaskPriority] = [:]

    private(set) var startCount = 0

    func render(_ request: RasterRenderRequest) async -> CGImage? {
        let start = Start(id: nextID, key: request.key)
        nextID += 1
        startCount += 1

        let image = await withCheckedContinuation { continuation in
            renderWaiters[start.id] = continuation

            if startWaiters.isEmpty {
                queuedStarts.append(start)
            } else {
                startWaiters.removeFirst().resume(returning: start)
            }
        }
        completionPriorities[start.id] = Task.currentPriority
        return image
    }

    func nextStart() async -> Start {
        if !queuedStarts.isEmpty {
            return queuedStarts.removeFirst()
        }
        return await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func complete(_ start: Start, with image: CGImage?) {
        guard let continuation = renderWaiters.removeValue(forKey: start.id) else {
            XCTFail("No suspended render for start \(start.id)")
            return
        }
        continuation.resume(returning: image)
    }

    func completionPriority(for start: Start) -> TaskPriority? {
        completionPriorities[start.id]
    }
}

private enum ContractTestError: Error {
    case unexpectedAcquisition
}

@MainActor
private final class RasterProducerMaterializationCounter {
    var count = 0
}

private final class BlockingRasterProducer: @unchecked Sendable {
    private let image: CGImage
    private let resumeSignal = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var recordedPriority: TaskPriority?
    private var recordedMainThread = false
    private var didStart = false
    private var startWaiter: CheckedContinuation<Void, Never>?

    init(image: CGImage) {
        self.image = image
    }

    var completionPriority: TaskPriority? {
        lock.lock()
        defer { lock.unlock() }
        return recordedPriority
    }

    var ranOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return recordedMainThread
    }

    func produce() -> CGImage? {
        lock.lock()
        didStart = true
        let waiter = startWaiter
        startWaiter = nil
        lock.unlock()
        waiter?.resume()
        resumeSignal.wait()
        lock.lock()
        recordedPriority = Task.currentPriority
        recordedMainThread = Thread.isMainThread
        lock.unlock()
        return image
    }

    func waitUntilStarted() async {
        await withCheckedContinuation { continuation in
            let shouldResume = lock.withLock {
                if didStart {
                    return true
                }
                startWaiter = continuation
                return false
            }
            if shouldResume {
                continuation.resume()
            }
        }
    }

    func resume() {
        resumeSignal.signal()
    }
}
#endif
