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
        
        // Render image on MainActor
        let image: NativeImage? = await MermaidSnapshotter.shared.takeSnapshot(source: source)
        
        guard let img = image else { return nil }
        
        let attachment = NSTextAttachment()
        #if canImport(UIKit)
        attachment.image = img
        #elseif canImport(AppKit)
        attachment.image = img
        #endif
        attachment.bounds = CGRect(origin: .zero, size: img.size)
        
        return NSAttributedString(attachment: attachment)
    }
}

enum MermaidResourceLocator {
    static let bundledScriptName = "mermaid.min"
    static let bundledScriptExtension = "js"
    static let fallbackRemoteURLString = "https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"

    static func bundledScriptURL() -> URL? {
        Bundle.module.url(
            forResource: bundledScriptName,
            withExtension: bundledScriptExtension
        )
    }

    static func preferredScriptURLString() -> String {
        bundledScriptURL()?.absoluteString ?? fallbackRemoteURLString
    }

    static func preferredBaseURL() -> URL? {
        bundledScriptURL()?.deletingLastPathComponent()
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

    static func makeHTML(source: String, scriptURLString: String) -> String {
        let sourceBase64 = Data(source.utf8).base64EncodedString()
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
            <script src="\(scriptURLString)"></script>
        </head>
        <body>
            <div id="mermaid-root"></div>
            <script>
                (function() {
                    const root = document.getElementById('mermaid-root');
                    if (!root || !window.mermaid) { return; }
                    const source = window.atob('\(sourceBase64)');
                    root.textContent = source;
                    window.mermaid.initialize({
                        startOnLoad: false,
                        theme: 'default',
                        securityLevel: 'strict'
                    });
                    window.mermaid.run({ nodes: [root] });
                })();
            </script>
        </body>
        </html>
        """
    }
}

@MainActor
private class MermaidSnapshotter: NSObject, WKNavigationDelegate {
    
    static let shared = MermaidSnapshotter()
    
    private var webView: WKWebView
    private var currentContinuation: CheckedContinuation<NativeImage?, Never>?
    private var activeRenderToken: UUID?
    private var timeoutWorkItem: DispatchWorkItem?
    private var readinessTimeoutWorkItem: DispatchWorkItem?
    private var isRendering = false
    private var queue: [(source: String, continuation: CheckedContinuation<NativeImage?, Never>)] = []
    private let renderTimeout: TimeInterval = 4.0
    private let snapshotDimensionLimit: CGFloat = 2048
    private var isWebViewReady = false
    
    override init() {
        let configuration = WKWebViewConfiguration()

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

        // Load base HTML and inject JS once
        webView.loadHTMLString(MermaidHTMLBuilder.makeBaseHTML(), baseURL: nil)
    }
    
    func takeSnapshot(source: String) async -> NativeImage? {
        return await withCheckedContinuation { continuation in
            queue.append((source, continuation))
            if isWebViewReady {
                processNext()
            } else {
                scheduleReadinessTimeoutIfNeeded()
            }
        }
    }
    
    private func processNext() {
        guard !isRendering, !queue.isEmpty else { return }
        guard isWebViewReady else {
            scheduleReadinessTimeoutIfNeeded()
            return
        }

        isRendering = true
        let (source, continuation) = queue.removeFirst()
        currentContinuation = continuation

        let renderToken = UUID()
        activeRenderToken = renderToken

        let timeout = DispatchWorkItem { [weak self] in
            if self?.activeRenderToken == renderToken {
                MermaidDiagramAdapter.logger.error("Mermaid WebView rendering timed out")
                self?.completeCurrentRender(image: nil, token: renderToken)
            }
        }
        timeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + renderTimeout, execute: timeout)

        let sourceBase64 = Data(source.utf8).base64EncodedString()
        let renderJS = """
        (function() {
            try {
                if (!window.mermaid) {
                    console.error("window.mermaid is missing");
                    return null;
                }
                const root = document.getElementById('mermaid-root');
                if (!root) { return null; }
                
                // Clear old diagram
                root.innerHTML = '';
                root.removeAttribute('data-processed');
                
                const source = window.atob('\(sourceBase64)');
                root.textContent = source;
                
                window.mermaid.initialize({
                    startOnLoad: false,
                    theme: 'default',
                    securityLevel: 'strict'
                });
                
                // Must be sync in order for execution to finish
                window.mermaid.run({ nodes: [root] });
                return "OK";
            } catch (e) {
                return e.toString();
            }
        })();
        """

        webView.evaluateJavaScript(renderJS) { [weak self, weak webView] result, error in
            guard let self, let webView else { return }
            
            if let error {
                MermaidDiagramAdapter.logger.error("Mermaid inline JS evaluation error: \(error)")
                self.completeCurrentRender(image: nil)
                return
            }
            
            if let resultStr = result as? String, resultStr == "OK" {
                // Wait briefly for SVG reflow
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.snapshotRenderedSVG(from: webView)
                }
            } else {
                MermaidDiagramAdapter.logger.error("Mermaid inline JS failed: \(String(describing: result))")
                self.completeCurrentRender(image: nil)
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Once HTML is loaded, inject mermaid.min.js manually to ensure global scope
        if let scriptURL = MermaidResourceLocator.bundledScriptURL(),
           let scriptSource = try? String(contentsOf: scriptURL, encoding: .utf8) {
            webView.evaluateJavaScript(scriptSource) { [weak self] _, error in
                guard let self else { return }
                if let error {
                    MermaidDiagramAdapter.logger.error("Failed to initialize mermaid JS bundle: \(error)")
                    self.failQueuedRenders()
                } else {
                    self.readinessTimeoutWorkItem?.cancel()
                    self.readinessTimeoutWorkItem = nil
                    self.isWebViewReady = true
                    // Process any queued items
                    let pending = self.queue
                    self.queue.removeAll()
                    self.isRendering = false
                    for item in pending {
                        self.queue.append(item)
                    }
                    self.processNext()
                }
            }
        } else {
            MermaidDiagramAdapter.logger.error("Could not load Mermaid script source")
            failQueuedRenders()
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        MermaidDiagramAdapter.logger.error("Mermaid WebView failed navigation: \(error)")
        completeCurrentRender(image: nil)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        MermaidDiagramAdapter.logger.error("Mermaid WebView failed provisional navigation: \(error)")
        completeCurrentRender(image: nil)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        if !isWebViewReady {
            failQueuedRenders()
            return
        }
        completeCurrentRender(image: nil)
    }

    private func scheduleReadinessTimeoutIfNeeded() {
        guard !isWebViewReady, readinessTimeoutWorkItem == nil, !queue.isEmpty else { return }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, !self.isWebViewReady else { return }
            MermaidDiagramAdapter.logger.error("Mermaid WebView initialization timed out")
            self.failQueuedRenders()
        }
        readinessTimeoutWorkItem = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + renderTimeout, execute: timeout)
    }

    private func failQueuedRenders() {
        readinessTimeoutWorkItem?.cancel()
        readinessTimeoutWorkItem = nil

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        let pending = queue
        queue.removeAll()

        let active = currentContinuation
        currentContinuation = nil
        activeRenderToken = nil
        isRendering = false

        active?.resume(returning: nil)
        for item in pending {
            item.continuation.resume(returning: nil)
        }
    }

    private func snapshotRenderedSVG(from webView: WKWebView) {
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

            if let error = error {
                MermaidDiagramAdapter.logger.error("Mermaid JS evaluation error: \(error)")
                self.completeCurrentRender(image: nil)
                return
            }

            guard let dimensions = result as? [String: Any],
                  let width = dimensions["width"] as? Double,
                  let height = dimensions["height"] as? Double else {
                MermaidDiagramAdapter.logger.error("Mermaid JS evaluation returned invalid result: \(String(describing: result))")
                self.completeCurrentRender(image: nil)
                return
            }

            let snapshotSize = self.clampedSnapshotSize(width: width, height: height)
            webView.frame = CGRect(origin: .zero, size: snapshotSize)

            let config = WKSnapshotConfiguration()
            config.rect = CGRect(origin: .zero, size: snapshotSize)
            webView.takeSnapshot(with: config) { [weak self] image, error in
                guard let self else { return }
                guard error == nil else {
                    self.completeCurrentRender(image: nil)
                    return
                }
                self.completeCurrentRender(image: image)
            }
        }
    }

    private func clampedSnapshotSize(width: Double, height: Double) -> CGSize {
        let clampedWidth = min(max(width, 1), snapshotDimensionLimit)
        let clampedHeight = min(max(height, 1), snapshotDimensionLimit)
        return CGSize(width: clampedWidth, height: clampedHeight)
    }

    private func completeCurrentRender(image: NativeImage?, token: UUID? = nil) {
        if let token, token != activeRenderToken {
            return
        }

        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil

        let continuation = currentContinuation
        currentContinuation = nil
        activeRenderToken = nil
        isRendering = false

        continuation?.resume(returning: image)
        processNext()
    }
}
