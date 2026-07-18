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

struct MermaidSnapshotterStatistics: Equatable, Sendable {
    let actualWebViewRenderStartCount: Int
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
    static func failNextJavaScriptEvaluationForTesting() {
        MermaidSnapshotter.shared.failNextJavaScriptEvaluationForTesting()
    }

    @MainActor
    static func timeOutActiveRenderForTesting() {
        MermaidSnapshotter.shared.timeOutActiveRenderForTesting()
    }

    @MainActor
    static func invalidateSnapshotterReadinessForTesting() {
        MermaidSnapshotter.shared.invalidateReadinessForTesting()
    }

}

enum MermaidResourceLocator {
    static let bundledScriptName = "mermaid.min"
    static let bundledScriptExtension = "js"

    static func bundledScriptURL() -> URL? {
        Bundle.module.url(
            forResource: bundledScriptName,
            withExtension: bundledScriptExtension
        )
    }
}

enum MermaidHTMLBuilder {
    static func makeBaseHTML() -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
            <style>
                html, body { margin: 0; padding: 0; background-color: transparent; overflow: hidden; }
                #mermaid-root { background-color: transparent; display: inline-block; }
            </style>
        </head>
        <body>
            <div id="mermaid-root"></div>
        </body>
        </html>
        """
    }

}

@MainActor
private final class MermaidSnapshotter: NSObject, WKNavigationDelegate {
    
    static let shared = MermaidSnapshotter()

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

    private var webView: WKWebView
    private let hasConfiguredBundledScript: Bool
    private var loadingNavigation: WKNavigation?
    private var readinessProbeID: UUID?
    private var activeRequest: Request?
    private var queue: [Request] = []
    private var timeoutTask: Task<Void, Never>?
    private var readinessTimeoutTask: Task<Void, Never>?
    // Cold WebKit navigation and bundled Mermaid script initialization can take several seconds in CI.
    private let readinessTimeout: TimeInterval = 15.0
    private let renderTimeout: TimeInterval = 15.0
    private let snapshotDimensionLimit: CGFloat = 2048
    private var isWebViewReady = false
    private let cacheTotalCostLimit = 64 * 1024 * 1024
    private let imageCache: NSCache<NSString, NativeImage> = {
        let cache = NSCache<NSString, NativeImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()
    private var actualWebViewRenderStartCount = 0
    private var cacheHitCount = 0
    private var shouldPauseNextRenderForTesting = false
    private var shouldFailNextJavaScriptEvaluationForTesting = false
    private weak var pausedRequestForTesting: Request?
    
    override init() {
        let configuration = WKWebViewConfiguration()
        if let scriptURL = MermaidResourceLocator.bundledScriptURL() {
            do {
                let scriptSource = try String(contentsOf: scriptURL, encoding: .utf8)
                configuration.userContentController.addUserScript(
                    WKUserScript(
                        source: scriptSource,
                        injectionTime: .atDocumentEnd,
                        forMainFrameOnly: true
                    )
                )
                hasConfiguredBundledScript = true
            } catch {
                MermaidDiagramAdapter.logger.error(
                    "Could not configure Mermaid script source: \(error)"
                )
                hasConfiguredBundledScript = false
            }
        } else {
            MermaidDiagramAdapter.logger.error("Could not locate Mermaid script source")
            hasConfiguredBundledScript = false
        }

        webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 640, height: 480),
            configuration: configuration
        )
        super.init()
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

        guard hasConfiguredBundledScript else {
            MermaidDiagramAdapter.logger.error(
                "Mermaid bundled script is unavailable; failing queued renders"
            )
            failQueuedRenders()
            return
        }

        if isWebViewReady {
            processNext()
        } else {
            ensureWebViewIsLoading()
            scheduleReadinessTimeoutIfNeeded()
        }
    }

    private func cancelRequest(id: UUID) {
        if let activeRequest, activeRequest.id == id {
            activeRequest.cancel()
            resume(activeRequest, image: nil)
            // The caller can stop waiting immediately, but this shared WebView
            // must drain the in-flight JS/snapshot callbacks before the next
            // request mutates the same DOM.
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
        guard isWebViewReady else {
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

            const source = window.atob(sourceBase64);
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

        let evaluatedScript: String
        if shouldFailNextJavaScriptEvaluationForTesting {
            shouldFailNextJavaScriptEvaluationForTesting = false
            evaluatedScript = "throw new Error('MarkdownKit forced Mermaid test failure')"
        } else {
            evaluatedScript = renderJS
        }

        actualWebViewRenderStartCount += 1
        webView.callAsyncJavaScript(
            evaluatedScript,
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
        guard hasConfiguredBundledScript else {
            MermaidDiagramAdapter.logger.error(
                "Mermaid bundled script was not configured; failing queued renders"
            )
            failQueuedRenders()
            return
        }
        guard !isWebViewReady,
              readinessProbeID == nil,
              isCurrentLoadingNavigation(navigation) else {
            return
        }

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
                  self.readinessProbeID == probeID else {
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
                self.readinessTimeoutTask?.cancel()
                self.readinessTimeoutTask = nil
                self.isWebViewReady = true
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
        if !isWebViewReady {
            failQueuedRenders()
            return
        }

        reloadWebView()
        if activeRequest != nil {
            finishCurrentActiveRequest(image: nil)
        } else {
            processNext()
        }
    }

    private func scheduleReadinessTimeoutIfNeeded() {
        guard !isWebViewReady, readinessTimeoutTask == nil, !queue.isEmpty else { return }

        let timeoutMilliseconds = Int(readinessTimeout * 1_000)
        readinessTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(timeoutMilliseconds))
            guard !Task.isCancelled, let self, !self.isWebViewReady else { return }
            MermaidDiagramAdapter.logger.error("Mermaid WebView initialization timed out")
            self.failQueuedRenders()
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
        guard !isWebViewReady, activeRequest == nil, queue.isEmpty else { return }
        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil
    }

    private func failQueuedRenders() {
        isWebViewReady = false
        loadingNavigation = nil
        readinessProbeID = nil
        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil

        timeoutTask?.cancel()
        timeoutTask = nil

        let pending = queue
        queue.removeAll()

        let active = activeRequest
        activeRequest = nil
        pausedRequestForTesting = nil

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
        loadBaseHTML()
    }

    private func ensureWebViewIsLoading() {
        guard !isWebViewReady,
              loadingNavigation == nil,
              readinessProbeID == nil else {
            return
        }
        loadBaseHTML()
    }

    private func loadBaseHTML() {
        isWebViewReady = false
        readinessProbeID = nil
        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil

        guard hasConfiguredBundledScript else {
            MermaidDiagramAdapter.logger.error(
                "Mermaid bundled script is unavailable; failing queued renders"
            )
            failQueuedRenders()
            return
        }

        loadingNavigation = webView.loadHTMLString(
            MermaidHTMLBuilder.makeBaseHTML(),
            baseURL: nil
        )
    }

    private func isCurrentLoadingNavigation(_ navigation: WKNavigation?) -> Bool {
        guard let navigation, let loadingNavigation else { return false }
        return navigation === loadingNavigation
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
        readinessTimeoutTask?.cancel()
        readinessTimeoutTask = nil
        pausedRequestForTesting = nil
        shouldPauseNextRenderForTesting = false
        shouldFailNextJavaScriptEvaluationForTesting = false
        imageCache.removeAllObjects()
        actualWebViewRenderStartCount = 0
        cacheHitCount = 0
    }

    func statisticsForTesting() -> MermaidSnapshotterStatistics {
        MermaidSnapshotterStatistics(
            actualWebViewRenderStartCount: actualWebViewRenderStartCount,
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

    func failNextJavaScriptEvaluationForTesting() {
        precondition(
            activeRequest == nil && queue.isEmpty,
            "Can only force the next Mermaid JavaScript failure while idle"
        )
        shouldFailNextJavaScriptEvaluationForTesting = true
    }

    func timeOutActiveRenderForTesting() {
        guard let requestID = activeRequest?.id else {
            preconditionFailure("A Mermaid render must be active before forcing a timeout")
        }
        handleRenderTimeout(requestID: requestID, shouldLog: false)
    }

}
