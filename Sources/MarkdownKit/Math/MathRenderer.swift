//
//  MathRenderer.swift
//  MarkdownKit
//

import Foundation

#if canImport(WebKit)
import WebKit
import MathJaxSwift

#if canImport(UIKit)
import UIKit
public typealias NativeImage = UIImage
#elseif canImport(AppKit)
import AppKit
public typealias NativeImage = NSImage
#endif

/// Converts LaTeX to SVG with `MathJaxSwift` (JavaScriptCore) and rasterizes the SVG
/// with a shared hidden `WKWebView` for use in `NSTextAttachment`.
public final class MathRenderer: NSObject, WKNavigationDelegate {

    public static let shared = MathRenderer()

    private struct PendingRender {
        let svg: String
        let completion: (NativeImage?) -> Void
    }

    private actor Engine {
        private var mathJax: MathJax?

        func tex2svg(_ latex: String, display: Bool) throws -> String {
            let engine: MathJax
            if let existing = mathJax {
                engine = existing
            } else {
                let created = try MathJax(preferredOutputFormat: .svg)
                mathJax = created
                engine = created
            }

            let conversionOptions = ConversionOptions(display: display)
            return try engine.tex2svg(
                latex,
                css: false,
                assistiveMml: false,
                container: false,
                styles: false,
                conversionOptions: conversionOptions
            )
        }
    }

    private let engine = Engine()

    private var webView: WKWebView?
    private var isWebViewReady = false
    private var pendingRenders: [PendingRender] = []
    private var isProcessingRender = false

    private override init() {
        super.init()
        setupBackgroundWebView()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isWebViewReady = true
        drainRenderQueue()
    }

    /// Converts LaTeX and asynchronously returns a rasterized image.
    /// - Parameters:
    ///   - latex: Raw TeX input.
    ///   - display: `true` for block equation layout, `false` for inline.
    ///   - completion: Completion callback returning rendered image or `nil`.
    public func render(latex: String, display: Bool = false, completion: @escaping (NativeImage?) -> Void) {
        Task { [weak self] in
            guard let self else {
                completion(nil)
                return
            }

            let svg: String
            do {
                svg = try await engine.tex2svg(latex, display: display)
            } catch {
                print("MathJaxSwift conversion failed: \(error)")
                completion(nil)
                return
            }

            self.pendingRenders.append(PendingRender(svg: svg, completion: completion))
            self.drainRenderQueue()
        }
    }

    private func setupBackgroundWebView() {
        DispatchQueue.main.async {
            let config = WKWebViewConfiguration()
            let webView = WKWebView(frame: .zero, configuration: config)
            webView.navigationDelegate = self

            #if canImport(UIKit)
            webView.isOpaque = false
            webView.backgroundColor = .clear
            #elseif canImport(AppKit)
            webView.setValue(false, forKey: "drawsBackground")
            #endif

            let html = """
            <!DOCTYPE html>
            <html>
            <head>
              <meta name="viewport" content="width=device-width, initial-scale=1.0">
              <style>
                html, body {
                    margin: 0;
                    padding: 0;
                    background: transparent;
                    overflow: hidden;
                }
                /* Use CSS variables for explicit color control, matching native appearances */
                :root {
                    color: -apple-system-label;
                }
                @media (prefers-color-scheme: dark) {
                    :root { color: white; }
                }
                @media (prefers-color-scheme: light) {
                    :root { color: black; }
                }
                #math-root {
                    display: inline-block;
                    margin: 0;
                    padding: 0;
                }
                /* Force MathJax output to inherit the text color */
                svg {
                    color: inherit;
                    fill: currentColor;
                }
                svg * {
                    fill: inherit;
                }
              </style>
            </head>
            <body>
              <div id="math-root"></div>
            </body>
            </html>
            """

            self.webView = webView
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    private func drainRenderQueue() {
        guard isWebViewReady, !isProcessingRender, !pendingRenders.isEmpty else { return }

        isProcessingRender = true
        let next = pendingRenders.removeFirst()
        processSVG(next.svg) { [weak self] image in
            next.completion(image)
            guard let self else { return }
            self.isProcessingRender = false
            self.drainRenderQueue()
        }
    }

    private func processSVG(_ svg: String, completion: @escaping (NativeImage?) -> Void) {
        guard let webView else {
            completion(nil)
            return
        }

        let base64SVG = Data(svg.utf8).base64EncodedString()
        let js = """
        (function() {
          const root = document.getElementById('math-root');
          if (!root) { return null; }
          root.innerHTML = window.atob('\(base64SVG)');
          const svg = root.querySelector('svg');
          if (!svg) { return null; }
          const rect = svg.getBoundingClientRect();
          return {
            width: Math.max(1, Math.ceil(rect.width)),
            height: Math.max(1, Math.ceil(rect.height))
          };
        })();
        """

        webView.evaluateJavaScript(js) { [weak self] result, error in
            guard let self else {
                completion(nil)
                return
            }

            guard error == nil,
                  let dimensions = result as? [String: Any],
                  let width = dimensions["width"] as? Double,
                  let height = dimensions["height"] as? Double else {
                completion(nil)
                return
            }

            let clampedSize = CGSize(
                width: min(max(width, 1), 4096),
                height: min(max(height, 1), 4096)
            )
            self.snapshotCurrentSVG(in: webView, size: clampedSize, completion: completion)
        }
    }

    private func snapshotCurrentSVG(
        in webView: WKWebView,
        size: CGSize,
        completion: @escaping (NativeImage?) -> Void
    ) {
        webView.frame = CGRect(origin: .zero, size: size)

        let config = WKSnapshotConfiguration()
        config.rect = CGRect(origin: .zero, size: size)

        webView.takeSnapshot(with: config) { image, error in
            guard error == nil else {
                completion(nil)
                return
            }
            completion(image)
        }
    }
}
#endif
