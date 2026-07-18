import Foundation
import WebKit
import os

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A pluggable adapter that renders Mermaid diagrams using a lightweight headless WKWebView
/// and converts them into an NSTextAttachment.
public struct MermaidDiagramAdapter: DiagramRenderingAdapter {

    static let logger = Logger(subsystem: "com.markdownkit", category: "MermaidDiagram")

    public let supportedLanguage: DiagramLanguage = .mermaid
    
    public init() {}
    
    public func render(source: String, language: DiagramLanguage) async -> NSAttributedString? {
        guard language == supportedLanguage else { return nil }
        guard !Task.isCancelled else { return nil }
        
        let image: NativeImage? = await MermaidSnapshotter.shared.takeSnapshot(source: source)
        
        guard !Task.isCancelled else { return nil }
        guard let img = image else { return nil }

        #if canImport(AppKit)
        let attachmentImage = (img.copy() as? NativeImage) ?? img
        #else
        let attachmentImage = img
        #endif
        
        let attachment = NSTextAttachment()
        #if canImport(UIKit)
        attachment.image = attachmentImage
        #elseif canImport(AppKit)
        attachment.image = attachmentImage
        #endif
        attachment.bounds = CGRect(origin: .zero, size: attachmentImage.size)
        
        return NSAttributedString(attachment: attachment)
    }
}

@MainActor
protocol MermaidSnapshotRenderDriver: AnyObject {
    func render(
        source: String,
        completion: @escaping @MainActor (NativeImage?) -> Void
    )
}

typealias MermaidSnapshotRenderDriverFactory = () -> any MermaidSnapshotRenderDriver

struct MermaidSnapshotterStatistics: Equatable, Sendable {
    let actualRenderStartCount: Int
    let cacheHitCount: Int
    let cacheCountLimit: Int
    let cacheTotalCostLimit: Int
    let queuedRequestCount: Int
    let isRendering: Bool
}

extension MermaidDiagramAdapter {
    @MainActor
    static func resetSnapshotterForTesting() {
        MermaidSnapshotter.shared.resetForTesting()
    }

    @MainActor
    static func snapshotterStatisticsForTesting() -> MermaidSnapshotterStatistics {
        MermaidSnapshotter.shared.statisticsForTesting()
    }

    @MainActor
    static func pauseNextRenderForTesting() {
        MermaidSnapshotter.shared.pauseNextRenderForTesting()
    }

    @MainActor
    static func resumePausedRenderForTesting() {
        MermaidSnapshotter.shared.resumePausedRenderForTesting()
    }

    @MainActor
    static func failNextRenderForTesting() {
        MermaidSnapshotter.shared.failNextRenderForTesting()
    }

    @MainActor
    static func timeOutActiveRenderForTesting() {
        MermaidSnapshotter.shared.timeOutActiveRenderForTesting()
    }

    @MainActor
    static func invalidateSnapshotterReadinessForTesting() {
        MermaidSnapshotter.shared.invalidateReadinessForTesting()
    }

    @MainActor
    static func installSnapshotRenderDriverFactoryForTesting(
        _ factory: @escaping MermaidSnapshotRenderDriverFactory
    ) {
        MermaidSnapshotter.installSnapshotRenderDriverFactoryForTesting(factory)
    }

    @MainActor
    static func renderedDiagramTextForTesting() async -> String? {
        await MermaidSnapshotter.shared.renderedDiagramTextForTesting()
    }
}

enum MermaidResourceLocator {
    static let bundledScriptName = "mermaid.min"
    static let bundledScriptExtension = "js"
    static let bundledBootstrapName = "mermaid-bootstrap"
    static let bundledBootstrapExtension = "html"

    static func bundledScriptURL() -> URL? {
        Bundle.module.url(
            forResource: bundledScriptName,
            withExtension: bundledScriptExtension
        )
    }

    static func bundledBootstrapURL() -> URL? {
        Bundle.module.url(
            forResource: bundledBootstrapName,
            withExtension: bundledBootstrapExtension
        )
    }

    static func bundledResourceDirectory() -> URL? {
        bundledBootstrapURL()?.deletingLastPathComponent()
    }
}

@MainActor
private final class MermaidSnapshotter: NSObject, WKNavigationDelegate {
    
    private static var sharedInstance: MermaidSnapshotter?
    private static var snapshotRenderDriverFactory: MermaidSnapshotRenderDriverFactory?

    static var shared: MermaidSnapshotter {
        if let sharedInstance {
            return sharedInstance
        }

        let snapshotter = MermaidSnapshotter(
            snapshotRenderDriver: snapshotRenderDriverFactory?()
        )
        sharedInstance = snapshotter
        return snapshotter
    }

    static func installSnapshotRenderDriverFactoryForTesting(
        _ factory: @escaping MermaidSnapshotRenderDriverFactory
    ) {
        if let sharedInstance {
            precondition(
                sharedInstance.snapshotRenderDriver != nil,
                "Cannot install a Mermaid snapshot render driver after the production snapshotter is created"
            )
            return
        }

        snapshotRenderDriverFactory = factory
    }

    private final class Request {
        let id: UUID
        let source: String
        private let cancellationFlag: CancellationFlag
        var continuation: CheckedContinuation<NativeImage?, Never>?
        var isCancelled: Bool {
            cancellationFlag.isCancelled
        }

        init(
            id: UUID,
            source: String,
            cancellationFlag: CancellationFlag,
            continuation: CheckedContinuation<NativeImage?, Never>
        ) {
            self.id = id
            self.source = source
            self.cancellationFlag = cancellationFlag
            self.continuation = continuation
        }

        func cancel() {
            cancellationFlag.cancel()
        }
    }

    private final class CancellationFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func cancel() {
            lock.lock()
            value = true
            lock.unlock()
        }
    }

    private let snapshotRenderDriver: (any MermaidSnapshotRenderDriver)?
    private var webView: WKWebView?
    private let hasBundledResources: Bool
    private var loadingNavigation: WKNavigation?
    private var readinessProbeID: UUID?
    private var bootstrapGeneration: UUID?
    private var activeRequest: Request?
    private var queue: [Request] = []
    private var timeoutTask: Task<Void, Never>?
    private var readinessTimeoutTask: Task<Void, Never>?
    private var readinessTimeoutID: UUID?
    private var bootstrapWatchdogTask: Task<Void, Never>?
    // Cold WebKit navigation and bundled Mermaid script initialization can take several seconds in CI.
    private let readinessTimeout: TimeInterval = 15.0
    private let bootstrapHardTimeout: TimeInterval = 120.0
    private let renderTimeout: TimeInterval = 15.0
    private let snapshotDimensionLimit: CGFloat = 2048
    private var isRenderBackendReady = false
    private let cacheTotalCostLimit = 64 * 1024 * 1024
    private let imageCache: NSCache<NSString, NativeImage> = {
        let cache = NSCache<NSString, NativeImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private var actualRenderStartCount = 0
    private var cacheHitCount = 0
    private var shouldPauseNextRenderForTesting = false
    private var shouldFailNextRenderForTesting = false
    private weak var pausedRequestForTesting: Request?

    private var isRenderBackendAvailable: Bool {
        snapshotRenderDriver != nil || hasBundledResources
    }
    
    private init(snapshotRenderDriver: (any MermaidSnapshotRenderDriver)?) {
        self.snapshotRenderDriver = snapshotRenderDriver
        hasBundledResources = MermaidResourceLocator.bundledScriptURL() != nil
            && MermaidResourceLocator.bundledBootstrapURL() != nil

        if snapshotRenderDriver == nil {
            let configuration = WKWebViewConfiguration()
            webView = WKWebView(
                frame: CGRect(x: 0, y: 0, width: 640, height: 480),
                configuration: configuration
            )
        } else {
            webView = nil
        }
        super.init()

        guard let webView else {
            isRenderBackendReady = true
            return
        }

        webView.navigationDelegate = self
        
        #if canImport(UIKit)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        #elseif canImport(AppKit)
        webView.setValue(false, forKey: "drawsBackground")
        #endif

        loadBaseHTML()
    }
    
    func takeSnapshot(source: String) async -> NativeImage? {
        let requestID = UUID()
        let cancellationFlag = CancellationFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation(isolation: MainActor.shared) { continuation in
                enqueueRequest(
                    id: requestID,
                    source: source,
                    cancellationFlag: cancellationFlag,
                    continuation: continuation
                )
            }
        } onCancel: {
            cancellationFlag.cancel()
            Task { @MainActor in
                MermaidSnapshotter.shared.cancelRequest(id: requestID)
            }
        }
    }

    private func enqueueRequest(
        id: UUID,
        source: String,
        cancellationFlag: CancellationFlag,
        continuation: CheckedContinuation<NativeImage?, Never>
    ) {
        let request = Request(
            id: id,
            source: source,
            cancellationFlag: cancellationFlag,
            continuation: continuation
        )

        if Task.isCancelled {
            request.cancel()
            finish(request, image: nil)
            return
        }

        queue.append(request)

        guard isRenderBackendAvailable else {
            MermaidDiagramAdapter.logger.error(
                "Mermaid bundled resources are unavailable; failing queued renders"
            )
            failQueuedRenders()
            return
        }

        if isRenderBackendReady {
            processNext()
        } else {
            ensureRenderBackendIsLoading()
            scheduleReadinessTimeoutIfNeeded()
        }
    }

    private func cancelRequest(id: UUID) {
        if let activeRequest, activeRequest.id == id {
            activeRequest.cancel()
            resume(activeRequest, image: nil)
            // The caller can stop waiting immediately, but the shared backend
            // must drain the in-flight completion before the next request.
            return
        }

        guard let index = queue.firstIndex(where: { $0.id == id }) else {
            return
        }

        let request = queue.remove(at: index)
        request.cancel()
        finish(request, image: nil)
        cancelReadinessTimeoutIfNoPendingRequests()
    }
    
    private func processNext() {
        guard activeRequest == nil else { return }
        guard isRenderBackendReady else {
            scheduleReadinessTimeoutIfNeeded()
            return
        }

        while activeRequest == nil, !queue.isEmpty {
            let request = queue.removeFirst()

            if request.isCancelled {
                finish(request, image: nil)
                continue
            }

            if let cachedImage = imageCache.object(forKey: request.source as NSString) {
                cacheHitCount += 1
                finish(request, image: cachedImage)
                continue
            }

            startRender(request)
            return
        }
    }

    private func startRender(_ request: Request) {
        activeRequest = request
        scheduleRenderTimeout(for: request.id)

        if shouldPauseNextRenderForTesting {
            shouldPauseNextRenderForTesting = false
            pausedRequestForTesting = request
            return
        }

        render(request)
    }

    private func render(_ request: Request) {
        guard isActiveRequest(id: request.id) else { return }
        guard !request.isCancelled else {
            finishActiveRequest(id: request.id, image: nil)
            return
        }

        let requestID = request.id
        actualRenderStartCount += 1

        if shouldFailNextRenderForTesting {
            shouldFailNextRenderForTesting = false
            finishActiveRequest(id: requestID, image: nil)
            return
        }

        if let snapshotRenderDriver {
            snapshotRenderDriver.render(source: request.source) { [weak self] image in
                guard let self, self.isActiveRequest(id: requestID) else { return }
                self.finishActiveRequest(id: requestID, image: image)
            }
            return
        }

        renderInWebView(request)
    }

    private func renderInWebView(_ request: Request) {
        guard let webView else {
            finishActiveRequest(id: request.id, image: nil)
            return
        }

        let requestID = request.id
        let sourceBase64 = Data(request.source.utf8).base64EncodedString()
        let renderJS = """
        try {
            if (!window.mermaid) {
                console.error("window.mermaid is missing");
                return null;
            }
            const root = document.getElementById('mermaid-root');
            if (!root) { return null; }

            root.innerHTML = '';
            root.removeAttribute('data-processed');

            const sourceBytes = window.atob(sourceBase64);
            const source = new TextDecoder('utf-8').decode(
                Uint8Array.from(sourceBytes, byte => byte.charCodeAt(0))
            );
            root.textContent = source;

            window.mermaid.initialize({
                startOnLoad: false,
                theme: 'default',
                securityLevel: 'strict'
            });

            await window.mermaid.run({ nodes: [root] });
            return "OK";
        } catch (e) {
            return e.toString();
        }
        """

        webView.callAsyncJavaScript(
            renderJS,
            arguments: ["sourceBase64": sourceBase64],
            in: nil,
            in: .page
        ) { [weak self, weak webView] result in
            guard let self, let webView else { return }
            guard self.isActiveRequest(id: requestID) else { return }

            switch result {
            case .failure(let error):
                MermaidDiagramAdapter.logger.error("Mermaid inline JS evaluation error: \(error)")
                self.finishActiveRequest(id: requestID, image: nil)
            case .success(let result):
                if let resultStr = result as? String, resultStr == "OK" {
                    self.snapshotRenderedSVG(from: webView, requestID: requestID)
                } else {
                    MermaidDiagramAdapter.logger.error("Mermaid inline JS failed: \(String(describing: result))")
                    self.finishActiveRequest(id: requestID, image: nil)
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard hasBundledResources else {
            MermaidDiagramAdapter.logger.error(
                "Mermaid bundled resources are unavailable; failing queued renders"
            )
            failQueuedRenders()
            return
        }
        guard !isRenderBackendReady,
              readinessProbeID == nil,
              isCurrentLoadingNavigation(navigation) else {
            return
        }

        guard let generation = bootstrapGeneration else { return }
        let probeID = UUID()
        readinessProbeID = probeID
        webView.callAsyncJavaScript(
            "return typeof window.mermaid !== 'undefined';",
            arguments: [:],
            in: nil,
            in: .page
        ) { [weak self, weak webView] result in
            guard let self, let webView,
                  self.webView === webView,
                  self.readinessProbeID == probeID,
                  self.bootstrapGeneration == generation else {
                return
            }

            switch result {
            case .failure(let error):
                MermaidDiagramAdapter.logger.error(
                    "Mermaid WebView readiness probe failed: \(error)"
                )
                self.failQueuedRenders()
            case .success(let result):
                guard let isMermaidAvailable = result as? Bool, isMermaidAvailable else {
                    MermaidDiagramAdapter.logger.error(
                        "Mermaid WebView readiness probe did not find window.mermaid"
                    )
                    self.failQueuedRenders()
                    return
                }

                self.readinessProbeID = nil
                self.loadingNavigation = nil
                self.bootstrapGeneration = nil
                self.cancelReadinessTimeout()
                self.cancelBootstrapWatchdog()
                self.isRenderBackendReady = true
                self.processNext()
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        guard isCurrentLoadingNavigation(navigation) else { return }
        MermaidDiagramAdapter.logger.error("Mermaid WebView failed navigation: \(error)")
        failQueuedRenders()
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        guard isCurrentLoadingNavigation(navigation) else { return }
        MermaidDiagramAdapter.logger.error("Mermaid WebView failed provisional navigation: \(error)")
        failQueuedRenders()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        MermaidDiagramAdapter.logger.error("Mermaid WebView content process terminated")
        failQueuedRenders(stopLoading: true)
    }

    private func scheduleReadinessTimeoutIfNeeded() {
        guard !isRenderBackendReady, readinessTimeoutTask == nil, !queue.isEmpty else { return }

        let timeoutID = UUID()
        readinessTimeoutID = timeoutID
        let timeoutMilliseconds = Int(readinessTimeout * 1_000)
        readinessTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
            guard !Task.isCancelled,
                  let self,
                  self.readinessTimeoutID == timeoutID else {
                return
            }
            self.readinessTimeoutTask = nil
            self.readinessTimeoutID = nil
            guard !self.isRenderBackendReady else { return }

            let phase = self.readinessProbeID == nil ? "loading document" : "probing"
            MermaidDiagramAdapter.logger.error(
                "Mermaid WebView initialization timed out while \(phase)"
            )
            self.failWaitingRequestsForReadinessTimeout()
        }
    }

    private func scheduleRenderTimeout(for requestID: UUID) {
        timeoutTask?.cancel()

        let timeoutMilliseconds = Int(renderTimeout * 1_000)
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
            guard !Task.isCancelled, let self, self.isActiveRequest(id: requestID) else { return }
            self.handleRenderTimeout(requestID: requestID, shouldLog: true)
        }
    }

    private func cancelReadinessTimeoutIfNoPendingRequests() {
        guard !isRenderBackendReady, activeRequest == nil, queue.isEmpty else { return }
        cancelReadinessTimeout()
    }

    private func failWaitingRequestsForReadinessTimeout() {
        // A caller deadline does not own the shared bootstrap. Keeping the
        // current generation alive avoids restart amplification; the separate
        // bootstrap watchdog bounds genuinely stalled WebKit initialization.
        let pending = queue
        queue.removeAll()

        for request in pending {
            finish(request, image: nil)
        }
    }

    private func failQueuedRenders(stopLoading: Bool = false) {
        isRenderBackendReady = false
        loadingNavigation = nil
        readinessProbeID = nil
        bootstrapGeneration = nil
        cancelReadinessTimeout()
        cancelBootstrapWatchdog()

        timeoutTask?.cancel()
        timeoutTask = nil

        let pending = queue
        queue.removeAll()

        let active = activeRequest
        activeRequest = nil
        pausedRequestForTesting = nil

        if stopLoading {
            webView?.stopLoading()
        }

        if let active {
            finish(active, image: nil)
        }
        for request in pending {
            finish(request, image: nil)
        }
    }

    private func snapshotRenderedSVG(from webView: WKWebView, requestID: UUID) {
        guard isActiveRequest(id: requestID) else { return }

        let sizeJS = """
        (function() {
            const svg = document.querySelector('#mermaid-root svg');
            if (!svg) { return null; }
            const rect = svg.getBoundingClientRect();
            return {
                width: Math.max(1, Math.ceil(rect.width)),
                height: Math.max(1, Math.ceil(rect.height))
            };
        })();
        """

        webView.evaluateJavaScript(sizeJS) { [weak self, weak webView] result, error in
            guard let self, let webView else { return }
            guard self.isActiveRequest(id: requestID) else { return }

            if let error = error {
                MermaidDiagramAdapter.logger.error("Mermaid JS evaluation error: \(error)")
                self.finishActiveRequest(id: requestID, image: nil)
                return
            }

            guard let dimensions = result as? [String: Any],
                  let width = dimensions["width"] as? Double,
                  let height = dimensions["height"] as? Double else {
                MermaidDiagramAdapter.logger.error("Mermaid JS evaluation returned invalid result: \(String(describing: result))")
                self.finishActiveRequest(id: requestID, image: nil)
                return
            }

            let snapshotSize = self.clampedSnapshotSize(width: width, height: height)
            guard self.isActiveRequest(id: requestID) else { return }
            webView.frame = CGRect(origin: .zero, size: snapshotSize)

            let config = WKSnapshotConfiguration()
            config.rect = CGRect(origin: .zero, size: snapshotSize)
            webView.takeSnapshot(with: config) { [weak self] image, error in
                guard let self else { return }
                guard self.isActiveRequest(id: requestID) else { return }
                guard error == nil else {
                    self.finishActiveRequest(id: requestID, image: nil)
                    return
                }
                self.finishActiveRequest(id: requestID, image: image)
            }
        }
    }

    private func clampedSnapshotSize(width: Double, height: Double) -> CGSize {
        let clampedWidth = min(max(width, 1), snapshotDimensionLimit)
        let clampedHeight = min(max(height, 1), snapshotDimensionLimit)
        return CGSize(width: clampedWidth, height: clampedHeight)
    }

    private func finishCurrentActiveRequest(image: NativeImage?) {
        guard let requestID = activeRequest?.id else {
            return
        }
        finishActiveRequest(id: requestID, image: image)
    }

    private func finishActiveRequest(id: UUID, image: NativeImage?) {
        guard let request = activeRequest, request.id == id else {
            return
        }
        finish(request, image: image)
    }

    private func handleRenderTimeout(requestID: UUID, shouldLog: Bool) {
        guard isActiveRequest(id: requestID) else { return }
        if shouldLog {
            MermaidDiagramAdapter.logger.error("Mermaid WebView rendering timed out")
        }

        reloadWebView()
        finishActiveRequest(id: requestID, image: nil)
    }

    private func reloadWebView() {
        guard snapshotRenderDriver == nil else {
            isRenderBackendReady = true
            return
        }
        loadBaseHTML()
    }

    private func ensureRenderBackendIsLoading() {
        if snapshotRenderDriver != nil {
            isRenderBackendReady = true
            processNext()
            return
        }

        guard !isRenderBackendReady,
              loadingNavigation == nil,
              readinessProbeID == nil else {
            return
        }
        loadBaseHTML()
    }

    private func loadBaseHTML() {
        isRenderBackendReady = false
        readinessProbeID = nil
        cancelReadinessTimeout()
        cancelBootstrapWatchdog()

        guard hasBundledResources,
              let webView,
              let bootstrapURL = MermaidResourceLocator.bundledBootstrapURL(),
              let resourceDirectory = MermaidResourceLocator.bundledResourceDirectory() else {
            MermaidDiagramAdapter.logger.error(
                "Mermaid bundled resources are unavailable; failing queued renders"
            )
            failQueuedRenders()
            return
        }

        let generation = UUID()
        bootstrapGeneration = generation
        loadingNavigation = webView.loadFileURL(
            bootstrapURL,
            allowingReadAccessTo: resourceDirectory
        )
        scheduleBootstrapWatchdog(for: generation)
    }

    private func isCurrentLoadingNavigation(_ navigation: WKNavigation?) -> Bool {
        guard let navigation, let loadingNavigation else { return false }
        return navigation === loadingNavigation
    }

    private func scheduleBootstrapWatchdog(for generation: UUID) {
        let timeoutMilliseconds = Int(bootstrapHardTimeout * 1_000)
        bootstrapWatchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
            guard !Task.isCancelled,
                  let self,
                  self.bootstrapGeneration == generation,
                  !self.isRenderBackendReady else {
                return
            }
            self.bootstrapWatchdogTask = nil
            MermaidDiagramAdapter.logger.error("Mermaid WebView bootstrap hard deadline exceeded")
            self.failQueuedRenders(stopLoading: true)
        }
    }

    private func cancelReadinessTimeout() {
        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil
        readinessTimeoutID = nil
    }

    private func cancelBootstrapWatchdog() {
        bootstrapWatchdogTask?.cancel()
        bootstrapWatchdogTask = nil
    }

    func invalidateReadinessForTesting() {
        failQueuedRenders()
    }

    private func finish(_ request: Request, image: NativeImage?) {
        let wasActive = activeRequest === request

        if wasActive {
            timeoutTask?.cancel()
            timeoutTask = nil
            activeRequest = nil
            if pausedRequestForTesting === request {
                pausedRequestForTesting = nil
            }
        }

        let wasCancelled = request.isCancelled
        if wasActive, !wasCancelled {
            _ = storeSnapshotResultInCache(source: request.source, image: image)
        }

        resume(request, image: wasCancelled ? nil : image)

        if wasActive {
            processNext()
        }
    }

    private func resume(_ request: Request, image: NativeImage?) {
        guard let continuation = request.continuation else { return }
        request.continuation = nil
        continuation.resume(returning: image)
    }

    private func isActiveRequest(id: UUID) -> Bool {
        activeRequest?.id == id
    }

    private func storeSnapshotResultInCache(
        source: String,
        image: NativeImage?
    ) -> Bool {
        guard let image else { return false }
        guard let cost = decodedByteCost(for: image) else { return false }
        imageCache.setObject(image, forKey: source as NSString, cost: cost)
        return true
    }

    private func decodedByteCost(for image: NativeImage) -> Int? {
        #if canImport(UIKit)
        if let cgImage = image.cgImage {
            return decodedByteCost(
                pixelWidth: cgImage.width,
                pixelHeight: cgImage.height,
                bitsPerPixel: cgImage.bitsPerPixel
            )
        }
        let scale = image.scale
        return decodedByteCost(
            width: Double(image.size.width * scale),
            height: Double(image.size.height * scale),
            bytesPerPixel: 4
        )
        #elseif canImport(AppKit)
        if let representation = image.representations
            .compactMap({ $0 as? NSBitmapImageRep })
            .max(by: { lhs, rhs in
                Double(lhs.pixelsWide) * Double(lhs.pixelsHigh)
                    < Double(rhs.pixelsWide) * Double(rhs.pixelsHigh)
            }) {
            return decodedByteCost(
                pixelWidth: representation.pixelsWide,
                pixelHeight: representation.pixelsHigh,
                bitsPerPixel: representation.bitsPerPixel
            )
        }
        return decodedByteCost(
            width: Double(image.size.width),
            height: Double(image.size.height),
            bytesPerPixel: 4
        )
        #endif
    }

    private func decodedByteCost(
        pixelWidth: Int,
        pixelHeight: Int,
        bitsPerPixel: Int
    ) -> Int? {
        let bytesPerPixel = max(1, Int(ceil(Double(max(bitsPerPixel, 1)) / 8.0)))
        return decodedByteCost(
            width: Double(pixelWidth),
            height: Double(pixelHeight),
            bytesPerPixel: bytesPerPixel
        )
    }

    private func decodedByteCost(
        width: Double,
        height: Double,
        bytesPerPixel: Int
    ) -> Int? {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else { return nil }

        let pixels = width.rounded(.up) * height.rounded(.up)
        let bytes = pixels * Double(max(bytesPerPixel, 1))
        guard bytes.isFinite,
              bytes >= 0,
              bytes <= Double(cacheTotalCostLimit) else {
            return nil
        }

        return Int(bytes)
    }

    func resetForTesting() {
        precondition(activeRequest == nil && queue.isEmpty, "MermaidSnapshotter test reset requires an idle snapshotter")
        timeoutTask?.cancel()
        timeoutTask = nil
        cancelReadinessTimeout()
        pausedRequestForTesting = nil
        shouldPauseNextRenderForTesting = false
        shouldFailNextRenderForTesting = false
        imageCache.removeAllObjects()
        actualRenderStartCount = 0
        cacheHitCount = 0
    }

    func renderedDiagramTextForTesting() async -> String? {
        guard snapshotRenderDriver == nil, let webView else { return nil }

        return await withCheckedContinuation { continuation in
            webView.callAsyncJavaScript(
                "return document.querySelector('#mermaid-root')?.textContent ?? null;",
                arguments: [:],
                in: nil,
                in: .page
            ) { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value as? String)
                case .failure:
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    func statisticsForTesting() -> MermaidSnapshotterStatistics {
        MermaidSnapshotterStatistics(
            actualRenderStartCount: actualRenderStartCount,
            cacheHitCount: cacheHitCount,
            cacheCountLimit: imageCache.countLimit,
            cacheTotalCostLimit: imageCache.totalCostLimit,
            queuedRequestCount: queue.count,
            isRendering: activeRequest != nil
        )
    }

    func pauseNextRenderForTesting() {
        precondition(activeRequest == nil && pausedRequestForTesting == nil, "Can only pause the next Mermaid render while idle")
        shouldPauseNextRenderForTesting = true
    }

    func resumePausedRenderForTesting() {
        guard let request = pausedRequestForTesting else { return }
        pausedRequestForTesting = nil
        render(request)
    }

    func failNextRenderForTesting() {
        precondition(
            activeRequest == nil && queue.isEmpty,
            "Can only force the next Mermaid render failure while idle"
        )
        shouldFailNextRenderForTesting = true
    }

    func timeOutActiveRenderForTesting() {
        guard let requestID = activeRequest?.id else {
            preconditionFailure("A Mermaid render must be active before forcing a timeout")
        }
        handleRenderTimeout(requestID: requestID, shouldLog: false)
    }

}
