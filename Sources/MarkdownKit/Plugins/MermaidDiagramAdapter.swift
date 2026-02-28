import Foundation
import WebKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A pluggable adapter that renders Mermaid diagrams using a lightweight headless WKWebView
/// and converts them into an NSTextAttachment.
public struct MermaidDiagramAdapter: DiagramRenderingAdapter {

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

@MainActor
private class MermaidSnapshotter: NSObject, WKNavigationDelegate {
    
    static let shared = MermaidSnapshotter()
    
    private var webView: WKWebView!
    private var currentContinuation: CheckedContinuation<NativeImage?, Never>?
    private var isRendering = false
    private var queue: [(source: String, continuation: CheckedContinuation<NativeImage?, Never>)] = []
    
    override init() {
        super.init()
        let configuration = WKWebViewConfiguration()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        webView.navigationDelegate = self
        
        #if canImport(UIKit)
        webView.backgroundColor = .clear
        webView.isOpaque = false
        webView.scrollView.isScrollEnabled = false
        #elseif canImport(AppKit)
        webView.setValue(false, forKey: "drawsBackground")
        #endif
    }
    
    func takeSnapshot(source: String) async -> NativeImage? {
        return await withCheckedContinuation { continuation in
            queue.append((source, continuation))
            processNext()
        }
    }
    
    private func processNext() {
        guard !isRendering, !queue.isEmpty else { return }
        isRendering = true
        let (source, continuation) = queue.removeFirst()
        currentContinuation = continuation
        
        let escapedSource = source
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
            
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
            <style>
                body { margin: 0; padding: 0; background-color: transparent; }
                .mermaid { background-color: transparent; }
            </style>
            <script type="module">
                import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
                mermaid.initialize({ startOnLoad: true, theme: 'default', background: 'transparent' });
            </script>
        </head>
        <body>
            <div class="mermaid">
                \(escapedSource)
            </div>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Wait briefly for Mermaid JS to execute and render
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let config = WKSnapshotConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: 800, height: 600) // Simplification for demo
            
            webView.takeSnapshot(with: config) { [weak self] image, error in
                guard let self = self else { return }
                
                let continuation = self.currentContinuation
                self.currentContinuation = nil
                self.isRendering = false
                
                if let image = image, error == nil {
                    continuation?.resume(returning: image)
                } else {
                    continuation?.resume(returning: nil)
                }
                
                self.processNext()
            }
        }
    }
}
