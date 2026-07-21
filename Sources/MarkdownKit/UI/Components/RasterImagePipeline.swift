#if canImport(UIKit) && !os(watchOS)
import UIKit

enum RasterContentKind: Hashable, Sendable {
    case attributedText
    case customDraw
}

struct RasterRenderKey: Hashable, Sendable {
    let renderFingerprint: Int
    let appearance: MarkdownAppearance
    let contentKind: RasterContentKind
    let logicalSize: CGSize
    let displayScale: CGFloat
}

struct RasterRenderRequest: Sendable {
    typealias Producer = @Sendable () -> CGImage?
    typealias ProducerFactory = @MainActor @Sendable () -> Producer

    let key: RasterRenderKey
    let priority: TaskPriority

    private let producer: Producer?
    private let producerFactory: ProducerFactory

    init(
        key: RasterRenderKey,
        priority: TaskPriority = .utility,
        produce: @escaping Producer
    ) {
        self.key = key
        self.priority = priority
        self.producer = produce
        self.producerFactory = { produce }
    }

    @MainActor
    init(
        key: RasterRenderKey,
        priority: TaskPriority = .utility,
        makeProducer: @escaping ProducerFactory
    ) {
        self.key = key
        self.priority = priority
        self.producer = nil
        self.producerFactory = makeProducer
    }

    @MainActor
    func produceSynchronously() -> CGImage? {
        materialized().produceImage()
    }

    @MainActor
    fileprivate func materialized() -> RasterRenderRequest {
        guard producer == nil else { return self }
        return RasterRenderRequest(
            key: key,
            priority: priority,
            produce: producerFactory()
        )
    }

    fileprivate func produceImage() -> CGImage? {
        producer?()
    }
}

enum RasterImageAcquisition {
    case cacheHit(CGImage)
    case pending(RasterImageLease)
}

struct RasterImagePipelineStatistics {
    let producerStarts: Int
    let producerJoins: Int
    let cacheHits: Int
    let cacheInsertions: Int
    let cacheEvictions: Int
    let activePublishableGenerations: Int
    let cacheEntryCount: Int
    let cachedByteCost: Int
    let cacheEntryLimit: Int
    let cacheByteCostLimit: Int
}

struct RasterContentLayout {
    let size: CGSize
    let renderFingerprint: Int
    let appearance: MarkdownAppearance
    let attributedString: NSAttributedString?
    let customDraw: (@Sendable (CGContext, CGSize) -> Void)?

    var contentKind: RasterContentKind {
        customDraw == nil ? .attributedText : .customDraw
    }

    static func resolve(layout: LayoutResult, theme: Theme) -> RasterContentLayout {
        let isInsetContent = layout.node is CodeBlockNode || layout.node is DiagramNode
        let padding = isInsetContent ? theme.codeBlock.viewPadding : 0
        let size = contentSize(containerSize: layout.size, padding: padding)

        return RasterContentLayout(
            size: size,
            renderFingerprint: layout.renderFingerprint,
            appearance: layout.appearance,
            attributedString: layout.attributedString,
            customDraw: layout.customDraw
        )
    }

    static func contentSize(containerSize: CGSize, padding: CGFloat) -> CGSize {
        let totalInset = padding * 2
        return CGSize(
            width: clampedDimension(containerSize.width - totalInset),
            height: clampedDimension(containerSize.height - totalInset)
        )
    }

    func rasterKey(displayScale: CGFloat) -> RasterRenderKey? {
        guard size.width > 0,
              size.height > 0,
              displayScale.isFinite,
              displayScale > 0,
              customDraw != nil || attributedString?.length ?? 0 > 0 else {
            return nil
        }

        return RasterRenderKey(
            renderFingerprint: renderFingerprint,
            appearance: appearance,
            contentKind: contentKind,
            logicalSize: size,
            displayScale: displayScale
        )
    }

    @MainActor
    func rasterRequest(
        displayScale: CGFloat,
        priority: TaskPriority = .utility
    ) -> RasterRenderRequest? {
        guard let key = rasterKey(displayScale: displayScale) else { return nil }

        if let customDraw {
            let appearance = appearance
            let size = size
            return RasterRenderRequest(
                key: key,
                priority: priority,
                makeProducer: {
                    let configuration = FrozenRasterConfiguration(
                        appearance: appearance,
                        scale: displayScale
                    )
                    return {
                        RasterImageRenderer.renderCustom(
                            customDraw: customDraw,
                            size: size,
                            configuration: configuration
                        )
                    }
                }
            )
        }

        guard let attributedString else { return nil }
        let source = RasterAttributedStringSource(attributedString)
        let appearance = appearance
        let size = size
        return RasterRenderRequest(
            key: key,
            priority: priority,
            makeProducer: {
                let frozenString = FrozenAttributedString(source.value)
                let configuration = FrozenRasterConfiguration(
                    appearance: appearance,
                    scale: displayScale
                )
                return {
                    RasterImageRenderer.renderAttributedString(
                        frozenString.value,
                        size: size,
                        configuration: configuration
                    )
                }
            }
        )
    }

    private static func clampedDimension(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else { return 0 }
        return max(0, value)
    }
}

@MainActor
private final class RasterAttributedStringSource {
    let value: NSAttributedString

    init(_ value: NSAttributedString) {
        self.value = value
    }
}

/// `NSAttributedString` is immutable after this defensive copy and is only read
/// by the raster worker. Foundation does not yet declare it `Sendable`, so this
/// private bridge narrowly documents the immutable cross-executor payload.
private final class FrozenAttributedString: @unchecked Sendable {
    let value: NSAttributedString

    init(_ value: NSAttributedString) {
        self.value = NSAttributedString(attributedString: value)
    }
}

/// UIKit's rendering configuration classes are fully initialized on MainActor
/// and then treated as immutable worker input. They are not annotated Sendable,
/// so this private bridge confines the unchecked boundary to that frozen state.
private final class FrozenRasterConfiguration: @unchecked Sendable {
    let traits: UITraitCollection
    let format: UIGraphicsImageRendererFormat

    @MainActor
    init(appearance: MarkdownAppearance, scale: CGFloat) {
        let interfaceStyle: UIUserInterfaceStyle = appearance == .dark ? .dark : .light
        let traits = UITraitCollection {
            $0.userInterfaceStyle = interfaceStyle
            $0.displayScale = scale
        }
        let format = UIGraphicsImageRendererFormat(for: traits)
        format.scale = scale
        self.traits = traits
        self.format = format
    }
}

/// NotificationCenter's opaque observer token is thread-safe to remove but is
/// not annotated `Sendable`. This private owner only stores the token and
/// unregisters it during teardown.
private final class RasterMemoryWarningObservation {
    let token: NSObjectProtocol

    init(token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}

private enum RasterImageRenderer {
    static nonisolated func renderAttributedString(
        _ attributedString: NSAttributedString,
        size: CGSize,
        configuration: FrozenRasterConfiguration
    ) -> CGImage? {
        render(size: size, configuration: configuration) { _ in
            let textStorage = NSTextStorage(attributedString: attributedString)
            let layoutManager = NSLayoutManager()
            let textContainer = NSTextContainer(size: size)

            textContainer.lineFragmentPadding = 0
            textContainer.maximumNumberOfLines = 0
            layoutManager.addTextContainer(textContainer)
            textStorage.addLayoutManager(layoutManager)

            let glyphRange = layoutManager.glyphRange(for: textContainer)
            guard !Task.isCancelled else { return }
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
        }
    }

    static nonisolated func renderCustom(
        customDraw: @Sendable (CGContext, CGSize) -> Void,
        size: CGSize,
        configuration: FrozenRasterConfiguration
    ) -> CGImage? {
        render(size: size, configuration: configuration) { context in
            guard !Task.isCancelled else { return }
            customDraw(context.cgContext, size)
        }
    }

    private static nonisolated func render(
        size: CGSize,
        configuration: FrozenRasterConfiguration,
        drawing: (UIGraphicsImageRendererContext) -> Void
    ) -> CGImage? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: size, format: configuration.format)
        var renderedImage: UIImage?
        configuration.traits.performAsCurrent {
            renderedImage = renderer.image(actions: drawing)
        }
        return renderedImage?.cgImage
    }
}

@MainActor
final class RasterImageLease {
    let key: RasterRenderKey
    let generation: Int

    private var pipeline: RasterImagePipeline?
    private let consumerID: UUID
    private let state: RasterImageLeaseState
    private var isReleased = false

    fileprivate init(
        key: RasterRenderKey,
        generation: Int,
        consumerID: UUID,
        state: RasterImageLeaseState,
        pipeline: RasterImagePipeline
    ) {
        self.key = key
        self.generation = generation
        self.consumerID = consumerID
        self.state = state
        self.pipeline = pipeline
    }

    func value() async -> CGImage? {
        await state.value()
    }

    func release() {
        guard !isReleased else { return }
        isReleased = true
        guard let pipeline else {
            state.complete(with: nil)
            return
        }
        self.pipeline = nil
        pipeline.release(
            key: key,
            generation: generation,
            consumerID: consumerID
        )
    }

    isolated deinit {
        release()
    }
}

@MainActor
private final class RasterImageLeaseState {
    private var result: CGImage??
    private var waiters: [CheckedContinuation<CGImage?, Never>] = []

    func value() async -> CGImage? {
        if let result {
            return result
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func complete(with image: CGImage?) {
        guard result == nil else { return }
        result = .some(image)
        let pendingWaiters = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in pendingWaiters {
            waiter.resume(returning: image)
        }
    }
}

@MainActor
final class RasterImagePipeline {
    static let shared = RasterImagePipeline()

    typealias Renderer = @MainActor (RasterRenderRequest) async -> CGImage?

    private final class ActiveGeneration {
        let id: Int
        var consumers: [UUID: RasterImageLeaseState]
        var task: Task<Void, Never>?
        var pixelTask: Task<CGImage?, Never>?
        var priority: TaskPriority
        var priorityBoostTask: Task<Void, Never>?
        let cacheEpoch: UInt

        init(
            id: Int,
            consumerID: UUID,
            state: RasterImageLeaseState,
            priority: TaskPriority,
            cacheEpoch: UInt
        ) {
            self.id = id
            self.consumers = [consumerID: state]
            self.priority = priority
            self.cacheEpoch = cacheEpoch
        }
    }

    private final class CacheEntry {
        let key: RasterRenderKey
        var image: CGImage
        var cost: Int
        weak var previous: CacheEntry?
        var next: CacheEntry?

        init(key: RasterRenderKey, image: CGImage, cost: Int) {
            self.key = key
            self.image = image
            self.cost = cost
        }
    }

    private let entryLimit: Int
    private let byteCostLimit: Int
    private let renderer: Renderer?

    private var activeGenerations: [RasterRenderKey: ActiveGeneration] = [:]
    private var producerTasks: [Int: Task<Void, Never>] = [:]
    private var nextGeneration = 0

    private var cacheEntries: [RasterRenderKey: CacheEntry] = [:]
    private var mostRecentCacheEntry: CacheEntry?
    private var leastRecentCacheEntry: CacheEntry?
    private var cachedByteCost = 0
    private var cacheEpoch: UInt = 0

    private var producerStarts = 0
    private var producerJoins = 0
    private var cacheHits = 0
    private var cacheInsertions = 0
    private var cacheEvictions = 0
    private var memoryWarningObservation: RasterMemoryWarningObservation?

    init(
        entryLimit: Int = 128,
        byteCostLimit: Int = 64 * 1_024 * 1_024,
        renderer: Renderer? = nil
    ) {
        self.entryLimit = max(0, entryLimit)
        self.byteCostLimit = max(0, byteCostLimit)
        self.renderer = renderer
        let observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.clearCache()
            }
        }
        self.memoryWarningObservation = RasterMemoryWarningObservation(token: observer)
    }

    var statistics: RasterImagePipelineStatistics {
        RasterImagePipelineStatistics(
            producerStarts: producerStarts,
            producerJoins: producerJoins,
            cacheHits: cacheHits,
            cacheInsertions: cacheInsertions,
            cacheEvictions: cacheEvictions,
            activePublishableGenerations: activeGenerations.count,
            cacheEntryCount: cacheEntries.count,
            cachedByteCost: cachedByteCost,
            cacheEntryLimit: entryLimit,
            cacheByteCostLimit: byteCostLimit
        )
    }

    func acquire(_ request: RasterRenderRequest) -> RasterImageAcquisition {
        if let image = cachedImageIfAvailable(for: request.key) {
            return .cacheHit(image)
        }

        let consumerID = UUID()
        let state = RasterImageLeaseState()

        if let activeGeneration = activeGenerations[request.key] {
            activeGeneration.consumers[consumerID] = state
            promote(activeGeneration, to: request.priority)
            producerJoins += 1
            return .pending(
                RasterImageLease(
                    key: request.key,
                    generation: activeGeneration.id,
                    consumerID: consumerID,
                    state: state,
                    pipeline: self
                )
            )
        }

        let generationID = nextGeneration
        nextGeneration &+= 1
        let generation = ActiveGeneration(
            id: generationID,
            consumerID: consumerID,
            state: state,
            priority: request.priority,
            cacheEpoch: cacheEpoch
        )
        activeGenerations[request.key] = generation
        producerStarts += 1
        let materializedRequest = request.materialized()

        let task: Task<Void, Never>
        if let renderer {
            task = Task(priority: request.priority) { [weak self] in
                let image = await renderer(materializedRequest)
                guard let self else { return }
                self.finishProducer(
                    key: materializedRequest.key,
                    generation: generationID,
                    image: image
                )
            }
        } else {
            let pixelTask = Task.detached(
                priority: request.priority
            ) { () -> CGImage? in
                guard !Task.isCancelled else { return nil }
                return materializedRequest.produceImage()
            }
            generation.pixelTask = pixelTask
            task = Task(priority: request.priority) { [weak self] in
                let image = await withTaskCancellationHandler {
                    await pixelTask.value
                } onCancel: {
                    pixelTask.cancel()
                }
                guard let self else { return }
                self.finishProducer(
                    key: materializedRequest.key,
                    generation: generationID,
                    image: image
                )
            }
        }
        generation.task = task
        producerTasks[generationID] = task

        return .pending(
            RasterImageLease(
                key: request.key,
                generation: generationID,
                consumerID: consumerID,
                state: state,
                pipeline: self
            )
        )
    }

    func cachedImageIfAvailable(for key: RasterRenderKey) -> CGImage? {
        guard let image = cachedImage(for: key) else { return nil }
        cacheHits += 1
        return image
    }

    func storeDirectlyRenderedImage(_ image: CGImage, for key: RasterRenderKey) {
        insert(image, for: key)
    }

    func clearCache() {
        cacheEpoch &+= 1
        cacheEntries.removeAll(keepingCapacity: false)
        mostRecentCacheEntry = nil
        leastRecentCacheEntry = nil
        cachedByteCost = 0
    }

    func cachedImageForTesting(for key: RasterRenderKey) -> CGImage? {
        cacheEntries[key]?.image
    }

    func drainForTesting() async {
        while !producerTasks.isEmpty {
            let tasks = Array(producerTasks.values)
            for task in tasks {
                await task.value
            }
        }
    }

    fileprivate func release(
        key: RasterRenderKey,
        generation: Int,
        consumerID: UUID
    ) {
        guard let activeGeneration = activeGenerations[key],
              activeGeneration.id == generation,
              let state = activeGeneration.consumers.removeValue(forKey: consumerID) else {
            return
        }

        state.complete(with: nil)
        guard activeGeneration.consumers.isEmpty else { return }

        activeGenerations.removeValue(forKey: key)
        activeGeneration.task?.cancel()
        activeGeneration.task = nil
        activeGeneration.pixelTask?.cancel()
        activeGeneration.pixelTask = nil
        activeGeneration.priorityBoostTask?.cancel()
        activeGeneration.priorityBoostTask = nil
    }

    private func finish(
        key: RasterRenderKey,
        generation: Int,
        image: CGImage?
    ) {
        guard let activeGeneration = activeGenerations[key],
              activeGeneration.id == generation else {
            return
        }

        activeGenerations.removeValue(forKey: key)
        activeGeneration.task = nil
        activeGeneration.pixelTask = nil
        activeGeneration.priorityBoostTask?.cancel()
        activeGeneration.priorityBoostTask = nil
        if let image, activeGeneration.cacheEpoch == cacheEpoch {
            insert(image, for: key)
        }
        for state in activeGeneration.consumers.values {
            state.complete(with: image)
        }
        activeGeneration.consumers.removeAll(keepingCapacity: false)
    }

    private func promote(
        _ activeGeneration: ActiveGeneration,
        to priority: TaskPriority
    ) {
        guard priority.rawValue > activeGeneration.priority.rawValue else {
            return
        }

        activeGeneration.priority = priority
        activeGeneration.priorityBoostTask?.cancel()
        if let pixelTask = activeGeneration.pixelTask {
            if #available(iOS 26.0, *) {
                pixelTask.escalatePriority(to: priority)
            }
            activeGeneration.priorityBoostTask = Task.detached(priority: priority) {
                _ = await pixelTask.value
            }
        } else if let producerTask = activeGeneration.task {
            if #available(iOS 26.0, *) {
                producerTask.escalatePriority(to: priority)
            }
            activeGeneration.priorityBoostTask = Task.detached(priority: priority) {
                await producerTask.value
            }
        }
    }

    private func finishProducer(
        key: RasterRenderKey,
        generation: Int,
        image: CGImage?
    ) {
        finish(key: key, generation: generation, image: image)
        producerTasks.removeValue(forKey: generation)
    }

    private func cachedImage(for key: RasterRenderKey) -> CGImage? {
        guard let entry = cacheEntries[key] else { return nil }
        moveToMostRecent(entry)
        return entry.image
    }

    private func insert(_ image: CGImage, for key: RasterRenderKey) {
        guard let cost = byteCost(of: image),
              entryLimit > 0,
              cost <= byteCostLimit else {
            return
        }

        if let existing = cacheEntries[key] {
            cachedByteCost -= existing.cost
            existing.image = image
            existing.cost = cost
            cachedByteCost += cost
            moveToMostRecent(existing)
        } else {
            let entry = CacheEntry(key: key, image: image, cost: cost)
            cacheEntries[key] = entry
            attachAsMostRecent(entry)
            cachedByteCost += cost
            cacheInsertions += 1
        }

        while cacheEntries.count > entryLimit || cachedByteCost > byteCostLimit {
            guard let entry = leastRecentCacheEntry else { break }
            removeCacheEntry(entry)
            cacheEvictions += 1
        }
    }

    private func byteCost(of image: CGImage) -> Int? {
        let (cost, overflow) = image.bytesPerRow.multipliedReportingOverflow(by: image.height)
        guard !overflow, cost >= 0 else { return nil }
        return cost
    }

    private func moveToMostRecent(_ entry: CacheEntry) {
        guard mostRecentCacheEntry !== entry else { return }
        detach(entry)
        attachAsMostRecent(entry)
    }

    private func attachAsMostRecent(_ entry: CacheEntry) {
        entry.previous = nil
        entry.next = mostRecentCacheEntry
        mostRecentCacheEntry?.previous = entry
        mostRecentCacheEntry = entry
        if leastRecentCacheEntry == nil {
            leastRecentCacheEntry = entry
        }
    }

    private func removeCacheEntry(_ entry: CacheEntry) {
        cacheEntries.removeValue(forKey: entry.key)
        cachedByteCost -= entry.cost
        detach(entry)
    }

    private func detach(_ entry: CacheEntry) {
        let previous = entry.previous
        let next = entry.next
        previous?.next = next
        next?.previous = previous

        if mostRecentCacheEntry === entry {
            mostRecentCacheEntry = next
        }
        if leastRecentCacheEntry === entry {
            leastRecentCacheEntry = previous
        }

        entry.previous = nil
        entry.next = nil
    }
}
#endif
